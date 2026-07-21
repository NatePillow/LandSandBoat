/*
===========================================================================

  Copyright (c) 2025 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see http://www.gnu.org/licenses/

===========================================================================
*/

#pragma once

#include "common/ipp.h"
#include "map_config.h"
#include <functional>
#include <map>

class CZone;
class CCharEntity;
class Scheduler;
struct MapSession;

class MapSessionContainer
{
public:
    // SINGLEPLAYER: ctor now takes MapConfig because createHeadlessSession's
    // call to charutils::LoadChar requires it post-rebase. Upstream's LoadChar
    // signature changed to LoadChar(Scheduler&, MapConfig, uint32).
    MapSessionContainer(Scheduler& scheduler, MapConfig config);

    auto createSession(IPP ipp) -> MapSession*;
    auto createPendingSession(uint32 charId) -> MapSession*;

    // SINGLEPLAYER BEGIN
    // Build a synthetic session for a headless char owned by `parentChar`.
    // - Calls charutils::LoadChar(charId) and inserts the char into parentChar's zone.
    // - Skips accounts_sessions plumbing (real session prereq); parent's session
    //   drives watchdog cascade via parentCharId.
    // - spawnIndex staggers the periodic persist deadline to avoid simultaneous DB writes
    //   when multiple headless chars spawn in the same packet.
    // Returns the new session, or nullptr on failure (DB miss, parent zone null, etc.).
    auto createHeadlessSession(uint32 charId, CCharEntity* parentChar, uint8 spawnIndex) -> MapSession*;

    // Provision a brand-new character (rows already INSERTed by char_create) into
    // its finished starting state, WITHOUT a client login or a live zone: LoadChar
    // runs xi.player.charCreate (playtime == 0 → firstLogin), then the post-cutscene
    // stamp + persist battery + playtime bump run and the entity is released. Needs
    // this container's scheduler_/config_ for LoadChar, so it lives here rather than
    // in the char_create free-function applier. Returns false on LoadChar failure.
    auto provisionNewCharacter(uint32 charId) -> bool;
    // SINGLEPLAYER END

    auto getSessionByIPP(IPP ipp) -> MapSession*;
    auto getSessionByIPP(uint64 ipp) -> MapSession*;
    auto getSessionByChar(CCharEntity* PChar) -> MapSession*;
    auto getSessionByCharId(uint32 charId) -> MapSession*;
    auto getPendingSessionByCharId(uint32 charId) -> MapSession*;
    auto getSessionByAccountId(uint32 accountId) -> MapSession*;
    auto getSessionByCharName(const std::string& name) -> MapSession*;

    void cleanupSessions(IPP mapIPP);

    void destroySession(IPP ipp);
    void destroySession(MapSession* map_session_data);
    void destroyPendingSession(MapSession* map_session_data);
    void destroyPendingSession(uint32 charId);

    // SINGLEPLAYER BEGIN
    // Despawn every active headless session whose parentCharId matches.
    // Returns the number of sessions destroyed (for logging).
    auto destroyHeadlessForParent(uint32 parentCharId) -> uint32;

    // Despawn the single headless session whose charID matches (i.e. the bot
    // *is* this char). Used by the 0x0A login handler to evict a stale
    // headless when a real client tries to log in as a char that's currently
    // spawned as someone's bot — the real client takes precedence.
    // Returns true if a matching headless was found and destroyed.
    auto destroyHeadlessByCharId(uint32 headlessCharId) -> bool;

    // Move every headless session owned by parentCharId into the parent's
    // current zone (snapping their position to the parent's). Called from
    // the 0x0A login handler after the parent has been placed in their new
    // zone — without this, bots get stranded in the previous zone when the
    // primary zones. Headless sessions stay alive across the move (this is
    // NOT removeCharFromZone — that's the persist/shutdown path).
    // Returns the number of headless sessions actually moved.
    auto moveHeadlessToPrimaryZone(uint32 parentCharId) -> uint32;

    // Yield every active headless session whose parentCharId matches to the
    // callback. Callback receives the session's PChar. Used by handlers that
    // need to apply a per-bot mutation that doesn't fit the existing
    // domain-specific helpers (e.g. SPAWN_DEAD revival).
    void forEachOwnedHeadless(uint32 parentCharId, const std::function<void(CCharEntity*)>& fn);

    // Set m_botMode on every active headless session whose parentCharId
    // matches. Used by AUTOBOTS SET_ALLIANCE_MODE to flip every owned bot
    // between idle (Off) and acting (Full) without despawning. Returns the
    // number of sessions whose mode was updated.
    auto setBotModeForOwnedBots(uint32 parentCharId, uint8 mode) -> uint32;
    // SINGLEPLAYER END

private:
    Scheduler&                                    scheduler_;
    MapConfig                                     config_;           // SINGLEPLAYER: used by createHeadlessSession's LoadChar call.
    std::map<IPP, std::unique_ptr<MapSession>>    sessions_;         // Confirmed sessions mapped by IP
    std::map<uint32, std::unique_ptr<MapSession>> pending_sessions_; // Pending sessions notified via IPC that a character may be arriving
};

// Global accessor for the active MapSessionContainer. Initialized by MapNetworking's
// constructor; used by packet handlers that need cross-session operations
// (e.g., 0x175 spawn_headless) without taking a MapNetworking dependency. Mirrors
// the existing ipc_client global-accessor pattern.
namespace mapsessions
{
    void init(MapSessionContainer* container);
    auto get() -> MapSessionContainer&;

    // SINGLEPLAYER: persist a headless bot's current live zone into
    // chars.pos_zone. Headless zone in-process (Decrease/IncreaseZoneCounter,
    // never SendToZone) and SaveCharPosition writes x/y/z but NOT pos_zone, so
    // the column would otherwise stay frozen at the char's last real-login zone.
    // The search server's party-list query (GetPartyList) and the map's 0x0C8
    // GROUP_TBL both read pos_zone for "where is each member", so the vanilla
    // Party menu shows a stale zone without this. Call it after EVERY headless
    // zone hop — there are several (spawn, follow-primary, instance pull,
    // revive-here) and they must not drift. No-op on null / zone-unset.
    void persistHeadlessPosZone(CCharEntity* PBot);
} // namespace mapsessions
