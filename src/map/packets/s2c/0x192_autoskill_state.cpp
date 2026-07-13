/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x192_autoskill_state.h"

#include <algorithm>
#include <cstring>

GP_SERV_COMMAND_AUTOSKILL_STATE::GP_SERV_COMMAND_AUTOSKILL_STATE(const std::string& botName, uint8_t mode)
{
    auto& packet = this->data();

    std::memset(packet.BotName, 0, sizeof(packet.BotName));
    std::memset(packet.Padding, 0, sizeof(packet.Padding));

    const size_t nameLen = std::min(botName.size(), sizeof(packet.BotName) - 1);
    std::memcpy(packet.BotName, botName.data(), nameLen);

    packet.Mode = mode;
}
