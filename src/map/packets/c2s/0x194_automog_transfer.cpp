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

#include "0x194_automog_transfer.h"

#include "common/database.h"
#include "entities/charentity.h"
#include "item_container.h"
#include "items/item.h"
#include "map_session_container.h"
#include "packets/s2c/0x01d_item_same.h"
#include "packets/s2c/0x020_item_attr.h"
#include "packets/s2c/0x195_automog_transfer_result.h"
#include "utils/charutils.h"
#include "utils/jailutils.h"

#include "common/logging.h"

#include <cstring>
#include <string>

namespace
{

const std::set<CONTAINER_ID> kTransferableContainers = {
    LOC_INVENTORY, LOC_MOGSAFE, LOC_STORAGE, LOC_MOGSATCHEL, LOC_MOGSACK, LOC_MOGCASE,
    LOC_WARDROBE, LOC_MOGSAFE2, LOC_WARDROBE2, LOC_WARDROBE3, LOC_WARDROBE4,
    LOC_WARDROBE5, LOC_WARDROBE6, LOC_WARDROBE7, LOC_WARDROBE8,
};

const std::set<CONTAINER_ID> kWardrobeContainers = {
    LOC_WARDROBE, LOC_WARDROBE2, LOC_WARDROBE3, LOC_WARDROBE4,
    LOC_WARDROBE5, LOC_WARDROBE6, LOC_WARDROBE7, LOC_WARDROBE8,
};

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

// True if `target` is the sender or a headless owned by sender.
auto ownedBy(const MapSession* targetSession, const CCharEntity* sender) -> bool
{
    if (targetSession == nullptr || sender == nullptr || targetSession->PChar == nullptr)
    {
        return false;
    }
    if (targetSession->PChar.get() == sender)
    {
        return true;
    }
    return targetSession->parentCharId == sender->id;
}

} // namespace

auto GP_CLI_COMMAND_AUTOMOG_TRANSFER::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    const auto src = static_cast<CONTAINER_ID>(SrcBag);
    const auto dst = static_cast<CONTAINER_ID>(DstBag);

    return PacketValidator(PChar)
        .mustEqual(jailutils::InPrison(PChar), false, "Cannot transfer items while jailed")
        .range("Count", Count, 1, 32)
        .oneOf("SrcBag", src, kTransferableContainers)
        .oneOf("DstBag", dst, kTransferableContainers)
        .custom([this](PacketValidator& v)
        {
            const std::string srcName = sanitizeName(SrcCharName);
            const std::string dstName = sanitizeName(DstCharName);
            if (srcName.empty())
            {
                v.mustEqual(true, false, "SrcCharName is empty");
                return;
            }
            if (dstName.empty())
            {
                v.mustEqual(true, false, "DstCharName is empty");
                return;
            }
            // Intra-char same-bag is invalid; cross-char same-bag is fine.
            if (srcName == dstName && SrcBag == DstBag)
            {
                v.mustEqual(true, false, "SrcBag and DstBag must differ for intra-char moves");
                return;
            }
        });
}

void GP_CLI_COMMAND_AUTOMOG_TRANSFER::process(MapSession* PSession, CCharEntity* PChar) const
{
    const std::string srcName = sanitizeName(SrcCharName);
    const std::string dstName = sanitizeName(DstCharName);

    auto& sessions   = mapsessions::get();
    auto* srcSession = sessions.getSessionByCharName(srcName);
    auto* dstSession = sessions.getSessionByCharName(dstName);

    if (srcSession == nullptr || dstSession == nullptr)
    {
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_TRANSFER_RESULT>(2u, 0u);
        return;
    }
    if (!ownedBy(srcSession, PChar) || !ownedBy(dstSession, PChar))
    {
        ShowWarningFmt("AUTOMOG_TRANSFER: ownership rejected (sender={} src={} dst={})",
                       PChar->name, srcName, dstName);
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_TRANSFER_RESULT>(2u, 0u);
        return;
    }

    CCharEntity* srcChar = srcSession->PChar.get();
    CCharEntity* dstChar = dstSession->PChar.get();
    const auto   srcId   = static_cast<CONTAINER_ID>(SrcBag);
    const auto   dstId   = static_cast<CONTAINER_ID>(DstBag);
    const bool   crossChar = (srcChar != dstChar);

    CItemContainer* srcStorage = srcChar->getStorage(srcId);
    CItemContainer* dstStorage = dstChar->getStorage(dstId);
    if (srcStorage == nullptr || dstStorage == nullptr)
    {
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_TRANSFER_RESULT>(2u, 0u);
        return;
    }

    uint8_t moved = 0;
    bool    full  = false;

    for (uint8_t i = 0; i < Count; ++i)
    {
        const uint8_t srcSlot = Slots[i];
        CItem*        PItem   = srcStorage->GetItem(srcSlot);
        if (!PItem)
        {
            continue;
        }
        if (PItem->isSubType(ITEM_LOCKED) || PItem->getReserve() > 0)
        {
            continue;
        }
        if (kWardrobeContainers.contains(dstId) &&
            !PItem->isType(ITEM_EQUIPMENT) && !PItem->isType(ITEM_WEAPON))
        {
            continue;
        }
        // RARE gate (cross-char only): if dst already holds this item ID,
        // skip — mirrors charutils::AddItem's refusal so cross-char moves
        // can't dual-own a RARE. Intra-char moves don't need this; the item
        // is already counted once for the owner.
        if (crossChar && PItem->hasFlag(ItemFlag::Rare) && charutils::HasItem(dstChar, PItem->getID()))
        {
            ShowDebugFmt("AUTOMOG_TRANSFER: skipping RARE item {} for '{}' (already owned)",
                         PItem->getID(), dstChar->getName());
            continue;
        }
        if (dstStorage->GetFreeSlotsCount() == 0)
        {
            full = true;
            break;
        }

        // Take ownership: srcStorage relinquishes the unique_ptr so we can
        // hand it to dstStorage. Capture a raw pointer first for use in
        // post-move attr packets and logging (the underlying CItem outlives
        // the move; only the unique_ptr changes hands).
        auto    PMoving = srcStorage->RemoveItem(srcSlot);
        CItem*  PRaw    = PMoving.get();
        if (!PRaw)
        {
            continue;
        }
        const uint16_t movedItemId = PRaw->getID();

        const uint8_t dstSlot = dstStorage->InsertItem(std::move(PMoving));
        if (dstSlot == ERROR_SLOTID)
        {
            // Should be impossible after GetFreeSlotsCount > 0, but if the
            // storage rejects it for any other reason we have to put it
            // back so we don't leak the item. PMoving is still empty here;
            // RemoveItem from dst yields nothing useful, so re-spawn the
            // raw pointer's slot is the only recovery. In practice we just
            // log and bail — upstream charutils::MoveItem does the same.
            ShowErrorFmt("AUTOMOG_TRANSFER: dst InsertItem failed (post free-slot check); item lost. "
                         "src={}({}:{}) dst={} item={}",
                         srcChar->name, SrcBag, srcSlot, dstChar->name, movedItemId);
            full = true;
            break;
        }

        // DB update — intra-char only changes location/slot; cross-char also
        // changes charid so the row's ownership follows the move.
        const auto rset = crossChar
            ? db::preparedStmt(
                  "UPDATE char_inventory SET charid = ?, location = ?, slot = ? WHERE charid = ? AND location = ? AND slot = ? LIMIT 1",
                  dstChar->id, static_cast<uint8_t>(dstId), dstSlot,
                  srcChar->id, static_cast<uint8_t>(srcId), srcSlot)
            : db::preparedStmt(
                  "UPDATE char_inventory SET location = ?, slot = ? WHERE charid = ? AND location = ? AND slot = ? LIMIT 1",
                  static_cast<uint8_t>(dstId), dstSlot,
                  srcChar->id, static_cast<uint8_t>(srcId), srcSlot);

        if (rset && rset->rowsAffected())
        {
            srcChar->pushPacket<GP_SERV_COMMAND_ITEM_ATTR>(nullptr, srcId, srcSlot, PRaw);
            dstChar->pushPacket<GP_SERV_COMMAND_ITEM_ATTR>(PRaw, dstId, dstSlot);
            ++moved;
        }
        else
        {
            // DB write failed — roll the item back into src. Reclaim the
            // unique_ptr from dst and re-insert at the original src slot.
            auto PRollback = dstStorage->RemoveItem(dstSlot);
            if (PRollback)
            {
                srcStorage->InsertItem(std::move(PRollback), srcSlot);
            }
            ShowErrorFmt("AUTOMOG_TRANSFER: DB update failed; rolled back. src={}({}:{}) dst={}({}:{}) cross={}",
                         srcChar->name, SrcBag, srcSlot,
                         dstChar->name, DstBag, dstSlot, crossChar);
            break;
        }
    }

    srcChar->pushPacket<GP_SERV_COMMAND_ITEM_SAME>(srcChar);
    if (crossChar)
    {
        dstChar->pushPacket<GP_SERV_COMMAND_ITEM_SAME>(dstChar);
    }
    PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_TRANSFER_RESULT>(full ? 1u : 0u, moved);
}
