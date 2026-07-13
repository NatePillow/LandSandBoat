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

#include "common/timer.h"

class CCharEntity;

namespace singleplayer
{
    // Singleplayer-fork hook called once from CCharEntity::PostTick. Handles
    // the three additions to that method:
    //   1. Server-ident heartbeat push (skipped for headless — no client)
    //   2. Headless housekeeping (packet queue drain + periodic forced save)
    //   3. Bot-AI tick dispatch when m_botMode != Off (OnBotTick into Lua)
    //
    // Lives in one call so upstream PostTick only grows by a single line.
    // Safe to call for every char each tick — internal predicates short-
    // circuit when nothing applies.
    void onCharPostTick(CCharEntity* PChar, timer::time_point now);
}
