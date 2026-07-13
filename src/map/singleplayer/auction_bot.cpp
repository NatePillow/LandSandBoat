/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  In-process auction-house bot. See auction_bot.h + #197 for design.

===========================================================================
*/

#include "auction_bot.h"

#include "common/database.h"
#include "common/earth_time.h"
#include "common/logging.h"
#include "common/settings.h"
#include "common/timer.h"

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace singleplayer::auction_bot
{
    namespace fs = std::filesystem;

    namespace
    {
        // Mirrors ffxiahbot/auction/manager.py:246 — UNIX timestamp of
        // 2099-01-01 00:00:00 UTC. Used as the `date` column on every bot
        // listing so search.expireAH's `date < (now - EXPIRE_DAYS)` never
        // matches → listings persist indefinitely.
        constexpr uint32_t kFarFutureDate = 4070908800u; // 2099-01-01 00:00:00 UTC

        // Cap inserts (refill + sellback) per tick. At first tick after boot, the
        // bot has 0 stock for every CSV rule → without a cap, refillPass would
        // fire 14k+ INSERTs in one tick and trip the 2s main-loop watchdog. With
        // the cap, the bot warms up over several seconds. Buy UPDATEs are NOT
        // capped — those run only against actual player listings (usually few).
        constexpr uint32_t kMaxInsertsPerTick = 500;

        struct ItemRule
        {
            uint16_t itemid       = 0;
            bool     sell_single  = false;
            bool     buy_single   = false;
            uint32_t price_single = 0;
            uint8_t  stock_single = 0;
            bool     sell_stacks  = false;
            bool     buy_stacks   = false;
            uint32_t price_stacks = 0;
            uint8_t  stock_stacks = 0;
        };

        struct Config
        {
            bool        enabled               = true;
            uint32_t    seller_char_id        = 0;
            std::string seller_name           = "M.H.M.U.";
            uint32_t    tick_interval_s       = 2;
            uint32_t    max_sellback_listings = 25;
            uint32_t    restock_delay_s       = 0; // hold restock this long after a buyer buys the bot's stock (0 = immediate)
            std::string csv_path              = "singleplayer/config/auction/items.csv";
        };

        Config                                gCfg;
        std::unordered_map<uint16_t, ItemRule> gRules;
        timer::time_point                      gNextTick{};
        bool                                   gReady = false;

        // --------------------------------------------------------------
        // Config loader — reads from settings/singleplayer.lua via the
        // standard settings::get<>() infrastructure (same pattern as the
        // other static singleplayer.* booleans like CUSTOM_TRUST_LOGIC).
        // CSV path stays hardcoded to singleplayer/config/auction/items.csv
        // since it's a fixed asset shipped with the singleplayer fork.
        // --------------------------------------------------------------
        void loadConfig()
        {
            gCfg.enabled               = settings::get<bool>("singleplayer.AUCTION_BOT_ENABLED");
            gCfg.seller_char_id        = settings::get<uint32>("singleplayer.AUCTION_BOT_SELLER_CHAR_ID");
            gCfg.seller_name           = settings::get<std::string>("singleplayer.AUCTION_BOT_SELLER_NAME");
            gCfg.tick_interval_s       = settings::get<uint32>("singleplayer.AUCTION_BOT_TICK_INTERVAL_S");
            gCfg.max_sellback_listings = settings::get<uint32>("singleplayer.AUCTION_BOT_MAX_SELLBACK_LISTINGS");
            gCfg.restock_delay_s       = settings::get<uint32>("singleplayer.AUCTION_BOT_RESTOCK_DELAY_S");

            if (gCfg.tick_interval_s == 0) { gCfg.tick_interval_s = 2; } // defensive: never tick at 0s
        }

        // --------------------------------------------------------------
        // CSV loader
        // --------------------------------------------------------------
        bool toBool(const std::string& s) { return !s.empty() && s != "0"; }

        uint32_t toU32(const std::string& s)
        {
            try { return static_cast<uint32_t>(std::stoul(s)); } catch (...) { return 0; }
        }

        uint8_t toU8(const std::string& s)
        {
            try { return static_cast<uint8_t>(std::min<uint32_t>(255u, std::stoul(s))); } catch (...) { return 0; }
        }

        // Trim leading/trailing whitespace in-place.
        void trim(std::string& s)
        {
            const auto first = s.find_first_not_of(" \t\r\n");
            const auto last  = s.find_last_not_of(" \t\r\n");
            if (first == std::string::npos) { s.clear(); return; }
            s = s.substr(first, last - first + 1);
        }

        std::vector<std::string> splitCsvLine(const std::string& line)
        {
            std::vector<std::string> out;
            std::stringstream        ss(line);
            std::string              cell;
            while (std::getline(ss, cell, ','))
            {
                trim(cell);
                out.push_back(cell);
            }
            return out;
        }

        void loadCsv()
        {
            gRules.clear();

            if (!fs::exists(gCfg.csv_path))
            {
                ShowError(fmt::format("auction_bot: items.csv not found at {}", gCfg.csv_path));
                return;
            }

            std::ifstream ifs(gCfg.csv_path);
            if (!ifs.is_open())
            {
                ShowError(fmt::format("auction_bot: could not open {}", gCfg.csv_path));
                return;
            }

            // Header: itemid, name, sell_single, buy_single, price_single, stock_single,
            //         sell_stacks, buy_stacks, price_stacks, stock_stacks
            std::string line;
            std::getline(ifs, line); // skip header

            while (std::getline(ifs, line))
            {
                if (line.empty()) { continue; }
                const auto cells = splitCsvLine(line);
                if (cells.size() < 10) { continue; }

                ItemRule r;
                r.itemid       = static_cast<uint16_t>(toU32(cells[0]));
                // cells[1] is name, ignored
                r.sell_single  = toBool(cells[2]);
                r.buy_single   = toBool(cells[3]);
                r.price_single = toU32(cells[4]);
                r.stock_single = toU8(cells[5]);
                r.sell_stacks  = toBool(cells[6]);
                r.buy_stacks   = toBool(cells[7]);
                r.price_stacks = toU32(cells[8]);
                r.stock_stacks = toU8(cells[9]);

                if (r.itemid != 0) { gRules[r.itemid] = r; }
            }

            ShowInfo(fmt::format("auction_bot: loaded {} item rules from {}", gRules.size(), gCfg.csv_path));
        }

        // --------------------------------------------------------------
        // One-shot history seed at boot. Idempotent: only inserts if no
        // future-dated (date=2099) history row exists for (itemid, stack).
        // Pattern mirrors ffxiahbot/auction/seller.py set_history.
        // --------------------------------------------------------------
        void seedHistory()
        {
            uint32_t inserted = 0;

            for (const auto& [itemid, r] : gRules)
            {
                // Single-item history
                if (r.sell_single && r.price_single > 0)
                {
                    const auto rset = db::preparedStmt(
                        "SELECT 1 FROM auction_house WHERE seller = ? AND itemid = ? AND stack = 0 AND date = ? LIMIT 1",
                        gCfg.seller_char_id, itemid, kFarFutureDate);

                    if (!rset || rset->rowsCount() == 0)
                    {
                        db::preparedStmt(
                            "INSERT INTO auction_house (itemid, stack, seller, seller_name, date, price, "
                            "buyer_name, sale, sell_date) VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?)",
                            itemid, gCfg.seller_char_id, gCfg.seller_name, kFarFutureDate, r.price_single,
                            gCfg.seller_name, r.price_single, kFarFutureDate);
                        ++inserted;
                    }
                }

                // Stack history
                if (r.sell_stacks && r.price_stacks > 0)
                {
                    const auto rset = db::preparedStmt(
                        "SELECT 1 FROM auction_house WHERE seller = ? AND itemid = ? AND stack = 1 AND date = ? LIMIT 1",
                        gCfg.seller_char_id, itemid, kFarFutureDate);

                    if (!rset || rset->rowsCount() == 0)
                    {
                        db::preparedStmt(
                            "INSERT INTO auction_house (itemid, stack, seller, seller_name, date, price, "
                            "buyer_name, sale, sell_date) VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?)",
                            itemid, gCfg.seller_char_id, gCfg.seller_name, kFarFutureDate, r.price_stacks,
                            gCfg.seller_name, r.price_stacks, kFarFutureDate);
                        ++inserted;
                    }
                }
            }

            ShowInfo(fmt::format("auction_bot: seeded {} new history rows ({} previously seeded — pre-existing)",
                                 inserted, gRules.size() * 2 - inserted));
        }

        // (itemid << 1) | stack  → count of bot listings with that (itemid, stack).
        // Built once per tick from a single GROUP BY query instead of 14k+
        // per-item COUNT(*)s. Cut watchdog-tripping query storms.
        using BotStockKey = uint32_t;
        static inline BotStockKey makeKey(uint16_t itemid, uint8_t stack)
        {
            return (static_cast<uint32_t>(itemid) << 1) | (stack ? 1u : 0u);
        }

        std::unordered_map<BotStockKey, uint32_t> snapshotBotStock()
        {
            std::unordered_map<BotStockKey, uint32_t> out;
            out.reserve(gRules.size() * 2);

            const auto rset = db::preparedStmt(
                "SELECT itemid, stack, COUNT(*) AS cnt FROM auction_house "
                "WHERE seller = ? AND sale = 0 GROUP BY itemid, stack",
                gCfg.seller_char_id);

            if (rset)
            {
                while (rset->next())
                {
                    const uint16_t itemid = rset->get<uint16_t>("itemid");
                    const uint8_t  stack  = rset->get<uint8_t>("stack");
                    const uint32_t cnt    = rset->get<uint32_t>("cnt");
                    out[makeKey(itemid, stack)] = cnt;
                }
            }
            return out;
        }

        // Keys (itemid, stack) for the bot's OWN listings that a buyer purchased
        // within the last `delaySeconds`. refillPass holds off restocking these
        // so a bought-out item stays scarce for the configured cooldown. Filters
        // on seller = bot, so a player selling INTO the bot (bot buys it, marked
        // sold under the player's seller id) never lands here — only buyer-side
        // purchases of bot stock do. Index-backed by idx_ah_history
        // (itemid, stack, sell_date). Empty when the delay is disabled.
        std::unordered_set<BotStockKey> snapshotRecentlySold()
        {
            std::unordered_set<BotStockKey> out;
            if (gCfg.restock_delay_s == 0) { return out; }

            const uint32_t nowTs  = earth_time::timestamp();
            const uint32_t cutoff = (nowTs > gCfg.restock_delay_s) ? (nowTs - gCfg.restock_delay_s) : 0;

            const auto rset = db::preparedStmt(
                "SELECT DISTINCT itemid, stack FROM auction_house "
                "WHERE seller = ? AND sale > 0 AND sell_date >= ?",
                gCfg.seller_char_id, cutoff);

            if (rset)
            {
                while (rset->next())
                {
                    const uint16_t itemid = rset->get<uint16_t>("itemid");
                    const uint8_t  stack  = rset->get<uint8_t>("stack");
                    out.insert(makeKey(itemid, stack));
                }
            }
            return out;
        }

        // --------------------------------------------------------------
        // Per-tick: scan all current player listings in ONE query, walk
        // results in memory to find buy-rule matches, UPDATE matching rows.
        // For sell_single=0 items, conditionally insert a sell-back row
        // using cached counts (no per-item COUNT(*) query).
        // --------------------------------------------------------------
        void buyPass(std::unordered_map<BotStockKey, uint32_t>& botStock,
                     uint32_t&                                   insertBudget,
                     uint32_t&                                   outBoughtSingles,
                     uint32_t&                                   outBoughtStacks,
                     uint32_t&                                   outRecycled,
                     uint32_t&                                   outSkipped)
        {
            const auto rset = db::preparedStmt(
                "SELECT id, itemid, stack, price FROM auction_house "
                "WHERE sale = 0 AND seller != ? "
                "ORDER BY itemid, stack, price ASC",
                gCfg.seller_char_id);
            if (!rset) { return; }

            const uint32_t now = earth_time::timestamp();

            while (rset->next())
            {
                const uint32_t id     = rset->get<uint32_t>("id");
                const uint16_t itemid = rset->get<uint16_t>("itemid");
                const uint8_t  stack  = rset->get<uint8_t>("stack");
                const uint32_t price  = rset->get<uint32_t>("price");

                const auto it = gRules.find(itemid);
                if (it == gRules.end()) { continue; }
                const ItemRule& r = it->second;

                const bool isStack       = (stack != 0);
                const bool ruleBuys      = isStack ? r.buy_stacks : r.buy_single;
                const uint32_t buyPrice  = isStack ? r.price_stacks : r.price_single;
                if (!ruleBuys || buyPrice == 0 || price > buyPrice) { continue; }

                // Buy: UPDATE this specific row by id (fast, indexed).
                const auto upd = db::preparedStmt(
                    "UPDATE auction_house SET sale = ?, buyer_name = ?, sell_date = ? "
                    "WHERE id = ? AND sale = 0",
                    price, gCfg.seller_name, now, id);
                if (!upd || upd->rowsAffected() == 0) { continue; }

                if (isStack) { ++outBoughtStacks; } else { ++outBoughtSingles; }

                // Sell-back applies only when bot doesn't auto-stock this item/stack.
                const bool ruleSells = isStack ? r.sell_stacks : r.sell_single;
                if (ruleSells) { continue; }

                const BotStockKey key   = makeKey(itemid, stack);
                const uint32_t    cur   = botStock[key];
                if (cur >= gCfg.max_sellback_listings) { ++outSkipped; continue; }
                if (insertBudget == 0) { continue; }

                const uint32_t insPrice = isStack ? r.price_stacks : r.price_single;
                db::preparedStmt(
                    "INSERT INTO auction_house (itemid, stack, seller, seller_name, date, price) "
                    "VALUES (?, ?, ?, ?, ?, ?)",
                    itemid, isStack ? 1u : 0u, gCfg.seller_char_id, gCfg.seller_name,
                    kFarFutureDate, insPrice);
                botStock[key] = cur + 1;
                --insertBudget;
                ++outRecycled;
            }
        }

        // --------------------------------------------------------------
        // Per-tick: top up bot stock for sell_single=1 / sell_stacks=1 items
        // to the CSV stock targets. Uses the cached snapshot (built once
        // at tick start) — no per-item COUNT(*) query.
        // --------------------------------------------------------------
        void refillPass(std::unordered_map<BotStockKey, uint32_t>& botStock,
                        const std::unordered_set<BotStockKey>&      cooldown,
                        uint32_t&                                   insertBudget,
                        uint32_t&                                   outInsertedSingles,
                        uint32_t&                                   outInsertedStacks)
        {
            // Round-robin start point so a budget-exhausted tick doesn't starve
            // items near the end of the map. Static, so successive ticks pick
            // up where the prior tick left off.
            static size_t sCursor = 0;
            if (gRules.empty()) { return; }
            if (sCursor >= gRules.size()) { sCursor = 0; }

            auto       it      = gRules.begin();
            std::advance(it, sCursor);
            const auto begin   = it;
            size_t     visited = 0;

            for (; visited < gRules.size(); ++visited)
            {
                if (insertBudget == 0) { break; }

                const auto&     [itemid, r] = *it;

                if (r.sell_single && r.stock_single > 0 && r.price_single > 0 &&
                    cooldown.find(makeKey(itemid, 0)) == cooldown.end())
                {
                    const BotStockKey key = makeKey(itemid, 0);
                    uint32_t          cur = botStock[key];
                    while (cur < r.stock_single && insertBudget > 0)
                    {
                        db::preparedStmt(
                            "INSERT INTO auction_house (itemid, stack, seller, seller_name, date, price) "
                            "VALUES (?, 0, ?, ?, ?, ?)",
                            itemid, gCfg.seller_char_id, gCfg.seller_name, kFarFutureDate, r.price_single);
                        ++cur;
                        --insertBudget;
                        ++outInsertedSingles;
                    }
                    botStock[key] = cur;
                }

                if (r.sell_stacks && r.stock_stacks > 0 && r.price_stacks > 0 &&
                    cooldown.find(makeKey(itemid, 1)) == cooldown.end())
                {
                    const BotStockKey key = makeKey(itemid, 1);
                    uint32_t          cur = botStock[key];
                    while (cur < r.stock_stacks && insertBudget > 0)
                    {
                        db::preparedStmt(
                            "INSERT INTO auction_house (itemid, stack, seller, seller_name, date, price) "
                            "VALUES (?, 1, ?, ?, ?, ?)",
                            itemid, gCfg.seller_char_id, gCfg.seller_name, kFarFutureDate, r.price_stacks);
                        ++cur;
                        --insertBudget;
                        ++outInsertedStacks;
                    }
                    botStock[key] = cur;
                }

                ++it;
                if (it == gRules.end()) { it = gRules.begin(); }
            }

            // Advance cursor by however many rule entries we visited this tick,
            // so the next tick continues from where we left off.
            sCursor = (sCursor + visited) % gRules.size();
            (void)begin; // silence unused-variable; kept for clarity in diffs
        }
    } // namespace

    void initialize()
    {
        loadConfig();

        if (!gCfg.enabled)
        {
            ShowInfo("auction_bot: disabled by config — skipping initialization");
            return;
        }

        loadCsv();
        if (gRules.empty())
        {
            ShowError("auction_bot: no rules loaded — disabling");
            return;
        }

        seedHistory();

        ShowInfo(fmt::format("auction_bot: ready (seller={} [{}], tick={}s, sellback_cap={})",
                             gCfg.seller_name, gCfg.seller_char_id, gCfg.tick_interval_s,
                             gCfg.max_sellback_listings));
        gReady = true;
    }

    void tick()
    {
        if (!gReady) { return; }

        const auto now = timer::now();
        if (now < gNextTick) { return; }
        gNextTick = now + std::chrono::seconds(gCfg.tick_interval_s);

        uint32_t boughtSingles = 0, boughtStacks = 0, recycled = 0, skipped = 0;
        uint32_t refilledSingles = 0, refilledStacks = 0;

        // ONE GROUP BY query at tick start → in-memory map of bot listing counts.
        // Buy + refill passes mutate this map locally so per-rule decisions need
        // no further COUNT(*) queries. Cut a watchdog-tripping query storm
        // (~30k roundtrips per tick) down to O(rules + matches).
        auto botStock = snapshotBotStock();

        // Items a buyer bought from the bot within AUCTION_BOT_RESTOCK_DELAY_S —
        // refillPass holds off restocking these so a bought-out item stays
        // scarce for the cooldown. Empty (no-op) when the delay is disabled.
        // Buying from players (buyPass) is unaffected — it stays next-tick.
        const auto restockCooldown = snapshotRecentlySold();

        // Shared insert budget across buy (sellback) + refill passes so the
        // total per-tick INSERT count stays bounded — protects the main loop
        // from a startup burst when the bot has 0 stock for every CSV rule.
        uint32_t insertBudget = kMaxInsertsPerTick;

        buyPass(botStock, insertBudget, boughtSingles, boughtStacks, recycled, skipped);
        refillPass(botStock, restockCooldown, insertBudget, refilledSingles, refilledStacks);

        // Suppress idle ticks; only log when something happened.
        if (boughtSingles || boughtStacks || recycled || skipped ||
            refilledSingles || refilledStacks)
        {
            ShowInfo(fmt::format(
                "auction_bot: bought={}+{}stacks recycled={} skipped_capped={} refilled={}+{}stacks",
                boughtSingles, boughtStacks, recycled, skipped,
                refilledSingles, refilledStacks));
        }
    }
} // namespace singleplayer::auction_bot
