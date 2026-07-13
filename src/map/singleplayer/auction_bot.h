/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  In-process auction-house bot. Replaces the external Python ffxiahbot for
  the singleplayer fork. Mirrors ffxiahbot's date=2099-01-01 hack so bot
  listings are invisible to search.expireAH and remain indefinitely.

  See task #197 for full design + rationale.

===========================================================================
*/

#pragma once

namespace singleplayer::auction_bot
{
    // Called once at boot from packet_registry. Reads config + items.csv,
    // seeds AH history rows (idempotent), opens for business.
    void initialize();

    // Called every char post-tick from post_tick.cpp. Rate-limited internally
    // by tick_interval_s — most calls are no-ops. Drives the buy + refill
    // passes when the interval elapses.
    void tick();
} // namespace singleplayer::auction_bot
