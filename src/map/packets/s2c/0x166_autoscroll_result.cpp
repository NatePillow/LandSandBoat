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

#include "0x166_autoscroll_result.h"

GP_SERV_COMMAND_AUTOSCROLL_RESULT::GP_SERV_COMMAND_AUTOSCROLL_RESULT(uint8_t count, const uint16_t* spellIds)
{
    auto& packet  = this->data();
    packet.Count  = count;
    for (uint8_t i = 0; i < count && i < 32; ++i)
    {
        packet.SpellID[i] = spellIds[i];
    }
}
