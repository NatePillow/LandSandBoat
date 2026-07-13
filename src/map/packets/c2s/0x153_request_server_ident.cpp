/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

===========================================================================
*/

#include "0x153_request_server_ident.h"

#include "entities/charentity.h"
#include "packets/s2c/0x150_server_ident.h"

auto GP_CLI_COMMAND_REQUEST_SERVER_IDENT::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_REQUEST_SERVER_IDENT::process(MapSession* PSession, CCharEntity* PChar) const
{
    if (PChar == nullptr)
    {
        return;
    }

    // One-shot reply with the fork identity. The client's existing 0x150
    // handler flips its `unlocked` flag and runs whatever rising-edge work
    // it has queued. Each addon sends its own request, gets its own reply.
    PChar->pushPacket<GP_SERV_COMMAND_SERVER_IDENT>();
}
