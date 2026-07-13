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

// Custom packet 0x184 (C2S): LOT_LIST_ACTION
// Mutates the server-side autolot lot-list table for the requesting char's
// alliance. The lot-list is a per-(primary, item_id) → set of bot names that
// should each receive ONE of this item; each named bot lots drops of itemId
// until they own one. See modules/singleplayer/lua/autolot.lua for the state
// model and grace-window behavior.
//
// We use a dedicated packet rather than a 0x176 subcommand because FFXI char
// names can be 15 chars (0x176's 12-byte payload would force truncation).
//
// Action codes:
//   0x01 ADD     — add BotName to the lot list for ItemId
//   0x02 REMOVE  — remove BotName from the lot list for ItemId
//   0x03 CLEAR   — clear the entire list for ItemId (BotName ignored)
//
// Layout:
//   Action[1]
//   Padding[3]
//   ItemId[4]    — uint32 LE
//   BotName[16]  — 15 chars + NUL terminator
//
// Total: 4 (header) + 1 + 3 + 4 + 16 = 28 bytes. PacketSize = 28 / 2 = 0x0E.
GP_CLI_PACKET(GP_CLI_COMMAND_LOT_LIST_ACTION,
    uint8_t  Action;
    uint8_t  Padding[3];
    uint32_t ItemId;
    char     BotName[16];
);
