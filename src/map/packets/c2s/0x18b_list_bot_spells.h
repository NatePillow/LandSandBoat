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

// Custom packet 0x18B (C2S): LIST_BOT_SPELLS request.
// Asks the server for the spells the named char has actually learned, filtered
// to a single group. Authorized iff target is the requester themselves or a
// headless owned by them (session.parentCharId == requester->id) — same gate
// as 0x18F GET_CHAR_INV.
//
// Replaces the earlier 0x18B LIST_TRUSTS packet which returned every trust in
// the server's spell DB regardless of who knew it. Two consumers today:
//   * Alliance editor trust dropdown: opens with the selected party leader as
//     the target, GroupFilter = 1 (trust only).
//   * AutoSkill addon's magic spell picker: target = selected alliance member,
//     GroupFilter = 0 (magic non-trust).
//
// BotName[16]   target char (NUL-padded)
// GroupFilter   0 = magic non-trust, 1 = trust only
// Padding[3]
//
// Total: 4 (header) + 16 + 1 + 3 = 24 bytes. PacketSize = 24 / 2 = 0x0C.
GP_CLI_PACKET(GP_CLI_COMMAND_LIST_BOT_SPELLS,
    char    BotName[16];
    uint8_t GroupFilter;
    uint8_t Padding[3];
);
