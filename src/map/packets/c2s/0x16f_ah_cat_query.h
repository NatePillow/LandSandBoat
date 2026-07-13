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

// Custom packet (singleplayer fork): AH category stock query for the autobuy browse UI.
// Client sends a single aH category ID; server responds with one or more
// GP_SERV_COMMAND_AH_CAT_RESULT (0x170) packets covering all current listings.
GP_CLI_PACKET(GP_CLI_COMMAND_AH_CAT_QUERY,
    uint8_t CatId;    // aH enum value (1-65)
    uint8_t padding[3];
);
