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

class CMobEntity;

// Custom packet (singleplayer fork): periodic enmity snapshot for a mob.
// Sent alongside entity updates in CMobEntity::PostTick. Contains up to
// MAX_ENTRIES entries sorted by CE+VE descending, plus the mob's current
// battle target.
class GP_SERV_COMMAND_ENMITY final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_ENMITY, GP_SERV_COMMAND_ENMITY>
{
public:
    static constexpr uint8_t MAX_ENTRIES = 24;

    struct Entry
    {
        uint32_t entity_id;
        int32_t  ce;
        int32_t  ve;
    };

    struct PacketData
    {
        uint32_t mob_id;
        uint32_t battle_target_id; // server ID of current #1 hate target; 0 if none
        uint8_t  entry_count;
        uint8_t  padding[3];
        Entry    entries[MAX_ENTRIES];
    };

    explicit GP_SERV_COMMAND_ENMITY(CMobEntity* PMob);
};
