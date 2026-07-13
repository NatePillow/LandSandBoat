/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#pragma once

#include "base.h"

// Custom packet 0x153 (C2S): REQUEST_SERVER_IDENT.
// Sent by an Ashita addon's load event to ask "is this our singleplayer fork?".
// Replaces the prior 1Hz server-side push of 0x150 (GP_SERV_COMMAND_SERVER_IDENT)
// which spammed every connected session every tick. Now the server only pushes
// the ident in response to this request — addons that don't ask never receive
// it (and stay inert against non-fork servers, which is the desired security
// behavior).
//
// No payload — the request is just "tell me who you are"; identity travels in
// the existing 0x150 reply (ServerIdent[32]).
//
// Total: 4 (header) bytes. PacketSize = 4 / 2 = 0x02.
GP_CLI_PACKET(GP_CLI_COMMAND_REQUEST_SERVER_IDENT,
);
