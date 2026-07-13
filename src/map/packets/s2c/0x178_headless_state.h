/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#pragma once

#include "base.h"

// Custom packet 0x178 (S2C): per-headless state update pushed to the primary client.
// StateType selects the meaning of the payload bytes; e.g.,
//   0x01 HP/MP percent     Payload: charId(4) + hpPercent(1) + mpPercent(1) + padding(2)
//   0x02 active role       Payload: charId(4) + role(1) + padding(3)
//   0x03 target id         Payload: charId(4) + targetId(4)
// All sub-types use the same fixed 8-byte payload; addons key in by StateType.
class GP_SERV_COMMAND_HEADLESS_STATE final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_HEADLESS_STATE, GP_SERV_COMMAND_HEADLESS_STATE>
{
public:
    struct PacketData
    {
        uint8_t StateType;
        uint8_t Padding[3];
        uint8_t Payload[8];
    };

    GP_SERV_COMMAND_HEADLESS_STATE(uint8_t stateType, const uint8_t* payload, size_t payloadLen);
};
