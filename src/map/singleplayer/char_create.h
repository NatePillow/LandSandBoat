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

// HTTP-backed "create a brand-new character" for the autobots addon.
//
// Route registered in config_http_server.cpp startup:
//   POST /chars/create   — mint a new account + character (async op)
//
// Replaces the retail client account-create + character-create screens so a
// roster of headless characters can be populated without logging in / out.
// The single map process owns the whole flow that retail splits across the
// login (xi_connect) and map servers:
//
//   1. Validate the requested name + look + nation + job with the SAME checks
//      the real flow uses (auth_session.cpp LOGIN_CREATE + view_session.cpp
//      0x22 name check). Nothing extra.
//   2. INSERT the accounts row (login = charname, password = bcrypt("password"),
//      NORMAL / USER) and the chars/char_look/char_stats/... rows — the map-side
//      replica of loginHelpers::saveCharacter (which lives only in xi_connect_lib
//      and is not linked here).
//   3. LoadChar the new charid on the main thread. Because stored playtime is 0,
//      LoadChar -> OnGameIn runs xi.player.charCreate (base + the singleplayer
//      headstart override) automatically — starting gear, gil, coupon, title,
//      nation ring/map, mission/trust/teleport headstart.
//   4. Stamp the post-cutscene end-state (position + home point at the nation's
//      CS-exit spot, HQuest[newCharacterCS]notSeen = 0) so first login is silent.
//   5. Persist everything and bump playtime > 0 so charCreate never re-fires.
//
// Validation runs on the httplib worker thread; the account/char INSERT +
// LoadChar + persist MUST run on the map main thread (CCharEntity work), so the
// handler enqueues an op_registry record drained in post_tick, same shape as
// POST /chars/sort-inventory and POST /ah/{sell,buy,cancel}. Client calls
// http_client.await_op('/chars/create', {...}) and polls /ops/<opId>.

namespace singleplayer::char_create
{
    // Register /chars/create on the shared config HTTP server.
    void registerRoutes(httplib::Server& server);

    // Called from post_tick on the map main thread. Applies pending "char_create"
    // ops. Fast no-op when none are pending.
    void drainOps();
}
