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

#include "0x1a2_autoequip_copy_xml_result.h"

#include <algorithm>
#include <cstring>

GP_SERV_COMMAND_AUTOEQUIP_COPY_XML_RESULT::GP_SERV_COMMAND_AUTOEQUIP_COPY_XML_RESULT(const std::string& destName, uint8_t status)
{
    auto& packet  = this->data();
    packet.Status = status;
    std::memset(packet.DestName, 0, sizeof(packet.DestName));
    const auto len = std::min(destName.size(), sizeof(packet.DestName));
    std::memcpy(packet.DestName, destName.data(), len);
}
