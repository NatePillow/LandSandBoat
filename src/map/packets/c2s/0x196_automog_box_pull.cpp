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

#include "0x196_automog_box_pull.h"

#include "common/database.h"
#include "common/logging.h"
#include "entities/charentity.h"
#include "item_container.h"
#include "items/item.h"
#include "map_session_container.h"
#include "packets/s2c/0x01d_item_same.h"
#include "packets/s2c/0x197_automog_box_result.h"
#include "utils/charutils.h"
#include "utils/itemutils.h"
#include "utils/jailutils.h"

#include <cstring>
#include <string>

namespace
{

auto sanitizeName(const char* raw) -> std::string
{
    if (raw == nullptr)
    {
        return {};
    }
    std::string s(raw, strnlen(raw, 16));
    while (!s.empty() && s.back() == '\0')
    {
        s.pop_back();
    }
    return s;
}

} // namespace

auto GP_CLI_COMMAND_AUTOMOG_BOX_PULL::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar)
        .mustEqual(jailutils::InPrison(PChar), false, "Cannot use delivery box while jailed");
}

void GP_CLI_COMMAND_AUTOMOG_BOX_PULL::process(MapSession* PSession, CCharEntity* PChar) const
{
    const std::string targetName = sanitizeName(TargetCharName);
    if (targetName.empty())
    {
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_BOX_RESULT>(2u, 0u);
        return;
    }

    auto& sessions      = mapsessions::get();
    auto* targetSession = sessions.getSessionByCharName(targetName);
    if (targetSession == nullptr || targetSession->PChar == nullptr)
    {
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_BOX_RESULT>(2u, 0u);
        return;
    }

    CCharEntity* targetChar = targetSession->PChar.get();
    const bool   owned      = (targetChar == PChar) || (targetSession->parentCharId == PChar->id);
    if (!owned)
    {
        ShowWarningFmt("AUTOMOG_BOX_PULL: ownership rejected (sender={} target={})", PChar->name, targetName);
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_BOX_RESULT>(2u, 0u);
        return;
    }

    const auto rset = db::preparedStmt(
        "SELECT itemid, itemsubid, slot, quantity, extra, sender FROM delivery_box "
        "WHERE charid = ? AND box = 1 ORDER BY slot ASC",
        targetChar->id);

    uint8_t moved = 0;
    bool    full  = false;

    if (rset)
    {
        while (rset->next())
        {
            // Build a fresh CItem from the templated definition (xi::items::spawn
            // returns a unique_ptr<CItem> with the item ID and base attrs set;
            // we overlay the row's slot/quantity/extra/sender before insertion).
            auto PItem = xi::items::spawn(rset->get<uint16>("itemid"));
            if (!PItem)
            {
                continue;
            }

            PItem->setSubID(rset->get<uint16>("itemsubid"));
            PItem->setSlotID(rset->get<uint8>("slot"));
            PItem->setQuantity(rset->get<uint32>("quantity"));
            db::extractFromBlob(rset, "extra", PItem->m_extra);
            PItem->setSender(rset->get<std::string>("sender"));
            PItem->setReceiver(targetChar->getName());

            if (!PItem->isType(ITEM_CURRENCY) && targetChar->getStorage(LOC_INVENTORY)->GetFreeSlotsCount() == 0)
            {
                full = true;
                break;
            }

            const uint8_t dbSlot = PItem->getSlotID();
            // Save a raw pointer pre-move so we can log on rollback (we surrender
            // ownership to AddItem inside the transaction).
            const auto    itemId = PItem->getID();
            const auto    success = db::transaction([&]()
            {
                const auto del = db::preparedStmt(
                    "DELETE FROM delivery_box WHERE charid = ? AND slot = ? AND box = 1 LIMIT 1",
                    targetChar->id, dbSlot);
                if (del && del->rowsAffected())
                {
                    if (charutils::AddItem(targetChar, LOC_INVENTORY, std::move(PItem), true) != ERROR_SLOTID)
                    {
                        return;
                    }
                }
                throw std::runtime_error(fmt::format("AUTOMOG_BOX_PULL: could not retrieve item {} from delivery_box slot {} (target: {} ({}))",
                                                     itemId, dbSlot, targetChar->getName(), targetChar->id));
            });

            if (success)
            {
                ++moved;
            }
            // PItem is either consumed by AddItem (success) or destroyed when
            // unique_ptr goes out of scope (failure path) — no explicit cleanup.
        }
    }

    if (moved > 0)
    {
        targetChar->pushPacket<GP_SERV_COMMAND_ITEM_SAME>(targetChar);
    }
    PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_BOX_RESULT>(full ? 1u : 0u, moved);
}
