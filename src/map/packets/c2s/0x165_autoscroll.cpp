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

#include "0x165_autoscroll.h"

#include "entities/charentity.h"
#include "item_container.h"
#include "items/item.h"
#include "packets/s2c/0x01d_item_same.h"
#include "packets/s2c/0x029_battle_message.h"
#include "packets/s2c/0x0aa_magic_data.h"
#include "packets/s2c/0x166_autoscroll_result.h"
#include "spell.h"
#include "utils/charutils.h"
#include "utils/jailutils.h"

auto GP_CLI_COMMAND_AUTOSCROLL::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar)
        .mustEqual(jailutils::InPrison(PChar), false, "Cannot use scrolls while jailed");
}

void GP_CLI_COMMAND_AUTOSCROLL::process(MapSession* PSession, CCharEntity* PChar) const
{
    auto* inventory = PChar->getStorage(LOC_INVENTORY);
    uint16_t learnedIds[32];
    uint8_t  learned = 0;

    for (uint8 slot = 0; slot <= inventory->GetSize(); ++slot)
    {
        auto* PItem = inventory->GetItem(slot);
        if (!PItem || PItem->getQuantity() == 0)
        {
            continue;
        }

        if (PItem->isSubType(ITEM_LOCKED) || PItem->getReserve() > 0)
        {
            continue;
        }

        if (!PItem->hasFlag(ItemFlag::Scroll))
        {
            continue;
        }

        const uint16 spellID = static_cast<uint16>(PItem->getSubID());

        if (charutils::hasSpell(PChar, spellID))
        {
            continue;
        }

        if (!spell::CanUseSpell(PChar, static_cast<SpellID>(spellID)))
        {
            continue;
        }

        if (charutils::addSpell(PChar, spellID))
        {
            charutils::SaveSpell(PChar, spellID);
            charutils::UpdateItem(PChar, LOC_INVENTORY, slot, -1);
            PChar->pushPacket<GP_SERV_COMMAND_BATTLE_MESSAGE>(PChar, PChar, 0, 0, MsgBasic::LearnsNewSpell);
            if (learned < 32)
            {
                learnedIds[learned] = spellID;
            }
            ++learned;
        }
    }

    if (learned > 0)
    {
        PChar->pushPacket<GP_SERV_COMMAND_MAGIC_DATA>(PChar);
        PChar->pushPacket<GP_SERV_COMMAND_ITEM_SAME>(PChar);
    }
    PChar->pushPacket<GP_SERV_COMMAND_AUTOSCROLL_RESULT>(learned, learnedIds);
}
