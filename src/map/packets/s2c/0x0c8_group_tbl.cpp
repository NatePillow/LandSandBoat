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

#include "0x0c8_group_tbl.h"

#include "alliance.h"
#include "common/database.h"
#include "common/logging.h"
#include "map_engine.h"
#include "party.h"

#include "entities/charentity.h"
#include "entities/trustentity.h"
#include "enums/party_kind.h"
#include "utils/zoneutils.h"

GP_SERV_COMMAND_GROUP_TBL::GP_SERV_COMMAND_GROUP_TBL(CParty* PParty, const bool loadTrust)
{
    auto& packet = this->data();

    if (PParty)
    {
        packet.Kind = PParty->m_PAlliance ? PartyKind::Alliance : PartyKind::Party;

        uint32 allianceid = 0;
        if (PParty->m_PAlliance)
        {
            allianceid = PParty->m_PAlliance->m_AllianceID;
        }

        const auto rset = db::preparedStmt("SELECT chars.charid, partyflag, pos_zone, pos_prevzone "
                                                   "FROM accounts_parties "
                                                   "LEFT JOIN chars ON accounts_parties.charid = chars.charid WHERE "
                                                   "IF (allianceid <> 0, allianceid = ?, partyid = ?) "
                                                   "ORDER BY partyflag & ?, timestamp",
                                                   allianceid,
                                                   PParty->GetPartyID(),
                                                   PARTY_SECOND | PARTY_THIRD);

        uint8 i = 0;
        uint16 current_party_bits = 0;
        std::vector<CCharEntity*> partyLeaders;

        FOR_DB_MULTIPLE_RESULTS(rset)
        {
            uint32 charid = rset->get<uint32>("charid");
            uint32 partyflag = rset->get<uint32>("partyflag");
            uint16 row_party_bits = partyflag & (PARTY_SECOND | PARTY_THIRD);

            // If we move to a new party in the alliance, process the PREVIOUS party's trusts first
            if (row_party_bits != current_party_bits)
            {
            // Add trusts for the PREVIOUS party leaders before starting the next PC group
                for (auto* PLeader : partyLeaders) {
                    for (auto* PTrust : PLeader->PTrusts) {
                        if (i >= 20) break;
                        packet.GroupTbl[i].UniqueNo = PTrust->id;
                        packet.GroupTbl[i].ActIndex = PTrust->targid;
                        packet.GroupTbl[i].PartyNo  = (current_party_bits >> 0) & 0x03;
                        packet.GroupTbl[i].ZoneNo   = PTrust->getZone();
                        i++;
                    }
                }
                current_party_bits = row_party_bits;
                partyLeaders.clear();
            }

            // 1. Add the Player (PCs always come first)
            if (i < 20) {
                packet.GroupTbl[i].UniqueNo          = charid;
                packet.GroupTbl[i].PartyNo           = (partyflag >> 0) & 0x03;
                packet.GroupTbl[i].PartyLeaderFlg    = (partyflag >> 2) & 0x01;
                packet.GroupTbl[i].AllianceLeaderFlg = (partyflag >> 3) & 0x01;
                packet.GroupTbl[i].PartyRFlg         = (partyflag >> 4) & 0x01;
                packet.GroupTbl[i].AllianceRFlg      = (partyflag >> 5) & 0x01;

                auto pos_zone = rset->getOrDefault<uint16>("pos_zone", 0);
                packet.GroupTbl[i].ZoneNo = pos_zone ? pos_zone : rset->get<uint16>("pos_prevzone");

                // If this is a leader, track them to add their trusts later
                if (packet.GroupTbl[i].PartyLeaderFlg) {
                    if (auto* PLeader = (CCharEntity*)zoneutils::GetChar(charid)) {
                        partyLeaders.push_back(PLeader);
                    }
                }
                i++;
            }
        }

        // Final cleanup: Add trusts for the last party in the result set
        for (auto* PLeader : partyLeaders) {
            for (auto* PTrust : PLeader->PTrusts) {
                if (i >= 20) break;
                packet.GroupTbl[i].UniqueNo = PTrust->id;
                packet.GroupTbl[i].ActIndex = PTrust->targid;
                packet.GroupTbl[i].PartyNo  = (current_party_bits >> 0) & 0x03;
                packet.GroupTbl[i].ZoneNo   = PTrust->getZone();
                i++;
            }
        }
    }
}
