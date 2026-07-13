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

#pragma once

#include "base.h"

// Custom packet (singleplayer fork): addon relay broadcast.
// Sent to all alliance members (or party/solo if not in alliance) in the same
// zone when the server receives a GP_CLI_COMMAND_ADDON_RELAY (0x151) from any
// member. Carries the original sender's server ID and the string payload,
// allowing Lua addons to communicate with each other through the server.
class GP_SERV_COMMAND_ADDON_RELAY final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_ADDON_RELAY, GP_SERV_COMMAND_ADDON_RELAY>
{
public:
    struct PacketData
    {
        uint32_t SenderServerId; // Server ID of the character who sent the relay
        char     Payload[240];   // Arbitrary string payload (total 248 bytes; protocol ceiling is 244 for S2C)
    };

    GP_SERV_COMMAND_ADDON_RELAY(uint32_t senderServerId, const char* payload);
};
