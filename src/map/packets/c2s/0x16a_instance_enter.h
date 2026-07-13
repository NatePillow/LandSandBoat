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

// Custom packet (singleplayer fork): bulk-add sender's party / alliance / a
// chosen subset to whatever instance the sender is currently in. Dispatch is
// auto-detected from the sender's current state; only one path can apply at
// a time because instance membership is physical (you are *in* the zone):
//   1. BCNM (active battlefield with sender as initiator) — call
//      CBattlefield::InsertEntity for each same-zone member.
//   2. Dynamis (sender's zone has ZONE_TYPE::DYNAMIS) — pull stranded bots
//      out of their entry zone into the sender's Dynamis zone via the
//      in-process DecreaseZoneCounter/IncreaseZoneCounter primitive. Static
//      Dynamis zones don't need CInstance integration.
//   3. INSTANCED (sender's zone is a CZoneInstance with PInstance set) —
//      same idea but attach each bot to sender's PInstance + RegisterChar
//      before IncreaseZoneCounter so they land in the correct instance copy.
// subcmd:
//   0 = PARTY     — sender's party members
//   1 = ALLIANCE  — sender's alliance members
//   2 = SPECIFIC  — only chars whose names appear in names[count]
GP_CLI_PACKET(GP_CLI_COMMAND_INSTANCE_ENTER,
    uint8_t subcmd;
    uint8_t count;
    uint8_t padding[2];
    char    names[18][16];
);
