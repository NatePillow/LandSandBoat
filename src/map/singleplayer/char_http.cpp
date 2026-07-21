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

#include "char_http.h"

#include "op_registry.h"

#include "entities/charentity.h"
#include "item_container.h"
#include "items/item.h"
#include "map_session_container.h"
#include "utils/charutils.h"
#include "utils/zoneutils.h"

#include "common/database.h"
#include "common/logging.h"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <any>
#include <array>
#include <optional>
#include <string>

namespace singleplayer::char_http
{
    using json = nlohmann::json;

    namespace
    {
        constexpr size_t kBagCount    = 18;   // MAX_CONTAINER_ID
        constexpr uint8  kBagUnavail  = 0xFF; // "container does not exist for this char"
        constexpr uint8  kMaxBagSlots = 80;   // CItemContainer::AddBuff clamp

        // -----------------------------------------------------------------
        // Shared helpers
        // -----------------------------------------------------------------
        auto resolveCharIdByName(const std::string& name) -> uint32
        {
            if (name.empty())
            {
                return 0;
            }
            const auto rset = db::preparedStmt(
                "SELECT charid FROM chars WHERE charname = ? LIMIT 1", name);
            if (rset && rset->rowsCount() && rset->next())
            {
                return rset->get<uint32>("charid");
            }
            return 0;
        }

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
                res.set_content(fmt::format(R"({{"error":"bad json: {}"}})", e.what()),
                                "application/json");
                return std::nullopt;
            }
        }

        void writeAcceptedOpId(httplib::Response& res, const std::string& opId)
        {
            res.status = 202;
            json j;
            j["opId"] = opId;
            res.set_content(j.dump(), "application/json");
            res.set_header("Cache-Control", "no-cache");
        }

        // -----------------------------------------------------------------
        // GET /chars/<name>/inventory
        //
        // Unauthenticated, matching GET /chars and GET /ah/listings?for=. The
        // 0x18F packet this replaces DID gate on "target is you, or a headless
        // parented to you" via PSession->parentCharId, but that lives only in
        // memory and has no DB equivalent. Anyone who can reach the port can
        // already enumerate every character through GET /chars.
        // -----------------------------------------------------------------
        void handleInventory(const httplib::Request& req, httplib::Response& res)
        {
            const std::string charName = req.matches[1].str();

            const uint32 charId = resolveCharIdByName(charName);
            if (charId == 0)
            {
                res.status = 404;
                res.set_content(R"({"error":"unknown char"})", "application/json");
                return;
            }

            // Capacities, indexed by CONTAINER_ID (item_container.h).
            //
            // Mirrors charutils::LoadChar's char_storage read. Four bags are
            // NOT columns in that table and have to be reconstructed exactly
            // the way charutils does, or the addon's free-slot math goes wrong:
            //   LOC_STORAGE (2)     — sum of installed furnishings' storage
            //   LOC_TEMPITEMS (3)   — hardcoded 50
            //   LOC_MOGSAFE2 (9)    — shares the `safe` column
            //   LOC_RECYCLEBIN (17) — hardcoded 10
            std::array<uint8, kBagCount> caps{};
            caps.fill(kBagUnavail);

            const auto storageRset = db::preparedStmt(
                "SELECT inventory, safe, locker, satchel, sack, `case`, "
                "       wardrobe, wardrobe2, wardrobe3, wardrobe4, "
                "       wardrobe5, wardrobe6, wardrobe7, wardrobe8 "
                "FROM char_storage WHERE charid = ? LIMIT 1",
                charId);
            if (!storageRset || !storageRset->rowsCount() || !storageRset->next())
            {
                res.status = 404;
                res.set_content(R"({"error":"no char_storage row"})", "application/json");
                return;
            }

            const uint8 safe = storageRset->get<uint8>("safe");
            caps[0]  = storageRset->get<uint8>("inventory");
            caps[1]  = safe;
            caps[3]  = 50;
            caps[4]  = storageRset->get<uint8>("locker");
            caps[5]  = storageRset->get<uint8>("satchel");
            caps[6]  = storageRset->get<uint8>("sack");
            caps[7]  = storageRset->get<uint8>("case");
            caps[8]  = storageRset->get<uint8>("wardrobe");
            caps[9]  = safe;
            caps[10] = storageRset->get<uint8>("wardrobe2");
            caps[11] = storageRset->get<uint8>("wardrobe3");
            caps[12] = storageRset->get<uint8>("wardrobe4");
            caps[13] = storageRset->get<uint8>("wardrobe5");
            caps[14] = storageRset->get<uint8>("wardrobe6");
            caps[15] = storageRset->get<uint8>("wardrobe7");
            caps[16] = storageRset->get<uint8>("wardrobe8");
            caps[17] = 10;

            // LOC_STORAGE: charutils sums getStorage() over furnishings sitting
            // in MOGSAFE/MOGSAFE2 that are flagged installed. The installed bit
            // is Exdata::Furniture::Installed — bit 6 of extra[1]. SUBSTRING is
            // 1-indexed, hence position 2.
            {
                uint32     storageCap = 0;
                const auto rset       = db::preparedStmt(
                    "SELECT COALESCE(SUM(f.storage), 0) AS storage "
                    "FROM char_inventory ci "
                    "JOIN item_furnishing f ON f.itemId = ci.itemId "
                    "WHERE ci.charid = ? AND ci.location IN (1, 9) "
                    "  AND (ORD(SUBSTRING(ci.extra, 2, 1)) & 64) <> 0",
                    charId);
                if (rset && rset->next())
                {
                    storageCap = rset->get<uint32>("storage");
                }
                caps[2] = static_cast<uint8>(std::min<uint32>(storageCap, kMaxBagSlots));
            }

            json items = json::array();
            {
                const auto rset = db::preparedStmt(
                    "SELECT location, slot, itemId, quantity "
                    "FROM char_inventory WHERE charid = ? "
                    "ORDER BY location, slot",
                    charId);
                if (rset)
                {
                    while (rset->next())
                    {
                        const uint8 bag = rset->get<uint8>("location");
                        if (bag >= kBagCount)
                        {
                            continue;
                        }
                        json e;
                        e["bag"]    = bag;
                        e["slot"]   = rset->get<uint8>("slot");
                        e["itemId"] = rset->get<uint16>("itemId");
                        e["count"]  = rset->get<uint32>("quantity");
                        items.push_back(e);
                    }
                }
            }

            json out;
            out["name"]  = charName;
            out["caps"]  = caps;
            out["items"] = items;
            res.set_content(out.dump(), "application/json");
            res.set_header("Cache-Control", "no-cache");
        }

        // -----------------------------------------------------------------
        // POST /chars/<name>/sort-inventory   body: { "by": <char>, "bag": n }
        // -----------------------------------------------------------------
        struct SortOp
        {
            uint32      requesterCharId; // resolved to CCharEntity* in drainOps
            std::string targetName;
            uint8       bagId;
        };

        void handleSortInventory(const httplib::Request& req, httplib::Response& res)
        {
            auto body = parseJsonBody(req, res);
            if (!body.has_value())
            {
                return;
            }
            SortOp op{};
            op.targetName = req.matches[1].str();
            try
            {
                op.requesterCharId = resolveCharIdByName(body->at("by").get<std::string>());
                op.bagId           = body->value("bag", uint8{ 0 });
            }
            catch (const std::exception& e)
            {
                res.status = 400;
                res.set_content(fmt::format(R"({{"error":"bad payload: {}"}})", e.what()),
                                "application/json");
                return;
            }
            if (op.requesterCharId == 0 || op.targetName.empty() || op.bagId >= kBagCount)
            {
                res.status = 400;
                res.set_content(R"({"error":"missing or invalid fields"})", "application/json");
                return;
            }
            const std::string opId = op_registry::enqueue("char_sort", op);
            writeAcceptedOpId(res, opId);
        }

        // -----------------------------------------------------------------
        // Main-thread appliers
        // -----------------------------------------------------------------
        auto findChar(uint32 charId) -> CCharEntity*
        {
            return charId ? zoneutils::GetChar(charId) : nullptr;
        }

        // Target must be the requester themselves OR a headless sessioned under
        // them. Preserves the authorization rule the 0x1A6 packet enforced —
        // unlike the read path, a sort mutates another char's containers.
        auto resolveTarget(CCharEntity* PRequester, const std::string& name) -> CCharEntity*
        {
            if (name.empty() || PRequester == nullptr)
            {
                return nullptr;
            }
            if (name == PRequester->getName())
            {
                return PRequester;
            }
            CCharEntity* PTarget = zoneutils::GetCharByName(name);
            if (PTarget == nullptr || PTarget->PSession == nullptr)
            {
                return nullptr;
            }
            if (PTarget->PSession->parentCharId != PRequester->id)
            {
                return nullptr;
            }
            return PTarget;
        }

        void applySort(const std::string& opId, const SortOp& op)
        {
            CCharEntity* PRequester = findChar(op.requesterCharId);
            if (PRequester == nullptr)
            {
                op_registry::markFailed(opId, "requester not in-zone");
                return;
            }
            CCharEntity* PTarget = resolveTarget(PRequester, op.targetName);
            if (PTarget == nullptr)
            {
                op_registry::markFailed(opId, "target not owned by requester");
                return;
            }
            CItemContainer* PContainer = PTarget->getStorage(op.bagId);
            if (PContainer == nullptr)
            {
                op_registry::markFailed(opId, "target has no such container");
                return;
            }
            charutils::ConsolidateContainerStacks(PTarget, PContainer);
            op_registry::markSuccess(opId, "sorted");
        }
    } // namespace

    void registerRoutes(httplib::Server& server)
    {
        server.Get(R"(/chars/([^/]+)/inventory)",       handleInventory);
        server.Post(R"(/chars/([^/]+)/sort-inventory)", handleSortInventory);
    }

    void drainOps()
    {
        op_registry::drain(
            [](const std::string& opId, const std::string& kind, const std::any& payload)
            {
                try
                {
                    if (kind == "char_sort")
                    {
                        applySort(opId, std::any_cast<SortOp>(payload));
                    }
                    // Other kinds ignored — this drainer only handles char_*.
                    // auction_http::drainOps has the matching ah_* half.
                }
                catch (const std::bad_any_cast& e)
                {
                    op_registry::markFailed(opId, fmt::format("payload cast: {}", e.what()));
                }
            });
    }
} // namespace singleplayer::char_http
