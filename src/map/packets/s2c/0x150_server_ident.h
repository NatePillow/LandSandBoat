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

// Custom packet (singleplayer fork): server capability handshake.
// Sent every server tick to each connected character so that Lua addons
// can confirm they are connected to this fork and enable extended features.
class GP_SERV_COMMAND_SERVER_IDENT final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_SERVER_IDENT, GP_SERV_COMMAND_SERVER_IDENT>
{
public:
    struct PacketData
    {
        char ServerIdent[32]; // Human-readable fork identifier string
    };

    GP_SERV_COMMAND_SERVER_IDENT();
};
