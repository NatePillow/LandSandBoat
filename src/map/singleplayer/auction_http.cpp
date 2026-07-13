/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "auction_http.h"

#include "op_registry.h"

#include "entities/charentity.h"
#include "item_container.h"
#include "items/item.h"
#include "items/item_usable.h"
#include "map_session_container.h"
#include "utils/charutils.h"
#include "utils/itemutils.h"
#include "utils/zoneutils.h"

#include "common/database.h"
#include "common/logging.h"
#include "common/mmo.h"
#include "common/timer.h"

#include <nlohmann/json.hpp>

#include <chrono>
#include <cstring>
#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace singleplayer::auction_http
{
    using json = nlohmann::json;

    namespace
    {
        // -----------------------------------------------------------------
        // Auth
        // -----------------------------------------------------------------
        // Mirrors resolveTarget in char_http.cpp: target
        // must be the requester themselves OR a headless sessioned under them.
        // Called from the main thread (post_tick applier) so the session
        // pointer is stable for the duration of the call.
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

        // Payloads carried on op_registry::Record::payload (std::any). The
        // HTTP handler builds one of these and enqueues; drainOps casts it
        // back out. Each struct captures inputs by value so we don't hold
        // dangling references to the request buffer past enqueue.
        struct SellOp
        {
            uint32      requesterCharId;   // resolved to CCharEntity* in drainOps
            std::string targetName;
            uint8       slot;
            uint16      itemId;
            bool        isStack;
            uint32      price;
        };
        struct BuyOp
        {
            uint32      requesterCharId;
            std::string targetName;
            // Buy modes:
            //   listingId != 0            : buy that specific listing (used by
            //                               MY_LISTINGS-style flows where the
            //                               client already knows the row id).
            //   listingId == 0 && itemId  : buy the cheapest available listing
            //                               matching (itemId, isStack), capped
            //                               at bidPrice. Retail 0x04E CMD_BID
            //                               targets this way, so the addon's
            //                               autobuy path uses this shape.
            uint32      listingId;
            uint32      bidPrice;
            bool        isStack;
            uint16      itemId;
        };
        struct CancelOp
        {
            uint32      requesterCharId;
            std::string targetName;
            uint32      listingId;
        };

        // Retrieve the requester's CCharEntity from a captured charId. HTTP
        // handler captured id-only (not pointer) because the pointer may be
        // invalidated by a logout between enqueue and drain — the drain-time
        // GetCharByID call is authoritative.
        auto findChar(uint32 charId) -> CCharEntity*
        {
            return charId ? zoneutils::GetChar(charId) : nullptr;
        }

        // Common inventory-item guard: refuses partially-charged items (usable
        // items with fewer than max charges) since retail forbids listing them
        // and the ah_history reader would misrepresent the charge count.
        auto isPartiallyUsed(const CItem* PItem) -> bool
        {
            if (PItem == nullptr || !PItem->isSubType(ITEM_CHARGED))
            {
                return false;
            }
            const auto PCharged = static_cast<const CItemUsable*>(PItem);
            return PCharged->getCurrentCharges() < PCharged->getMaxCharges();
        }

        // 2099-01-01 UTC — same "far-future date" the auction_bot uses to
        // distinguish auto-bot listings from real seller listings. User
        // listings get the real current timestamp so the client shows a
        // "listed on <date>" that isn't a lie.
        constexpr uint32_t kFarFutureDate = 4070908800u;

        // -----------------------------------------------------------------
        // /ah/listings?for=<char> — synchronous DB read.
        // -----------------------------------------------------------------
        // Auth: caller must match the target OR the target must be their
        // headless. Since we're on a worker thread the CCharEntity pointer
        // isn't guaranteed stable, so we don't dereference it — we key on
        // charname and reject if the requester header + target name pair
        // can't be resolved to an ownership relation. For singleplayer
        // loopback that's already loose enough; harden if this ever leaves
        // localhost.
        //
        // We accept `for=` as the target name and `by=` as the requester
        // (defaults to `for` — i.e. self-query). This mirrors the loopback
        // shape /bot-state uses (?for=<primary>).
        void handleListings(const httplib::Request& req, httplib::Response& res)
        {
            const auto forIt = req.params.find("for");
            if (forIt == req.params.end() || forIt->second.empty())
            {
                res.status = 400;
                res.set_content(R"({"error":"missing ?for"})", "application/json");
                return;
            }
            const std::string sellerName = forIt->second;
            // Look up seller's charId via DB — no in-memory reliance on
            // whether the target is currently zoned in.
            uint32 sellerCharId = 0;
            {
                const auto rset = db::preparedStmt(
                    "SELECT charid FROM chars WHERE charname = ? LIMIT 1", sellerName);
                if (rset && rset->rowsCount() && rset->next())
                {
                    sellerCharId = rset->get<uint32>("charid");
                }
            }
            if (sellerCharId == 0)
            {
                res.status = 404;
                res.set_content(R"({"error":"unknown seller"})", "application/json");
                return;
            }

            // Active listings only. Sold rows are historical and were
            // flooding the UI with irrelevant [SOLD] entries in the
            // singleplayer case where the auction_bot buys the seller out
            // frequently. If a "history" view is ever wanted it'll be a
            // separate endpoint.
            json arr = json::array();
            const auto rset = db::preparedStmt(
                "SELECT id, itemid, stack, price, date "
                "FROM auction_house "
                "WHERE seller = ? AND sale = 0 "
                "ORDER BY id DESC",
                sellerCharId);
            if (rset)
            {
                while (rset->next())
                {
                    json entry;
                    entry["id"]     = rset->get<uint32>("id");
                    entry["itemId"] = rset->get<uint16>("itemid");
                    entry["stack"]  = rset->get<uint8>("stack");
                    entry["price"]  = rset->get<uint32>("price");
                    entry["date"]   = rset->get<uint32>("date");
                    arr.push_back(entry);
                }
            }
            res.set_content(arr.dump(), "application/json");
            res.set_header("Cache-Control", "no-cache");
        }

        // -----------------------------------------------------------------
        // /ah/stock?items=<itemId>:<stack>[,<itemId>:<stack>...]
        //
        // Active-listing counts for a batch of (itemId, stack) pairs. Read
        // only, so it answers straight off the HTTP thread — no op_registry
        // round-trip. This replaces the retired 0x162 AH_QUERY packet, whose
        // handler ran the same COUNT(*) queries on the map tick thread and
        // tripped the inactivity watchdog when autobuy's craft-tab pre-check
        // fired a batch of them.
        //
        // Max 64 pairs, which is well past the largest recipe ingredient set;
        // a bad caller gets 400 rather than an unbounded query loop.
        // -----------------------------------------------------------------
        constexpr std::size_t kMaxStockPairs = 64;

        void handleStock(const httplib::Request& req, httplib::Response& res)
        {
            const auto itemsIt = req.params.find("items");
            if (itemsIt == req.params.end() || itemsIt->second.empty())
            {
                res.status = 400;
                res.set_content(R"({"error":"missing ?items"})", "application/json");
                return;
            }

            // Parse "738:0,739:1" into pairs, preserving request order so the
            // response is index-aligned to what the caller asked for.
            std::vector<std::pair<uint16, uint8>> pairs;
            {
                const std::string& raw = itemsIt->second;
                std::size_t        pos = 0;
                while (pos <= raw.size())
                {
                    const std::size_t comma = raw.find(',', pos);
                    const std::string tok   = raw.substr(pos, comma == std::string::npos ? std::string::npos : comma - pos);
                    if (!tok.empty())
                    {
                        const std::size_t colon = tok.find(':');
                        if (colon == std::string::npos)
                        {
                            res.status = 400;
                            res.set_content(R"({"error":"malformed pair, want itemId:stack"})", "application/json");
                            return;
                        }
                        try
                        {
                            const unsigned long itemId = std::stoul(tok.substr(0, colon));
                            const unsigned long stack  = std::stoul(tok.substr(colon + 1));
                            if (itemId == 0 || itemId > 0xFFFF)
                            {
                                res.status = 400;
                                res.set_content(R"({"error":"itemId out of range"})", "application/json");
                                return;
                            }
                            pairs.emplace_back(static_cast<uint16>(itemId), stack != 0 ? uint8{ 1 } : uint8{ 0 });
                        }
                        catch (const std::exception&)
                        {
                            res.status = 400;
                            res.set_content(R"({"error":"non-numeric pair"})", "application/json");
                            return;
                        }
                        if (pairs.size() > kMaxStockPairs)
                        {
                            res.status = 400;
                            res.set_content(R"({"error":"too many pairs, max 64"})", "application/json");
                            return;
                        }
                    }
                    if (comma == std::string::npos)
                    {
                        break;
                    }
                    pos = comma + 1;
                }
            }

            if (pairs.empty())
            {
                res.status = 400;
                res.set_content(R"({"error":"no pairs parsed"})", "application/json");
                return;
            }

            // A recipe routinely names the same (itemId, stack) more than once
            // across variants; query each distinct pair once and fan the result
            // back out to every request slot that wanted it.
            std::map<std::pair<uint16, uint8>, uint32> counts;
            for (const auto& p : pairs)
            {
                if (counts.contains(p))
                {
                    continue;
                }
                uint32     cnt  = 0;
                const auto rset = db::preparedStmt(
                    "SELECT COUNT(*) AS cnt FROM auction_house "
                    "WHERE itemid = ? AND stack = ? AND buyer_name IS NULL AND sale = 0",
                    p.first, p.second);
                if (rset && rset->next())
                {
                    cnt = rset->get<uint32>("cnt");
                }
                counts[p] = cnt;
            }

            json arr = json::array();
            for (const auto& p : pairs)
            {
                json entry;
                entry["itemId"] = p.first;
                entry["stack"]  = p.second;
                entry["count"]  = counts[p];
                arr.push_back(entry);
            }
            res.set_content(arr.dump(), "application/json");
            res.set_header("Cache-Control", "no-cache");
        }

        // -----------------------------------------------------------------
        // /ops/<opId> — op status poll.
        // -----------------------------------------------------------------
        void handleOpStatus(const httplib::Request& req, httplib::Response& res)
        {
            const std::string opId = req.matches[1].str();
            const auto        rec  = op_registry::query(opId);
            if (!rec.has_value())
            {
                res.status = 404;
                res.set_content(R"({"error":"unknown opId"})", "application/json");
                return;
            }
            const char* statusStr = "pending";
            if (rec->status == op_registry::Status::Success) { statusStr = "success"; }
            else if (rec->status == op_registry::Status::Failed)  { statusStr = "failed";  }
            json j;
            j["status"]  = statusStr;
            j["kind"]    = rec->kind;
            j["message"] = rec->message;
            res.set_content(j.dump(), "application/json");
            res.set_header("Cache-Control", "no-cache");
        }

        // Small helper: parse the request body as JSON, or 400.
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

        // Common accepted-response envelope: 202 + { opId }. Client polls
        // /ops/<opId> from here.
        void writeAcceptedOpId(httplib::Response& res, const std::string& opId)
        {
            res.status = 202;
            json j;
            j["opId"] = opId;
            res.set_content(j.dump(), "application/json");
            res.set_header("Cache-Control", "no-cache");
        }

        // Sender-charId helper. Reads a "by" charname from the JSON body and
        // resolves to a chars.charid via a single indexed lookup. Returns 0
        // on miss — caller replies 400. HTTP-side auth: `by` names the client's
        // primary; the SellOp/BuyOp/CancelOp appliers verify that the target
        // char (from `for`) is either `by` or `by`'s headless.
        auto resolveCharIdByName(const std::string& name) -> uint32
        {
            if (name.empty()) { return 0; }
            const auto rset = db::preparedStmt(
                "SELECT charid FROM chars WHERE charname = ? LIMIT 1", name);
            if (rset && rset->rowsCount() && rset->next())
            {
                return rset->get<uint32>("charid");
            }
            return 0;
        }

        // -----------------------------------------------------------------
        // POST /ah/sell
        // Body: { "by": "<primary>", "for": "<target>", "slot": u8,
        //         "itemId": u16, "isStack": bool, "price": u32 }
        // -----------------------------------------------------------------
        void handleSell(const httplib::Request& req, httplib::Response& res)
        {
            auto body = parseJsonBody(req, res);
            if (!body.has_value()) { return; }
            SellOp op{};
            try
            {
                op.requesterCharId = resolveCharIdByName(body->at("by").get<std::string>());
                op.targetName      = body->at("for").get<std::string>();
                op.slot            = body->at("slot").get<uint8>();
                op.itemId          = body->at("itemId").get<uint16>();
                op.isStack         = body->at("isStack").get<bool>();
                op.price           = body->at("price").get<uint32>();
            }
            catch (const std::exception& e)
            {
                res.status = 400;
                res.set_content(fmt::format(R"({{"error":"bad payload: {}"}})", e.what()),
                                "application/json");
                return;
            }
            if (op.requesterCharId == 0 || op.targetName.empty() || op.price == 0)
            {
                res.status = 400;
                res.set_content(R"({"error":"missing required fields"})", "application/json");
                return;
            }
            const std::string opId = op_registry::enqueue("ah_sell", op);
            writeAcceptedOpId(res, opId);
        }

        // -----------------------------------------------------------------
        // POST /ah/buy
        // Body: { "by": "<primary>", "for": "<target>",
        //         "bidPrice": u32,
        //         // one of:
        //         "listingId": u32                     (buy this specific row)
        //         "itemId": u16, "isStack": bool       (cheapest matching row) }
        // -----------------------------------------------------------------
        void handleBuy(const httplib::Request& req, httplib::Response& res)
        {
            auto body = parseJsonBody(req, res);
            if (!body.has_value()) { return; }
            BuyOp op{};
            try
            {
                op.requesterCharId = resolveCharIdByName(body->at("by").get<std::string>());
                op.targetName      = body->at("for").get<std::string>();
                op.bidPrice        = body->at("bidPrice").get<uint32>();
                op.listingId       = body->value("listingId", 0u);
                op.itemId          = body->value("itemId",    uint16{ 0 });
                op.isStack         = body->value("isStack",   false);
            }
            catch (const std::exception& e)
            {
                res.status = 400;
                res.set_content(fmt::format(R"({{"error":"bad payload: {}"}})", e.what()),
                                "application/json");
                return;
            }
            const bool haveSpecific = op.listingId != 0;
            const bool haveCheapest = op.itemId    != 0;
            if (op.requesterCharId == 0 || op.targetName.empty() ||
                op.bidPrice == 0 || (!haveSpecific && !haveCheapest))
            {
                res.status = 400;
                res.set_content(R"({"error":"missing required fields"})", "application/json");
                return;
            }
            const std::string opId = op_registry::enqueue("ah_buy", op);
            writeAcceptedOpId(res, opId);
        }

        // -----------------------------------------------------------------
        // POST /ah/cancel
        // Body: { "by": "<primary>", "for": "<target>", "listingId": u32 }
        // -----------------------------------------------------------------
        void handleCancel(const httplib::Request& req, httplib::Response& res)
        {
            auto body = parseJsonBody(req, res);
            if (!body.has_value()) { return; }
            CancelOp op{};
            try
            {
                op.requesterCharId = resolveCharIdByName(body->at("by").get<std::string>());
                op.targetName      = body->at("for").get<std::string>();
                op.listingId       = body->at("listingId").get<uint32>();
            }
            catch (const std::exception& e)
            {
                res.status = 400;
                res.set_content(fmt::format(R"({{"error":"bad payload: {}"}})", e.what()),
                                "application/json");
                return;
            }
            if (op.requesterCharId == 0 || op.targetName.empty() || op.listingId == 0)
            {
                res.status = 400;
                res.set_content(R"({"error":"missing required fields"})", "application/json");
                return;
            }
            const std::string opId = op_registry::enqueue("ah_cancel", op);
            writeAcceptedOpId(res, opId);
        }

        // =================================================================
        // Post-tick appliers — main-thread. These do the actual inventory /
        // gil / DB mutation and mark the op record terminal.
        // =================================================================

        void applySell(const std::string& opId, const SellOp& op)
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
            CItemContainer* PInv = PTarget->getStorage(LOC_INVENTORY);
            if (PInv == nullptr)
            {
                op_registry::markFailed(opId, "no inventory");
                return;
            }
            CItem* PItem = PInv->GetItem(op.slot);
            if (PItem == nullptr || PItem->getID() == 0)
            {
                op_registry::markFailed(opId, "no item in slot");
                return;
            }
            if (PItem->getID() != op.itemId)
            {
                op_registry::markFailed(opId, "item id mismatch");
                return;
            }
            if (PItem->isSubType(ITEM_LOCKED))
            {
                op_registry::markFailed(opId, "item locked");
                return;
            }
            if (PItem->hasFlag(ItemFlag::NoAuction))
            {
                op_registry::markFailed(opId, "item non-auctionable");
                return;
            }
            if (isPartiallyUsed(PItem))
            {
                op_registry::markFailed(opId, "item partially used");
                return;
            }
            if (op.isStack)
            {
                if (PItem->getStackSize() == 1 || PItem->getQuantity() != PItem->getStackSize())
                {
                    op_registry::markFailed(opId, "not a full stack");
                    return;
                }
            }
            // Insert the listing row. Real seller charid + real timestamp so
            // the listing reads as a real user listing (auction_bot uses
            // kFarFutureDate to distinguish its own).
            const uint32 now = earth_time::timestamp();
            if (!db::preparedStmt(
                    "INSERT INTO auction_house(itemid, stack, seller, seller_name, date, price) "
                    "VALUES(?, ?, ?, ?, ?, ?)",
                    PItem->getID(),
                    op.isStack ? 1u : 0u,
                    PTarget->id,
                    PTarget->getName(),
                    now,
                    op.price))
            {
                op_registry::markFailed(opId, "DB insert failed");
                return;
            }
            // Deduct the item from inventory. No AH fee — this is the fork's
            // "AH-anywhere" pattern and fees are retail-economy overhead.
            const int32 stackDelta = op.isStack ? -static_cast<int32>(PItem->getStackSize()) : -1;
            charutils::UpdateItem(PTarget, LOC_INVENTORY, op.slot, stackDelta);
            op_registry::markSuccess(opId, "listed");
        }

        void applyBuy(const std::string& opId, const BuyOp& op)
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
            // Resolve the specific listing row we're buying. Two modes:
            //   listingId != 0 : caller already knows the row (MY_LISTINGS-
            //                    style flows / server-side resolved row).
            //   listingId == 0 : find the cheapest matching (itemId, stack)
            //                    whose price <= bidPrice. Mirrors retail
            //                    0x04E CMD_BID targeting.
            uint32 listingId = op.listingId;
            uint16 itemId    = 0;
            uint8  stack     = 0;
            uint32 sellPrice = 0;
            if (listingId != 0)
            {
                const auto rset = db::preparedStmt(
                    "SELECT itemid, stack, price FROM auction_house "
                    "WHERE id = ? AND sale = 0 AND buyer_name IS NULL LIMIT 1",
                    listingId);
                if (rset && rset->rowsCount() && rset->next())
                {
                    itemId    = rset->get<uint16>("itemid");
                    stack     = rset->get<uint8>("stack");
                    sellPrice = rset->get<uint32>("price");
                }
            }
            else
            {
                const auto rset = db::preparedStmt(
                    "SELECT id, itemid, stack, price FROM auction_house "
                    "WHERE itemid = ? AND stack = ? AND sale = 0 "
                    "AND buyer_name IS NULL AND price <= ? "
                    "ORDER BY price ASC, id ASC LIMIT 1",
                    op.itemId,
                    op.isStack ? 1u : 0u,
                    op.bidPrice);
                if (rset && rset->rowsCount() && rset->next())
                {
                    listingId = rset->get<uint32>("id");
                    itemId    = rset->get<uint16>("itemid");
                    stack     = rset->get<uint8>("stack");
                    sellPrice = rset->get<uint32>("price");
                }
            }
            if (listingId == 0 || itemId == 0)
            {
                op_registry::markFailed(opId, "no matching listing");
                return;
            }
            if (op.bidPrice < sellPrice)
            {
                op_registry::markFailed(opId, "bid too low");
                return;
            }
            CItemContainer* PInv = PTarget->getStorage(LOC_INVENTORY);
            if (PInv == nullptr || PInv->GetFreeSlotsCount() == 0)
            {
                op_registry::markFailed(opId, "inventory full");
                return;
            }
            const CItem* PGil = PInv->GetItem(0);
            if (PGil == nullptr || !PGil->isType(ITEM_CURRENCY) ||
                PGil->getQuantity() < op.bidPrice || PGil->getReserve() != 0)
            {
                op_registry::markFailed(opId, "not enough gil");
                return;
            }
            const CItem* PItemLookup = xi::items::lookup(itemId);
            if (PItemLookup == nullptr)
            {
                op_registry::markFailed(opId, "unknown item id");
                return;
            }
            if (PItemLookup->hasFlag(ItemFlag::Rare))
            {
                // Rare check — reject if buyer already has one anywhere.
                for (uint8 loc = 0; loc < CONTAINER_ID::MAX_CONTAINER_ID; ++loc)
                {
                    CItemContainer* PC = PTarget->getStorage(loc);
                    if (PC != nullptr && PC->SearchItem(itemId) != ERROR_SLOTID)
                    {
                        op_registry::markFailed(opId, "rare item already owned");
                        return;
                    }
                }
            }
            const uint32 now = earth_time::timestamp();
            // Atomic UPDATE that races other buyers cleanly — rowsAffected==0
            // means someone else grabbed it between our SELECT and here.
            const auto upd = db::preparedStmt(
                "UPDATE auction_house SET buyer_name = ?, sale = ?, sell_date = ? "
                "WHERE id = ? AND sale = 0 AND buyer_name IS NULL",
                PTarget->getName(), sellPrice, now, listingId);
            if (!upd || upd->rowsAffected() == 0)
            {
                op_registry::markFailed(opId, "listing gone (race)");
                return;
            }
            const uint32 quantity = stack ? PItemLookup->getStackSize() : 1;
            if (charutils::AddItem(PTarget, LOC_INVENTORY, itemId, quantity) == ERROR_SLOTID)
            {
                // Very unlikely (we checked GetFreeSlotsCount), but if it
                // happens roll the UPDATE back so the listing reappears.
                db::preparedStmt(
                    "UPDATE auction_house SET buyer_name = NULL, sale = 0, sell_date = 0 "
                    "WHERE id = ?", listingId);
                op_registry::markFailed(opId, "AddItem failed after DB update");
                return;
            }
            // Charge the actual listing price, not the bid ceiling — retail
            // semantics: "bidPrice" is the client's max, actual cost is the
            // listing's price. Saves the buyer the delta when they bid over.
            charutils::UpdateItem(PTarget, LOC_INVENTORY, 0, -static_cast<int32>(sellPrice));
            op_registry::markSuccess(opId, "purchased");
        }

        void applyCancel(const std::string& opId, const CancelOp& op)
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
            // Read the listing so we know what to return to inventory.
            uint16 itemId = 0;
            uint8  stack  = 0;
            {
                const auto rset = db::preparedStmt(
                    "SELECT itemid, stack FROM auction_house "
                    "WHERE id = ? AND seller = ? AND sale = 0 LIMIT 1",
                    op.listingId, PTarget->id);
                if (rset && rset->rowsCount() && rset->next())
                {
                    itemId = rset->get<uint16>("itemid");
                    stack  = rset->get<uint8>("stack");
                }
            }
            if (itemId == 0)
            {
                op_registry::markFailed(opId, "listing not found or not yours");
                return;
            }
            const CItem* PItemLookup = xi::items::lookup(itemId);
            if (PItemLookup == nullptr)
            {
                op_registry::markFailed(opId, "unknown item id");
                return;
            }
            // Delete the row FIRST so a concurrent buy racing us either
            // succeeds first (and we then bail on the delete) or fails.
            const auto del = db::preparedStmt(
                "DELETE FROM auction_house WHERE id = ? AND seller = ? AND sale = 0 LIMIT 1",
                op.listingId, PTarget->id);
            if (!del || del->rowsAffected() == 0)
            {
                op_registry::markFailed(opId, "listing gone (race)");
                return;
            }
            const uint32 quantity = stack ? PItemLookup->getStackSize() : 1;
            if (charutils::AddItem(PTarget, LOC_INVENTORY, itemId, quantity) == ERROR_SLOTID)
            {
                op_registry::markFailed(opId, "AddItem failed — inventory full");
                return;
            }
            op_registry::markSuccess(opId, "cancelled");
        }
    } // namespace

    void registerRoutes(httplib::Server& server)
    {
        server.Get("/ah/listings", handleListings);
        server.Get("/ah/stock",    handleStock);
        server.Post("/ah/sell",    handleSell);
        server.Post("/ah/buy",     handleBuy);
        server.Post("/ah/cancel",  handleCancel);
        server.Get(R"(/ops/([^/]+))", handleOpStatus);
    }

    void drainOps()
    {
        op_registry::drain(
            [](const std::string& opId, const std::string& kind, const std::any& payload)
            {
                try
                {
                    if (kind == "ah_sell")
                    {
                        applySell(opId, std::any_cast<SellOp>(payload));
                    }
                    else if (kind == "ah_buy")
                    {
                        applyBuy(opId, std::any_cast<BuyOp>(payload));
                    }
                    else if (kind == "ah_cancel")
                    {
                        applyCancel(opId, std::any_cast<CancelOp>(payload));
                    }
                    // Other kinds ignored — drainOps only handles ah_*.
                    // Future non-AH kinds get their own drainer or a
                    // registry-side kind dispatcher.
                }
                catch (const std::bad_any_cast& e)
                {
                    op_registry::markFailed(opId, fmt::format("payload cast: {}", e.what()));
                }
            });
    }
}
