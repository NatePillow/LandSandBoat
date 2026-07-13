/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "login_hooks.h"

#include "common/logging.h"
#include "entities/charentity.h"
#include "map_session_container.h"

namespace singleplayer
{
    void evictConflictingHeadlessForLogin(CCharEntity* PChar)
    {
        if (PChar == nullptr)
        {
            return;
        }
        // If this char is currently spawned as someone's headless (different
        // session, parentCharId != 0), evict that headless before proceeding —
        // the real client takes precedence. Without this, two CCharEntity
        // copies would race on the same DB rows. Mirrors the spawnHeadless
        // refusal at lua_baseentity.cpp ("'<name>' is already in the world")
        // in the opposite direction. The headless's owning primary, if still
        // online, receives a GP_SERV_COMMAND_AUTOSKILL_STATE clear so their
        // addon caches update.
        if (mapsessions::get().destroyHeadlessByCharId(PChar->id))
        {
            ShowInfoFmt("GP_CLI_COMMAND_LOGIN: evicted headless session for '{}' (id {}) — real client took over",
                        PChar->getName(), PChar->id);
        }
    }

    void moveOwnedHeadlessIntoPrimaryZone(CCharEntity* PChar)
    {
        if (PChar == nullptr)
        {
            return;
        }
        // Headless follow-along: pull every bot owned by this primary into the
        // new zone, snapping to the primary's position. Without this, bots
        // get stranded in the previous zone when the primary zones. Skipped
        // implicitly for clients with no headless (count == 0).
        const uint32 moved = mapsessions::get().moveHeadlessToPrimaryZone(PChar->id);
        if (moved > 0)
        {
            ShowDebugFmt("GP_CLI_COMMAND_LOGIN: moved {} headless bot(s) to follow '{}' into zone {}",
                         moved, PChar->getName(), PChar->getZone());
        }
    }
}
