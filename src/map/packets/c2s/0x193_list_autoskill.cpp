/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x193_list_autoskill.h"

#include "entities/charentity.h"
#include "lua/luautils.h"

auto GP_CLI_COMMAND_LIST_AUTOSKILL::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_LIST_AUTOSKILL::process(MapSession* PSession, CCharEntity* PChar) const
{
    if (PChar == nullptr)
    {
        return;
    }
    luautils::OnListAutoskill(PChar);
}
