/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#pragma once

#include "base.h"

#include "entities/charentity.h"

#include <string>

// Custom packet 0x1A8 (S2C): CHAR_PROFILE
//
// Reply to C2S 0x1A7 GET_CHAR_PROFILE. Single fixed-size packet carrying
// the full automog Status-tab view for one character.
//
// Layout (268 bytes total, divisible by 4 -> size field = 268/4 = 67, fits the
// 7-bit header size and the 0x1FF buffer): 4 header + 264 body (see PacketData).
//
// Sized to fit alongside the other 0x1A0-range singleplayer packets. The
// fields chosen mirror the standard 0x061 CLISTATUS payload so the
// addon-side stats display reads the same way as the FFXI client UI:
// base value + adjustment from gear/buffs.
class GP_SERV_COMMAND_CHAR_PROFILE final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_CHAR_PROFILE, GP_SERV_COMMAND_CHAR_PROFILE>
{
public:
    static constexpr size_t kEquipSlots = 16;  // main..back; LINK1/LINK2 excluded

    struct PacketData
    {
        char     Name[16];     // 16 -> 16

        // Jobs + look + identity.
        uint8_t  MJob;
        uint8_t  MLevel;
        uint8_t  SJob;
        uint8_t  SLevel;       //  4 -> 20
        uint8_t  Race;
        uint8_t  Face;
        uint8_t  Padding1[2];  //  4 -> 24

        // HP/MP (current + max).
        int32_t  HpCur;
        int32_t  HpMax;
        int32_t  MpCur;
        int32_t  MpMax;        // 16 -> 40

        // Exp on the current main job + threshold for next level.
        uint32_t ExpCurrent;
        uint32_t ExpToNext;    //  8 -> 48

        // Base + bonus stats. Same ordering as stats_t (STR, DEX, VIT, AGI,
        // INT, MND, CHR) with parallel bonus arrays from getMod(Mod::STAT).
        // Bonus is signed because gear/effects can subtract.
        uint16_t StatBase[7];  // 14
        int16_t  StatBonus[7]; // 14 -> 76

        // Combat-effective stats. ATK uses SLOT_MAIN; ACC uses attackNumber=0.
        // RATT/RACC included for ranged jobs.
        int16_t  Atk;
        int16_t  Def;
        int16_t  Acc;
        int16_t  Eva;
        int16_t  Ratk;
        int16_t  Racc;         // 12 -> 88

        // Elemental MEVA - same order as 0x061: Fire, Ice, Wind, Earth,
        // Thunder, Water, Light, Dark.
        int16_t  ResistMeva[8];// 16 -> 104

        // Equipment slot -> itemId, 16 slots in standard FFXI order:
        // 0 main, 1 sub, 2 ranged, 3 ammo, 4 head, 5 body, 6 hands, 7 legs,
        // 8 feet, 9 neck, 10 waist, 11 ear1, 12 ear2, 13 ring1, 14 ring2,
        // 15 back. 0 = empty slot. Linkshell slots (16/17) excluded since
        // the Status tab UI shows gear, not LSes.
        uint16_t Equipment[kEquipSlots]; // 32 -> 136

        // Working skills — raw copy of WorkingSkills.skill[64] (same as the
        // standard 0x062 packet). Each entry's low 15 bits (& 0x7FFF) is the
        // skill value; the high bit (0x8000) flags it CAPPED for the char's
        // job/level — vanilla renders capped skills in blue. Combat skills are
        // at ids 1-12 and 25-31, magic at 32-45 (see SKILLTYPE in battleentity.h).
        uint16_t Skills[64];             // 128 -> 264
    };

    GP_SERV_COMMAND_CHAR_PROFILE(CCharEntity* PTarget);
};
