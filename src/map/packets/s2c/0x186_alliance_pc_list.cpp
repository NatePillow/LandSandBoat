/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x186_alliance_pc_list.h"

#include <algorithm>
#include <cstring>

GP_SERV_COMMAND_ALLIANCE_PC_LIST::GP_SERV_COMMAND_ALLIANCE_PC_LIST(const std::vector<std::pair<std::string, uint8_t>>& pcs)
{
    auto& packet = this->data();

    std::memset(packet.Padding, 0, sizeof(packet.Padding));
    std::memset(packet.Entries, 0, sizeof(packet.Entries));

    const size_t count = std::min(pcs.size(), kMaxEntries);
    packet.Count       = static_cast<uint8_t>(count);

    for (size_t i = 0; i < count; ++i)
    {
        const auto&  [name, partyNo] = pcs[i];
        const size_t nameLen         = std::min(name.size(), kNameLen - 1);
        std::memcpy(packet.Entries[i].Name, name.data(), nameLen);
        packet.Entries[i].PartyNo = partyNo;
    }
}
