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

// Custom packet (singleplayer fork): one batch of AH listings in response to
// GP_CLI_COMMAND_AH_CAT_QUERY (0x16F). The server streams all results by
// sending consecutive packets; IsLast=1 marks the final packet for the query.
// Client accumulates all batches into a single list keyed by CatId.
class GP_SERV_COMMAND_AH_CAT_RESULT final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_AH_CAT_RESULT, GP_SERV_COMMAND_AH_CAT_RESULT>
{
public:
    struct Entry
    {
        uint16_t ItemId;
        uint8_t  SingleCount;    // number of single-item listings (capped at 255)
        uint8_t  StackCount;     // number of stack listings (capped at 255)
        uint32_t MinSinglePrice; // lowest current single-listing ask, gil; 0 = no listings
        uint32_t MinStackPrice;  // lowest current stack-listing ask, gil; 0 = no listings
    };

    struct PacketData
    {
        uint8_t CatId;
        uint8_t Offset;  // index of the first entry in this packet (for ordering)
        uint8_t Count;   // entries in this packet (0-30)
        uint8_t IsLast;  // 1 = no more packets for this query
        Entry   Entries[30]; // 30 * 12 = 360 bytes; total PacketData = 364 bytes
    };

    GP_SERV_COMMAND_AH_CAT_RESULT(uint8_t catId, uint8_t offset, uint8_t count, uint8_t isLast, const Entry* entries);
};
