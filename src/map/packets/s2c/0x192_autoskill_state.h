/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#pragma once

#include "base.h"
#include <string>

// Custom packet 0x192 (S2C): AUTOSKILL_STATE push.
// Fired by the server whenever a bot's autoskill override mode changes — both
// in response to an inbound 0x191 SET_AUTOSKILL and on automatic clears (bot
// despawn, alliance hot-swap, etc.). The primary's autoskill + autobots
// addons each maintain their own local cache from this push so the UI can
// render override state without polling.
//
// BotName[16]   target char
// Mode[1]       0=Off, 1=RA, 2=Magic
// Padding[3]
//
// Total: 4 (header) + 16 + 1 + 3 = 24 bytes. PacketSize = 24 / 2 = 0x0C.
class GP_SERV_COMMAND_AUTOSKILL_STATE final : public GP_SERV_PACKET<PacketS2C::GP_SERV_COMMAND_AUTOSKILL_STATE, GP_SERV_COMMAND_AUTOSKILL_STATE>
{
public:
    struct PacketData
    {
        char    BotName[16];
        uint8_t Mode;
        uint8_t Padding[3];
    };

    GP_SERV_COMMAND_AUTOSKILL_STATE(const std::string& botName, uint8_t mode);
};
