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

// Custom packet 0x17d: USE_FOOD_CONFIG
// On-demand "feed everyone now" — the primary char's addon sends this to fire
// food usage across every headless listed in a named food config. Server reads
// singleplayer/config/food/<ConfigName>.json (a char-name → food-item
// map) and dispatches bot:useItem on each linked headless.
//
// ConfigName[32] : null-padded base-name; server resolves to
//                  singleplayer/config/food/<ConfigName>.json
//
// Total: 4 (header) + 32 = 36 bytes. PacketSize = 36 / 2 = 0x12.
GP_CLI_PACKET(GP_CLI_COMMAND_USE_FOOD_CONFIG,
    char ConfigName[32];
);
