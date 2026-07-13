/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "0x1a4_puller_nearby_names.h"

#include <cstring>

GP_SERV_COMMAND_PULLER_NEARBY_NAMES::GP_SERV_COMMAND_PULLER_NEARBY_NAMES(uint8_t count, const Entry* entries)
{
    auto& packet  = this->data();
    packet.Count  = count;
    if (entries && count > 0)
    {
        std::memcpy(packet.Entries, entries, sizeof(Entry) * std::min<uint8_t>(count, 20));
    }
}
