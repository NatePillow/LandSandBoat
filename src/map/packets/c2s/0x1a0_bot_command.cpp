/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "0x1a0_bot_command.h"

#include "entities/charentity.h"
#include "lua/luautils.h"

#include <cstring>
#include <string>

auto GP_CLI_COMMAND_BOT_COMMAND::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_BOT_COMMAND::process(MapSession* PSession, CCharEntity* PChar) const
{
    auto safeStr = [](const char* buf, size_t maxLen) -> std::string
    {
        return std::string(buf, strnlen(buf, maxLen));
    };

    const std::string botName    = safeStr(this->BotName,    16);
    const std::string actionKind = safeStr(this->ActionKind,  8);
    const std::string actionName = safeStr(this->ActionName, 32);

    if (botName.empty() || actionKind.empty())
    {
        return;
    }

    luautils::OnBotIssueCommand(PChar, botName, actionKind, actionName, this->TargetId);
}
