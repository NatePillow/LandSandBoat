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

// Custom packet 0x1A2 (C2S): SET_PULLER_NAME_FILTER
// Player-selected mob-name filter for the puller AI. Empty list (Count==0)
// clears the filter — puller falls back to "any mob in the con range."
//
// Wire layout (4-byte aligned, even size byte):
//   Count    uint8       0..16 names valid
//   _pad     uint8[3]    alignment
//   Names    char[16][24]  null-padded; mob display names from the
//                          0x1A4 PULLER_NEARBY_NAMES discovery list.
//
// Total: 4 (header) + 4 + 384 = 392 bytes. PacketSize = 0xC4.
GP_CLI_PACKET(GP_CLI_COMMAND_SET_PULLER_NAME_FILTER,
    uint8_t  Count;
    uint8_t  _pad[3];
    char     Names[16][24];
);
