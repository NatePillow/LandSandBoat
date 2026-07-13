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

#include "0x16a_instance_enter.h"

#include "battlefield.h"
#include "battlefield_handler.h"
#include "entities/charentity.h"
#include "enums/chat_message_type.h"
#include "instance.h"
#include "map_session_container.h"
#include "packets/s2c/0x017_chat_std.h"
#include "packets/s2c/0x1a0_instance_enter_result.h"
#include "zone.h"
#include "zone_instance.h"

#include "common/logging.h"

#include <cstring>
#include <functional>
#include <string>
#include <unordered_set>

namespace
{

// Build the "is this member selected by the sender's scope" predicate.
//   subcmd 0 → every party member
//   subcmd 1 → every alliance member
//   subcmd 2 → only chars whose names appear in the names[] window
auto buildSelector(uint8 subcmd, uint8 count, const char (&names)[18][16])
    -> std::function<bool(const CCharEntity*)>
{
    if (subcmd != 2)
    {
        return [](const CCharEntity*) { return true; };
    }
    std::unordered_set<std::string> wanted;
    wanted.reserve(count);
    for (uint8 i = 0; i < count && i < 18; ++i)
    {
        const size_t len  = strnlen(names[i], sizeof(names[i]));
        std::string  name(names[i], len);
        if (!name.empty())
        {
            wanted.insert(std::move(name));
        }
    }
    return [wanted = std::move(wanted)](const CCharEntity* PMember)
    {
        return wanted.find(PMember->getName()) != wanted.end();
    };
}

// Walk PARTY (subcmd 0) or ALLIANCE (1 / 2) and apply fn to each selected
// CCharEntity. subcmd 2 still walks the alliance — names[] is the filter,
// not a separate routing channel.
void walkScope(CCharEntity* PChar, uint8 subcmd,
               const std::function<bool(const CCharEntity*)>& selector,
               const std::function<void(CCharEntity*)>& fn)
{
    auto callback = [&](CBattleEntity* PEntity)
    {
        auto* PMember = dynamic_cast<CCharEntity*>(PEntity);
        if (PMember == nullptr || !selector(PMember))
        {
            return;
        }
        fn(PMember);
    };
    if (subcmd == 0)
    {
        PChar->ForParty(callback);
    }
    else
    {
        PChar->ForAlliance(callback);
    }
}

// Common in-process bot move: detach from old zone, snap to sender's
// position, attach to sender's zone. Returns true if anything moved.
// Caller is responsible for setting up CInstance association BEFORE calling
// for CZoneInstance targets (IncreaseZoneCounter uses PChar->PInstance to
// route into the right copy).
auto moveBotIntoSenderZone(CCharEntity* PSender, CCharEntity* PBot) -> bool
{
    CZone* destZone = PSender->loc.zone;
    if (destZone == nullptr)
    {
        return false;
    }
    if (PBot->loc.zone == destZone && PBot->PInstance == PSender->PInstance)
    {
        // Already in the right spot; just snap position so the user can see
        // we acknowledged the request.
        PBot->loc.p = PSender->loc.p;
        return false;
    }
    if (PBot->loc.zone != nullptr)
    {
        PBot->loc.zone->DecreaseZoneCounter(PBot);
    }
    PBot->loc.destination = destZone->GetID();
    PBot->loc.p           = PSender->loc.p;
    // SINGLEPLAYER: loc.zoning field removed upstream — auto-managed now.
    destZone->IncreaseZoneCounter(PBot);
    PBot->status = STATUS_TYPE::NORMAL;
    mapsessions::persistHeadlessPosZone(PBot); // keep chars.pos_zone in sync with the hop
    PBot->clearPacketList();
    return true;
}

} // namespace

auto GP_CLI_COMMAND_INSTANCE_ENTER::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidationResult();
}

void GP_CLI_COMMAND_INSTANCE_ENTER::process(MapSession* PSession, CCharEntity* PChar) const
{
    // Status: 0=ok 1=no_active_instance 2=no_pinstance 3=no_zone
    // Branch: 0=BCNM 1=DYNAMIS 2=INSTANCED 0xFF=no match
    auto sendResult = [&](uint8_t status, uint8_t branch, uint8_t moved)
    {
        PChar->pushPacket<GP_SERV_COMMAND_INSTANCE_ENTER_RESULT>(status, branch, moved);
    };

    auto sendError = [&](const std::string& msg)
    {
        PChar->pushPacket<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SYSTEM_1, msg);
    };

    if (PChar->loc.zone == nullptr)
    {
        sendError("No zone state on sender.");
        sendResult(3u, 0xFFu, 0u);
        return;
    }

    auto selector = buildSelector(subcmd, count, names);

    // Branch 1 — BCNM (active battlefield with sender as initiator).
    // Members must already be physically in the same zone as the battlefield;
    // CBattlefield::InsertEntity inserts them into the battlefield's tracking
    // and runs the per-BCNM OnBattlefieldEnter Lua hook + level restrictions.
    if (PChar->loc.zone->m_BattlefieldHandler != nullptr)
    {
        if (CBattlefield* PBattlefield =
                PChar->loc.zone->m_BattlefieldHandler->GetBattlefieldByInitiator(PChar->id))
        {
            const uint16 senderZone = PChar->getZone();
            uint32       insertedCount = 0;
            walkScope(PChar, subcmd, selector, [&](CCharEntity* PMember)
            {
                if (PMember->getZone() != senderZone)
                {
                    return;
                }
                if (PBattlefield->InsertEntity(PMember, true))
                {
                    ++insertedCount;
                }
            });
            sendResult(0u, 0u, static_cast<uint8_t>(std::min<uint32>(insertedCount, 255u)));
            return;
        }
    }

    const uint16 typeMask = static_cast<uint16>(PChar->loc.zone->GetTypeMask());

    // Branch 2 — Dynamis (static instance zones; ZONE_TYPE::DYNAMIS).
    // Pulls bots that the moveHeadlessToPrimaryZone filter stranded when
    // the sender used a Dragon's Aery / Veridical Conflux / etc. to enter
    // Dynamis solo. No CInstance work needed — Dynamis zones are static
    // (single shared zone, alliances coexist).
    if ((typeMask & static_cast<uint16>(ZONE_TYPE::DYNAMIS)) != 0)
    {
        uint32 movedCount = 0;
        walkScope(PChar, subcmd, selector, [&](CCharEntity* PMember)
        {
            if (moveBotIntoSenderZone(PChar, PMember))
            {
                ++movedCount;
            }
        });
        ShowDebugFmt("INSTANCE_ENTER (DYNAMIS): pulled {} member(s) to '{}' in zone {}",
                     movedCount, PChar->getName(), PChar->getZone());
        sendResult(0u, 1u, static_cast<uint8_t>(std::min<uint32>(movedCount, 255u)));
        return;
    }

    // Branch 3 — INSTANCED (CZoneInstance — Salvage, Limbus, Einherjar,
    // Walk of Echoes, etc.). Sender must already be inside an instance
    // copy (PInstance is non-null). We attach each member to the same
    // CInstance and RegisterChar before IncreaseZoneCounter so they land
    // in the correct copy rather than the CZoneInstance "exit area"
    // fallback for unregistered chars.
    if ((typeMask & static_cast<uint16>(ZONE_TYPE::INSTANCED)) != 0)
    {
        if (PChar->PInstance == nullptr)
        {
            sendError("Sender has no active instance assignment.");
            sendResult(2u, 2u, 0u);
            return;
        }
        CInstance* PInstance  = PChar->PInstance;
        uint32     movedCount = 0;
        walkScope(PChar, subcmd, selector, [&](CCharEntity* PMember)
        {
            if (PMember->PInstance == PInstance && PMember->loc.zone == PChar->loc.zone)
            {
                return;
            }
            PMember->PInstance = PInstance;
            if (!PInstance->CharRegistered(PMember))
            {
                PInstance->RegisterChar(PMember);
            }
            if (moveBotIntoSenderZone(PChar, PMember))
            {
                ++movedCount;
            }
        });
        ShowDebugFmt("INSTANCE_ENTER (INSTANCED): pulled {} member(s) to '{}' in instance of zone {}",
                     movedCount, PChar->getName(), PChar->getZone());
        sendResult(0u, 2u, static_cast<uint8_t>(std::min<uint32>(movedCount, 255u)));
        return;
    }

    sendError("No active battlefield, Dynamis, or instance in this zone.");
    sendResult(1u, 0xFFu, 0u);
}
