/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x1a3_sync_ack.h"

#include <cstring>

GP_SERV_COMMAND_SYNC_ACK::GP_SERV_COMMAND_SYNC_ACK(uint8_t kind, uint32_t count)
{
    auto& packet = this->data();

    std::memset(packet.Padding, 0, sizeof(packet.Padding));

    packet.Kind  = kind;
    packet.Count = count;
}
