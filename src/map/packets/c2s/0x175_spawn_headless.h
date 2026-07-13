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

#include "base.h"

// Custom packet 0x175: SPAWN_HEADLESS
// Sent by the primary client's autobots addon (once, after confirming the SP-fork
// server ident at 0x150) to spawn one or more "headless" character sessions on the
// server from a named combined bot config.
//
// Payload (32 bytes):
//   ConfigName[32] : null-padded config base-name. Server resolves to
//                    singleplayer/config/alliance/<ConfigName>.json
//                    and dispatches to xi.singleplayer.bots.spawn_from_config(player, ConfigName)
//                    on the Lua side. That module walks the combined JSON
//                    (alliance + roles + sc1/sc2 + solo + nm/stationary flags),
//                    creates synthetic sessions per spawn-list member, forms
//                    parties, and queues per-party trust casts.
//
// Total: 4 (header) + 32 (config name) = 36 bytes
// PacketSize = 36 / 2 = 0x12
GP_CLI_PACKET(GP_CLI_COMMAND_SPAWN_HEADLESS,
    char ConfigName[32];
);
