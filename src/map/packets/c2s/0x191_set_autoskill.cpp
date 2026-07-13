/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x191_set_autoskill.h"

#include "entities/charentity.h"
#include "lua/luautils.h"

#include "common/logging.h"

#include <cstring>
#include <string>
#include <vector>

auto GP_CLI_COMMAND_SET_AUTOSKILL::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_SET_AUTOSKILL::process(MapSession* PSession, CCharEntity* PChar) const
{
    if (PChar == nullptr)
    {
        return;
    }

    const std::string name(BotName, strnlen(BotName, sizeof(BotName)));
    if (name.empty())
    {
        return;
    }

    // Clamp + materialize the spell list (only the first SpellCount entries
    // are meaningful — guarded against malicious oversized counts).
    const uint8 count = std::min<uint8>(SpellCount, 16);
    std::vector<uint16_t> spellIds;
    spellIds.reserve(count);
    for (uint8 i = 0; i < count; ++i)
    {
        spellIds.push_back(SpellIds[i]);
    }

    luautils::OnSetAutoskill(PChar, name, Mode, spellIds);
}
