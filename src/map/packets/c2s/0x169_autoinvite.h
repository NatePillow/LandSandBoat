/*
===========================================================================

  Copyright (c) 2025 Single Player Dev Teams

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

// Custom packet 0x169: AUTOINVITE
// Sent by the AutoInvite Ashita addon to form a party or full alliance in one shot.
// Payload (304 bytes):
//   party_count (u8)      : number of parties to form (1–3)
//   padding (u8×3)
//   parties[3]:
//     leader   (char[16]) : null-padded party leader name
//     member_count (u8)   : number of additional members (0–5)
//     padding  (u8×3)
//     members[5][16]      : null-padded member names (unused slots zeroed)
// Total: 4 (header) + 304 (payload) = 308 bytes  →  PacketSize = 0x9A
GP_CLI_PACKET(GP_CLI_COMMAND_AUTOINVITE,
    uint8_t party_count;
    uint8_t padding0[3];
    char    pt1_leader[16];
    uint8_t pt1_member_count;
    uint8_t pt1_padding[3];
    char    pt1_members[5][16];
    char    pt2_leader[16];
    uint8_t pt2_member_count;
    uint8_t pt2_padding[3];
    char    pt2_members[5][16];
    char    pt3_leader[16];
    uint8_t pt3_member_count;
    uint8_t pt3_padding[3];
    char    pt3_members[5][16];
);
