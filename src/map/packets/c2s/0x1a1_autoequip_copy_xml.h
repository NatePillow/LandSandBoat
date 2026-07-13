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

// Custom packet (singleplayer fork): copy an AutoEquip XML file from one
// (char, job) to another. Both names are the {char}_{job} stems (e.g.
// "Cornelia_RDM") under singleplayer/config/equip/. Server validates
// the source file exists and that names are path-safe (no '/', '\\', '.'),
// then performs a single fs::copy_file overwriting the destination if any.
// S2C response: 0x1A2 AUTOEQUIP_COPY_XML_RESULT.
//   Status: 0 = ok
//           1 = source file not found
//           2 = invalid source / destination name (path-unsafe or empty)
//           3 = filesystem error during copy
GP_CLI_PACKET(GP_CLI_COMMAND_AUTOEQUIP_COPY_XML,
    char SourceName[32];
    char DestName[32];
);
