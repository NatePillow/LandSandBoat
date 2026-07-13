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

#include "0x173_equip_by_id.h"

#include <array>

#include "entities/battleentity.h"  // SLOTTYPE enum, used by oneOf<SLOTTYPE>
#include "entities/charentity.h"
#include "item_container.h"
#include "items/item.h"
#include "lua/luautils.h"
#include "packets/s2c/0x174_equip_by_id_result.h"
#include "utils/charutils.h"

namespace
{

const auto validContainers = [](const CCharEntity* PChar) -> std::set<CONTAINER_ID>
{
    std::set allowedContainers = {
        LOC_INVENTORY,
        LOC_WARDROBE,
        LOC_WARDROBE2,
    };

    const std::set unlockableContainers = {
        LOC_WARDROBE3,
        LOC_WARDROBE4,
        LOC_WARDROBE5,
        LOC_WARDROBE6,
        LOC_WARDROBE7,
        LOC_WARDROBE8,
    };

    const std::set additionalContainers = {
        LOC_MOGSATCHEL, LOC_MOGSACK, LOC_MOGCASE
    };

    for (const auto containerId : unlockableContainers)
    {
        if (PChar->getStorage(containerId)->GetSize() > 0)
        {
            allowedContainers.insert(containerId);
        }
    }

    if (settings::get<bool>("main.EQUIP_FROM_OTHER_CONTAINERS"))
    {
        for (const auto containerId : additionalContainers)
        {
            if (PChar->getStorage(containerId)->GetSize() > 0)
            {
                allowedContainers.insert(containerId);
            }
        }
    }

    return allowedContainers;
};

} // namespace

auto GP_CLI_COMMAND_EQUIP_BY_ID::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    auto pv = PacketValidator(PChar)
                  .blockedBy({ BlockedState::AbnormalStatus })
                  .range("Count", Count, 1, 16);

    if (Count <= 16)
    {
        for (uint8_t i = 0; i < Count; i++)
        {
            pv.oneOf<SLOTTYPE>(Equipment[i].EquipKind);
        }
    }

    return pv;
}

void GP_CLI_COMMAND_EQUIP_BY_ID::process(MapSession* PSession, CCharEntity* PChar) const
{
    const auto containers = validContainers(PChar);

    std::array<uint8_t, 16> results{};
    std::fill(results.begin(), results.end(), 1); // default: not found
    bool anyChanged = false;

    for (uint8_t i = 0; i < Count; i++)
    {
        const uint16_t targetId  = Equipment[i].ItemId;
        const uint8_t  equipSlot = Equipment[i].EquipKind;

        for (const auto containerId : containers)
        {
            CItemContainer* container = PChar->getStorage(containerId);
            if (!container)
            {
                continue;
            }

            const uint8_t size = container->GetSize();
            for (uint8_t slotID = 1; slotID <= size; ++slotID)
            {
                CItem* PItem = container->GetItem(slotID);
                if (PItem && PItem->getID() == targetId)
                {
                    const CItemEquipment* before = PChar->getEquip(static_cast<SLOTTYPE>(equipSlot));
                    if (before && before->getID() == targetId)
                    {
                        results[i] = 3; // already equipped, no-op
                    }
                    else
                    {
                        charutils::EquipItem(PChar, slotID, equipSlot, static_cast<uint8_t>(containerId));
                        const CItemEquipment* after = PChar->getEquip(static_cast<SLOTTYPE>(equipSlot));
                        if (after && after->getID() == targetId)
                        {
                            results[i] = 0; // success
                            anyChanged  = true;
                        }
                        else
                        {
                            results[i] = 2; // blocked by game mechanic
                        }
                    }
                    goto next_entry;
                }
            }
        }
        next_entry:;
    }

    if (anyChanged)
    {
        PChar->RequestPersist(CHAR_PERSIST::EQUIP);
        luautils::CheckForGearSet(PChar);
        PChar->UpdateHealth();
        PChar->retriggerLatents = true;
    }

    PChar->pushPacket<GP_SERV_COMMAND_EQUIP_BY_ID_RESULT>(Count, results);
}
