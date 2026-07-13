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

class CCharEntity;

// Custom packet (singleplayer fork): response to 0x19E AUTOMOG_GET_JOB_INFO.
// Carries the target's name, current MJ + SJ, the unlocked-jobs bitfield,
// per-job levels for the first MAX_JOB_LEVEL_ENTRIES (24 — covers all current
// and forseeable jobs), and the target's current appearance (race/face/size)
// so the Change-Look UI can seed its staged values from the same fetch.
// Status = 0 ok, 1 = no target, 2 = ownership rejected.
class GP_SERV_COMMAND_AUTOMOG_JOB_INFO final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_AUTOMOG_JOB_INFO, GP_SERV_COMMAND_AUTOMOG_JOB_INFO>
{
public:
    static constexpr std::size_t MAX_JOB_LEVEL_ENTRIES = 24;

    struct PacketData
    {
        char     TargetCharName[16];
        uint8_t  Status;
        uint8_t  CurrentMJob;
        uint8_t  CurrentSJob;
        uint8_t  padding;
        uint32_t UnlockedMask;
        uint8_t  JobLevels[MAX_JOB_LEVEL_ENTRIES];
        uint8_t  CurrentRace;
        uint8_t  CurrentFace;
        uint8_t  CurrentSize;
        uint8_t  lookPadding;
    };

    GP_SERV_COMMAND_AUTOMOG_JOB_INFO(CCharEntity* targetChar, uint8_t status);
    // Error-only variant when there's no target (just sets status + leaves the
    // rest zero so the addon can render an error toast).
    GP_SERV_COMMAND_AUTOMOG_JOB_INFO(const std::string& targetName, uint8_t status);
};
