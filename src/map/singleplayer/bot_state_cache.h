/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#pragma once

#include <string>

// Thread-safe cache of the per-primary "alliance + per-bot config state"
// JSON blob. Written by Lua's bots.publish_state_snapshot (via a sol2
// binding) on the main thread at onBotTick cadence (~400ms). Read by the
// loopback HTTP server's GET /bot-state handler on a worker thread.
//
// Existed to break the 504-byte FFXI wire ceiling that the legacy 0x1A5
// BOT_STATE_SNAPSHOT packet was bumping against once per-bot fields were
// added to the snapshot. Plain mutex-guarded map: a few hundred primaries
// at most, single short JSON string per entry — no need for a fancier
// concurrent structure.
//
// Keyed by primary character name (case-sensitive). Name is what the
// addon already has at HTTP-fetch time; using it as the key avoids a SQL
// round-trip per request. Rename collisions would leave stale entries
// that the next tick overwrites with the new name's snapshot.
namespace botstate
{
    // Store the latest snapshot JSON for `charName`. Empty `json` clears
    // the entry. Thread-safe; takes the writer lock.
    void publishSnapshot(const std::string& charName, std::string json);

    // Look up the cached snapshot for `charName`. Returns empty string if
    // no snapshot has been published. Thread-safe; takes the reader lock.
    auto getSnapshot(const std::string& charName) -> std::string;
} // namespace botstate
