/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x1a8_char_profile.h"

#include "entities/charentity.h"
#include "item_container.h"
#include "items/item.h"
#include "modifier.h"
#include "utils/charutils.h"

#include <algorithm>
#include <cstring>

namespace
{
    // Pack one base/bonus stat pair. Mirrors the clamp behavior of 0x061
    // CLISTATUS so the displayed numbers match the standard client UI.
    void packStat(uint16_t& base, int16_t& bonus, uint16_t baseValue, int16_t bonusValue)
    {
        base  = baseValue;
        bonus = std::clamp<int16_t>(bonusValue, -999 + static_cast<int16_t>(baseValue), 999 - static_cast<int16_t>(baseValue));
    }

    // Resolve a single equipped item's itemId via the equip->inventory map.
    // PChar->equipLocation(slotId) returns {Container, Slot} pointing into
    // the actual storage container; we then read the item there. 0 = empty.
    uint16_t getEquippedItemId(CCharEntity* PChar, uint8 equipSlot)
    {
        auto eloc = PChar->equipLocation(equipSlot);
        if (!eloc)
        {
            return 0;
        }
        CItemContainer* container = PChar->getStorage(static_cast<uint8>(eloc->Container));
        if (container == nullptr)
        {
            return 0;
        }
        const CItem* PItem = container->GetItem(eloc->Slot);
        if (PItem == nullptr)
        {
            return 0;
        }
        return static_cast<uint16_t>(PItem->getID());
    }
} // namespace

GP_SERV_COMMAND_CHAR_PROFILE::GP_SERV_COMMAND_CHAR_PROFILE(CCharEntity* PTarget)
{
    auto& packet = this->data();
    if (PTarget == nullptr)
    {
        return;
    }

    // Name (echo for the addon's per-char cache key).
    const std::string name = PTarget->getName();
    std::memset(packet.Name, 0, sizeof(packet.Name));
    std::memcpy(packet.Name, name.data(), std::min(name.size(), sizeof(packet.Name) - 1));

    // Jobs + look.
    packet.MJob   = PTarget->GetMJob();
    packet.MLevel = PTarget->GetMLevel();
    packet.SJob   = PTarget->GetSJob();
    packet.SLevel = PTarget->GetSLevel();
    packet.Race   = PTarget->look.race;
    packet.Face   = PTarget->look.face;

    // HP/MP (current and max).
    packet.HpCur = PTarget->health.hp;
    packet.HpMax = PTarget->GetMaxHP();
    packet.MpCur = PTarget->health.mp;
    packet.MpMax = PTarget->GetMaxMP();

    // Exp on current main job. GetExpNEXTLevel takes the actual job
    // level entry (jobs.job[mainjob]) per the 0x061 CLISTATUS pattern.
    packet.ExpCurrent = PTarget->jobs.exp[PTarget->GetMJob()];
    packet.ExpToNext  = charutils::GetExpNEXTLevel(PTarget->jobs.job[PTarget->GetMJob()]);

    // Base + bonus stats. Same order as stats_t in mmo.h.
    packStat(packet.StatBase[0], packet.StatBonus[0], PTarget->stats.STR, PTarget->getMod(Mod::STR));
    packStat(packet.StatBase[1], packet.StatBonus[1], PTarget->stats.DEX, PTarget->getMod(Mod::DEX));
    packStat(packet.StatBase[2], packet.StatBonus[2], PTarget->stats.VIT, PTarget->getMod(Mod::VIT));
    packStat(packet.StatBase[3], packet.StatBonus[3], PTarget->stats.AGI, PTarget->getMod(Mod::AGI));
    packStat(packet.StatBase[4], packet.StatBonus[4], PTarget->stats.INT, PTarget->getMod(Mod::INT));
    packStat(packet.StatBase[5], packet.StatBonus[5], PTarget->stats.MND, PTarget->getMod(Mod::MND));
    packStat(packet.StatBase[6], packet.StatBonus[6], PTarget->stats.CHR, PTarget->getMod(Mod::CHR));

    // Combat-effective values.
    packet.Atk  = static_cast<int16_t>(PTarget->ATT(SLOT_MAIN));
    packet.Def  = static_cast<int16_t>(PTarget->DEF());
    packet.Acc  = static_cast<int16_t>(PTarget->ACC(0, 0));
    packet.Eva  = static_cast<int16_t>(PTarget->EVA());
    packet.Ratk = static_cast<int16_t>(PTarget->RATT(0));
    packet.Racc = static_cast<int16_t>(PTarget->RACC(0));

    // Elemental MEVA. Same order as 0x061 for cross-UI consistency.
    packet.ResistMeva[0] = PTarget->getMod(Mod::FIRE_MEVA);
    packet.ResistMeva[1] = PTarget->getMod(Mod::ICE_MEVA);
    packet.ResistMeva[2] = PTarget->getMod(Mod::WIND_MEVA);
    packet.ResistMeva[3] = PTarget->getMod(Mod::EARTH_MEVA);
    packet.ResistMeva[4] = PTarget->getMod(Mod::THUNDER_MEVA);
    packet.ResistMeva[5] = PTarget->getMod(Mod::WATER_MEVA);
    packet.ResistMeva[6] = PTarget->getMod(Mod::LIGHT_MEVA);
    packet.ResistMeva[7] = PTarget->getMod(Mod::DARK_MEVA);

    // Equipment slot -> itemId via equipLocation().
    for (uint8 slot = 0; slot < kEquipSlots; ++slot)
    {
        packet.Equipment[slot] = getEquippedItemId(PTarget, slot);
    }

    // Working skills (value in low 15 bits, capped flag in bit 0x8000). Mirrors
    // the standard 0x062 packet's raw WorkingSkills copy.
    std::memcpy(packet.Skills, &PTarget->WorkingSkills, sizeof(packet.Skills));
}
