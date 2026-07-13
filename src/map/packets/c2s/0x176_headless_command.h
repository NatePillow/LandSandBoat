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

// Custom packet 0x176: HEADLESS_COMMAND
// Generic command channel from the primary client's addon to the server-side bot
// AI. Single opcode, dispatched internally by Namespace + Subcommand. Payload is
// a fixed 32-byte chunk interpreted per subcommand. (Originally 12 bytes; bumped
// to 32 in 2026-06-28 when SetBrdSongRoster needed Name[10] + 4×uint16 = 18
// bytes. Existing 12-byte-or-less subcommands continue to work unchanged —
// they read fixed offsets and ignore the trailing zero-padded bytes.)
//
// Namespace IDs:
//   0x01 AUTOBOTS  — runtime bot control (set mode, attack, disengage, set role)
//   0x02 AUTOMOG   — mog/inventory ops (reserved for later phases)
//   0x03 AUTOTANK  — per-role overrides (reserved)
//   ...
//
// AUTOBOTS subcommands (Phase 2 minimum set):
//   0x01 SET_BOT_MODE      Payload: char Name[12]  — toggles m_botMode on named char
//                                                    (uses Payload[0] as mode byte if Name is empty / 0)
//                          Mode byte: 0=Off 1=CombatOnly 2=Full
//   0x02 ATTACK            Payload: uint32 TargetId — primary's selected target
//   0x03 DISENGAGE         Payload: ignored
//   0x04 SET_ROLE          Payload: char Name[10] + uint8 Role + uint8 Padding
//   0x0E SYNC_QUESTS       Payload: ignored. Cascade primary's completed quests onto
//                                   every linked headless. Server replies via S2C 0x1A3.
//   0x0F SYNC_MISSIONS     Payload: ignored. Same for nation/expansion missions.
//
// Total: 4 (header) + 1 + 1 + 2 + 32 = 40 bytes → PacketSize = 0x14
GP_CLI_PACKET(GP_CLI_COMMAND_HEADLESS_COMMAND,
    uint8_t Namespace;
    uint8_t Subcommand;
    uint8_t Padding[2];
    uint8_t Payload[32];
);
