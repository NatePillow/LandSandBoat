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

#include "0x076_group_effects.h"
#include "base.h"
#include <vector>

class CCharEntity;

// Custom packet (singleplayer fork): sends buff data for alliance members
// outside the recipient's own party (up to 12 members across 2 other parties).
// Mirrors the structure of GP_SERV_COMMAND_GROUP_EFFECTS (0x076) but covers
// the full alliance. The vanilla client ignores unknown opcodes; Lua addons
// intercept this to build an allianceStatus table.
class GP_SERV_COMMAND_ALLIANCE_EFFECTS final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_ALLIANCE_EFFECTS, GP_SERV_COMMAND_ALLIANCE_EFFECTS>
{
public:
    struct PacketData
    {
        partymemberbuffs_t Members[12]; // Up to 12 members from other alliance parties
    };

    explicit GP_SERV_COMMAND_ALLIANCE_EFFECTS(const std::vector<CCharEntity*>& membersList);
};
