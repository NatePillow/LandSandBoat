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

#pragma once

#include <httplib.h>

// HTTP-backed per-char container access for the automog / autoequip / autobox
// addons.
//
// Routes registered in config_http_server.cpp startup:
//   GET  /chars/<name>/inventory       — full snapshot: caps + occupied slots
//   POST /chars/<name>/sort-inventory  — stack-consolidate one bag (async op)
//
// Replaces the 0x16D / 0x16E / 0x18F / 0x190 / 0x1A6 packet family. Those were
// slow for a structural reason rather than a bandwidth one: the map server only
// flushes a char's outbound queue when a client packet arrives (send_parse is
// called from the receive path in map_networking.cpp), and each flush is capped
// at kMaxPacketPerCompression packets. 0x16D pushed one 0x020 ITEM_ATTR packet
// per item across all 18 containers, so a few hundred items meant tens of client
// round-trips. Worse, every addon requiring libs/inv_cache.lua has its own Lua
// state and therefore issued its own independent dump.
//
// The read is served straight off the HTTP worker thread from the DB, like
// GET /chars and GET /ah/listings. char_inventory is write-through — AddItem
// inserts, quantity changes update, removals delete — so it tracks live
// container state. Gil is an ordinary row: location 0, slot 0, itemId 65535.
//
// The sort MUTATES containers, so it cannot run on an HTTP thread. It enqueues
// an op_registry record and post_tick applies it on the main thread, same as
// POST /ah/{sell,buy,cancel}. Callers use http_client.await_op and then re-GET
// the inventory; the applier's DB writes are complete before it marks success,
// so the follow-up read never observes a half-sorted bag.

namespace singleplayer::char_http
{
    // Register /chars/<name>/* routes on the shared config HTTP server.
    void registerRoutes(httplib::Server& server);

    // Called from post_tick on the map main thread. Applies pending ops whose
    // kind starts with "char_". Fast no-op when none are pending.
    void drainOps();
}
