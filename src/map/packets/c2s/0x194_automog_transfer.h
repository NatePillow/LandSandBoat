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

// Custom packet (singleplayer fork): cross-char inventory transfer used by
// AutoMog Transfer tab. The sending primary specifies SrcChar / DstChar by
// name; both must be sessioned and owned by the sender (primary itself or
// one of its headless chars). When Src == Dst this behaves identically to
// 0x16B BULKXFER (intra-char move). S2C response: 0x195.
GP_CLI_PACKET(GP_CLI_COMMAND_AUTOMOG_TRANSFER,
    uint8_t SrcBag;
    uint8_t DstBag;
    uint8_t Count;
    uint8_t padding;
    char    SrcCharName[16];
    char    DstCharName[16];
    uint8_t Slots[32];
);
