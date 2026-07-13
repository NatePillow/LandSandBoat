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

#include "0x162_automog_change_look.h"

#include "ai/ai_container.h"
#include "common/database.h"
#include "common/logging.h"
#include "entities/charentity.h"
#include "items/item_equipment.h"
#include "map_session_container.h"
#include "packets/basic.h"
#include "packets/s2c/0x163_automog_change_look_result.h"
#include "utils/charutils.h"
#include "utils/jailutils.h"
#include "zone.h"

#include <cstring>
#include <string>

namespace
{

constexpr uint8_t FLAG_CHANGE_RACE = 0x01;
constexpr uint8_t FLAG_CHANGE_FACE = 0x02;
constexpr uint8_t FLAG_CHANGE_SIZE = 0x04;

constexpr uint8_t STATUS_OK        = 0;
constexpr uint8_t STATUS_NO_TARGET = 1;
constexpr uint8_t STATUS_NOT_OWNED = 2;
constexpr uint8_t STATUS_ENGAGED   = 3;
constexpr uint8_t STATUS_OUT_RANGE = 4;
constexpr uint8_t STATUS_NOOP      = 6;

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

// Refresh a headless bot's appearance in place. ForceRezone (used by the
// primary path via charutils::raceChange) would tear down the synthetic
// session, so instead we mirror raceChange's side effects — DB write, drop of
// race-locked gear — then mutate the live look and re-broadcast the char to
// everyone in the zone with a despawn/respawn so clients rebuild the model.
void refreshHeadlessLook(CCharEntity* targetChar, uint8_t newRace, uint8_t newFace, uint8_t newSize)
{
    if (!db::preparedStmt("UPDATE char_look SET face = ?, race = ?, size = ? WHERE charid = ?",
                          newFace, newRace, newSize, targetChar->id))
    {
        ShowError("AUTOMOG_CHANGE_LOOK: Failed to update char_look for charid: %u", targetChar->id);
        return;
    }

    targetChar->look.race = newRace;
    targetChar->look.face = newFace;
    targetChar->look.size = newSize;

    for (uint8 slotId = SLOT_MAIN; slotId <= SLOT_BACK; ++slotId)
    {
        if (auto* PItem = targetChar->getEquip(static_cast<SLOTTYPE>(slotId)))
        {
            if (!PItem->isEquippableByRace(newRace))
            {
                charutils::UnequipItem(targetChar, slotId);
            }
        }
    }

    if (targetChar->loc.zone != nullptr)
    {
        targetChar->loc.zone->UpdateEntityPacket(targetChar, ENTITY_DESPAWN, UPDATE_NONE);
        targetChar->loc.zone->UpdateEntityPacket(targetChar, ENTITY_SPAWN, UPDATE_ALL_CHAR);
    }
}

} // namespace

auto GP_CLI_COMMAND_AUTOMOG_CHANGE_LOOK::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar)
        .mustEqual(jailutils::InPrison(PChar), false, "Cannot change appearance while jailed");
}

void GP_CLI_COMMAND_AUTOMOG_CHANGE_LOOK::process(MapSession* PSession, CCharEntity* PChar) const
{
    auto sendResult = [&](uint8_t status)
    {
        PChar->pushPacket<GP_SERV_COMMAND_AUTOMOG_CHANGE_LOOK_RESULT>(status);
    };

    const std::string targetName = sanitizeName(TargetCharName);
    if (targetName.empty())
    {
        sendResult(STATUS_NO_TARGET);
        return;
    }

    auto* targetSession = mapsessions::get().getSessionByCharName(targetName);
    if (targetSession == nullptr || targetSession->PChar == nullptr)
    {
        sendResult(STATUS_NO_TARGET);
        return;
    }

    CCharEntity* targetChar = targetSession->PChar.get();
    const bool   owned      = (targetChar == PChar) || (targetSession->parentCharId == PChar->id);
    if (!owned)
    {
        ShowWarningFmt("AUTOMOG_CHANGE_LOOK: ownership rejected (sender={} target={})",
                       PChar->getName(), targetName);
        sendResult(STATUS_NOT_OWNED);
        return;
    }

    if (targetChar->PAI->IsEngaged())
    {
        sendResult(STATUS_ENGAGED);
        return;
    }

    const bool wantRace = (Flags & FLAG_CHANGE_RACE) != 0;
    const bool wantFace = (Flags & FLAG_CHANGE_FACE) != 0;
    const bool wantSize = (Flags & FLAG_CHANGE_SIZE) != 0;

    const uint8_t newRace = wantRace ? NewRace : targetChar->look.race;
    const uint8_t newFace = wantFace ? NewFace : targetChar->look.face;
    const uint8_t newSize = wantSize ? NewSize : targetChar->look.size;

    const bool differs = (newRace != targetChar->look.race) ||
                         (newFace != targetChar->look.face) ||
                         (newSize != targetChar->look.size);
    if (!differs)
    {
        sendResult(STATUS_NOOP);
        return;
    }

    // race 1-8, face 0-15, size 0-2 (see reference_char_appearance memory).
    if (newRace < 1 || newRace > 8 || newFace > 15 || newSize > 2)
    {
        sendResult(STATUS_OUT_RANGE);
        return;
    }

    if (targetChar == PChar)
    {
        // Primary has a real client — raceChange handles DB, gear cleanup and
        // ForceRezone (which snaps owned headless to the primary but does not
        // tear their sessions down).
        charutils::raceChange(PChar,
                              static_cast<CharRace>(newRace),
                              static_cast<CharFace>(newFace),
                              static_cast<CharSize>(newSize));
    }
    else
    {
        refreshHeadlessLook(targetChar, newRace, newFace, newSize);
    }

    sendResult(STATUS_OK);
}
