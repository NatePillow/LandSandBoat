/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "lifecycle_hooks.h"

#include "common/logging.h"
#include "common/settings.h"
#include "entities/charentity.h"
#include "map_session.h"
#include "map_session_container.h"

namespace singleplayer
{
    void onPrimaryRemovingFromZone(CCharEntity* PChar)
    {
        if (PChar == nullptr || PChar->PSession == nullptr)
        {
            return;
        }
        // Skip when PChar is itself a headless (parentCharId != 0) so we
        // don't recurse — destroyHeadlessForParent only matches sessions
        // *owned by* PChar's id, not the other way around.
        if (PChar->PSession->parentCharId != 0)
        {
            return;
        }

        const uint32 botCount = mapsessions::get().destroyHeadlessForParent(PChar->id);
        if (botCount > 0)
        {
            ShowDebug(fmt::format("removeCharFromZone: tore down {} headless bot(s) for primary '{}'",
                                  botCount, PChar->getName()));
        }
    }

    auto shouldSkipMobAggro(const CCharEntity* PChar) -> bool
    {
        if (PChar == nullptr)
        {
            return false;
        }
        // Per-char m_aggroMode replaces the old static singleplayer.HEADLESS_MOB_AGGRO
        // setting (#XYZ): each headless's aggro behavior is now cascaded from the
        // alliance-level addon UI control via 0x176 SET_AGGRO_MODE, so users can
        // flip mode at runtime instead of editing settings + restarting.
        //   0 = Off       — trust-like, mobs never proximity-aggro the headless
        //   1 = Full      — mobs aggro the headless like a real player
        //   2 = Engaged   — invisible until the headless has a battle target,
        //                   then vanilla aggro/link rules apply. Lets a group
        //                   travel freely through a zone but still get linked
        //                   onto by family mobs once a fight starts.
        // Add discriminated modes (sight-only / sound-only / magic-only) by
        // returning false for those values here once the corresponding upstream
        // aggro path is plumbed to read the mode.
        if (!PChar->isHeadless())
        {
            return false;
        }
        if (PChar->m_aggroMode == 0)
        {
            return true;
        }
        if (PChar->m_aggroMode == 2)
        {
            // Engaged: skip aggro iff not currently swinging at something.
            // GetBattleTargetID() returns 0 when disengaged. We deliberately
            // don't walk enmity lists here — the proxy "is engaged" is one
            // member read per aggro check and good enough in practice (a
            // headless that has hate but disengaged-to-rest is briefly
            // invisible, same as the moment they finish a kill).
            return PChar->GetBattleTargetID() == 0;
        }
        return false;
    }
}
