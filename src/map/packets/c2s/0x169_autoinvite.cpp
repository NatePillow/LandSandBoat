/*
===========================================================================

  Copyright (c) 2025 LandSandBoat Dev Teams

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

#include "0x169_autoinvite.h"

#include "alliance.h"
#include "entities/charentity.h"
#include "enums/chat_message_type.h"
#include "packets/s2c/0x017_chat_std.h"
#include "party.h"
#include "utils/zoneutils.h"

#include <algorithm>
#include <array>
#include <string>
#include <vector>

auto GP_CLI_COMMAND_AUTOINVITE::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar)
        .range("party_count", party_count, 1, 3);
}

void GP_CLI_COMMAND_AUTOINVITE::process(MapSession* PSession, CCharEntity* PChar) const
{
    auto safeName = [](const char* buf, size_t maxLen) -> std::string
    {
        return std::string(buf, strnlen(buf, maxLen));
    };

    auto sendError = [&](const std::string& msg)
    {
        PChar->pushPacket<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SYSTEM_1, msg);
    };

    // ----------------------------------------------------------------
    // Slot definitions from packet fields
    // ----------------------------------------------------------------
    struct SlotDef
    {
        std::string              leaderName;
        uint8_t                  memberCount;
        std::array<std::string, 5> memberNames;
    };

    std::array<SlotDef, 3> defs = {};
    defs[0] = { safeName(pt1_leader, 16), pt1_member_count, { safeName(pt1_members[0], 16), safeName(pt1_members[1], 16), safeName(pt1_members[2], 16), safeName(pt1_members[3], 16), safeName(pt1_members[4], 16) } };
    defs[1] = { safeName(pt2_leader, 16), pt2_member_count, { safeName(pt2_members[0], 16), safeName(pt2_members[1], 16), safeName(pt2_members[2], 16), safeName(pt2_members[3], 16), safeName(pt2_members[4], 16) } };
    defs[2] = { safeName(pt3_leader, 16), pt3_member_count, { safeName(pt3_members[0], 16), safeName(pt3_members[1], 16), safeName(pt3_members[2], 16), safeName(pt3_members[3], 16), safeName(pt3_members[4], 16) } };

    // ----------------------------------------------------------------
    // Resolve all characters and validate before touching any party state
    // ----------------------------------------------------------------
    struct SlotChars
    {
        CCharEntity*              leader = nullptr;
        std::vector<CCharEntity*> members;
    };

    std::vector<SlotChars> slots(party_count);

    for (uint8_t s = 0; s < party_count; s++)
    {
        const auto& def = defs[s];
        auto&       sc  = slots[s];

        if (def.leaderName.empty())
        {
            sendError("AutoInvite: pt" + std::to_string(s + 1) + " leader name is empty.");
            return;
        }

        sc.leader = zoneutils::GetCharByName(def.leaderName);
        if (sc.leader == nullptr)
        {
            sendError("AutoInvite: Leader not found: " + def.leaderName);
            return;
        }

        if (sc.leader->PParty != nullptr)
        {
            sendError("AutoInvite: " + def.leaderName + " is already in a party.");
            return;
        }

        uint8_t count = std::min(def.memberCount, (uint8_t)5);
        for (uint8_t m = 0; m < count; m++)
        {
            if (def.memberNames[m].empty())
            {
                continue;
            }

            CCharEntity* PMember = zoneutils::GetCharByName(def.memberNames[m]);
            if (PMember == nullptr)
            {
                sendError("AutoInvite: Member not found: " + def.memberNames[m]);
                return;
            }

            if (PMember->PParty != nullptr)
            {
                sendError("AutoInvite: " + def.memberNames[m] + " is already in a party.");
                return;
            }

            sc.members.push_back(PMember);
        }
    }

    // ----------------------------------------------------------------
    // Form parties
    // ----------------------------------------------------------------
    for (uint8_t s = 0; s < party_count; s++)
    {
        auto& sc    = slots[s];
        sc.leader->PParty = new CParty(sc.leader);
        for (auto* PMember : sc.members)
        {
            sc.leader->PParty->AddMember(PMember);
        }
    }

    // ----------------------------------------------------------------
    // Form alliance if more than one party
    // ----------------------------------------------------------------
    if (party_count > 1)
    {
        slots[0].leader->PParty->m_PAlliance = new CAlliance(slots[0].leader);
        for (uint8_t s = 1; s < party_count; s++)
        {
            slots[0].leader->PParty->m_PAlliance->addParty(slots[s].leader->PParty);
        }
    }

    ShowInfo("AutoInvite: %d-party group formed by request from %s", party_count, PChar->getName());
}
