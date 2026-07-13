/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "0x185_list_alliance_pcs.h"

#include "alliance.h"
#include "entities/charentity.h"
#include "packets/s2c/0x186_alliance_pc_list.h"
#include "party.h"

#include <utility>
#include <vector>

auto GP_CLI_COMMAND_LIST_ALLIANCE_PCS::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_LIST_ALLIANCE_PCS::process(MapSession* PSession, CCharEntity* PChar) const
{
    std::vector<std::pair<std::string, uint8>> pcs;

    auto collect = [&pcs](CParty* PParty, uint8 partyNo)
    {
        if (PParty == nullptr)
        {
            return;
        }
        for (auto* PMember : PParty->members)
        {
            if (auto* PChr = dynamic_cast<CCharEntity*>(PMember))
            {
                pcs.emplace_back(PChr->getName(), partyNo);
            }
        }
    };

    if (PChar->PParty != nullptr && PChar->PParty->m_PAlliance != nullptr)
    {
        const auto& parties = PChar->PParty->m_PAlliance->partyList;
        for (size_t i = 0; i < parties.size(); ++i)
        {
            collect(parties[i], static_cast<uint8>(i + 1));
        }
    }
    else if (PChar->PParty != nullptr)
    {
        collect(PChar->PParty, 1);
    }
    else
    {
        // Solo: only the caller.
        pcs.emplace_back(PChar->getName(), 1);
    }

    PChar->pushPacket<GP_SERV_COMMAND_ALLIANCE_PC_LIST>(pcs);
}
