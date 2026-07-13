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

// Custom packet 0x193 (C2S): LIST_AUTOSKILL request.
// Header-only. Asks the server to walk xi.singleplayer.bots.skillup.state for every bot
// owned by the requester (parentCharId == requester->id) and push one
// 0x192 AUTOSKILL_STATE for each active override. Used by the autoskill and
// autobots addons on load to populate their caches when an override is
// already in place from a previous session.
//
// Total: 4 (header) bytes. PacketSize = 4 / 2 = 0x02.
GP_CLI_PACKET(GP_CLI_COMMAND_LIST_AUTOSKILL,
);
