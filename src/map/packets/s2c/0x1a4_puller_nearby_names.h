/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#pragma once

#include "base.h"

// Custom packet 0x1A4 (S2C): PULLER_NEARBY_NAMES
// Response to C2S 0x176 REQUEST_PULLER_NAMES. Sends back up to 20 unique mob
// names within 255y of the alliance camp anchor, along with current counts.
// Sorted server-side by count descending; addon merges with its own cache.
//
// Name was originally Name[24] giving Entry=26 bytes, but 20×26 + 4 header +
// 4 count/pad = 528 bytes exceeds PACKET_SIZE (0x1FF = 511) — fortify-source
// caught the buffer overflow at runtime. FFXI character names cap at 15
// chars so Name[16] (15 + null terminator) is the maximum we ever need.
// Each entry: char Name[16] + uint16 Count = 18 bytes.
// 20 entries * 18 = 360 + 4 header + 4 count/pad = 368 bytes total (fits).
class GP_SERV_COMMAND_PULLER_NEARBY_NAMES final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_PULLER_NEARBY_NAMES, GP_SERV_COMMAND_PULLER_NEARBY_NAMES>
{
public:
    struct Entry
    {
        char     Name[16];
        uint16_t Count;
    };

    struct PacketData
    {
        uint8_t Count;        // entries actually populated (0..20)
        uint8_t _pad[3];
        Entry   Entries[20];  // 20 * 18 = 360 bytes
    };

    GP_SERV_COMMAND_PULLER_NEARBY_NAMES(uint8_t count, const Entry* entries);
};
