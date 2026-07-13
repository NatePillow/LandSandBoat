/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x178_set_lot_assignment.h"

#include "entities/charentity.h"
#include "enums/chat_message_type.h"
#include "lua/luautils.h"
#include "packets/s2c/0x017_chat_std.h"

#include "common/logging.h"

#include <cstring>
#include <string>

auto GP_CLI_COMMAND_SET_LOT_ASSIGNMENT::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_SET_LOT_ASSIGNMENT::process(MapSession* PSession, CCharEntity* PChar) const
{
    const std::string charName(CharName,  strnlen(CharName,  sizeof(CharName)));
    const std::string groupName(GroupName, strnlen(GroupName, sizeof(GroupName)));
    const bool        on = (On != 0);

    if (charName.empty() || groupName.empty())
    {
        return;
    }

    // Reject path-traversal in the group name — Lua side joins it into a
    // path under singleplayer/config/lot/ when resolving the items list.
    if (groupName.find_first_of("/\\.") != std::string::npos)
    {
        PChar->pushPacket<GP_SERV_COMMAND_CHAT_STD>(
            PChar, MESSAGE_SYSTEM_1,
            std::string("SetLotAssignment: invalid group name '") + groupName + "'.");
        return;
    }

    luautils::OnSetLotAssignment(PChar, charName, groupName, on);
}
