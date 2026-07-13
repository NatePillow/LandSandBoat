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

#include "0x19f_automog_job_info.h"

#include "entities/charentity.h"

#include <algorithm>
#include <cstring>

namespace
{

void writeName(char (&dest)[16], const std::string& src)
{
    const auto len = std::min(src.size(), sizeof(dest));
    std::memset(dest, 0, sizeof(dest));
    std::memcpy(dest, src.data(), len);
}

} // namespace

GP_SERV_COMMAND_AUTOMOG_JOB_INFO::GP_SERV_COMMAND_AUTOMOG_JOB_INFO(CCharEntity* targetChar, uint8_t status)
{
    auto& packet  = this->data();
    packet.Status = status;
    if (targetChar == nullptr)
    {
        return;
    }
    writeName(packet.TargetCharName, targetChar->getName());
    packet.CurrentMJob  = static_cast<uint8_t>(targetChar->GetMJob());
    packet.CurrentSJob  = static_cast<uint8_t>(targetChar->GetSJob());
    packet.UnlockedMask = targetChar->jobs.unlocked;
    const auto limit    = std::min<std::size_t>(MAX_JOB_LEVEL_ENTRIES, MAX_JOBTYPE);
    for (std::size_t i = 0; i < limit; ++i)
    {
        packet.JobLevels[i] = targetChar->jobs.job[i];
    }
    packet.CurrentRace = targetChar->look.race;
    packet.CurrentFace = targetChar->look.face;
    packet.CurrentSize = targetChar->look.size;
}

GP_SERV_COMMAND_AUTOMOG_JOB_INFO::GP_SERV_COMMAND_AUTOMOG_JOB_INFO(const std::string& targetName, uint8_t status)
{
    auto& packet  = this->data();
    packet.Status = status;
    writeName(packet.TargetCharName, targetName);
}
