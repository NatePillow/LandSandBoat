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

#include "0x170_ah_cat_result.h"

#include <cstring>

GP_SERV_COMMAND_AH_CAT_RESULT::GP_SERV_COMMAND_AH_CAT_RESULT(
    uint8_t catId, uint8_t offset, uint8_t count, uint8_t isLast, const Entry* entries)
{
    auto& packet   = this->data();
    packet.CatId   = catId;
    packet.Offset  = offset;
    packet.Count   = count;
    packet.IsLast  = isLast;
    if (entries && count > 0)
    {
        std::memcpy(packet.Entries, entries, sizeof(Entry) * std::min<uint8_t>(count, 30));
    }
}
