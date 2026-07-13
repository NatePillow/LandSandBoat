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

class CCharEntity;

namespace singleplayer
{
    // Headless eviction on real-client login. If the char being logged in is
    // currently spawned as someone's headless, destroy the headless first so
    // there aren't two CCharEntity copies racing on the same DB rows.
    void evictConflictingHeadlessForLogin(CCharEntity* PChar);

    // Headless follow-along on zone change. After the primary has been placed
    // in their new zone via destZone->IncreaseZoneCounter, pull every owned
    // headless bot into the same zone (snapping position to the primary).
    void moveOwnedHeadlessIntoPrimaryZone(CCharEntity* PChar);
}
