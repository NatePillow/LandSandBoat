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

// Custom packet (singleplayer fork): response to GP_CLI_COMMAND_EQUIP_BY_ID (0x173).
// Count mirrors the request Count so the client can correlate entries by index.
// Per-entry result codes in Results[]:
//   0 = success        (item is now equipped in the requested slot)
//   1 = not found      (item not present in any valid container)
//   2 = blocked        (item was found but game mechanic rejected the equip:
//                       m_EquipBlock, level/job/race restriction, etc.)
//   3 = no-op          (item was already equipped in that slot; no change made)
class GP_SERV_COMMAND_EQUIP_BY_ID_RESULT final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_EQUIP_BY_ID_RESULT, GP_SERV_COMMAND_EQUIP_BY_ID_RESULT>
{
public:
    struct PacketData
    {
        uint8_t Count;
        uint8_t padding[3];
        uint8_t Results[16];
    };

    GP_SERV_COMMAND_EQUIP_BY_ID_RESULT(uint8_t count, const std::array<uint8_t, 16>& results);
};
