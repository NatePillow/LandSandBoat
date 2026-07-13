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

#include "0x150_server_ident.h"

#include <cstring>

static constexpr const char SERVER_IDENT_STRING[] = "singleplayer-fork";

GP_SERV_COMMAND_SERVER_IDENT::GP_SERV_COMMAND_SERVER_IDENT()
{
    auto& packet = this->data();
    std::memset(packet.ServerIdent, 0, sizeof(packet.ServerIdent));
    std::strncpy(packet.ServerIdent, SERVER_IDENT_STRING, sizeof(packet.ServerIdent) - 1);
}
