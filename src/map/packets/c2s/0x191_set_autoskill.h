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

// Custom packet 0x191 (C2S): SET_AUTOSKILL.
// Sets / clears an autoskill override for a single bot. Authorized iff target
// is the requester themselves or a headless owned by them (same gate as 0x18F
// GET_CHAR_INV).
//
// When Mode is non-zero this overrides the bot's normal role dispatch for as
// long as it's set — see autoai.lua runCombatTick's autoskill gate. When Mode
// is Off the bot resumes its assigned alliance-config role automatically.
//
// BotName[16]      target char (NUL-padded)
// Mode[1]          0=Off, 1=RA, 2=Magic
// SpellCount[1]    0..16, only meaningful for Magic
// Padding[2]
// SpellIds[16]     uint16 spell IDs (LE); only the first SpellCount are read
//
// Total: 4 (header) + 16 + 1 + 1 + 2 + 32 = 56 bytes. PacketSize = 56 / 2 = 0x1C.
GP_CLI_PACKET(GP_CLI_COMMAND_SET_AUTOSKILL,
    char     BotName[16];
    uint8_t  Mode;
    uint8_t  SpellCount;
    uint8_t  Padding[2];
    uint16_t SpellIds[16];
);
