/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "0x1a2_set_puller_name_filter.h"

#include "entities/charentity.h"
#include "lua/luautils.h"

#include <cstring>
#include <string>
#include <vector>

auto GP_CLI_COMMAND_SET_PULLER_NAME_FILTER::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_SET_PULLER_NAME_FILTER::process(MapSession* PSession, CCharEntity* PChar) const
{
    std::vector<std::string> names;
    const uint8 count = std::min<uint8>(this->Count, 16);
    names.reserve(count);
    for (uint8 i = 0; i < count; ++i)
    {
        const char* raw = this->Names[i];
        const auto  len = strnlen(raw, sizeof(this->Names[i]));
        if (len > 0)
        {
            names.emplace_back(raw, len);
        }
    }
    luautils::OnBotSetPullerNameFilter(PChar, names);
}
