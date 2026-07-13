/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

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

// Custom packet (singleplayer fork): AutoMog Synth — runs an instant-synth on
// behalf of the named target char (must be primary's own char or a headless
// owned by primary). Self-contained as of #233 (2026-06-17): parses the
// 0x161-shape InnerPacket inline, builds a SynthOffer against the target's
// inventory, and calls synthutils::doInstantSynth (no animation, no 15s wait).
// 0x161 FAST_SYNTH no longer exists as a standalone packet — the addon always
// wraps in 0x19A regardless of whether the synth is local or cross-char,
// using primary's own name as TargetCharName for self-targeted synths.
// S2C reply: 0x19B AUTOMOG_SYNTH_RESULT (wrapper-level errors only;
// COMBINE_ANS is pushed by doInstantSynth to the target session).
GP_CLI_PACKET(GP_CLI_COMMAND_AUTOMOG_SYNTH,
    char    TargetCharName[16];
    uint8_t InnerPacket[64];
);
