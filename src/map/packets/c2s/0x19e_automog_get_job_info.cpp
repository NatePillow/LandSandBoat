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

#include "0x19e_automog_get_job_info.h"

#include "common/logging.h"
#include "entities/charentity.h"
#include "map_session_container.h"
#include "packets/s2c/0x19f_automog_job_info.h"

#include <cstring>
#include <string>

namespace
{

auto sanitizeName(const char* raw) -> std::string
{
    if (raw == nullptr)
    {
        return {};
    }
    std::string s(raw, strnlen(raw, 16));
    while (!s.empty() && s.back() == '\0')
    {
        s.pop_back();
    }
    return s;
}

} // namespace

auto GP_CLI_COMMAND_AUTOMOG_GET_JOB_INFO::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidationResult();
}

void GP_CLI_COMMAND_AUTOMOG_GET_JOB_INFO::process(MapSession* PSession, CCharEntity* PChar) const
{
    const std::string targetName = sanitizeName(TargetCharName);
    if (targetName.empty())
    {
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_JOB_INFO>(targetName, 1u);
        return;
    }

    auto* targetSession = mapsessions::get().getSessionByCharName(targetName);
    if (targetSession == nullptr || targetSession->PChar == nullptr)
    {
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_JOB_INFO>(targetName, 1u);
        return;
    }

    CCharEntity* targetChar = targetSession->PChar.get();
    const bool   owned      = (targetChar == PChar) || (targetSession->parentCharId == PChar->id);
    if (!owned)
    {
        ShowWarningFmt("AUTOMOG_GET_JOB_INFO: ownership rejected (sender={} target={})",
                       PChar->getName(), targetName);
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_JOB_INFO>(targetName, 2u);
        return;
    }

    PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_JOB_INFO>(targetChar, 0u);
}
