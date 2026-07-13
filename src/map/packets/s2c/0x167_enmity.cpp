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

#include "0x167_enmity.h"

#include "enmity_container.h"
#include "entities/mobentity.h"

#include <algorithm>
#include <vector>

GP_SERV_COMMAND_ENMITY::GP_SERV_COMMAND_ENMITY(CMobEntity* PMob)
{
    auto& packet = this->data();

    packet.mob_id = PMob->id;

    auto* target          = PMob->GetEntity(PMob->GetBattleTargetID(), TYPE_PC | TYPE_MOB | TYPE_PET | TYPE_TRUST);
    packet.battle_target_id = target ? target->id : 0;

    auto* list = PMob->PEnmityContainer->GetEnmityList();

    std::vector<const EnmityObject_t*> sorted;
    sorted.reserve(list->size());
    for (const auto& [id, entry] : *list)
    {
        if (entry.active && entry.PEnmityOwner)
        {
            sorted.push_back(&entry);
        }
    }

    std::sort(sorted.begin(), sorted.end(), [](const EnmityObject_t* a, const EnmityObject_t* b)
    {
        return (a->CE + a->VE) > (b->CE + b->VE);
    });

    const auto count    = static_cast<uint8_t>(std::min<size_t>(sorted.size(), MAX_ENTRIES));
    packet.entry_count  = count;

    for (uint8_t i = 0; i < count; ++i)
    {
        packet.entries[i].entity_id = sorted[i]->PEnmityOwner->id;
        packet.entries[i].ce        = sorted[i]->CE;
        packet.entries[i].ve        = sorted[i]->VE;
    }
}
