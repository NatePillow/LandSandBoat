/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x18c_bot_spells_list.h"

#include <algorithm>
#include <cstring>

GP_SERV_COMMAND_BOT_SPELLS_LIST::GP_SERV_COMMAND_BOT_SPELLS_LIST(const std::string& botName, uint8_t groupFilter, bool isFinal,
                                                                  const std::vector<std::pair<uint16_t, std::string>>& entries)
{
    auto& packet = this->data();

    std::memset(packet.BotName, 0, sizeof(packet.BotName));
    std::memset(packet.Entries, 0, sizeof(packet.Entries));

    const size_t nameLen = std::min(botName.size(), sizeof(packet.BotName) - 1);
    std::memcpy(packet.BotName, botName.data(), nameLen);

    packet.GroupFilter = groupFilter;
    packet.IsFinal     = isFinal ? 1 : 0;
    packet.Padding     = 0;

    const size_t count = std::min(entries.size(), kEntriesPerChunk);
    packet.Count       = static_cast<uint8_t>(count);

    for (size_t i = 0; i < count; ++i)
    {
        const auto&  [spellId, name] = entries[i];
        const size_t entryNameLen     = std::min(name.size(), kNameLen - 1);
        packet.Entries[i].SpellId = spellId;
        std::memcpy(packet.Entries[i].Name, name.data(), entryNameLen);
    }
}
