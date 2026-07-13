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

// Custom packet (singleplayer fork): response to GP_CLI_COMMAND_AUTOSCROLL (0x165).
// Lists up to 32 spell IDs that were learned in this pass.
class GP_SERV_COMMAND_AUTOSCROLL_RESULT final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_AUTOSCROLL_RESULT, GP_SERV_COMMAND_AUTOSCROLL_RESULT>
{
public:
    struct PacketData
    {
        uint8_t  Count;
        uint8_t  padding[3];
        uint16_t SpellID[32];
    };

    GP_SERV_COMMAND_AUTOSCROLL_RESULT(uint8_t count, const uint16_t* spellIds);
};
