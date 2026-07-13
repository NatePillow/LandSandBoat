/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "op_registry.h"

#include <atomic>
#include <mutex>
#include <unordered_map>
#include <vector>

namespace singleplayer::op_registry
{
    namespace
    {
        // 5-minute record TTL — long enough that a stuck-tabbed-out client
        // gets an answer when it comes back, short enough that the map
        // hash-map doesn't grow unbounded across a long session.
        constexpr auto kRecordTtl = std::chrono::minutes(5);

        std::mutex                              gMu;
        std::unordered_map<std::string, Record> gRecords;    // opId -> record
        std::atomic<uint64_t>                   gNextOpId{ 1 };

        // GC pass — evict any Success/Failed record older than kRecordTtl.
        // Cheap because we only look at terminal-state records; Pending ops
        // are always kept regardless of age (a stuck op is a bug worth
        // seeing, not a candidate for eviction). Caller must hold gMu.
        void gcLocked(std::chrono::steady_clock::time_point now)
        {
            for (auto it = gRecords.begin(); it != gRecords.end(); )
            {
                if (it->second.status != Status::Pending &&
                    now - it->second.finishedAt > kRecordTtl)
                {
                    it = gRecords.erase(it);
                }
                else
                {
                    ++it;
                }
            }
        }
    }

    auto enqueue(std::string kind, std::any payload) -> std::string
    {
        const auto        now  = std::chrono::steady_clock::now();
        const uint64_t    id   = gNextOpId.fetch_add(1);
        const std::string opId = std::to_string(id);

        std::lock_guard<std::mutex> lock(gMu);
        gcLocked(now);
        Record r{};
        r.kind      = std::move(kind);
        r.status    = Status::Pending;
        r.payload   = std::move(payload);
        r.queuedAt  = now;
        gRecords.emplace(opId, std::move(r));
        return opId;
    }

    auto query(const std::string& opId) -> std::optional<Record>
    {
        std::lock_guard<std::mutex> lock(gMu);
        const auto it = gRecords.find(opId);
        if (it == gRecords.end())
        {
            return std::nullopt;
        }
        return it->second;
    }

    void drain(Applier applier)
    {
        // Snapshot pending ops under the lock, then release the lock BEFORE
        // running the applier. The applier calls `charutils::UpdateItem`,
        // which fires `luautils::OnItemDrop` (arbitrary Lua callbacks) —
        // holding gMu across that is a deadlock hazard for any HTTP worker
        // polling /ops/<opId> via query(), and can hard-stall the main
        // thread past the watchdog if a Lua handler takes real time.
        //
        // Correctness: markSuccess/markFailed re-acquire gMu briefly at
        // apply time. Payloads are captured by value (charId etc.), so a
        // logout mid-drain just means findChar returns nullptr and the
        // applier fails cleanly.
        struct PendingSnapshot
        {
            std::string id;
            std::string kind;
            std::any    payload;
        };
        std::vector<PendingSnapshot> pending;
        {
            std::lock_guard<std::mutex> lock(gMu);
            pending.reserve(gRecords.size());
            for (const auto& [id, rec] : gRecords)
            {
                if (rec.status == Status::Pending)
                {
                    pending.push_back({ id, rec.kind, rec.payload });
                }
            }
        }
        for (const auto& item : pending)
        {
            applier(item.id, item.kind, item.payload);
        }
    }

    void markSuccess(const std::string& opId, std::string message)
    {
        std::lock_guard<std::mutex> lock(gMu);
        const auto it = gRecords.find(opId);
        if (it == gRecords.end() || it->second.status != Status::Pending)
        {
            return;
        }
        it->second.status     = Status::Success;
        it->second.message    = std::move(message);
        it->second.finishedAt = std::chrono::steady_clock::now();
    }

    void markFailed(const std::string& opId, std::string message)
    {
        std::lock_guard<std::mutex> lock(gMu);
        const auto it = gRecords.find(opId);
        if (it == gRecords.end() || it->second.status != Status::Pending)
        {
            return;
        }
        it->second.status     = Status::Failed;
        it->second.message    = std::move(message);
        it->second.finishedAt = std::chrono::steady_clock::now();
    }
}
