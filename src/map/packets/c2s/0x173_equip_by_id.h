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

struct equip_by_id_entry_t
{
    uint16_t ItemId;
    uint8_t  EquipKind;
    uint8_t  padding;
};

// Custom packet (singleplayer fork): equip up to 16 items by item ID rather than
// inventory slot.  The server searches all valid equip containers for each ItemId
// and calls charutils::EquipItem for the first match.  Entries whose ItemId is not
// found in any container are silently skipped.
GP_CLI_PACKET(GP_CLI_COMMAND_EQUIP_BY_ID,
    uint8_t            Count;
    uint8_t            padding[3];
    equip_by_id_entry_t Equipment[16];
);
