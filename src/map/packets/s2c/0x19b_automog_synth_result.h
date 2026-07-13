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

// Custom packet (singleplayer fork): completion code for an AUTOMOG_SYNTH
// dispatch. 0x19A resolves and commits the synth inline against the target
// char, pushing any player-facing messages onto the target itself; this
// packet carries only the sender-facing status.
//   Status: 0 = ok, 1 = no target session, 2 = ownership rejected,
//           3 = inner opcode mismatch.
class GP_SERV_COMMAND_AUTOMOG_SYNTH_RESULT final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_AUTOMOG_SYNTH_RESULT, GP_SERV_COMMAND_AUTOMOG_SYNTH_RESULT>
{
public:
    struct PacketData
    {
        uint8_t Status;
        uint8_t padding[3];
    };

    explicit GP_SERV_COMMAND_AUTOMOG_SYNTH_RESULT(uint8_t status);
};
