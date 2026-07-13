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

// Custom packet (singleplayer fork): AutoMog Change-Look. Changes the target
// char's race, face and/or size. Flags bit 0 == change Race, bit 1 == change
// Face, bit 2 == change Size; any combination may be set in one packet. Server
// validates that the sender owns the named target (primary or a sessioned
// headless owned by the sender), that the target is not engaged in combat, that
// each requested value is in range (race 1-8, face 0-15, size 0-2), and that at
// least one value actually differs from the current. Primary refreshes via
// charutils::raceChange (DB write + gear cleanup + ForceRezone); a headless is
// refreshed in place (DB write + gear cleanup + live look mutation + zone
// despawn/respawn) because ForceRezone would tear down the synthetic session.
// Reuses the retired 0x162 AH_QUERY opcode (hole-fill). S2C result: 0x163.
GP_CLI_PACKET(GP_CLI_COMMAND_AUTOMOG_CHANGE_LOOK,
    char    TargetCharName[16];
    uint8_t NewRace;
    uint8_t NewFace;
    uint8_t NewSize;
    uint8_t Flags;
);
