/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x18b_list_bot_spells.h"

#include "entities/charentity.h"
#include "map_session_container.h"
#include "packets/s2c/0x18c_bot_spells_list.h"
#include "spell.h"
#include "utils/charutils.h"
#include "utils/zoneutils.h"

#include "common/logging.h"

#include <algorithm>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

namespace
{
    // Authorized iff target is the requester themselves or a headless owned by
    // them. Mirrors the gate in 0x18F GET_CHAR_INV.
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
}

auto GP_CLI_COMMAND_LIST_BOT_SPELLS::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_LIST_BOT_SPELLS::process(MapSession* PSession, CCharEntity* PChar) const
{
    if (PChar == nullptr)
    {
        return;
    }

    const std::string name(BotName, strnlen(BotName, sizeof(BotName)));
    const bool        wantTrusts = (GroupFilter == 1);

    CCharEntity* PTarget = resolveAuthorizedTarget(PChar, name);
    if (PTarget == nullptr)
    {
        ShowDebug(fmt::format("ListBotSpells: refused or unknown target '{}' from '{}'",
                              name, PChar->getName()));
        // Send an empty final chunk so the requester's callback fires.
        PChar->pushPacket<GP_SERV_COMMAND_BOT_SPELLS_LIST>(
            name, GroupFilter, true, std::vector<std::pair<uint16_t, std::string>>{});
        return;
    }

    // Collect spells the target has learned within the requested group AND
    // can actually cast under their current main/sub job + level. Without the
    // CanUseSpell gate, a char who learned WHM spells while WHM but is now
    // BLM would still see every WHM spell in the picker UI even though the
    // server would silently reject any cast attempt. Mirrors the original
    // ffxi-ashita autobots filter (job + level checked client-side).
    std::vector<std::pair<uint16_t, std::string>> entries;
    entries.reserve(64);
    for (uint16 id = 0; id < MAX_SPELL_ID; ++id)
    {
        CSpell* PSpell = spell::GetSpell(static_cast<SpellID>(id));
        if (PSpell == nullptr)
        {
            continue;
        }
        const SPELLGROUP group = PSpell->getSpellGroup();
        const bool       isTrust = (group == SPELLGROUP_TRUST);
        if (wantTrusts != isTrust)
        {
            continue;
        }
        if (charutils::hasSpell(PTarget, id) == 0)
        {
            continue;
        }
        // Trusts skip the job-level gate: trust availability is governed by
        // separate unlock state, and CanUseSpell on trusts isn't meaningful.
        if (!isTrust && !spell::CanUseSpell(PTarget, PSpell))
        {
            continue;
        }
        entries.emplace_back(id, PSpell->getName());
    }

    constexpr size_t kPerChunk = GP_SERV_COMMAND_BOT_SPELLS_LIST::kEntriesPerChunk;
    const size_t     total     = entries.size();

    if (total == 0)
    {
        PChar->pushPacket<GP_SERV_COMMAND_BOT_SPELLS_LIST>(
            name, GroupFilter, true, std::vector<std::pair<uint16_t, std::string>>{});
        return;
    }

    for (size_t offset = 0; offset < total; offset += kPerChunk)
    {
        const size_t end     = std::min(offset + kPerChunk, total);
        const bool   isFinal = (end == total);
        std::vector<std::pair<uint16_t, std::string>> chunk(entries.begin() + offset, entries.begin() + end);
        PChar->pushPacket<GP_SERV_COMMAND_BOT_SPELLS_LIST>(name, GroupFilter, isFinal, chunk);
    }
}
