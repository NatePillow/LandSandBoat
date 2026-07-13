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

// Custom packet (singleplayer fork): instantly learn all usable scrolls in
// inventory without going through CItemState or the scroll animation.
// No payload fields — the server scans inventory unconditionally.
// S2C: one GP_SERV_COMMAND_BATTLE_MESSAGE(LearnsNewSpell) per scroll learned,
// one GP_SERV_COMMAND_MAGIC_DATA at the end, one GP_SERV_COMMAND_ITEM_SAME.
GP_CLI_PACKET(GP_CLI_COMMAND_AUTOSCROLL,
    uint8_t padding[4];
);
