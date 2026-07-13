/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x17d_use_food_config.h"

#include "entities/charentity.h"
#include "enums/chat_message_type.h"
#include "lua/luautils.h"
#include "packets/s2c/0x017_chat_std.h"

#include "common/logging.h"

#include <cstring>
#include <string>

auto GP_CLI_COMMAND_USE_FOOD_CONFIG::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_USE_FOOD_CONFIG::process(MapSession* PSession, CCharEntity* PChar) const
{
    const std::string configName(ConfigName, strnlen(ConfigName, sizeof(ConfigName)));
    if (configName.empty())
    {
        PChar->pushPacket<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SYSTEM_1, std::string("UseFoodConfig: empty config name."));
        return;
    }

    // Reject path-traversal — server joins this string into a path under
    // singleplayer/config/food/.
    if (configName.find_first_of("/\\.") != std::string::npos)
    {
        PChar->pushPacket<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SYSTEM_1, std::string("UseFoodConfig: invalid config name '") + configName + "'.");
        return;
    }

    luautils::OnUseFoodFromConfig(PChar, configName);
}
