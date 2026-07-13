/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "packet_registry.h"

#include "auction_bot.h"
#include "config_cache.h"
#include "config_http_server.h"

namespace singleplayer
{
    // Compile-time custom-packet registration moved to packet_registry.h as
    // a consteval function called from packet_system.cpp::buildPacketHandlers.
    // What remains here is the runtime initialization of singleplayer-only
    // subsystems that used to ride along with the old registerCustomPackets()
    // free function: the in-memory config cache (#177), the in-process
    // auction-house bot (#197), and the loopback config HTTP server.
    void initializeRuntime()
    {
        // Boot the in-memory config cache. The cache holds raw file bodies
        // plus mtimes; reads go through configcache::get / forEach (the
        // HTTP server below reads from it, and ai_equip_swap / ai_lot use
        // GetServerConfig for the mtime-on-read freshness check). Writes
        // go through configcache::putAndPersist, which atomically updates
        // body + mtime and persists to disk — the HTTP PUT handler is the
        // only writer today.
        configcache::initialize();

        // Boot the loopback HTTP server that serves configcache to addons
        // over localhost on a fixed port (51220). Replaces the chunked
        // 0x17E pipeline for reads — same source-of-truth (configcache),
        // ~50× faster on big files, sidesteps the FFXI wire-zlib edge
        // cases that show up as decode errors in client logs. Initialize
        // AFTER configcache::initialize so the very first GET that
        // arrives can already hit a populated cache.
        config_http_server::initialize();

        // Boot the in-process auction-house bot (#197). Replaces external
        // Python ffxiahbot. No-op if settings/singleplayer.lua
        // AUCTION_BOT_ENABLED is false.
        auction_bot::initialize();
    }
}
