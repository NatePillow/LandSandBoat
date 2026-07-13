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

#include "0x151_addon_relay.h"

#include "entities/charentity.h"
#include "map_session.h"
#include "packets/s2c/0x152_addon_relay.h"
#include "party.h"
#include "alliance.h"

auto GP_CLI_COMMAND_ADDON_RELAY::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidationResult{};
}

void GP_CLI_COMMAND_ADDON_RELAY::process(MapSession* PSession, CCharEntity* PChar) const
{
    auto sendToMember = [&](CCharEntity* PMember)
    {
        if (PMember && PMember->getZone() == PChar->getZone())
        {
            PMember->pushPacket<GP_SERV_COMMAND_ADDON_RELAY>(PChar->id, this->Payload);
        }
    };

    if (PChar->PParty && PChar->PParty->m_PAlliance)
    {
        for (auto* PParty : PChar->PParty->m_PAlliance->partyList)
        {
            for (auto& PMemberB : PParty->members)
            {
                sendToMember(static_cast<CCharEntity*>(PMemberB));
            }
        }
    }
    else if (PChar->PParty)
    {
        for (auto& PMemberB : PChar->PParty->members)
        {
            sendToMember(static_cast<CCharEntity*>(PMemberB));
        }
    }
    else
    {
        sendToMember(PChar);
    }
}
