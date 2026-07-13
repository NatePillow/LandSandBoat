/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x179_headless_event.h"

#include <algorithm>
#include <cstring>

GP_SERV_COMMAND_HEADLESS_EVENT::GP_SERV_COMMAND_HEADLESS_EVENT(uint8_t eventType, const char* payload, size_t payloadLen)
{
    auto& packet     = this->data();
    packet.EventType = eventType;

    std::memset(packet.Padding, 0, sizeof(packet.Padding));
    std::memset(packet.Payload, 0, sizeof(packet.Payload));

    if (payload != nullptr && payloadLen > 0)
    {
        const size_t toCopy = std::min(payloadLen, sizeof(packet.Payload));
        std::memcpy(packet.Payload, payload, toCopy);
    }
}
