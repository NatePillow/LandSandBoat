/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#pragma once

#include "base.h"

// Custom packet 0x1A7 (C2S): GET_CHAR_PROFILE
//
// Request a one-shot full profile snapshot for a single character - the
// "Status tab" view in automog. Server replies via S2C 0x1A8 CHAR_PROFILE
// carrying base + bonus stats, equipment slot mapping, jobs/levels, exp,
// HP/MP, and resistances.
//
// Authorization: target must be the requester themselves OR a headless
// sessioned under the requester (same rule as 0x18F GET_CHAR_INV).
//
// Layout (24 bytes total -> PacketSize = 12 = 0x0C, even):
//   4 header + 16 CharName + 4 padding
GP_CLI_PACKET(GP_CLI_COMMAND_GET_CHAR_PROFILE,
    char    CharName[16];
    uint8_t Padding[4];
);
