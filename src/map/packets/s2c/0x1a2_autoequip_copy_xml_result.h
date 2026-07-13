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

// Custom packet (singleplayer fork): result for 0x1A1 AUTOEQUIP_COPY_XML.
// Carries the destination filename so the addon can confirm which slot got
// populated, plus a status byte (see 0x1a1_autoequip_copy_xml.h).
class GP_SERV_COMMAND_AUTOEQUIP_COPY_XML_RESULT final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_AUTOEQUIP_COPY_XML_RESULT, GP_SERV_COMMAND_AUTOEQUIP_COPY_XML_RESULT>
{
public:
    struct PacketData
    {
        char     DestName[32];
        uint8_t  Status;
        uint8_t  padding[3];
    };

    GP_SERV_COMMAND_AUTOEQUIP_COPY_XML_RESULT(const std::string& destName, uint8_t status);
};
