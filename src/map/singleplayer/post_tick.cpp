/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "post_tick.h"

#include "auction_bot.h"
#include "auction_http.h"
#include "char_http.h"
#include "config_cache.h"
#include "entities/charentity.h"
#include "lua/luautils.h"

namespace singleplayer
{
    namespace
    {
        // Filesystem-watcher cadence for the config cache. Cheap to poll (one
        // stat per file across ~50 files), but no point doing it every tick —
        // the user-perceived latency of a manual edit landing in the cache is
        // dominated by the next push being queued and drained, which is on
        // the order of a second anyway. Once every 2 s gives a sub-3 s manual-
        // edit-to-client-visible latency without burning IO on a fast loop.
        constexpr auto kConfigPollInterval = std::chrono::seconds(2);
        timer::time_point gNextConfigPoll{};

        // HTTP op drain cadence. Must be alliance-cheap: onCharPostTick fires
        // per-char, so without a gate an alliance of 6 walks the op registry
        // 6 times per tick. Empty-queue case is a lock+iterator, which sounds
        // free but stacks up alongside auction_bot::tick's DB churn and can
        // push the tick over the 2s watchdog. 200 ms is well below the
        // client's 500 ms poll cadence in await_op so user-perceived latency
        // is unchanged.
        constexpr auto kOpDrainInterval = std::chrono::milliseconds(200);
        timer::time_point gNextOpDrain{};
    }

    void onCharPostTick(CCharEntity* PChar, timer::time_point now)
    {
        if (PChar == nullptr)
        {
            return;
        }

        // Config cache mtime poll. Fires once across all chars per cadence —
        // we just happen to ride a per-char tick to find a thread context
        // (no zone-wide tick exists today). The first char to cross the
        // deadline does the poll; the rest no-op.
        if (now >= gNextConfigPoll)
        {
            gNextConfigPoll = now + kConfigPollInterval;
            configcache::poll();
        }

        // Auction-house bot tick (#197). Internally rate-limited by its own
        // tick_interval_s config; most calls are no-ops. Riding the per-char
        // tick for thread context, same justification as configcache::poll
        // above.
        auction_bot::tick();

        // HTTP op drain. HTTP handlers enqueue on their worker threads;
        // any main-thread mutation (inventory / gil / DB commit) happens
        // here. Gated to once per kOpDrainInterval instead of every char's
        // tick so an alliance of N doesn't multiply the registry walk by N.
        //
        // Each drainer ignores kinds it doesn't own, so both must run: the
        // registry hands every Pending record to whichever applier is walking
        // it, and a record stays Pending until its own drainer marks it.
        if (now >= gNextOpDrain)
        {
            gNextOpDrain = now + kOpDrainInterval;
            auction_http::drainOps();
            char_http::drainOps();
        }

        const bool isHeadless = PChar->isHeadless();

        // Note: the GP_SERV_COMMAND_SERVER_IDENT (0x150) heartbeat used to fire
        // here every second. Addons now pull the ident on demand via the
        // 0x153 REQUEST_SERVER_IDENT C2S packet from their `load` handler, so
        // the push lives in that handler instead. Saves a packet/sec/client
        // for the entire session lifetime and lets reloaded addons re-verify
        // identity immediately without waiting for the next heartbeat tick.

        // Headless session housekeeping: drain the packet queue (no socket to
        // send to) and force a periodic save (no client input to dirty
        // dataToPersist).
        if (isHeadless)
        {
            PChar->clearPacketList();

            if (now >= PChar->m_nextHeadlessPersist)
            {
                PChar->m_nextHeadlessPersist = now + TIME_BETWEEN_PERSIST;
                PChar->dataToPersist |= CHAR_PERSIST::POSITION | CHAR_PERSIST::EFFECTS | CHAR_PERSIST::EQUIP;
                PChar->PersistData(now);
            }
        }

        // Bot AI tick:
        //   - Headless: ALWAYS fires, regardless of m_botMode, BUT only after
        //     createHeadlessSession finishes wiring the AI container.
        //   - Primary: ALWAYS fires for spawn-finalized chars, regardless of
        //     m_botMode. Required so utility chainers (autoequip autoupdate,
        //     autolot, autodps) continue to run on the primary even while
        //     they're in BotMode::Off doing manual play. The Lua-side bots
        //     base early-returns on BotMode::Off before running combat or
        //     movement; chainer bodies run after super() returns either way.
        // "Stop Actions" flipping m_botMode to Off on every owned headless
        // pauses combat AI but lets utility behaviors keep running while the
        // user is camped and resting.
        if (PChar->m_spawnFinalized)
        {
            luautils::OnBotTick(PChar, now, static_cast<uint8>(PChar->m_botMode));
        }
    }
}
