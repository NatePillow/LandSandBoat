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

// Custom packet (singleplayer fork): result for 0x19C AUTOMOG_CHANGE_JOB.
//   Status: 0 = ok                  — at least one of MJ/SJ changed
//           1 = no target session   — name didn't resolve to a live session
//           2 = ownership rejected  — target not owned by sender
//           3 = engaged in combat   — bot/primary is engaged; reject like moogle
//           4 = job locked          — requested job's bit not set in jobs.unlocked
//           5 = level 0             — requested job is unlocked but never leveled
//           6 = no-op               — requested job(s) match current; nothing to do
class GP_SERV_COMMAND_AUTOMOG_CHANGE_JOB_RESULT final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_AUTOMOG_CHANGE_JOB_RESULT, GP_SERV_COMMAND_AUTOMOG_CHANGE_JOB_RESULT>
{
public:
    struct PacketData
    {
        uint8_t Status;
        uint8_t padding[3];
    };

    explicit GP_SERV_COMMAND_AUTOMOG_CHANGE_JOB_RESULT(uint8_t status);
};
