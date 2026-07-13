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

// Custom packet (singleplayer fork): AutoMog Change-Job. Changes the target
// char's main and/or subjob to the requested ids. Flags bit 0 == change MJ,
// bit 1 == change SJ; both can be set in one packet. Server validates that
// the sender owns the named target (primary or a sessioned headless owned by
// the sender), that the target is not engaged in combat, that each requested
// job is unlocked and at level >= 1, and that at least one job actually
// differs from the current. S2C result: 0x19D.
GP_CLI_PACKET(GP_CLI_COMMAND_AUTOMOG_CHANGE_JOB,
    char    TargetCharName[16];
    uint8_t NewMJob;
    uint8_t NewSJob;
    uint8_t Flags;
    uint8_t padding;
);
