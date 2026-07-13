/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x17c_dps_update.h"

#include <cstring>

GP_SERV_COMMAND_DPS_UPDATE::GP_SERV_COMMAND_DPS_UPDATE(uint32_t charId, bool isFinal, uint32_t totalDamage, uint32_t activeMs, const CategoryStats* categories)
{
    auto& packet = this->data();

    packet.CharId      = charId;
    packet.IsFinal     = isFinal ? 1 : 0;
    packet.TotalDamage = totalDamage;
    packet.ActiveMs    = activeMs;
    std::memset(packet.Padding, 0, sizeof(packet.Padding));

    if (categories != nullptr)
    {
        std::memcpy(packet.Categories, categories, sizeof(packet.Categories));
    }
    else
    {
        std::memset(packet.Categories, 0, sizeof(packet.Categories));
    }
}
