/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#pragma once

#include "base.h"

// Custom packet 0x178: SET_LOT_ASSIGNMENT
// Primary char's autolot addon tells the server "char X should (or should not)
// be lotting items in group Y, right now." Pure runtime state — there's no
// persistence layer. Assignments apply only while the named char is currently
// spawned; if the char isn't a live PC entity at apply time, the server
// silently no-ops (the addon UI only renders rows for currently-spawned
// alliance members so this only happens on race).
//
// Payload (28 bytes):
//   CharName[12]  : NUL-padded FFXI char name (primary OR owned headless).
//                   FFXI names cap at 11 chars; the extra byte covers the
//                   NUL terminator and keeps the field 4-byte aligned.
//   GroupName[12] : NUL-padded autolot group name (matches the file basename
//                   under singleplayer/config/lot/<GroupName>.json). Caps at
//                   the same 11+NUL bound — longer group names get truncated
//                   client-side and the user sees a no-match silently.
//   On            : 1 = add the group to char's activeGroups, 0 = remove.
//   Pad[3]        : reserved; zero-filled. Keeps the struct 4-byte aligned
//                   so the FFXI wire size byte (`& 0xFE`) lands even.
//
// Total: 4 (header) + 28 = 32 bytes. PacketSize = 32 / 2 = 0x10.
GP_CLI_PACKET(GP_CLI_COMMAND_SET_LOT_ASSIGNMENT,
    char  CharName[12];
    char  GroupName[12];
    uint8 On;
    uint8 Pad[3];
);
