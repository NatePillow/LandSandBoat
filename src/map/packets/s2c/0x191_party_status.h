/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#pragma once

#include "base.h"

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

// Custom packet 0x191 (S2C): PARTY_STATUS.
// Periodic push (~2s cadence from bots_status.lua) describing each member of
// one party — name, race/face for the portrait lookup, current job EXP for the
// progress bar, and the active status effect IDs the addon renders as icons.
// Sent per-party so a full alliance snapshot is up to 3 packets. The addon's
// status tab renders all of it; the portrait PNG lookup is client-local
// (addons/autobots/portraits/<race*100+face>.png — see status_tab.lua).
//
// Layout (offsets relative to PacketData start):
//   PartyNumber  @ 0x00 : 1..3 (which party in the alliance)
//   MemberCount  @ 0x01 : 0..6
//   Padding      @ 0x02 : 2 bytes
//   Entries      @ 0x04 : 6 × {
//     char     Name[16];            // null-padded
//     uint8    EffectCount;
//     uint8    Race;                // FFXI race enum (0=none, 1..8 per char_look)
//     uint8    Face;                // 1..8 face index within the race
//     uint8    Padding;             // align next u32 field
//     uint32   ExpCurrent;          // main-job exp (0..ExpToNext-1)
//     uint32   ExpToNext;           // main-job exp threshold for next level
//     uint16   EffectIds[20];       // FFXI status effect IDs (or 0)
//   }
//
// Per entry: 16 + 1 + 1 + 1 + 1 + 4 + 4 + 40 = 68 bytes.
// PacketData : 1 + 1 + 2 + (6 × 68) = 412 bytes.
// Total with FFXI 4-byte header: 416 bytes. Wire size byte = 416/2 = 0xD0
// (under the 0xFE cap). Total bytes are divisible by 4 (104) so the &0xFE
// size-byte mask leaves the value intact — no silent bounce.
//
// HISTORY: Previously held 32 effects per bot and no portrait/exp fields.
// Was 500 bytes total. Trimmed effects to 20 (still well above the practical
// max — real headless rarely carry more than 10–12 buffs) and used the freed
// 24 bytes per entry for the portrait + exp fields.
class GP_SERV_COMMAND_PARTY_STATUS final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_PARTY_STATUS, GP_SERV_COMMAND_PARTY_STATUS>
{
public:
    static constexpr size_t kMaxEntries        = 6;
    static constexpr size_t kMaxEffectsPerBot  = 20;
    static constexpr size_t kNameLen           = 16;

    struct Entry
    {
        char     Name[kNameLen];
        uint8_t  EffectCount;
        uint8_t  Race;
        uint8_t  Face;
        uint8_t  Padding;
        uint32_t ExpCurrent;
        uint32_t ExpToNext;
        uint16_t EffectIds[kMaxEffectsPerBot];
    };

    struct PacketData
    {
        uint8_t PartyNumber;
        uint8_t MemberCount;
        uint8_t Padding[2];
        Entry   Entries[kMaxEntries];
    };

    // Member input record. Mirrors the per-entry fields the addon needs to
    // render a card: name + portrait keys (race/face) + main-job EXP +
    // status-effect IDs (truncated to kMaxEffectsPerBot).
    struct Member
    {
        std::string           Name;
        uint8_t               Race;
        uint8_t               Face;
        uint32_t              ExpCurrent;
        uint32_t              ExpToNext;
        std::vector<uint16_t> Effects;
    };

    GP_SERV_COMMAND_PARTY_STATUS(uint8_t partyNumber, const std::vector<Member>& members);
};
