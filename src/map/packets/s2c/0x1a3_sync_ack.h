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

// Custom packet 0x1A3 (S2C): SYNC_ACK
// Reply to C2S 0x176 HEADLESS_COMMAND subcommand SYNC_QUESTS (0x0E) or
// SYNC_MISSIONS (0x0F). Single-packet ACK sent after the cascade applies, so
// the AutoBots addon can clear its in-flight guard on the corresponding
// Sync Quests / Sync Missions button.
//
// Layout:
//   Kind          : 0 = quests, 1 = missions
//   Padding[3]    : alignment
//   Count         : total completions applied across linked headless
//
// Total: 4 (header) + 1 + 3 + 4 = 12 bytes. PacketSize = 12 / 2 = 0x06.
class GP_SERV_COMMAND_SYNC_ACK final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_SYNC_ACK, GP_SERV_COMMAND_SYNC_ACK>
{
public:
    struct PacketData
    {
        uint8_t  Kind;
        uint8_t  Padding[3];
        uint32_t Count;
    };

    GP_SERV_COMMAND_SYNC_ACK(uint8_t kind, uint32_t count);
};
