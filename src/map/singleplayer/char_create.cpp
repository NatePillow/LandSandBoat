/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see http://www.gnu.org/licenses/

===========================================================================
*/

#include "char_create.h"

#include "grades.h"
#include "map_session_container.h"
#include "op_registry.h"

#include "lua/luautils.h"

#include "common/database.h"
#include "common/logging.h"
#include "common/lua.h"
#include "common/settings.h"

#include <bcrypt/BCrypt.hpp>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <cctype>
#include <optional>
#include <string>

namespace singleplayer::char_create
{
    using json = nlohmann::json;

    namespace
    {
        // Op payload — one requested new character. Populated + fully validated
        // on the HTTP worker thread; the account/char INSERT + LoadChar happen
        // later on the main thread in applyCreate.
        struct CreateOp
        {
            std::string name;
            uint8       race;   // 1-8  (HumeM..Galka)
            uint8       face;   // 0-15
            uint8       size;   // 0-2  (Small/Medium/Large)
            uint8       nation; // 0-2  (Sandoria/Bastok/Windurst)
            uint8       mjob;   // 1-6  (starting jobs; clamped like retail)
        };

        // -----------------------------------------------------------------
        // Nation -> canonical starting city zone. Retail randomizes among a
        // nation's three cities; we pin one per nation (the exact CS-exit
        // coordinates live in the Lua stamp, keyed by zone). See #3 in design.
        //   0 Sandoria -> Southern San d'Oria (230)
        //   1 Bastok   -> Bastok Mines        (234)
        //   2 Windurst -> Windurst Woods       (241)
        // -----------------------------------------------------------------
        auto nationStartZone(uint8 nation) -> uint16
        {
            switch (nation)
            {
                case 1:  return 234; // Bastok Mines
                case 2:  return 241; // Windurst Woods
                default: return 230; // Southern San d'Oria
            }
        }

        // -----------------------------------------------------------------
        // Name validation — the SAME checks the retail create flow runs, in the
        // same order, nothing extra:
        //   - account-name uniqueness   (auth_session.cpp:334, LOGIN_CREATE)
        //   - alpha-only                (view_session.cpp:218, 0x22)
        //   - length 3-15               (view_session.cpp:230)
        //   - char-name uniqueness LIKE (view_session.cpp:236)
        //   - (opt) NPC/mob names       (view_session.cpp:247, gated)
        // Returns an error reason on failure, std::nullopt when the name is OK.
        //
        // Thread-safe: only DB queries + settings::get (a read of the C++ settings
        // cache), so it may run on the httplib worker thread. The bad-words check
        // (view_session.cpp:272) reads the shared sol Lua state and is NOT thread
        // safe, so it lives separately in checkBannedWords, main-thread only.
        // -----------------------------------------------------------------
        auto validateName(const std::string& name) -> std::optional<std::string>
        {
            // alpha-only
            for (const auto c : name)
            {
                if (!std::isalpha(static_cast<unsigned char>(c)))
                {
                    return "Invalid characters present in name.";
                }
            }

            // length 3-15
            if (name.size() < 3 || name.size() > 15)
            {
                return "Invalid name length.";
            }

            // We create login = charname, so the retail account-uniqueness check
            // (LOGIN_CREATE) and the char-name uniqueness check (0x22) both apply.
            const auto rsetAcc = db::preparedStmt("SELECT id FROM accounts WHERE login = ?", name);
            if (!rsetAcc)
            {
                return "Internal account name query failed.";
            }
            if (rsetAcc->rowsCount() != 0)
            {
                return "Account name already in use.";
            }

            const auto rsetChar = db::preparedStmt("SELECT charname FROM chars WHERE charname LIKE ?", name);
            if (!rsetChar)
            {
                return "Internal entity name query failed.";
            }
            if (rsetChar->rowsCount() != 0)
            {
                return "Name already in use.";
            }

            // (optional) NPC / mob name collision — gated, default off
            if (settings::get<bool>("login.DISABLE_MOB_NPC_CHAR_NAMES"))
            {
                const auto rsetNpc = db::preparedStmt(
                    "SELECT polutils_name AS `name` FROM npc_list "
                    "WHERE REPLACE(REPLACE(UPPER(polutils_name), '-', ''), '_', '') "
                    "LIKE REPLACE(REPLACE(UPPER(?), '-', ''), '_', '') "
                    "UNION "
                    "SELECT packet_name AS `name` FROM mob_pools "
                    "WHERE REPLACE(REPLACE(UPPER(packet_name), '-', ''), '_', '') "
                    "LIKE REPLACE(REPLACE(UPPER(?), '-', ''), '_', '')",
                    name, name);
                if (!rsetNpc)
                {
                    return "Internal entity name query failed";
                }
                if (rsetNpc->rowsCount() != 0)
                {
                    return "Name already in use.";
                }
            }

            return std::nullopt;
        }

        // (optional) bad-words list — same raw sol read as view_session.cpp:271.
        // MAIN THREAD ONLY (touches the shared Lua state). Returns an error reason
        // on a match, std::nullopt otherwise.
        auto checkBannedWords(const std::string& name) -> std::optional<std::string>
        {
            const auto loginSettingsTable = lua["xi"]["settings"]["login"].get<sol::table>();
            if (auto badWordsList = loginSettingsTable.get_or<sol::table>("BANNED_WORDS_LIST", sol::lua_nil); badWordsList.valid())
            {
                std::string upperName = name;
                std::transform(upperName.begin(), upperName.end(), upperName.begin(),
                               [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
                for (const auto& entry : badWordsList)
                {
                    std::string badWord = entry.second.as<std::string>();
                    std::transform(badWord.begin(), badWord.end(), badWord.begin(),
                                   [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
                    if (upperName.find(badWord) != std::string::npos)
                    {
                        return fmt::format("Name matched with bad words list <{}>.", badWord);
                    }
                }
            }
            return std::nullopt;
        }

        // -----------------------------------------------------------------
        // Roll back a partially-created character. Called when a later INSERT
        // fails after the account row already landed, so we never leak an
        // orphan account / half-char.
        // -----------------------------------------------------------------
        void rollbackChar(uint32 accid, uint32 charid)
        {
            static const char* charTables[] = {
                "chars", "char_look", "char_stats", "char_exp", "char_flags",
                "char_jobs", "char_points", "char_unlocks", "char_profile",
                "char_storage", "char_inventory", "char_vars"
            };
            for (const auto* table : charTables)
            {
                db::preparedStmt(fmt::format("DELETE FROM {} WHERE charid = ?", table), charid);
            }
            db::preparedStmt("DELETE FROM accounts WHERE id = ?", accid);
        }

        // -----------------------------------------------------------------
        // Create the account + character DB rows. Map-side replica of
        // loginHelpers::saveCharacter (which lives only in xi_connect_lib and is
        // not linked into the map target) plus the LOGIN_CREATE account INSERT.
        // Returns the new charid on success, std::nullopt on failure (after
        // cleaning up any partial rows).
        // -----------------------------------------------------------------
        auto createAccountAndChar(const CreateOp& op) -> std::optional<uint32>
        {
            // accid = MAX(id)+1, floored to 1000 (auth_session.cpp:346-357)
            uint32     accid    = 0;
            const auto rsetAcc  = db::preparedStmt("SELECT COALESCE(MAX(id), 0) AS max_id FROM accounts");
            if (rsetAcc && rsetAcc->rowsCount() != 0 && rsetAcc->next())
            {
                accid = rsetAcc->get<uint32>("max_id") + 1;
            }
            else
            {
                return std::nullopt;
            }
            accid = std::max<uint32>(accid, 1000);

            // status 1 = NORMAL, priv 1 = USER (schema defaults; the enums live
            // in login-only auth_session.h which the map target does not link).
            const auto rsetIns = db::preparedStmt(
                "INSERT INTO accounts(id, login, password, timecreate, status, priv) "
                "VALUES(?, ?, ?, NOW(), 1, 1)",
                accid, op.name, BCrypt::generateHash("password"));
            if (!rsetIns)
            {
                return std::nullopt;
            }

            // charid = MAX(charid)+1 (login_helpers.cpp:324)
            uint32     charid    = 0;
            const auto rsetChar  = db::preparedStmt("SELECT COALESCE(MAX(charid), 0) AS max_id FROM chars");
            if (rsetChar && rsetChar->rowsCount() != 0 && rsetChar->next())
            {
                charid = rsetChar->get<uint32>("max_id") + 1;
            }
            if (charid == 0)
            {
                db::preparedStmt("DELETE FROM accounts WHERE id = ?", accid);
                return std::nullopt;
            }

            const uint16 posZone = nationStartZone(op.nation);

            // Replica of loginHelpers::saveCharacter (login_helpers.cpp:170-247).
            // Every statement mirrors the login server, in the same order.
            bool ok = true;
            ok = ok && db::preparedStmt("INSERT INTO chars(charid, accid, charname, pos_zone, nation) VALUES(?, ?, ?, ?, ?)",
                                        charid, accid, op.name, posZone, op.nation);
            ok = ok && db::preparedStmt("INSERT INTO char_look(charid, face, race, size) VALUES(?, ?, ?, ?)",
                                        charid, op.face, op.race, op.size);
            ok = ok && db::preparedStmt("INSERT INTO char_stats(charid, mjob) VALUES(?, ?)", charid, op.mjob);
            ok = ok && db::preparedStmt("INSERT INTO char_exp(charid) VALUES(?) ON DUPLICATE KEY UPDATE charid = charid", charid);
            ok = ok && db::preparedStmt("INSERT INTO char_flags(charid) VALUES(?) ON DUPLICATE KEY UPDATE disconnecting = disconnecting", charid);
            ok = ok && db::preparedStmt("INSERT INTO char_jobs(charid) VALUES(?) ON DUPLICATE KEY UPDATE charid = charid", charid);
            ok = ok && db::preparedStmt("INSERT INTO char_points(charid) VALUES(?) ON DUPLICATE KEY UPDATE charid = charid", charid);
            ok = ok && db::preparedStmt("INSERT INTO char_unlocks(charid) VALUES(?) ON DUPLICATE KEY UPDATE charid = charid", charid);
            ok = ok && db::preparedStmt("INSERT INTO char_profile(charid) VALUES(?) ON DUPLICATE KEY UPDATE charid = charid", charid);
            ok = ok && db::preparedStmt("INSERT INTO char_storage(charid) VALUES(?) ON DUPLICATE KEY UPDATE charid = charid", charid);
            ok = ok && db::preparedStmt("DELETE FROM char_inventory WHERE charid = ?", charid);
            ok = ok && db::preparedStmt("INSERT INTO char_inventory(charid) VALUES(?)", charid);

            // Retail seeds the intro-cutscene charvar when the CS is enabled; the
            // post-CS stamp (Lua) clears it back to 0 so first login is silent.
            if (settings::get<bool>("main.NEW_CHARACTER_CUTSCENE"))
            {
                ok = ok && db::preparedStmt("INSERT INTO char_vars(charid, varname, value) VALUES(?, ?, ?)",
                                            charid, "HQuest[newCharacterCS]notSeen", 1);
            }

            if (!ok)
            {
                rollbackChar(accid, charid);
                return std::nullopt;
            }

            return charid;
        }

        // -----------------------------------------------------------------
        // POST /chars/create
        // Body: { "name": "...", "race": 1-8, "face": 0-15, "size": 0-2,
        //         "nation": 0-2, "job": 1-6 }
        // -----------------------------------------------------------------
        auto parseJsonBody(const httplib::Request& req, httplib::Response& res) -> std::optional<json>
        {
            if (req.body.empty())
            {
                res.status = 400;
                res.set_content(R"({"error":"empty body"})", "application/json");
                return std::nullopt;
            }
            try
            {
                return json::parse(req.body);
            }
            catch (const std::exception& e)
            {
                res.status = 400;
                res.set_content(fmt::format(R"({{"error":"bad json: {}"}})", e.what()), "application/json");
                return std::nullopt;
            }
        }

        void handleCreate(const httplib::Request& req, httplib::Response& res)
        {
            // creation-enabled gates (retail: view_session.cpp:200-202 + auth_session.cpp:325)
            if (settings::get<uint8>("login.MAINT_MODE") > 0 ||
                !settings::get<bool>("login.CHARACTER_CREATION") ||
                !settings::get<bool>("login.ACCOUNT_CREATION"))
            {
                res.status = 403;
                res.set_content(R"({"error":"character creation disabled"})", "application/json");
                return;
            }

            auto body = parseJsonBody(req, res);
            if (!body.has_value())
            {
                return;
            }

            CreateOp op{};
            try
            {
                op.name   = body->at("name").get<std::string>();
                op.race   = body->at("race").get<uint8>();
                op.face   = body->at("face").get<uint8>();
                op.size   = body->at("size").get<uint8>();
                op.nation = body->at("nation").get<uint8>();
                op.mjob   = body->at("job").get<uint8>();
            }
            catch (const std::exception& e)
            {
                res.status = 400;
                res.set_content(fmt::format(R"({{"error":"bad payload: {}"}})", e.what()), "application/json");
                return;
            }

            // Look / nation validation — retail rejects out-of-range race/size/
            // face/nation (login_helpers.cpp:262-299) and clamps the job to a
            // starting job (login_helpers.cpp:282).
            if (op.race < 1 || op.race > 8 || op.size > 2 || op.face > 15 || op.nation > 2)
            {
                res.status = 400;
                res.set_content(R"({"error":"invalid look or nation"})", "application/json");
                return;
            }
            op.mjob = std::clamp<uint8>(op.mjob, 1, 6);

            if (const auto reason = validateName(op.name); reason.has_value())
            {
                res.status = 400;
                res.set_content(fmt::format(R"({{"error":"{}"}})", *reason), "application/json");
                return;
            }

            const std::string opId = op_registry::enqueue("char_create", op);
            res.status             = 202;
            json j;
            j["opId"] = opId;
            res.set_content(j.dump(), "application/json");
            res.set_header("Cache-Control", "no-cache");
        }

        // -----------------------------------------------------------------
        // Main-thread applier — account/char INSERT, then LoadChar (which runs
        // charCreate because playtime == 0), stamp the post-cutscene end-state,
        // persist, and bump playtime so charCreate never re-fires.
        //
        // NOTE: the LoadChar + persist section is finalized against the
        // entity-lifecycle recipe (scheduler/config access, persist set,
        // playtime bump).
        // -----------------------------------------------------------------
        void applyCreate(const std::string& opId, const CreateOp& op)
        {
            // Re-validate the name on the main thread: another create could have
            // landed between the HTTP-thread check and now. The bad-words check
            // (Lua) only runs here, never on the HTTP worker thread.
            if (const auto reason = validateName(op.name); reason.has_value())
            {
                op_registry::markFailed(opId, *reason);
                return;
            }
            if (const auto reason = checkBannedWords(op.name); reason.has_value())
            {
                op_registry::markFailed(opId, *reason);
                return;
            }

            const auto charIdOpt = createAccountAndChar(op);
            if (!charIdOpt.has_value())
            {
                op_registry::markFailed(opId, "failed to create account/character rows");
                return;
            }

            // Load the new char (runs xi.player.charCreate because playtime == 0),
            // stamp the post-cutscene end-state, persist, and bump playtime so
            // charCreate never re-fires. Needs the session container's
            // scheduler_/config_ for LoadChar, so it lives as a container method.
            if (!mapsessions::get().provisionNewCharacter(*charIdOpt))
            {
                // Rows exist but charCreate/persist failed. Roll the char back so a
                // retry with the same name isn't blocked by a half-provisioned char.
                uint32     accid    = 0;
                const auto rsetAcc  = db::preparedStmt("SELECT accid FROM chars WHERE charid = ?", *charIdOpt);
                if (rsetAcc && rsetAcc->rowsCount() != 0 && rsetAcc->next())
                {
                    accid = rsetAcc->get<uint32>("accid");
                }
                rollbackChar(accid, *charIdOpt);
                op_registry::markFailed(opId, "failed to provision new character");
                return;
            }

            op_registry::markSuccess(opId, fmt::format("created charid {}", *charIdOpt));
        }

        // -----------------------------------------------------------------
        // POST /chars/create-preview  { "race": 1-8, "job": 1-6 }
        //
        // Returns the starting stats + gear a new char of (race, job) WOULD get,
        // for the create-tab right column, without creating anything. Gear comes
        // from xi.player.charCreatePreview (the same tables charCreate applies, so
        // it stays in sync); stats are the level-1 grade-table values. Async like
        // create because the gear read touches Lua (main-thread only). The payload
        // rides back in the op's success message; the addon json-decodes it.
        // -----------------------------------------------------------------
        struct PreviewOp
        {
            uint8 race; // 1-8
            uint8 job;  // 1-6
        };

        // Encoded look.race (1-8) -> the 0-4 race index the grade tables use
        // (gender-agnostic; mirrors the switch in charutils::CalculateStats).
        auto raceGradeIndex(uint8 race) -> uint8
        {
            switch (race)
            {
                case 3:
                case 4:  return 1; // Elvaan
                case 5:
                case 6:  return 2; // Tarutaru
                case 7:  return 3; // Mithra
                case 8:  return 4; // Galka
                default: return 0; // Hume
            }
        }

        void handlePreview(const httplib::Request& req, httplib::Response& res)
        {
            auto body = parseJsonBody(req, res);
            if (!body.has_value())
            {
                return;
            }
            PreviewOp op{};
            try
            {
                op.race = body->at("race").get<uint8>();
                op.job  = body->at("job").get<uint8>();
            }
            catch (const std::exception& e)
            {
                res.status = 400;
                res.set_content(fmt::format(R"({{"error":"bad payload: {}"}})", e.what()), "application/json");
                return;
            }
            if (op.race < 1 || op.race > 8 || op.job < 1 || op.job > 6)
            {
                res.status = 400;
                res.set_content(R"({"error":"invalid race or job"})", "application/json");
                return;
            }
            const std::string opId = op_registry::enqueue("char_create_preview", op);
            res.status             = 202;
            json j;
            j["opId"] = opId;
            res.set_content(j.dump(), "application/json");
            res.set_header("Cache-Control", "no-cache");
        }

        void applyPreview(const std::string& opId, const PreviewOp& op)
        {
            const uint8   r = raceGradeIndex(op.race);
            const JOBTYPE j = static_cast<JOBTYPE>(op.job);

            // Level-1 stats: every level-scaling term in CalculateStats is 0 at
            // level 1, leaving race-base + job-base from grade column 0.
            json stats;
            stats["hp"] = static_cast<int>(grade::GetHPScale(grade::GetRaceGrades(r, 0), 0) +
                                           grade::GetHPScale(grade::GetJobGrade(j, 0), 0));

            int mp = 0;
            if (grade::GetJobGrade(j, 1) > 0) // job has an MP rating
            {
                mp = static_cast<int>(grade::GetMPScale(grade::GetRaceGrades(r, 1), 0) +
                                      grade::GetMPScale(grade::GetJobGrade(j, 1), 0));
            }
            stats["mp"] = mp;

            // Stat indices 2..8 = STR, DEX, VIT, AGI, INT, MND, CHR.
            static const char* kStatKeys[] = { "str", "dex", "vit", "agi", "int", "mnd", "chr" };
            for (uint8 s = 2; s <= 8; ++s)
            {
                stats[kStatKeys[s - 2]] = static_cast<int>(grade::GetStatScale(grade::GetRaceGrades(r, s), 0) +
                                                           grade::GetStatScale(grade::GetJobGrade(j, s), 0));
            }

            // Starting gear from the same Lua tables charCreate applies.
            json equipped  = json::array();
            json inventory = json::array();
            const auto preview = luautils::callGlobal<sol::table>("xi.player.charCreatePreview", op.race, op.job);
            if (preview.valid())
            {
                if (sol::optional<sol::table> eq = preview["equipped"]; eq)
                {
                    for (auto& kv : *eq) { equipped.push_back(kv.second.as<uint16>()); }
                }
                if (sol::optional<sol::table> inv = preview["inventory"]; inv)
                {
                    for (auto& kv : *inv) { inventory.push_back(kv.second.as<uint16>()); }
                }
            }

            json out;
            out["stats"]     = stats;
            out["equipped"]  = equipped;  // item ids; the addon resolves names
            out["inventory"] = inventory;
            op_registry::markSuccess(opId, out.dump());
        }
    } // namespace

    void registerRoutes(httplib::Server& server)
    {
        server.Post("/chars/create", handleCreate);
        server.Post("/chars/create-preview", handlePreview);
    }

    void drainOps()
    {
        op_registry::drain(
            [](const std::string& opId, const std::string& kind, const std::any& payload)
            {
                try
                {
                    if (kind == "char_create")
                    {
                        applyCreate(opId, std::any_cast<CreateOp>(payload));
                    }
                    else if (kind == "char_create_preview")
                    {
                        applyPreview(opId, std::any_cast<PreviewOp>(payload));
                    }
                    // Other kinds ignored — auction_http / char_http own theirs.
                }
                catch (const std::bad_any_cast& e)
                {
                    op_registry::markFailed(opId, fmt::format("payload cast: {}", e.what()));
                }
            });
    }
} // namespace singleplayer::char_create
