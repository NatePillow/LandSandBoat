/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x184_lot_list_action.h"

#include "entities/charentity.h"
#include "lua/luautils.h"

#include "common/logging.h"

#include <cstring>
#include <string>

namespace
{
    constexpr uint8 ACT_ADD    = 0x01;
    constexpr uint8 ACT_REMOVE = 0x02;
    constexpr uint8 ACT_CLEAR  = 0x03;
}

auto GP_CLI_COMMAND_LOT_LIST_ACTION::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_LOT_LIST_ACTION::process(MapSession* PSession, CCharEntity* PChar) const
{
    if (ItemId == 0)
    {
        return;
    }

    if (Action == ACT_CLEAR)
    {
        luautils::OnLotListClear(PChar, ItemId);
        return;
    }

    const std::string botName(BotName, strnlen(BotName, sizeof(BotName)));
    if (botName.empty())
    {
        return;
    }

    if (Action == ACT_ADD)
    {
        luautils::OnLotListAdd(PChar, ItemId, botName);
    }
    else if (Action == ACT_REMOVE)
    {
        luautils::OnLotListRemove(PChar, ItemId, botName);
    }
    else
    {
        ShowDebug(fmt::format("LOT_LIST_ACTION: unknown Action 0x{:02x}", Action));
    }
}
