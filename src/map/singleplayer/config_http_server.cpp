/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "config_http_server.h"

#include "auction_http.h"
#include "bot_state_cache.h"
#include "char_http.h"
#include "config_cache.h"

#include "common/database.h"
#include "common/logging.h"
#include "common/settings.h"

#include <algorithm>
#include <atomic>
#include <map>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include <httplib.h>
#include <nlohmann/json.hpp>

namespace singleplayer
{
namespace config_http_server
{
    using json = nlohmann::json;

    namespace
    {
        // The listener lives in this anonymous namespace as static state.
        // Mirrors the world HTTPServer shape — server + thread, the thread
        // blocks in listen() and the server's stop() unblocks it.
        std::unique_ptr<httplib::Server> gServer;
        std::thread                      gThread;
        std::atomic<bool>                gRunning{ false };

        // Pick a Content-Type from the cached file extension. Falls back
        // to text/plain for unknown ext so callers can still consume the
        // body — the cache already includes the file extension since the
        // addons need it for save-back path resolution.
        auto contentTypeFor(const std::string& ext) -> std::string
        {
            if (ext == ".xml")  { return "application/xml"; }
            if (ext == ".json") { return "application/json"; }
            if (ext == ".lua")  { return "text/x-lua";      }
            if (ext == ".txt")  { return "text/plain";      }
            return "text/plain";
        }

        // Inverse of contentTypeFor for the PUT path: trim any "; charset=..."
        // suffix httplib may have parsed in, then map back to an extension we
        // know how to persist. Returns empty string for unsupported types so
        // the caller can reject with 415.
        auto extensionForContentType(std::string ct) -> std::string
        {
            const auto semi = ct.find(';');
            if (semi != std::string::npos)
            {
                ct.erase(semi);
            }
            // Trim trailing whitespace.
            while (!ct.empty() && (ct.back() == ' ' || ct.back() == '\t'))
            {
                ct.pop_back();
            }
            if (ct == "application/xml")  { return ".xml";  }
            if (ct == "application/json") { return ".json"; }
            if (ct == "text/x-lua")       { return ".lua";  }
            if (ct == "text/plain")       { return ".txt";  }
            return {};
        }

        // Reject path components that could escape the configcache root.
        // The route regex already enforces "no slash," but a name like ".."
        // or a leading "." would still be accepted by the regex and could
        // resolve into the parent dir via fs::path joining.
        auto safeComponent(const std::string& s) -> bool
        {
            if (s.empty())        { return false; }
            if (s.front() == '.') { return false; }  // catches "." and ".."
            for (char c : s)
            {
                if (c == '\\' || c == '\0')
                {
                    return false;
                }
            }
            return true;
        }

        // Quoted-ETag from mtime. Spec-compliant strong validator format;
        // matches what the addon's If-None-Match header will echo back.
        auto etagFor(int64_t mtime) -> std::string
        {
            return fmt::format("\"{}\"", mtime);
        }

        // GET /chars — JSON array of every character row, sorted by name.
        // Each entry: { "name": "Brutus", "mjob": 8 }. Replaces the prior
        // chunked 0x18D/0x18E packet pair the AutoBots/AutoEquip/AutoMog/
        // AutoSkill addons used for their char-selector dropdowns.
        //
        // Threading: this handler runs on httplib's worker pool. db::
        // preparedStmt routes through detail::getState().write which
        // serializes DB access via an internal lock, so the call is safe
        // off the main thread.
        //
        // mjob lives in char_stats (rows created on first character setup);
        // LEFT JOIN so chars without a stats row still appear with mjob=0.
        void handleListChars(const httplib::Request& /*req*/, httplib::Response& res)
        {
            json arr = json::array();
            const auto rset = db::preparedStmt(
                "SELECT chars.charname AS charname, "
                "       COALESCE(char_stats.mjob, 0) AS mjob "
                "FROM chars "
                "LEFT JOIN char_stats ON chars.charid = char_stats.charid "
                "ORDER BY chars.charname");
            if (rset)
            {
                while (rset->next())
                {
                    json entry;
                    entry["name"] = rset->get<std::string>("charname");
                    entry["mjob"] = rset->get<uint8>("mjob");
                    arr.push_back(entry);
                }
            }
            res.set_content(arr.dump(), "application/json");
            res.set_header("Cache-Control", "no-cache");
        }

        // GET /nms?lo=<int>&hi=<int>&limit=<int> — JSON array of every
        // notorious-monster spawn point whose [minLevel,maxLevel] overlaps
        // [lo,hi]. Bounds default to 1..99 when missing/unparseable so a
        // query-string-less hit still returns the full NM list. lo and hi
        // may be negative coming in (client-side "your level - 5"); clamped
        // to >=1 here since FFXI levels live in [1, 99]. limit defaults to
        // kDefaultLimit and is hard-capped at kMaxLimit — the addon UI
        // sweats badly at multi-thousand-row lists, and the wire bandwidth
        // is wasted on rows the user scrolls past.
        //
        // Output entries: { id, name, lo, hi, zoneid, zone }. id is the
        // composite mobid (zoneid << 12 | per-zone index) so the client can
        // disambiguate when several zones share an NM name. mobType is read
        // from mob_pools and masked against MOBTYPE_NOTORIOUS (0x02).
        //
        // Critical JOIN detail: mob_groups PRIMARY KEY is (zoneid, groupid),
        // meaning the same groupid exists in every zone with different
        // payload data. Joining only on groupid produced a cartesian-
        // product explosion (one spawn point × every zone's row for that
        // groupid), e.g. a 42 MB response for what should have been a few
        // hundred NMs. The fix is to also constrain on zoneid, which we
        // recover from the spawn point's mobid encoding: bits 12-23 of
        // mobid are the zoneid, so the canonical extraction is
        //   ((mobid >> 12) & 0xFFF)
        // The high bits beyond 0xFFF are NOT zero in practice (mobids run
        // 0x010_0000+), so the mask is required — see zoneutils.cpp:439
        // and instance_loader.cpp:93 for the same pattern.
        //
        // Threading note matches handleListChars — db::preparedStmt is
        // safe off the main thread.
        void handleListNMs(const httplib::Request& req, httplib::Response& res)
        {
            constexpr int kDefaultLimit = 500;
            constexpr int kMaxLimit     = 1000;

            auto parseBound = [&](const std::string& key, int dflt) -> int
            {
                auto it = req.params.find(key);
                if (it == req.params.end()) return dflt;
                try { return std::stoi(it->second); } catch (...) { return dflt; }
            };
            int lo    = std::clamp(parseBound("lo",  1),  1, 99);
            int hi    = std::clamp(parseBound("hi", 99),  1, 99);
            int limit = std::clamp(parseBound("limit", kDefaultLimit), 1, kMaxLimit);
            if (lo > hi) std::swap(lo, hi);

            json arr = json::array();
            // Pull polutils_name (wiki-friendly capitalization) when present,
            // otherwise fall back to mobname. (mg.zoneid = msp.mobid >> 12)
            // is the cartesian-product fix — see comment above.
            const auto rset = db::preparedStmt(
                "SELECT msp.mobid AS mobid, "
                "       COALESCE(NULLIF(msp.polutils_name, ''), msp.mobname) AS name, "
                "       msp.minLevel AS minLevel, "
                "       msp.maxLevel AS maxLevel, "
                "       mg.zoneid    AS zoneid,  "
                "       COALESCE(zs.name, '?')   AS zonename "
                "FROM mob_spawn_points msp "
                "JOIN mob_groups  mg ON mg.groupid = msp.groupid "
                "                   AND mg.zoneid  = ((msp.mobid >> 12) & 0xFFF) "
                "JOIN mob_pools   mp ON mp.poolid  = mg.poolid "
                "LEFT JOIN zone_settings zs ON zs.zoneid = mg.zoneid "
                "WHERE (mp.mobType & 0x02) = 0x02 "
                "  AND msp.maxLevel >= ? "
                "  AND msp.minLevel <= ? "
                // Order by level, NOT zoneid — when the level band matches more
                // NMs than the LIMIT, truncation should drop the highest-level
                // (least-relevant) ones, not silently cut whole high-zoneid zones
                // (which was hiding in-band NMs like Serket in Kuftal Tunnel).
                "ORDER BY msp.minLevel, name "
                "LIMIT ?",
                lo, hi, limit);
            if (rset)
            {
                while (rset->next())
                {
                    json entry;
                    entry["id"]     = rset->get<uint32>("mobid");
                    entry["name"]   = rset->get<std::string>("name");
                    entry["lo"]     = rset->get<uint8>("minLevel");
                    entry["hi"]     = rset->get<uint8>("maxLevel");
                    entry["zoneid"] = rset->get<uint16>("zoneid");
                    entry["zone"]   = rset->get<std::string>("zonename");
                    arr.push_back(entry);
                }
            }
            res.set_content(arr.dump(), "application/json");
            res.set_header("Cache-Control", "no-cache");
        }

        // GET /nms/<mobid>/drops — drop list for a single NM. Resolves
        // mobid → mob_groups → mob_droplist via the same zoneid-masked
        // JOIN as handleListNMs. Filters to dropType=0 (kill drops; steal /
        // despoil are separate mechanics, excluded). Grouped rare-or-ex rows
        // (groupId > 0) ARE included now — an NM's signature loot frequently
        // lives in a "rolls one of this pool" group, so excluding them hid
        // real drops. DISTINCT collapses fanout from multiple spawn-point rows
        // sharing a group. itemRate is sent raw — the addon formats it (/10.0);
        // for grouped rows that's the within-group weight, not an absolute rate.
        void handleNMDrops(const httplib::Request& req, httplib::Response& res)
        {
            uint32 mobid = 0;
            try { mobid = static_cast<uint32>(std::stoul(req.matches[1])); }
            catch (...) { res.status = 400; return; }

            json arr = json::array();
            const auto rset = db::preparedStmt(
                "SELECT DISTINCT md.itemId AS itemId, md.itemRate AS rate "
                "FROM mob_spawn_points msp "
                "JOIN mob_groups   mg ON mg.groupid = msp.groupid "
                "                    AND mg.zoneid  = ((msp.mobid >> 12) & 0xFFF) "
                "JOIN mob_droplist md ON md.dropid  = mg.dropid "
                "WHERE msp.mobid    = ? "
                "  AND md.dropType  = 0 "
                "ORDER BY md.itemRate DESC, md.itemId",
                mobid);
            if (rset)
            {
                while (rset->next())
                {
                    json entry;
                    entry["itemId"] = rset->get<uint32>("itemId");
                    entry["rate"]   = rset->get<uint32>("rate");
                    arr.push_back(entry);
                }
            }
            res.set_content(arr.dump(), "application/json");
            res.set_header("Cache-Control", "no-cache");
        }

        // GET /healthz — addon's existence probe. Single short response,
        // no cache touch, no allocation worth speaking of. Used during
        // addon startup to decide "HTTP path available" vs "fall back to
        // the legacy 0x17E packet path."
        void handleHealthz(const httplib::Request& /*req*/, httplib::Response& res)
        {
            res.set_content("ok", "text/plain");
        }

        // GET /configs — JSON object { category: count }. Counts come
        // from one configcache::forEach walk. Stable ordering is provided
        // by std::map (lexicographic) so addon pickers don't jitter.
        void handleListAll(const httplib::Request& /*req*/, httplib::Response& res)
        {
            std::map<std::string, uint32_t> counts;
            configcache::forEach(
                [&counts](const std::string& category,
                          const std::string& /*name*/,
                          const configcache::ConfigEntry& /*entry*/)
                {
                    counts[category] += 1;
                });

            json j = json::object();
            for (const auto& [cat, n] : counts)
            {
                j[cat] = n;
            }
            res.set_content(j.dump(), "application/json");
        }

        // GET /configs/{category} — JSON { names: [...] } for one
        // category. Names are sorted (forEachInCategory's underlying iter
        // doesn't promise an order, so we collect then sort). Empty list
        // is the correct response for a category that has no files —
        // 404 is reserved for "this category isn't a real bucket," which
        // configcache doesn't currently distinguish.
        void handleListCategory(const httplib::Request& req, httplib::Response& res)
        {
            const std::string category = req.matches[1].str();

            std::vector<std::string> names;
            configcache::forEachInCategory(category,
                [&names](const std::string& name, const configcache::ConfigEntry& /*entry*/)
                {
                    names.push_back(name);
                });
            std::sort(names.begin(), names.end());

            json j;
            j["names"] = names;
            res.set_content(j.dump(), "application/json");
        }

        // GET /configs/{category}/{name} — raw file body. ETag is the
        // cached mtime; If-None-Match → 304 fast path saves the body
        // transfer on unchanged files. addon-side opens for view +
        // refreshes don't pay the body cost when nothing's edited.
        void handleGetContent(const httplib::Request& req, httplib::Response& res)
        {
            const std::string category = req.matches[1].str();
            const std::string name     = req.matches[2].str();
            if (!safeComponent(category) || !safeComponent(name))
            {
                res.status = 400;
                return;
            }

            const auto* entry = configcache::get(category, name);
            if (entry == nullptr)
            {
                res.status = 404;
                return;
            }

            const std::string etag = etagFor(entry->mtime);
            res.set_header("ETag", etag);
            res.set_header("Cache-Control", "no-cache"); // always revalidate

            // Conditional GET — addon caches the body keyed by ETag and
            // re-asks with If-None-Match on every fetch. Saves the wire
            // copy on the common "open the same config twice" flow.
            const std::string inm = req.get_header_value("If-None-Match");
            if (!inm.empty() && inm == etag)
            {
                res.status = 304;
                return;
            }

            res.set_content(entry->body, contentTypeFor(entry->ext));
        }

        // PUT /configs/{category}/{name} — create or replace. Body is the
        // new content; Content-Type picks the extension on disk
        // (application/xml → .xml, application/json → .json, text/x-lua →
        // .lua, text/plain → .txt). When replacing an existing entry, the
        // server prefers the existing extension over the request's
        // Content-Type — a Zariah_THF.xml stays .xml even if the PUT
        // tagged the body as text/plain. That keeps addons from
        // accidentally duplicating files with different extensions when
        // they upload with a sloppy header.
        //
        // Returns 201 Created on first PUT, 200 OK on replace.
        void handlePutContent(const httplib::Request& req, httplib::Response& res)
        {
            const std::string category = req.matches[1].str();
            const std::string name     = req.matches[2].str();
            if (!safeComponent(category) || !safeComponent(name))
            {
                res.status = 400;
                return;
            }

            std::string ext;
            const auto* existing = configcache::get(category, name);
            const bool  isNew    = (existing == nullptr);
            if (existing != nullptr)
            {
                ext = existing->ext;
            }
            else
            {
                ext = extensionForContentType(req.get_header_value("Content-Type"));
                if (ext.empty())
                {
                    res.status = 415; // Unsupported Media Type
                    res.set_content("Content-Type must be one of: application/xml, "
                                    "application/json, text/x-lua, text/plain",
                                    "text/plain");
                    return;
                }
            }

            if (!configcache::putAndPersist(category, name, req.body, ext))
            {
                res.status = 500;
                res.set_content("configcache write failed", "text/plain");
                return;
            }

            // Stamp the new ETag so the client can keep its cache aligned
            // without immediately re-GETting. mtime advances on the disk
            // write inside putAndPersist.
            if (const auto* fresh = configcache::get(category, name))
            {
                res.set_header("ETag", etagFor(fresh->mtime));
            }
            res.status = isNew ? 201 : 200;
        }

        // GET /bot-state?for=<charName> — JSON snapshot of the named primary's
        // alliance-wide + per-bot config state. Replaces the legacy 0x1A5
        // BOT_STATE_SNAPSHOT packet, which was bumping FFXI's 504-byte wire
        // ceiling once per-bot fields were added. The snapshot is published
        // from Lua (bots.publish_state_snapshot) on the main thread at
        // onBotTick cadence (~400ms); this handler just reads the cached
        // string. No SQL hop, no Lua call from the worker thread.
        //
        // Response: 200 with JSON body when a snapshot is cached, 404 when
        // the named char has no snapshot (alliance never spawned, primary
        // not online, or first request before the first publish fired).
        // 400 when the for= param is missing or invalid.
        void handleBotState(const httplib::Request& req, httplib::Response& res)
        {
            const auto it = req.params.find("for");
            if (it == req.params.end() || it->second.empty())
            {
                res.status = 400;
                res.set_content("missing for= query param", "text/plain");
                return;
            }
            const std::string& charName = it->second;
            // Reject obviously bogus names — FFXI chars are <= 15 chars and
            // never contain control characters or path separators. A slow-
            // path SQL lookup happens nowhere in this handler, but pruning
            // garbage saves log noise on misbehaving callers.
            if (charName.size() > 15)
            {
                res.status = 400;
                return;
            }
            for (char c : charName)
            {
                if (c < 0x20 || c == '/' || c == '\\')
                {
                    res.status = 400;
                    return;
                }
            }

            const std::string snapshot = botstate::getSnapshot(charName);
            if (snapshot.empty())
            {
                res.status = 404;
                return;
            }
            res.set_content(snapshot, "application/json");
            res.set_header("Cache-Control", "no-cache");
        }

        // DELETE /configs/{category}/{name}. 204 No Content on success,
        // 404 when the file wasn't there (idempotency would prefer 204
        // either way, but distinguishing helps the addon tell "I just
        // raced another writer" from "OK, gone").
        void handleDeleteContent(const httplib::Request& req, httplib::Response& res)
        {
            const std::string category = req.matches[1].str();
            const std::string name     = req.matches[2].str();
            if (!safeComponent(category) || !safeComponent(name))
            {
                res.status = 400;
                return;
            }

            if (configcache::erase(category, name))
            {
                res.status = 204;
                return;
            }
            res.status = 404;
        }
    } // namespace

    void initialize()
    {
        if (gRunning.load())
        {
            ShowWarning("config_http_server::initialize called twice; ignoring");
            return;
        }

        // Read configurable knobs from settings/singleplayer.lua. End-user
        // deployments vary (loopback-only, VM-host-NAT, LAN-exposed) and the
        // FFXI server's port range may conflict with other services on the
        // host — both have to be adjustable without a recompile.
        const auto bindAddr = settings::get<std::string>("singleplayer.CONFIG_HTTP_BIND_ADDR");
        const auto port     = settings::get<uint16>("singleplayer.CONFIG_HTTP_PORT");

        gServer = std::make_unique<httplib::Server>();

        // Tight timeouts. Loopback latency is sub-millisecond, so generous
        // upstream defaults (5s read, 5s write) would only ever paper over
        // bugs. 1s here is still 1000× the expected RTT.
        gServer->set_read_timeout(1, 0);
        gServer->set_write_timeout(1, 0);

        gServer->Get("/healthz", handleHealthz);
        gServer->Get("/chars",    handleListChars);
        gServer->Get("/nms",      handleListNMs);
        gServer->Get(R"(/nms/(\d+)/drops)", handleNMDrops);
        gServer->Get("/bot-state", handleBotState);
        gServer->Get("/configs",  handleListAll);
        gServer->Get(R"(/configs/([^/]+))",            handleListCategory);
        gServer->Get(R"(/configs/([^/]+)/([^/]+))",    handleGetContent);
        gServer->Put(R"(/configs/([^/]+)/([^/]+))",    handlePutContent);
        gServer->Delete(R"(/configs/([^/]+)/([^/]+))", handleDeleteContent);

        // /ah/* + /ops/<opId> — custom AH backend for automog. Reads hit the
        // DB on this HTTP thread; writes enqueue into op_registry and are
        // drained on the main thread in post_tick. See auction_http.cpp.
        auction_http::registerRoutes(*gServer);

        // /chars/<name>/{inventory,sort-inventory} — replaces the 0x16D/0x18F
        // packet inventory fetches. Read is a plain DB query on this thread;
        // the sort enqueues an op drained on the main thread. See char_http.cpp.
        char_http::registerRoutes(*gServer);

        // Body cap. Largest configs today are autoequip XMLs (~100 KB);
        // 4 MB is a generous ceiling that still rejects pathological
        // uploads. cpp-httplib drops connections exceeding this with
        // a 413 before the route handler is invoked.
        gServer->set_payload_max_length(4 * 1024 * 1024);

        // TEMPORARY (perf-analysis pass, 2026-06-20): log EVERY request
        // with method, path, status, and body sizes so we can audit how
        // often the addon side is calling each endpoint and spot any
        // per-frame fetch loops. Remove or downgrade to >=400 only when
        // perf review is done. Marked with a [HTTP-ACCESS] tag so the
        // grep target is unambiguous later.
        gServer->set_logger(
            [](const httplib::Request& req, const httplib::Response& res)
            {
                ShowInfo(fmt::format(
                    "[HTTP-ACCESS] {} {} -> {} (reqBody={}B respBody={}B)",
                    req.method, req.path, res.status,
                    req.body.size(), res.body.size()));
                if (res.status >= 400)
                {
                    ShowWarning(fmt::format(
                        "config_http_server: {} {} -> {}",
                        req.method, req.path, res.status));
                }
            });

        // Pre-bind probe. httplib::Server::listen returns false on bind
        // failure but only after spawning the accept thread, so we'd hit
        // a race detecting bind state from the boot thread. bind_to_port
        // synchronously attempts the bind and reports — call it here so
        // we fail loud BEFORE detaching the listener thread.
        const int boundPort = gServer->bind_to_port(bindAddr, port);
        if (boundPort == 0)
        {
            ShowCritical(fmt::format(
                "config_http_server: failed to bind {}:{} — "
                "another process is using the port. Addon HTTP config "
                "fetch will be unavailable.", bindAddr, port));
            gServer.reset();
            return;
        }

        gRunning.store(true);

        // listen_after_bind blocks the calling thread, so we detach a
        // dedicated listener thread. Routes execute on httplib's per-
        // request worker pool (separate threads still), so route handlers
        // must respect configcache's internal mutex — which they already
        // do because every public configcache function takes it.
        gThread = std::thread(
            [&]()
            {
                gServer->listen_after_bind();
            });

        ShowInfo(fmt::format("config_http_server: listening on http://{}:{}", bindAddr, port));
    }

    void shutdown()
    {
        if (!gRunning.exchange(false))
        {
            return;
        }
        if (gServer)
        {
            gServer->stop();
        }
        if (gThread.joinable())
        {
            gThread.join();
        }
        gServer.reset();
    }
} // namespace config_http_server
} // namespace singleplayer
