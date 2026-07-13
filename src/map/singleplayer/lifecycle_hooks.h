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
    // Immediate headless cleanup on primary logout. Called from
    // charutils::removeCharFromZone when PChar->status == SHUTDOWN. Without
    // this the watchdog cleanupSessions would catch orphan bots a few seconds
    // later, but during that window they'd keep ticking. Safe to call with
    // any PChar — it skips when PChar is itself headless or has no session.
    void onPrimaryRemovingFromZone(CCharEntity* PChar);

    // Returns true if mob proximity-aggro should skip this PChar. Used in
    // CZoneEntities::SpawnMOBs's tapAggro lambda — headless bots behave
    // trust-like by default (no aggro) unless their m_aggroMode has been
    // bumped above 0 via the addon-driven 0x176 SET_AGGRO_MODE cascade.
    auto shouldSkipMobAggro(const CCharEntity* PChar) -> bool;
}
