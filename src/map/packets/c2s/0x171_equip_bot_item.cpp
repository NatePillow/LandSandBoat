/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x171_equip_bot_item.h"

#include "entities/charentity.h"
#include "item_container.h"
#include "items/item.h"
#include "map_session_container.h"
#include "packets/s2c/0x1a8_char_profile.h"
#include "utils/charutils.h"
#include "utils/zoneutils.h"

#include "common/logging.h"

#include <cstring>
#include <string>

namespace
{
    // Same authorization model as 0x18F GET_CHAR_INV / 0x1A6 SORT_CHAR_INV
    // / 0x1A7 GET_CHAR_PROFILE: target must be the requester themselves OR
    // a headless sessioned under the requester. nullptr return = unknown
    // or unauthorized, refused silently with a debug log so a stray packet
    // from a stale client can't reach into another account's char.
    CCharEntity* resolveAuthorizedTarget(CCharEntity* PRequester, const std::string& name)
    {
        if (name.empty() || PRequester == nullptr)
        {
            return nullptr;
        }
        if (name == PRequester->getName())
        {
            return PRequester;
        }
        CCharEntity* PTarget = zoneutils::GetCharByName(name);
        if (PTarget == nullptr || PTarget->PSession == nullptr)
        {
            return nullptr;
        }
        if (PTarget->PSession->parentCharId != PRequester->id)
        {
            return nullptr;
        }
        return PTarget;
    }

    // Equip-bearing containers in the order we walk for the item search.
    // Mirrors EQUIP_CONTAINERS in libs/autoequip.lua so server- and
    // client-side enumerations agree: inventory first (where headless
    // gear primarily lives), then wardrobes 1..8. Mog Safe / Storage are
    // intentionally excluded — items there can't be equipped without a
    // separate retrieval, so surfacing them in the picker would just
    // produce silent failures.
    constexpr std::array<uint8, 9> kEquipContainers = {
        LOC_INVENTORY,
        LOC_WARDROBE,
        LOC_WARDROBE2,
        LOC_WARDROBE3,
        LOC_WARDROBE4,
        LOC_WARDROBE5,
        LOC_WARDROBE6,
        LOC_WARDROBE7,
        LOC_WARDROBE8,
    };

    // Find the first inventory slot that holds the given item id on the
    // target char, walking the equip-bearing containers in order. Returns
    // {containerId, slotId} on hit, or {0xFF, 0xFF} on miss.
    struct ItemLoc
    {
        uint8 containerId;
        uint8 slotId;
    };
    ItemLoc findItem(CCharEntity* PTarget, uint16 itemId)
    {
        for (uint8 containerId : kEquipContainers)
        {
            CItemContainer* PContainer = PTarget->getStorage(containerId);
            if (PContainer == nullptr)
            {
                continue;
            }
            const uint8 slotId = PContainer->SearchItem(itemId);
            if (slotId != ERROR_SLOTID)
            {
                return { containerId, slotId };
            }
        }
        return { 0xFF, 0xFF };
    }
} // namespace

auto GP_CLI_COMMAND_EQUIP_BOT_ITEM::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar)
        .range("SlotId", this->SlotId, 0, 15);
}

void GP_CLI_COMMAND_EQUIP_BOT_ITEM::process(MapSession* PSession, CCharEntity* PChar) const
{
    if (PChar == nullptr)
    {
        return;
    }

    const std::string name(CharName, strnlen(CharName, sizeof(CharName)));
    CCharEntity*      PTarget = resolveAuthorizedTarget(PChar, name);
    if (PTarget == nullptr)
    {
        ShowDebug(fmt::format("EquipBotItem: refused or unknown target '{}' from '{}'",
                              name, PChar->getName()));
        return;
    }

    // ItemId == 0 is the unequip sentinel — drop whatever is in SlotId.
    // Lets the addon UI reuse this packet for X-on-left "clear this slot"
    // actions without a second packet number. Push the fresh profile back
    // so the addon's char_profile_cache reflects the cleared slot (same
    // packet the equip branch below fires).
    if (this->ItemId == 0)
    {
        ShowDebug(fmt::format("EquipBotItem: unequip slot {} on '{}' (requested by '{}')",
                              this->SlotId, PTarget->getName(), PChar->getName()));
        charutils::UnequipItem(PTarget, this->SlotId);
        PChar->pushPacket<GP_SERV_COMMAND_CHAR_PROFILE>(PTarget);
        return;
    }

    const ItemLoc loc = findItem(PTarget, this->ItemId);
    if (loc.containerId == 0xFF)
    {
        ShowDebug(fmt::format("EquipBotItem: item {} not found in '{}'s equip-bearing containers",
                              this->ItemId, PTarget->getName()));
        return;
    }

    // charutils::EquipItem does the heavy lifting: validates the item is
    // an equipment, checks slot-mask / job / level gates, swaps with any
    // currently-equipped item in the slot, applies/removes mods, and
    // pushes the appropriate client-side equipment updates. For the
    // primary (target == requester) this drives their own client's
    // equip animation; for a headless it updates the bot's m_equipped
    // and look_t, which then propagates to nearby clients via the
    // standard char_update path.
    charutils::EquipItem(PTarget, loc.slotId, this->SlotId, loc.containerId);

    // Push a fresh char profile back to the REQUESTER (always) so the
    // addon's char_profile_cache picks up the new equipment without a
    // separate poll. We push to PChar even when the target is PChar
    // themselves — same code path, the requester is the only client
    // that needs the snapshot regardless of who got equipped.
    PChar->pushPacket<GP_SERV_COMMAND_CHAR_PROFILE>(PTarget);
}
