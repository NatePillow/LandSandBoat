/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#pragma once

#include "base.h"

// Custom packet 0x179 (S2C): cross-cutting bot event broadcast to the primary client.
// EventType selects the meaning of the payload bytes; e.g.,
//   0x01 LOG_MESSAGE       Payload: Tag[16] + Message[44]  (autoutil.log style)
//   0x02 DPS_RESET         Payload: zeros
//   0x03 CONFIG_CHANGED    Payload: configName[60]
// Replaces the 0x152 relay channel that the old addons used for inter-client
// chatter, now server-originated.
class GP_SERV_COMMAND_HEADLESS_EVENT final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_HEADLESS_EVENT, GP_SERV_COMMAND_HEADLESS_EVENT>
{
public:
    struct PacketData
    {
        uint8_t EventType;
        uint8_t Padding[3];
        char    Payload[60];
    };

    GP_SERV_COMMAND_HEADLESS_EVENT(uint8_t eventType, const char* payload, size_t payloadLen);
};
