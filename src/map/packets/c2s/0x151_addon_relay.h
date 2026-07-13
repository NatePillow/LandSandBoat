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

// Custom packet (singleplayer fork): addon relay send.
// Sent by a Lua addon to broadcast a string payload to all alliance members
// in the same zone. The server echoes it back as GP_SERV_COMMAND_ADDON_RELAY
// (0x152) to all recipients including the sender.
// Payload capacity: 240 bytes (total 244 bytes; protocol ceiling is 248 for C2S).
GP_CLI_PACKET(GP_CLI_COMMAND_ADDON_RELAY,
    char Payload[240];
);
