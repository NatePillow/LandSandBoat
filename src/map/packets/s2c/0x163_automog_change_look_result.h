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

// Custom packet (singleplayer fork): result for 0x162 AUTOMOG_CHANGE_LOOK.
//   Status: 0 = ok                  — at least one of race/face/size changed
//           1 = no target session   — name didn't resolve to a live session
//           2 = ownership rejected  — target not owned by sender
//           3 = engaged in combat   — bot/primary is engaged; reject like moogle
//           4 = out of range        — race/face/size value outside valid bounds
//           6 = no-op               — requested value(s) match current; nothing to do
// Reuses the retired 0x163 AH_QUERY_RESULT opcode (hole-fill).
class GP_SERV_COMMAND_AUTOMOG_CHANGE_LOOK_RESULT final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_AUTOMOG_CHANGE_LOOK_RESULT, GP_SERV_COMMAND_AUTOMOG_CHANGE_LOOK_RESULT>
{
public:
    struct PacketData
    {
        uint8_t Status;
        uint8_t padding[3];
    };

    explicit GP_SERV_COMMAND_AUTOMOG_CHANGE_LOOK_RESULT(uint8_t status);
};
