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

// Custom packet 0x186 (S2C): ALLIANCE_PC_LIST.
// Reply to C2S 0x185 LIST_ALLIANCE_PCS. Single packet — alliance maxes at 18
// chars. Each entry is { Name[15] NUL-padded, Party uint8 (1/2/3) }; the
// 15+1 layout keeps entries 16 bytes for easy addon-side indexing.
//
// Layout:
//   Count    @ 0x04
//   Padding  @ 0x05 .. 0x07
//   Entries  @ 0x08 : 18 × { char Name[15]; uint8_t PartyNo; }
//
// Total: 4 (header) + 1 + 3 + 18*16 = 296 bytes. PacketSize = 296 / 2 = 0x94.
class GP_SERV_COMMAND_ALLIANCE_PC_LIST final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_ALLIANCE_PC_LIST, GP_SERV_COMMAND_ALLIANCE_PC_LIST>
{
public:
    static constexpr size_t kMaxEntries = 18;
    static constexpr size_t kNameLen    = 15;

    struct Entry
    {
        char    Name[kNameLen];
        uint8_t PartyNo;
    };

    struct PacketData
    {
        uint8_t Count;
        uint8_t Padding[3];
        Entry   Entries[kMaxEntries];
    };

    GP_SERV_COMMAND_ALLIANCE_PC_LIST(const std::vector<std::pair<std::string, uint8_t>>& pcs);
};
