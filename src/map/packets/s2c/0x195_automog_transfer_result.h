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

// Custom packet (singleplayer fork): response to GP_CLI_COMMAND_AUTOMOG_TRANSFER (0x194).
// Result codes:
//   0 = success (all requested items moved)
//   1 = destination full (partial or none moved)
//   2 = source bag invalid / dst char not sessioned / ownership rejected
// Moved is the number of items actually transferred.
class GP_SERV_COMMAND_AUTOMOG_TRANSFER_RESULT final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_AUTOMOG_TRANSFER_RESULT, GP_SERV_COMMAND_AUTOMOG_TRANSFER_RESULT>
{
public:
    struct PacketData
    {
        uint8_t Result;
        uint8_t Moved;
        uint8_t padding[2];
    };

    GP_SERV_COMMAND_AUTOMOG_TRANSFER_RESULT(uint8_t result, uint8_t moved);
};
