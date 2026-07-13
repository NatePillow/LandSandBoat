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

#include "0x175_spawn_headless.h"

#include "entities/charentity.h"
#include "enums/chat_message_type.h"
#include "lua/luautils.h"
#include "packets/s2c/0x017_chat_std.h"

#include "common/logging.h"

#include <cstring>
#include <string>

auto GP_CLI_COMMAND_SPAWN_HEADLESS::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_SPAWN_HEADLESS::process(MapSession* PSession, CCharEntity* PChar) const
{
    const std::string configName(ConfigName, strnlen(ConfigName, sizeof(ConfigName)));
    if (configName.empty())
    {
        PChar->pushPacket<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SYSTEM_1, std::string("SpawnHeadless: empty config name."));
        return;
    }

    // Reject path-traversal attempts in the config name. Spawn config files live
    // under singleplayer/config/alliance/<name>.json; the Lua loader
    // joins this string into a path so we filter any separator-like chars here.
    if (configName.find_first_of("/\\.") != std::string::npos)
    {
        PChar->pushPacket<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SYSTEM_1, std::string("SpawnHeadless: invalid config name '") + configName + "'.");
        return;
    }

    ShowInfo("SpawnHeadless: %s requested config '%s'", PChar->getName().c_str(), configName.c_str());

    luautils::OnBotSpawnFromConfig(PChar, configName);
}
