/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#pragma once

#include "base.h"

// Custom packet 0x171 (C2S): EQUIP_BOT_ITEM
//
// Hole-filled the previously-deprecated ITEM_TRADE slot (2026-06-22).
// Equip a single item by ID on an owned character (the primary themselves
// or a headless they parent) at a specified equip slot. Same call shape
// for both primary and headless to keep the addon side simple — the
// existing 0x173 EQUIP_BY_ID handles primary-only via the standard
// EquipFinish path, but it carries no target-char field so we couldn't
// reuse it for cross-char headless equip.
//
// Server flow:
//   1. Validate target is requester themselves OR a headless owned by
//      requester (same auth rule as 0x18F GET_CHAR_INV / 0x1A6
//      SORT_CHAR_INV / 0x1A7 GET_CHAR_PROFILE).
//   2. Find the item in the target's equip-bearing containers
//      (inventory + wardrobes 1..8).
//   3. Call charutils::EquipItem with the resolved location. Server-side
//      job / level / slot-mask gates apply.
//   4. Push a fresh S2C 0x1A8 CHAR_PROFILE for the target so the addon's
//      char_profile_cache picks up the new equipment slot id without a
//      separate poll.
//
// Layout (24 bytes total -> PacketSize = 12 = 0x0C, even):
//   4 header + 16 CharName + 2 ItemId + 1 SlotId + 1 padding
GP_CLI_PACKET(GP_CLI_COMMAND_EQUIP_BOT_ITEM,
    char     CharName[16];
    uint16_t ItemId;
    uint8_t  SlotId;
    uint8_t  Padding;
);
