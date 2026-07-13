/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  Loopback HTTP server that exposes the in-memory configcache to addons.
  Replaces the chunked 0x17E GET_CONFIG_CONTENT pipeline for reads —
  same source of truth (configcache), totally different transport.

  Why HTTP instead of more packets:
   - The packet pipeline ships 32 chunks × 506 bytes per ~400ms tick
     (~40 KB/s ceiling) and runs every chunk through FFXI's static-
     dictionary wire zlib. Big autoequip XMLs spend seconds in flight
     and occasionally trip zlib edge cases that show up as decode
     errors in the client log.
   - cpp-httplib on loopback hits sub-ms latency and ~500 MB/s sustained.
     A 100 KB XML opens in ~10ms vs ~2.5s on the packet path.
   - LuaSocket ships with Ashita v3 (libs/socket.lua, libs/socket/http.lua),
     so the addon side is one `require('socket.http')` away.

  Scope (Phase 1):
   - GET-only. Three routes plus a /healthz.
   - Singleplayer fork has no auth; binding restricts the security
     boundary (loopback-only by default, 0.0.0.0 if you need a VM
     guest to reach the host).
   - Port + bind address come from settings/singleplayer.lua so end
     users can adjust without recompiling. Fail loud if the bind
     fails — no fallback, no port discovery in the addon, both
     sides have to agree on the value.

  Future phases (separate PRs):
   - PUT / POST / DELETE for full CRUD.
   - Migrate autoequip readers off the chunked path (Phase 2).
   - Migrate the rest of the addons (Phase 3).
   - Delete the chunked configtransfer / 0x17E / 0x1A0 plumbing (Phase 5).

===========================================================================
*/

#pragma once

#include <cstdint>

namespace singleplayer
{
namespace config_http_server
{
    // Spawn the listener thread + register routes. Called once from
    // singleplayer::initializeRuntime() at map boot. Reads port + bind
    // address from settings/singleplayer.lua (CONFIG_HTTP_PORT and
    // CONFIG_HTTP_BIND_ADDR). The addon-side helper has to be told
    // the same port AND a reachable host (see libs/http_client.lua).
    // On bind failure logs ShowCritical and the server stays down.
    void initialize();

    // Stop the listener and join its thread. Safe to call when initialize()
    // never ran or already shut down. Today this is a no-op on process
    // exit (OS reclaims) — present for future graceful-shutdown plumbing.
    void shutdown();
} // namespace config_http_server
} // namespace singleplayer
