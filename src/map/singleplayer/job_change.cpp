/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

// Out-of-line definitions for the singleplayer-fork CCharEntity additions
// (isHeadless, changeMJob, changeSJob). Declarations live in charentity.h
// (they have to — they're class member methods) but keeping the bodies here
// means upstream charentity.cpp stays at its vanilla footprint.

#include "entities/charentity.h"

#include "char_recast_container.h"
#include "job_points.h"
#include "latent_effect_container.h"
#include "packets/char_status.h"
#include "packets/char_sync.h"
#include "packets/s2c/0x01b_job_info.h"
#include "packets/s2c/0x061_clistatus.h"
#include "packets/s2c/0x062_clistatus2.h"
#include "packets/s2c/0x063_miscdata_merits.h"
#include "packets/s2c/0x063_miscdata_monstrosity.h"
#include "packets/s2c/0x0ac_command_data.h"
#include "packets/s2c/0x119_abil_recast.h"
#include "lua/luautils.h"
#include "map_session.h"
#include "status_effect_container.h"
#include "ai/ai_container.h"

#include "utils/blueutils.h"
#include "utils/charutils.h"
#include "utils/puppetutils.h"

auto CCharEntity::isHeadless() const -> bool
{
    return PSession != nullptr && PSession->parentCharId != 0;
}

void CCharEntity::changeMJob(uint8 newJob)
{
    JOBTYPE prevjob = GetMJob();

    resetPetZoningInfo();

    charutils::RemoveAllEquipMods(this);
    jobs.unlocked |= (1 << newJob);
    SetMJob(newJob);
    charutils::ApplyAllEquipMods(this);

    if (newJob == JOB_BLU)
    {
        if (prevjob != JOB_BLU)
        {
            blueutils::LoadSetSpells(this);
        }
    }
    else if (GetSJob() != JOB_BLU)
    {
        blueutils::UnequipAllBlueSpells(this);
    }

    puppetutils::LoadAutomaton(this);
    ShowInfo(fmt::format("[STYLELOCK] caller=changeMJob char={}", this->getName()));
    charutils::SetStyleLock(this, false);
    luautils::CheckForGearSet(this);
    jobpointutils::RefreshGiftMods(this);
    charutils::BuildingCharSkillsTable(this);
    charutils::CalculateStats(this);
    charutils::CheckValidEquipment(this);
    PRecastContainer->ChangeJob();
    charutils::BuildingCharAbilityTable(this);
    charutils::BuildingCharTraitsTable(this);

    // clang-format off
    ForParty([](CBattleEntity* PMember)
    {
        static_cast<CCharEntity*>(PMember)->PLatentEffectContainer->CheckLatentsPartyJobs();
    });
    // clang-format on

    UpdateHealth();
    health.hp = GetMaxHP();
    health.mp = GetMaxMP();

    charutils::SaveCharStats(this);
    charutils::SaveCharJob(this, GetMJob());
    charutils::SaveCharExp(this, GetMJob());
    updatemask |= UPDATE_HP;

    pushPacket<GP_SERV_COMMAND_JOB_INFO>(this);
    pushPacket<GP_SERV_COMMAND_CLISTATUS>(this);
    pushPacket<GP_SERV_COMMAND_CLISTATUS2>(this);
    pushPacket<GP_SERV_COMMAND_ABIL_RECAST>(this);
    pushPacket<GP_SERV_COMMAND_COMMAND_DATA>(this);
    pushPacket<CCharStatusPacket>(this);
    pushPacket<GP_SERV_COMMAND_MISCDATA::MERITS>(this);
    pushPacket<GP_SERV_COMMAND_MISCDATA::MONSTROSITY1>(this);
    pushPacket<GP_SERV_COMMAND_MISCDATA::MONSTROSITY2>(this);
    pushPacket<CCharSyncPacket>(this);
}

void CCharEntity::changeSJob(uint8 newJob)
{
    jobs.unlocked |= (1 << newJob);
    SetSJob(newJob);
    charutils::UpdateSubJob(this);

    if (newJob == JOB_BLU)
    {
        blueutils::LoadSetSpells(this);
    }
    else
    {
        blueutils::UnequipAllBlueSpells(this);
    }

    puppetutils::LoadAutomaton(this);
}
