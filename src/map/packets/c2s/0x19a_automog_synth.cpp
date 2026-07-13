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

#include "0x19a_automog_synth.h"

#include "common/logging.h"
#include "entities/charentity.h"
#include "enums/msg_std.h"
#include "items.h"
#include "item_container.h"
#include "items/transactions/synth.h"
#include "map_session_container.h"
#include "packets/c2s/base.h"
#include "packets/s2c/0x029_battle_message.h"
#include "packets/s2c/0x19b_automog_synth_result.h"
#include "universal_container.h"
#include "utils/jailutils.h"
#include "utils/synthutils.h"

#include <cstring>
#include <set>
#include <string>

namespace
{

// Embedded 0x161-shape body the addon stuffs into InnerPacket — identical to
// the legacy GP_CLI_COMMAND_FAST_SYNTH layout. 0x161 itself was retired in
// #233 (2026-06-17); this struct preserves the wire format so addon code
// doesn't change. Total body = 30 bytes; well under InnerPacket[64].
struct InnerSynth
{
    GP_CLI_HEADER header;
    uint8_t       HashNo;
    uint8_t       padding00;
    uint16_t      Crystal;
    uint8_t       CrystalIdx;
    uint8_t       Items;
    uint16_t      ItemNo[8];
    uint8_t       TableNo[8];
};
static_assert(sizeof(InnerSynth) <= 64, "InnerSynth must fit in InnerPacket[64]");

const std::set validCrystals = {
    FIRE_CRYSTAL,
    ICE_CRYSTAL,
    WIND_CRYSTAL,
    EARTH_CRYSTAL,
    LIGHTNING_CRYSTAL,
    WATER_CRYSTAL,
    LIGHT_CRYSTAL,
    DARK_CRYSTAL,
    DARK_CLUSTER,
    INFERNO_CRYSTAL,
    GLACIER_CRYSTAL,
    CYCLONE_CRYSTAL,
    TERRA_CRYSTAL,
    PLASMA_CRYSTAL,
    TORRENT_CRYSTAL,
    AURORA_CRYSTAL,
    TWILIGHT_CRYSTAL,
    PYRE_CRYSTAL,
    FROST_CRYSTAL,
    VORTEX_CRYSTAL,
    GEO_CRYSTAL,
    BOLT_CRYSTAL,
    FLUID_CRYSTAL,
    GLIMMER_CRYSTAL,
    SHADOW_CRYSTAL,
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

auto inner(const uint8_t* bytes) -> const InnerSynth*
{
    return reinterpret_cast<const InnerSynth*>(bytes);
}

} // namespace

auto GP_CLI_COMMAND_AUTOMOG_SYNTH::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    const auto* body = inner(InnerPacket);
    return PacketValidator(PChar)
        .mustEqual(jailutils::InPrison(PChar), false, "Cannot craft while jailed")
        .oneOf("Crystal", static_cast<ITEMID>(body->Crystal), validCrystals)
        .range("Items", body->Items, 1, 8)
        .custom([this](PacketValidator& v)
        {
            if (sanitizeName(TargetCharName).empty())
            {
                v.mustEqual(true, false, "TargetCharName is empty");
                return;
            }
        });
}

void GP_CLI_COMMAND_AUTOMOG_SYNTH::process(MapSession* PSession, CCharEntity* PChar) const
{
    const std::string targetName = sanitizeName(TargetCharName);

    auto& sessions      = mapsessions::get();
    auto* targetSession = sessions.getSessionByCharName(targetName);
    if (targetSession == nullptr || targetSession->PChar == nullptr)
    {
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_SYNTH_RESULT>(1u); // target not sessioned
        return;
    }

    CCharEntity* targetChar = targetSession->PChar.get();
    const bool   owned      = (targetChar == PChar) || (targetSession->parentCharId == PChar->id);
    if (!owned)
    {
        ShowWarningFmt("AUTOMOG_SYNTH: ownership rejected (sender={} target={})", PChar->name, targetName);
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_SYNTH_RESULT>(2u); // ownership rejected
        return;
    }

    if (jailutils::InPrison(targetChar))
    {
        targetChar->pushPacket<GP_SERV_COMMAND_BATTLE_MESSAGE>(targetChar, targetChar, 0, 0, MsgBasic::CannotUseInArea);
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_SYNTH_RESULT>(0u);
        return;
    }

    if (targetChar->UContainer->GetType() != UCONTAINER_EMPTY)
    {
        targetChar->pushPacket<GP_SERV_COMMAND_MESSAGE>(MsgStd::CannotBeProcessed);
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_SYNTH_RESULT>(0u);
        return;
    }

    const auto* body = inner(InnerPacket);

    const auto* PItem = targetChar->getStorage(LOC_INVENTORY)->GetItem(body->CrystalIdx);
    if (!PItem || body->Crystal != PItem->getID() || PItem->getQuantity() == 0)
    {
        targetChar->pushPacket<GP_SERV_COMMAND_BATTLE_MESSAGE>(targetChar, targetChar, 0, 0, MsgBasic::CannotUseInArea);
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_SYNTH_RESULT>(0u);
        return;
    }

    if (PItem->isBusy() || PItem->isSubType(ITEM_LOCKED))
    {
        ShowWarningFmt("AUTOMOG_SYNTH: {} trying to use unavailable crystal", targetChar->getName());
        targetChar->pushPacket<GP_SERV_COMMAND_BATTLE_MESSAGE>(targetChar, targetChar, 0, 0, MsgBasic::CannotUseInArea);
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_SYNTH_RESULT>(0u);
        return;
    }

    SynthOffer offer{
        .crystal = { body->Crystal, body->CrystalIdx },
    };

    std::vector<uint8> slotQty(MAX_CONTAINER_SIZE);
    for (int32 slotId = 0; slotId < body->Items; ++slotId)
    {
        const uint16 itemId    = body->ItemNo[slotId];
        const uint8  invSlotId = body->TableNo[slotId];

        slotQty[invSlotId]++;

        const auto* PSlotItem = targetChar->getStorage(LOC_INVENTORY)->GetItem(invSlotId);
        if (!PSlotItem || PSlotItem->getID() != itemId)
        {
            continue;
        }

        if (PSlotItem->isBusy() || PSlotItem->isSubType(ITEM_LOCKED) ||
            slotQty[invSlotId] > PSlotItem->getQuantity())
        {
            ShowWarningFmt("AUTOMOG_SYNTH: {} trying to use unavailable ingredient", targetChar->getName());
            continue;
        }

        offer.ingredients[slotId] = { itemId, invSlotId };
    }

    synthutils::doInstantSynth(targetChar, offer);
    PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_SYNTH_RESULT>(0u);
}
