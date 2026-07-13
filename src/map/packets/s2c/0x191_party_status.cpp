/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x191_party_status.h"

#include <algorithm>
#include <cstring>

GP_SERV_COMMAND_PARTY_STATUS::GP_SERV_COMMAND_PARTY_STATUS(uint8_t partyNumber,
                                                          const std::vector<Member>& members)
{
    auto& packet = this->data();

    std::memset(&packet, 0, sizeof(packet));

    packet.PartyNumber = partyNumber;

    const size_t count = std::min(members.size(), kMaxEntries);
    packet.MemberCount = static_cast<uint8_t>(count);

    for (size_t i = 0; i < count; ++i)
    {
        const auto& m = members[i];
        Entry&      e = packet.Entries[i];

        const size_t nameLen = std::min(m.Name.size(), kNameLen - 1);
        std::memcpy(e.Name, m.Name.data(), nameLen);

        e.Race       = m.Race;
        e.Face       = m.Face;
        e.ExpCurrent = m.ExpCurrent;
        e.ExpToNext  = m.ExpToNext;

        const size_t effCount = std::min(m.Effects.size(), kMaxEffectsPerBot);
        e.EffectCount         = static_cast<uint8_t>(effCount);
        for (size_t j = 0; j < effCount; ++j)
        {
            e.EffectIds[j] = m.Effects[j];
        }
    }
}
