/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x178_headless_state.h"

#include <algorithm>
#include <cstring>

GP_SERV_COMMAND_HEADLESS_STATE::GP_SERV_COMMAND_HEADLESS_STATE(uint8_t stateType, const uint8_t* payload, size_t payloadLen)
{
    auto& packet     = this->data();
    packet.StateType = stateType;

    std::memset(packet.Padding, 0, sizeof(packet.Padding));
    std::memset(packet.Payload, 0, sizeof(packet.Payload));

    if (payload != nullptr && payloadLen > 0)
    {
        const size_t toCopy = std::min(payloadLen, sizeof(packet.Payload));
        std::memcpy(packet.Payload, payload, toCopy);
    }
}
