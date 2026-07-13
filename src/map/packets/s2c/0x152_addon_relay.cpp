/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see http://www.gnu.org/licenses/

===========================================================================
*/

#include "0x152_addon_relay.h"

#include <cstring>

GP_SERV_COMMAND_ADDON_RELAY::GP_SERV_COMMAND_ADDON_RELAY(uint32_t senderServerId, const char* payload)
{
    auto& packet = this->data();
    packet.SenderServerId = senderServerId;
    std::memset(packet.Payload, 0, sizeof(packet.Payload));
    std::strncpy(packet.Payload, payload, sizeof(packet.Payload) - 1);
}
