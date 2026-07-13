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

// Custom packet 0x1A0 (C2S): BOT_COMMAND
// Primary issues a one-shot action command at a specific headless bot. The bot
// queues the command on its per-bot scratch state (single-slot, last-write-wins)
// and consumes it in the next tick where it's not mid-action. Acks come back as
// printToPlayer chat messages — no S2C reply packet.
//
// Wire format (4-byte aligned, even size byte for FFXI's `& 0xFE` mask):
//   BotName[16]    headless to command (null-padded)
//   ActionKind[8]  one of "ma", "ja", "ws", "ra", "item" (null-padded)
//   ActionName[32] spell / ability / WS / item name (empty for /ra)
//   TargetId u32   server entity ID. 0 = self (server resolves to bot's own id).
//
// Total: 4 (header) + 16 + 8 + 32 + 4 = 64 bytes. PacketSize = 64 / 2 = 0x20.
GP_CLI_PACKET(GP_CLI_COMMAND_BOT_COMMAND,
    char     BotName[16];
    char     ActionKind[8];
    char     ActionName[32];
    uint32_t TargetId;
);
