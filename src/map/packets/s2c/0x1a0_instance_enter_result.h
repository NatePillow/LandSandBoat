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

// Custom packet (singleplayer fork): result for 0x16A INSTANCE_ENTER. Sits
// at 0x1A0 rather than the more obvious 0x16B because 0x16B is already C2S
// BULKXFER; the LSB convention keeps each packet ID single-purpose across
// both directions, so this lands in the freshly-allocated 0x1Ax range.
//   Status: 0 = ok (at least one member processed)
//           1 = no active instance — sender's zone has none of (BCNM with
//               sender as initiator, ZONE_TYPE::DYNAMIS, CZoneInstance with
//               sender's PInstance set)
//           2 = sender has no PInstance assignment in an INSTANCED zone
//           3 = no zone state on sender
//   Branch: 0 = BCNM, 1 = DYNAMIS, 2 = INSTANCED, 0xFF = no branch matched
//   Moved : number of members the dispatch acted on (InsertEntity for BCNM,
//           in-process bot moves for DYNAMIS / INSTANCED)
class GP_SERV_COMMAND_INSTANCE_ENTER_RESULT final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_INSTANCE_ENTER_RESULT, GP_SERV_COMMAND_INSTANCE_ENTER_RESULT>
{
public:
    struct PacketData
    {
        uint8_t Status;
        uint8_t Branch;
        uint8_t Moved;
        uint8_t padding;
    };

    GP_SERV_COMMAND_INSTANCE_ENTER_RESULT(uint8_t status, uint8_t branch, uint8_t moved);
};
