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

#include "0x19c_automog_change_job.h"

#include "ai/ai_container.h"
#include "common/logging.h"
#include "entities/charentity.h"
#include "map_session_container.h"
#include "packets/s2c/0x19d_automog_change_job_result.h"
#include "status_effect_container.h"
#include "utils/jailutils.h"

#include <cstring>
#include <string>

namespace
{

constexpr uint8_t FLAG_CHANGE_MJ = 0x01;
constexpr uint8_t FLAG_CHANGE_SJ = 0x02;

constexpr uint8_t STATUS_OK         = 0;
constexpr uint8_t STATUS_NO_TARGET  = 1;
constexpr uint8_t STATUS_NOT_OWNED  = 2;
constexpr uint8_t STATUS_ENGAGED    = 3;
constexpr uint8_t STATUS_JOB_LOCKED = 4;
constexpr uint8_t STATUS_LEVEL_ZERO = 5;
constexpr uint8_t STATUS_NOOP       = 6;

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

auto GP_CLI_COMMAND_AUTOMOG_CHANGE_JOB::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar)
        .mustEqual(jailutils::InPrison(PChar), false, "Cannot change job while jailed");
}

void GP_CLI_COMMAND_AUTOMOG_CHANGE_JOB::process(MapSession* PSession, CCharEntity* PChar) const
{
    auto sendResult = [&](uint8_t status)
    {
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_CHANGE_JOB_RESULT>(status);
    };

    const std::string targetName = sanitizeName(TargetCharName);
    if (targetName.empty())
    {
        sendResult(STATUS_NO_TARGET);
        return;
    }

    auto* targetSession = mapsessions::get().getSessionByCharName(targetName);
    if (targetSession == nullptr || targetSession->PChar == nullptr)
    {
        sendResult(STATUS_NO_TARGET);
        return;
    }

    CCharEntity* targetChar = targetSession->PChar.get();
    const bool   owned      = (targetChar == PChar) || (targetSession->parentCharId == PChar->id);
    if (!owned)
    {
        ShowWarningFmt("AUTOMOG_CHANGE_JOB: ownership rejected (sender={} target={})",
                       PChar->getName(), targetName);
        sendResult(STATUS_NOT_OWNED);
        return;
    }

    if (targetChar->PAI->IsEngaged())
    {
        sendResult(STATUS_ENGAGED);
        return;
    }

    const bool wantMJ = (Flags & FLAG_CHANGE_MJ) != 0;
    const bool wantSJ = (Flags & FLAG_CHANGE_SJ) != 0;

    const bool mjDiffers = wantMJ && NewMJob != static_cast<uint8_t>(targetChar->GetMJob());
    const bool sjDiffers = wantSJ && NewSJob != static_cast<uint8_t>(targetChar->GetSJob());

    if (!mjDiffers && !sjDiffers)
    {
        sendResult(STATUS_NOOP);
        return;
    }

    auto jobIsAvailable = [&](uint8_t jobId) -> uint8_t
    {
        if (jobId >= MAX_JOBTYPE)
        {
            return STATUS_JOB_LOCKED;
        }
        if ((targetChar->jobs.unlocked & (1u << jobId)) == 0)
        {
            return STATUS_JOB_LOCKED;
        }
        if (targetChar->jobs.job[jobId] == 0)
        {
            return STATUS_LEVEL_ZERO;
        }
        return STATUS_OK;
    };

    if (mjDiffers)
    {
        if (auto err = jobIsAvailable(NewMJob); err != STATUS_OK)
        {
            sendResult(err);
            return;
        }
    }
    if (sjDiffers)
    {
        if (auto err = jobIsAvailable(NewSJob); err != STATUS_OK)
        {
            sendResult(err);
            return;
        }
    }

    if (mjDiffers)
    {
        targetChar->changeMJob(NewMJob);
    }
    if (sjDiffers)
    {
        targetChar->changeSJob(NewSJob);
    }

    sendResult(STATUS_OK);
}
