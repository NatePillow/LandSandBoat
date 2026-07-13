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

#include "0x168_autowarp.h"

#include "ai/ai_container.h"
#include "entities/charentity.h"
#include "entities/mobentity.h"
#include "enums/chat_message_type.h"
#include "packets/s2c/0x017_chat_std.h"
#include "packets/s2c/0x05b_wpos.h"
#include "utils/zoneutils.h"
#include "zone.h"
#include "zone_entities.h"

#include <algorithm>

auto GP_CLI_COMMAND_WARP::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar)
        .range("subcmd", subcmd, 0, 2);
}

void GP_CLI_COMMAND_WARP::process(MapSession* PSession, CCharEntity* PChar) const
{
    std::string targetName(target_name, strnlen(target_name, sizeof(target_name)));
    std::replace(targetName.begin(), targetName.end(), '_', ' ');

    if (subcmd == 0) // player
    {
        CCharEntity* PTarget = zoneutils::GetCharByName(targetName);
        if (!PTarget)
        {
            PChar->pushPacket<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SYSTEM_1,
                "Player \"" + targetName + "\" not found.");
            return;
        }

        PTarget->loc.p = PChar->loc.p;

        uint16 destZone = PChar->getZone();
        if (PTarget->getZone() != destZone)
        {
            auto ipp = zoneutils::GetZoneIPP(destZone);
            if (ipp == 0)
            {
                PChar->pushPacket<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SYSTEM_1,
                    "Could not enter the target zone.");
                return;
            }
            PTarget->loc.destination     = destZone;
            PTarget->status              = STATUS_TYPE::DISAPPEAR;
            PTarget->loc.boundary        = 0;
            PTarget->m_moghouseID        = 0;
            PTarget->requestedZoneChange = true;
            if (PTarget->shouldPetPersistThroughZoning())
            {
                PTarget->setPetZoningInfo();
            }
        }
        else if (PTarget->status != STATUS_TYPE::DISAPPEAR)
        {
            PTarget->pushPacket<GP_SERV_COMMAND_WPOS>(PTarget, PTarget->loc.p);
        }
        PTarget->updatemask |= UPDATE_POS;
    }
    else if (subcmd == 2) // self position sync: echo sender's current server position back to them as WPOS
    {
        if (PChar->status != STATUS_TYPE::DISAPPEAR)
        {
            PChar->pushPacket<GP_SERV_COMMAND_WPOS>(PChar, PChar->loc.p);
        }
    }
    else if (subcmd == 1) // enemy
    {
        CMobEntity* PTarget = nullptr;
        for (auto& [targid, PEntity] : PChar->loc.zone->GetZoneEntities()->GetMobList())
        {
            if (PEntity->getName() == targetName)
            {
                auto* PMob = static_cast<CMobEntity*>(PEntity);
                if (PMob->PAI->IsSpawned())
                {
                    PTarget = PMob;
                    break;
                }
            }
        }
        if (!PTarget)
        {
            PChar->pushPacket<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SYSTEM_1,
                "Enemy \"" + targetName + "\" not found in this zone.");
            return;
        }
        float dx = PTarget->loc.p.x - PChar->loc.p.x;
        float dz = PTarget->loc.p.z - PChar->loc.p.z;
        float dy = PTarget->loc.p.y - PChar->loc.p.y;
        if ((dx * dx + dz * dz + dy * dy) > 100.0f * 100.0f)
        {
            PChar->pushPacket<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SYSTEM_1,
                "Enemy \"" + targetName + "\" is too far away (limit: 100 yalms).");
            return;
        }
        PTarget->loc.p.x        = PChar->loc.p.x;
        PTarget->loc.p.y        = PChar->loc.p.y;
        PTarget->loc.p.z        = PChar->loc.p.z;
        PTarget->loc.p.rotation = PChar->loc.p.rotation;
        PTarget->updatemask |= UPDATE_POS;
    }
}
