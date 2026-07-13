/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#pragma once

#include "base.h"

// Custom packet 0x17C (S2C): per-bot DPS snapshot pushed to the primary client.
// Server-driven, pushed every ~2 seconds while the bot is engaged plus once on
// disengage as a final summary. Replaces the upstream client-side autodps
// 0x152 relay path for headless characters.
//
// Categories track the same six damage types as upstream autodps:
//   0 melee, 1 ranged, 2 ws, 3 magic, 4 burst, 5 ja
//
// Payload layout:
//   CharId          : the bot the stats are for
//   IsFinal         : 1 if this is the disengage summary; 0 if mid-fight tick
//   Padding[3]
//   TotalDamage     : sum across all categories
//   ActiveMs        : active-fight ms (>30s idle gaps excluded, matches upstream)
//   Categories[6]   : per-category {Damage, Hits, Misses}
//
// Total: 4 (header) + 4 + 4 + 4 + 4 + 6*(4+2+2) = 68 bytes. PacketSize = 0x22.
class GP_SERV_COMMAND_DPS_UPDATE final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_DPS_UPDATE, GP_SERV_COMMAND_DPS_UPDATE>
{
public:
    static constexpr uint8_t kCategoryCount = 6;

    struct CategoryStats
    {
        uint32_t Damage;
        uint16_t Hits;
        uint16_t Misses;
    };

    struct PacketData
    {
        uint32_t      CharId;
        uint8_t       IsFinal;
        uint8_t       Padding[3];
        uint32_t      TotalDamage;
        uint32_t      ActiveMs;
        CategoryStats Categories[kCategoryCount];
    };

    GP_SERV_COMMAND_DPS_UPDATE(uint32_t charId, bool isFinal, uint32_t totalDamage, uint32_t activeMs, const CategoryStats* categories);
};
