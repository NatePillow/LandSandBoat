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

// Custom packet 0x185 (C2S): LIST_ALLIANCE_PCS request.
// No payload — sender's identity drives the response. Server walks the
// requester's alliance and replies with a single 0x186 ALLIANCE_PC_LIST
// containing every CCharEntity member (trusts and other non-PC entities are
// excluded by virtue of the alliance walk only enumerating chars).
//
// Used by the autobots Battlefield section: when the addon detects an active
// battlefield (0x075 Flags > 0) it fires this request so the checkbox list of
// "who do I want to bring in?" is sourced from the authoritative PC roster
// instead of the client party manager (which mixes trusts with PCs).
//
// Total: 4 (header) bytes. PacketSize = 4 / 2 = 0x02.
GP_CLI_PACKET(GP_CLI_COMMAND_LIST_ALLIANCE_PCS,
);
