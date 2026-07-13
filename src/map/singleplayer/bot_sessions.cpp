/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

// Out-of-line definitions for the singleplayer-fork MapSessionContainer
// methods (declarations live in map_session_container.h). Keeping the bodies
// here means upstream map_session_container.cpp stays at its original
// footprint — any upstream changes there merge cleanly.

#include "map_session_container.h"

#include "map_networking.h"
#include "map_session.h"
#include "packets/s2c/0x192_autoskill_state.h"
#include "status_effect_container.h"

#include "common/database.h"
#include "common/logging.h"
#include "common/xi.h"

#include "ai/ai_container.h"
#include "ai/helpers/pathfind.h"
#include "ai/helpers/action_queue.h"
#include "entities/charentity.h"
#include "zone.h"

#include "lua/luautils.h"
#include "utils/charutils.h"
#include "utils/petutils.h"
#include "utils/zoneutils.h"

using namespace std::chrono_literals;

namespace mapsessions
{
    // TODO: refactor away the singleton, mirror eventual ipc_client cleanup.
    static MapSessionContainer* g_pContainer = nullptr;

    void init(MapSessionContainer* container)
    {
        g_pContainer = container;
    }

    auto get() -> MapSessionContainer&
    {
        return *g_pContainer;
    }

    void persistHeadlessPosZone(CCharEntity* PBot)
    {
        if (PBot == nullptr || PBot->loc.zone == nullptr)
        {
            return;
        }
        db::preparedStmt("UPDATE chars SET pos_zone = ? WHERE charid = ?",
                         PBot->getZone(), PBot->id);
    }
} // namespace mapsessions

auto MapSessionContainer::createHeadlessSession(uint32 charId, CCharEntity* parentChar, uint8 spawnIndex) -> MapSession*
{
    TracyZoneScoped;

    if (parentChar == nullptr || parentChar->loc.zone == nullptr)
    {
        ShowWarning("createHeadlessSession: parent char or parent zone is null");
        return nullptr;
    }

    // Synthetic IPP. IP 0.0.0.0 is never a real client connection, so this can't
    // collide with a normal session. charId is packed across IP (upper 16 bits) and
    // port (lower 16 bits) to keep each headless unique even if charIds grow > 65535.
    const IPP syntheticIPP{ static_cast<uint32>(charId >> 16), static_cast<uint16>(charId & 0xFFFF) };

    if (sessions_.find(syntheticIPP) != sessions_.end())
    {
        ShowWarning(fmt::format("createHeadlessSession: synthetic IPP collision for charId {}", charId));
        return nullptr;
    }

    auto PChar = charutils::LoadChar(scheduler_, config_, charId);
    if (PChar == nullptr)
    {
        ShowWarning(fmt::format("createHeadlessSession: LoadChar returned null for charId {}", charId));
        return nullptr;
    }

    auto session             = std::make_unique<MapSession>();
    session->parentCharId    = parentChar->id;
    session->charID          = charId;
    session->accountID       = PChar->accid;
    session->client_ipp      = syntheticIPP;
    session->last_update     = timer::now();
    session->shuttingDown    = 0;
    session->PChar           = std::move(PChar);
    session->PChar->PSession = session.get();

    CCharEntity* PC = session->PChar.get();

    // Pre-zone: gate the bot AI tick until everything below is wired. PostTick
    // can fire on this entity as soon as IncreaseZoneCounter inserts into
    // m_charList; without this guard the Lua bot tick could run against the
    // partially-initialized AI container.
    PC->m_spawnFinalized = false;

    // Synthetic accounts_sessions row for FK compatibility. accounts_parties
    // and a handful of other tables FK against accounts_sessions(charid), so
    // any DB-driven party broadcast (CParty::AddMember → ipc PartyReload →
    // handleMessage_PartyReload's join over accounts_sessions) silently
    // skipped headless bots without this row, leaving the primary's client
    // showing "solo" even after formAllianceFromSpec wired the bots into
    // PParty->members.
    //
    // server_addr/server_port = 0/0 keeps headless out of map-server routing
    // (they have no socket to route to anyway). client_addr = 0 doubles as
    // the "synthetic — skip me in /search" sentinel; the search query can
    // filter on client_addr != 0 to drop these.
    //
    // REPLACE rather than INSERT IGNORE so re-spawn (despawn → respawn within
    // the same map run) overwrites any stale row left behind by a crash.
    db::preparedStmt(
        "REPLACE INTO accounts_sessions "
        "(accid, charid, server_addr, server_port, client_addr, version_mismatch) "
        "VALUES (?, ?, 0, 0, 0, 0)",
        PC->accid,
        charId);

    // Cross-zone fix: LoadChar set loc.destination to the last-saved zone (could be
    // anywhere). Snap the headless to the parent's current zone and position.
    PC->loc.destination = parentChar->getZone();
    PC->loc.p           = parentChar->loc.p;
    // SINGLEPLAYER: loc.zoning field removed upstream — auto-managed now.

    // Dead-on-spawn loop prevention: if the headless was saved at HP=0 (died last
    // session, parent logged out before reviving), spawning them would just re-die.
    // Treat every spawn as a clean respawn.
    if (PC->health.hp == 0)
    {
        PC->health.hp = PC->GetMaxHP();
        PC->health.mp = PC->GetMaxMP();
    }

    // Place into the world. IncreaseZoneCounter allocates a real targid from the
    // 0x400-0x6FF pool, inserts into m_charList, and notifies nearby chars.
    parentChar->loc.zone->IncreaseZoneCounter(PC);
    PC->status = STATUS_TYPE::NORMAL;

    // Keep chars.pos_zone in sync with the live zone (see the helper decl for
    // why headless need this and the party menu breaks without it).
    mapsessions::persistHeadlessPosZone(PC);

    // Drain the initial OnZoneIn/OnGameIn burst — those hooks pushed status/mission/
    // equip packets that nobody will read.
    PC->clearPacketList();

    // Same 4s post-zone-in delay as real chars. Includes zone afterZoneIn script hook.
    PC->PAI->QueueAction(queueAction_t(4000ms, false, zoneutils::AfterZoneIn));

    // Second drain right after AfterZoneIn fires so the queue doesn't stall with the
    // packets it pushes (mission lists, zone announce, etc.).
    PC->PAI->QueueAction(queueAction_t(4100ms, false, [](CBaseEntity* e) {
        static_cast<CCharEntity*>(e)->clearPacketList();
    }));

    PC->m_botMode = BotMode::Full;

    // Allocate a CPathFind on the headless's AI container so it can use the
    // engine's pathfinding pipeline instead of our setPos teleport-stepping.
    // PCs normally don't have PathFind (they're player-driven), but headless
    // are server-driven — they want what mob/trust movement uses. Same
    // pattern as player_charm_controller.cpp:32 which sets one up on a
    // charmed PC. Once set, ai_container.cpp:420 will FollowPath() each
    // tick when no controller is active (PCs have no Controller). Result:
    // velocity smoothing + animation flags + proper packet cadence — fixes
    // the visible jerk that setPos-based movement produces.
    PC->PAI->PathFind = std::make_unique<CPathFind>(PC);

    // Spread the periodic persist deadlines across a window so multiple headless
    // chars don't all hit the DB on the same tick every TIME_BETWEEN_PERSIST.
    PC->m_nextHeadlessPersist = timer::now() + TIME_BETWEEN_PERSIST + std::chrono::seconds(spawnIndex * 4);

    MapSession* result      = session.get();
    sessions_[syntheticIPP] = std::move(session);

    // Spawn fully assembled: zone insertion, status, queued actions, botMode,
    // session ownership transfer are all done. Flip the gate so the next
    // zone tick can call into the Lua bot AI.
    PC->m_spawnFinalized = true;

    ShowDebug(fmt::format("createHeadlessSession: spawned '{}' (charId {}) under parent '{}' (charId {})",
                          result->PChar->name, charId, parentChar->name, parentChar->id));

    return result;
}

auto MapSessionContainer::destroyHeadlessForParent(uint32 parentCharId) -> uint32
{
    TracyZoneScoped;

    // Collect matches first; mutating mid-iteration invalidates the std::map iterator.
    std::vector<IPP> targetIpps;
    for (auto& [ipp, session] : sessions_)
    {
        if (session && session->parentCharId == parentCharId)
        {
            targetIpps.push_back(ipp);
        }
    }

    // Resolve the requesting parent so we can push autoskill-state-cleared
    // events at them as we tear each bot down. Falls back to no-op if the
    // parent session is already gone (parent disconnected first).
    CCharEntity* PParent = nullptr;
    if (MapSession* parentSession = getSessionByCharId(parentCharId))
    {
        if (parentSession->PChar)
        {
            PParent = parentSession->PChar.get();
        }
    }

    for (auto ipp : targetIpps)
    {
        auto it = sessions_.find(ipp);
        if (it == sessions_.end()) { continue; }
        auto& PSession = it->second;

        PSession->shuttingDown = 1;

        // Mirror the proper headless teardown done by cleanupSessions when a
        // parent goes missing: persist data via removeCharFromZone, drop the
        // entity, erase the session. Skipping removeCharFromZone here would
        // lose any inventory / equip / status-effect changes that happened
        // since the last periodic persist tick.
        if (auto* PChar = PSession->PChar.get())
        {
            // Push autoskill cleared to the parent so its addon caches (and the
            // AutoBots "Skill:" readout) drop this name before the entity goes
            // away. Quietly skipped when there's no parent to push to.
            if (PParent != nullptr)
            {
                PParent->pushPacket<GP_SERV_COMMAND_AUTOSKILL_STATE>(PChar->getName(), 0);
            }

            // Let the Lua AI modules clear their per-bot state tables before
            // PChar is removed — the hook runs while the entity is still valid
            // so handlers can read getID() etc.
            luautils::OnBotDespawn(PChar);

            if (PChar->PPet != nullptr && PChar->PPet->objtype == TYPE_MOB)
            {
                petutils::DespawnPet(PChar);
            }
            PChar->status = STATUS_TYPE::SHUTDOWN;
            charutils::removeCharFromZone(PChar);

            // Drop the synthetic accounts_sessions row we INSERTed in
            // createHeadlessSession. accounts_parties has ON DELETE CASCADE
            // against accounts_sessions(charid), so this also pulls the
            // party-row that AddMember inserted.
            db::preparedStmt("DELETE FROM accounts_sessions WHERE charid = ?", PChar->id);
        }
        PSession->PChar.reset();
        sessions_.erase(it);
    }
    return static_cast<uint32>(targetIpps.size());
}

auto MapSessionContainer::destroyHeadlessByCharId(uint32 headlessCharId) -> bool
{
    TracyZoneScoped;

    // Find the (single) headless session whose char IS headlessCharId. A
    // headless is identified by parentCharId != 0; real-client sessions for
    // the same charId aren't candidates (they'd have parentCharId == 0).
    IPP  targetIpp{};
    bool found = false;
    for (auto& [ipp, session] : sessions_)
    {
        if (session && session->charID == headlessCharId && session->parentCharId != 0)
        {
            targetIpp = ipp;
            found     = true;
            break;
        }
    }
    if (!found)
    {
        return false;
    }

    auto it = sessions_.find(targetIpp);
    if (it == sessions_.end())
    {
        return false;
    }
    auto& PSession         = it->second;
    PSession->shuttingDown = 1;

    // Mirror destroyHeadlessForParent's teardown: persist via removeCharFromZone
    // (so the headless's last-known inventory/equip/effects flush to DB before
    // the real-client load happens), despawn any pet, drop the entity, erase
    // the session. Note: we deliberately do NOT push AUTOSKILL_STATE here — the
    // primary owning this bot may still be online and needs that notification.
    if (MapSession* parentSession = getSessionByCharId(PSession->parentCharId))
    {
        if (parentSession->PChar)
        {
            parentSession->PChar->pushPacket<GP_SERV_COMMAND_AUTOSKILL_STATE>(
                PSession->PChar->getName(), 0);
        }
    }

    if (auto* PChar = PSession->PChar.get())
    {
        // Let the Lua AI modules clear their per-bot state tables before
        // PChar is removed.
        luautils::OnBotDespawn(PChar);

        if (PChar->PPet != nullptr && PChar->PPet->objtype == TYPE_MOB)
        {
            petutils::DespawnPet(PChar);
        }
        PChar->status = STATUS_TYPE::SHUTDOWN;
        charutils::removeCharFromZone(PChar);

        // Drop the synthetic accounts_sessions row (see createHeadlessSession
        // for the rationale). ON DELETE CASCADE on accounts_parties.charid
        // pulls the party row with it.
        db::preparedStmt("DELETE FROM accounts_sessions WHERE charid = ?", PChar->id);
    }
    PSession->PChar.reset();
    sessions_.erase(it);
    return true;
}

auto MapSessionContainer::moveHeadlessToPrimaryZone(uint32 parentCharId) -> uint32
{
    TracyZoneScoped;

    MapSession* parentSession = getSessionByCharId(parentCharId);
    if (parentSession == nullptr || parentSession->PChar == nullptr ||
        parentSession->PChar->loc.zone == nullptr)
    {
        return 0;
    }
    CCharEntity* PParent = parentSession->PChar.get();
    CZone*       newZone = PParent->loc.zone;

    // Bot-unfriendly destinations: instanced content (BCNM, Salvage, Limbus,
    // Einherjar, etc. — headless wasn't registered with the instance) and
    // Dynamis (same registration concern), plus the primary's own Mog House
    // (per-character personal space). When the destination matches, the
    // bots are intentionally stranded in their previous zone — they idle on
    // bot_ai "no nearby party member" branches and will be pulled forward
    // the next time the primary lands in a bot-friendly zone. Keeps the
    // alliance roster intact across detours like BCNM runs.
    const uint16 typeMask = static_cast<uint16>(newZone->GetTypeMask());
    constexpr uint16 kBotUnfriendlyTypeMask =
        static_cast<uint16>(ZONE_TYPE::INSTANCED) | static_cast<uint16>(ZONE_TYPE::DYNAMIS);
    if ((typeMask & kBotUnfriendlyTypeMask) != 0 || PParent->inMogHouse())
    {
        return 0;
    }

    uint32 movedCount = 0;
    for (auto& [ipp, session] : sessions_)
    {
        if (!session || session->parentCharId != parentCharId)
        {
            continue;
        }
        CCharEntity* PHeadless = session->PChar.get();
        if (PHeadless == nullptr)
        {
            continue;
        }
        if (PHeadless->loc.zone == newZone)
        {
            // Already in the right zone; just snap position so the bot ends up
            // standing next to the primary rather than wherever it was.
            PHeadless->loc.p = PParent->loc.p;
            continue;
        }

        // Minimal in-process zone hop: decrement counter on the old zone,
        // update loc, increment on the new zone. This is NOT removeCharFromZone
        // — that would PersistData, set shuttingDown, and ultimately tear the
        // session down. Headless sessions stay alive across the move so the
        // primary's bot management stays intact.
        if (PHeadless->loc.zone != nullptr)
        {
            PHeadless->loc.zone->DecreaseZoneCounter(PHeadless);
        }
        PHeadless->loc.destination = newZone->GetID();
        PHeadless->loc.p           = PParent->loc.p;
        // SINGLEPLAYER: loc.zoning field removed upstream — auto-managed now.
        newZone->IncreaseZoneCounter(PHeadless);
        // Don't normalize a dead headless: it follows the primary into the new
        // zone but stays cleanly dead (hp 0 / CDeathState) and raiseable there.
        // Forcing NORMAL here would desync the status flag from isDead() (which
        // is HP/AI-state based), risking a corpse-shown-standing render glitch
        // and tripping anything that reads status instead of isDead(). Unlike
        // the spawn path (which heals hp==0 → full), zoning does not revive.
        if (!PHeadless->isDead())
        {
            PHeadless->status = STATUS_TYPE::NORMAL;
        }

        // Keep chars.pos_zone in sync with the hop (party menu breaks otherwise).
        mapsessions::persistHeadlessPosZone(PHeadless);

        // LSB simultaneous-zone-in race: this whole function runs inside the
        // primary's 0x00A zone-in handler, so the IncreaseZoneCounter above just
        // added the bot to the primary's SpawnPCList and sent a 0x0D the client
        // drops (its entity cache is wiped for the fresh zone). SpawnPCs() then
        // skips the bot forever ("already in SpawnPCList"), leaving it invisible
        // to the primary even though it exists and acts (this is the same race
        // real clients hit when two players zone in at the same instant). Undo
        // the premature add so the next SpawnPCs() — driven by the primary's own
        // 0x015 position packet once its client is settled — re-spawns the bot
        // and it finally renders.
        PParent->SpawnPCList.erase(PHeadless->id);

        // Drain the OnZoneIn / OnGameIn packet burst — those events ran for
        // a non-existent client, the packets have nowhere to go.
        PHeadless->clearPacketList();
        ++movedCount;
    }
    return movedCount;
}

void MapSessionContainer::forEachOwnedHeadless(uint32 parentCharId, const std::function<void(CCharEntity*)>& fn)
{
    TracyZoneScoped;

    for (auto& [ipp, session] : sessions_)
    {
        if (!session || session->parentCharId != parentCharId || !session->PChar)
        {
            continue;
        }
        fn(session->PChar.get());
    }
}

auto MapSessionContainer::setBotModeForOwnedBots(uint32 parentCharId, uint8 mode) -> uint32
{
    TracyZoneScoped;
    if (mode > static_cast<uint8>(BotMode::MovementOnly))
    {
        return 0;
    }
    const auto newMode = static_cast<BotMode>(mode);
    uint32     touched = 0;
    for (auto& [ipp, session] : sessions_)
    {
        if (!session || session->parentCharId != parentCharId)
        {
            continue;
        }
        if (auto* PChar = session->PChar.get())
        {
            PChar->m_botMode = newMode;
            ++touched;
        }
    }
    return touched;
}
