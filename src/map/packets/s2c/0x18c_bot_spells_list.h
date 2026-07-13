/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#pragma once

#include "base.h"
#include <string>
#include <utility>
#include <vector>

// Custom packet 0x18C (S2C): BOT_SPELLS_LIST chunk.
// Reply to C2S 0x18B LIST_BOT_SPELLS. Carries the spell ID + display name for
// every spell the named char has learned in the requested group. Chunked.
// Caller routes by (BotName, GroupFilter) so concurrent fetches for different
// targets don't collide.
//
// Layout:
//   BotName[16]
//   GroupFilter   echoed from the request (0=magic, 1=trust)
//   IsFinal       1 on the last chunk for this (BotName, GroupFilter)
//   Count         populated entries in this chunk (0..kEntriesPerChunk)
//   Padding[1]
//   Entries[14]   { SpellId[u16] + Name[30] = 32 bytes per entry }
//
// Total: 4 (header) + 16 + 1 + 1 + 1 + 1 + 14*32 = 472 bytes.
// PacketSize = 472 / 2 = 0xEC.
class GP_SERV_COMMAND_BOT_SPELLS_LIST final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_BOT_SPELLS_LIST, GP_SERV_COMMAND_BOT_SPELLS_LIST>
{
public:
    static constexpr size_t kEntriesPerChunk = 14;
    static constexpr size_t kNameLen         = 30;

    struct Entry
    {
        uint16_t SpellId;
        char     Name[kNameLen];
    };

    struct PacketData
    {
        char    BotName[16];
        uint8_t GroupFilter;
        uint8_t IsFinal;
        uint8_t Count;
        uint8_t Padding;
        Entry   Entries[kEntriesPerChunk];
    };

    GP_SERV_COMMAND_BOT_SPELLS_LIST(const std::string& botName, uint8_t groupFilter, bool isFinal,
                                     const std::vector<std::pair<uint16_t, std::string>>& entries);
};
