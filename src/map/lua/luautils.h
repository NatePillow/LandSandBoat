/*
===========================================================================

  Copyright (c) 2010-2015 Darkstar Dev Teams

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

#ifndef _LUAUTILS_H
#define _LUAUTILS_H

#include <common/cbasetypes.h>
#include <common/types/maybe.h>

#include <string>
#include <vector>

#include "common/lua.h"
extern sol::state lua;

// Sol compilation definitions are in the base CMakeLists file
// SOL_ALL_SAFETIES_ON = 1
// SOL_NO_CHECK_NUMBER_PRECISION = 1
#include "sol/sol.hpp"
#include "sol_bindings.h"

#include "common/xi.h"

#include "attack.h"
#include "items/item_equipment.h"
#include "spell.h"

#include "lua_ability.h"
#include "lua_action.h"
#include "lua_attack.h"
#include "lua_baseentity.h"
#include "lua_battlefield.h"
#include "lua_instance.h"
#include "lua_item.h"
#include "lua_mobskill.h"
#include "lua_petskill.h"
#include "lua_spell.h"
#include "lua_statuseffect.h"
#include "lua_trade_container.h"
#include "lua_trigger_area.h"
#include "lua_zone.h"

enum class SendToDBoxReturnCode : uint8
{
    SUCCESS                       = 0,
    SUCCESS_LIMITED_TO_STACK_SIZE = 1,
    PLAYER_NOT_FOUND              = 2,
    ITEM_NOT_FOUND                = 3,
    QUERY_ERROR                   = 4
};

class CAbility;
class CSpell;
class CBaseEntity;
class CBattleEntity;
class CAutomatonEntity;
class CPetEntity;
class CCharEntity;
class CBattlefield;
class CItem;
class CInstance;
class CMobSkill;
class CPetSkill;
class ITriggerArea;
class CStatusEffect;
class CTradeContainer;
class CItemPuppet;
class CItemWeapon;
class CItemEquipment;
class CItemFurnishing;
class CInstance;
class CWeaponSkill;
class CZone;
class CZoneInstance;

class CLuaAbility;
class CLuaAction;
class CLuaBaseEntity;
class CLuaBattlefield;
class CLuaInstance;
class CLuaItem;
class CLuaMobSkill;
class CLuaPetSkill;
class CLuaTriggerArea;
class CLuaSpell;
class CLuaStatusEffect;
class CLuaTradeContainer;
class CLuaZone;

struct action_t;
struct action_target_t;
struct action_result_t;

enum ConquestUpdate : uint8;
enum class Emote : uint8;

namespace luautils
{
namespace detail
{

// TODO:
// Instead of always taking a string of the form "xi.server.onTimeServerTick"
// and splitting it into parts, then using those parts to walk up the Lua
// global table, we can build a map of that string to the underlying sol::reference.
//
// This however comes with the cost of maintaining this map, and those sol::references
// keep the underlying objects alive, so we need to be careful about what we cache.

// auto findCachedObject(const std::string& objName) -> sol::reference;
// void cacheObject(const std::string& objName, sol::reference obj);
auto findGlobalLuaFunction(const std::string& funcName) -> sol::function;

} // namespace detail

void init(IPP mapIPP, bool isRunningInCI);
void garbageCollectStep();
void garbageCollectFull();
void cleanup();

// Find and call a global function in Lua from C++.
//
// If the function is not found or an error occurs, an error message is printed to the console.
//
// Examples:
//
// ```cpp
// luautils::callGlobal<void>("xi.server.onTimeServerTick");
// luautils::callGlobal<void>("xi.player.onPlayerDeath", PChar);
// auto value = callGlobal<uint32>("xi.server.functionThatReturnsANumber");
// ```
//
// NOTE: This is slower (but safet) than looking up something manually like this:
//     : lua["xi"]["server"]["onTimeServerTick"]();
template <typename T, typename... Targs>
auto callGlobal(const std::string& funcName, Targs... args)
{
    auto func = detail::findGlobalLuaFunction(funcName);
    if (!func.valid())
    {
        ShowError("luautils::callGlobalFunction: %s: Function not found", funcName);
        if constexpr (std::is_void_v<T>)
        {
            return;
        }
        else
        {
            return T{};
        }
    }

    const auto result = func(std::forward<Targs>(args)...);
    if (!result.valid())
    {
        sol::error err = result;
        ShowError("luautils::callGlobalFunction: %s: %s", funcName, err.what());
        if constexpr (std::is_void_v<T>)
        {
            return;
        }
        else
        {
            return T{};
        }
    }

    if constexpr (std::is_void_v<T>)
    {
        return;
    }
    else
    {
        auto returnObject = result.template get<sol::object>();
        if (returnObject.template is<T>())
        {
            return returnObject.template as<T>();
        }
        else
        {
            ShowError("luautils::callGlobalFunction: %s: Invalid return type", funcName);
            return T{};
        }
    }
}

void TryReloadFilewatchList();

auto GetContainerFilenamesList() -> std::vector<std::string>;

// Cache helpers
auto getEntityCachedFunction(CBaseEntity* PEntity, std::string funcName) -> sol::function;
void CacheLuaObjectFromFile(const std::string& filename, bool overwriteCurrentEntry = false);
auto GetCacheEntryFromFilename(const std::string& filename) -> sol::table;
void OnEntityLoad(CBaseEntity* PEntity);

void LoadExpDifficultyCurves(const sol::table& expToDifficultyTable, const uint8 incrediblyEasyPreyLevel, const uint16 incrediblyEasyPreyMinExp);

void PopulateIDLookupsByFilename(Maybe<std::string> maybeFilename = std::nullopt);
void PopulateIDLookupsByZone(Maybe<uint16> maybeZoneId = std::nullopt);

void SendEntityVisualPacket(uint32 npcId, const char* command);
void InitInteractionGlobal();
auto GetZone(uint16 zoneId) -> CZone*;
auto GetItemByID(uint32 itemId) -> const CItem*;
auto GetItemFlagsByID(uint32 itemId) -> ItemFlag;
auto GetItemLevelRequirementsByID(uint32 itemId) -> uint8;
auto GetNPCByID(uint32 npcid, const sol::object& instanceObj) -> CBaseEntity*;
auto GetMobByID(uint32 mobid, const sol::object& instanceObj) -> CBaseEntity*;
auto GetEntityByID(uint32 mobid, const sol::object& instanceObj, const sol::object& arg3) -> CBaseEntity*;

// Resolves a weapon-skill English name to its ID from the loaded WS list.
// Returns 0 if not found. (GetItemIDByName already exists elsewhere with a
// DB-backed implementation — reuse that.)
uint16      GetWeaponskillByName(const std::string& name);
std::string GetWeaponskillNameByID(uint16 id);

// Returns { primary, secondary, tertiary } SC properties for a WS ID, or nil
// if the ID is unknown. Used to decode the engine's EFFECT_SKILLCHAIN power
// bits (primary | secondary<<4 | tertiary<<8) against a configured opener WS
// so callers can answer "is the pending SC ours?" without a Lua-side action
// listener.
auto GetWeaponskillProperties(uint16 id) -> sol::table;

// Returns a Lua table { id, name, element, skill, mpcost } for a spell ID, or
// nil if the ID is unknown. Used by bot_equip's build_spell_info for ad_name
// / ad_element / ad_skill XML conditions.
auto GetSpellMetaByID(uint16 spellId) -> sol::table;

void  WeekUpdateConquest(uint8 updateType);
uint8 GetRegionOwner(uint8 type);
uint8 GetRegionInfluence(uint8 type); // Return influence graphics
uint8 GetNationRank(uint8 nation);
uint8 GetConquestBalance();
bool  IsConquestAlliance();
void  SetRegionalConquestOverseers(uint8 regionID); // Update NPC Conquest Guard
void  SendLuaFuncStringToZone(uint16 requestingZoneId, uint16 executorZoneId, const std::string& str);

void UpdateSanrakusMobs(); // Update sanraku's (ZNM) subject of interest and recommended fauna
void ZNMPopPriceDecay();   // Price of ZNM pop items decay over time

auto GetReadOnlyItem(uint32 id) -> const CItem*; // Returns a read only lookup item object of the specified ID
auto GetAbility(uint16 id) -> CAbility*;
auto GetSpell(uint16 id) -> CSpell*;

auto SpawnMob(uint32 mobid, const sol::object& arg2, const sol::object& arg3) -> CBaseEntity*; // Spawn Mob By Mob Id - NMs, BCNM...
void DespawnMob(uint32 mobid, const sol::object& arg2);                                        // Despawn (Fade Out) Mob By Id
auto GetPlayerByName(const std::string& name) -> CBaseEntity*;
auto GetPlayerByID(uint32 pid) -> CBaseEntity*;
bool PlayerHasValidSession(uint32 playerId);
void SendToJailOffline(uint32 playerId, int8 cellId, float posX, float posY, float posZ, uint8 rot);
void DrawIn(CLuaBaseEntity* PLuaBaseEntity, const sol::table& table, float offset, float degrees);

uint32 GetSystemTime();
uint32 JstMidnight();

auto LoadLinkshellConciergeSlots(uint16 zoneId) -> sol::table;
void SetLinkshellConciergeSlot(uint16 zoneId, uint8 slotIndex, const sol::table& data);
void DeleteLinkshellConciergeSlot(uint16 zoneId, uint8 slotIndex);
void DecrementLinkshellConciergeMembersGoal(uint16 zoneId, uint32 linkshellid);

uint32 JstDayOfTheYear();
uint32 JstDayOfTheMonth();
uint32 JstDayOfTheWeek();
int32  JstYear();
uint32 JstMonth();
uint32 JstHour();

uint32 NextGameTime(uint32 intervalSeconds);
uint32 NextJstWeek();

uint32 VanadielTime();
uint8  VanadielTOTD();
uint32 VanadielHour();
uint32 VanadielMinute();
uint32 VanadielDayOfTheYear();  // Gets Integer Value for Day of the Year (Jan 01 = Day 1)
uint32 VanadielDayOfTheMonth(); // Gets day of the month (Feb 6 = Day 6)
uint32 VanadielDayOfTheWeek();  // Gets day of the week (Fire Earth Water Wind Ice Lightning Light Dark)
uint32 VanadielYear();
uint32 VanadielMonth();
uint32 VanadielUniqueDay();  // Gets the unique day number. (Vanadiel year * 360 + VanadielDayOfTheYear)
uint8  VanadielDayElement(); // Gets element of the day (1: Fire  2: Ice  3: Wind  4: Earth  5: Lightning  6: Water  7: Light  8: Dark)
uint32 VanadielMoonPhase();
uint8  VanadielMoonDirection();
uint8  VanadielRSERace();
uint8  VanadielRSELocation();
void   SetTimeOffset(int32 offset); // Manipulate earth time forward or backward by offset seconds. Affects Vana'Diel time.
void   StartElevator(uint32 ElevatorID);
int16  GetElevatorState(uint8 id); // Returns -1 if elevator is not found. Otherwise, returns the uint8 state.

int32 GetServerVariable(const std::string& name);
void  SetServerVariable(const std::string& name, int32 value, const sol::object& expiry);
int32 GetVolatileServerVariable(const std::string& varName);
void  SetVolatileServerVariable(const std::string& varName, int32 value, const sol::object& expiry);
int32 GetCharVar(uint32 charId, const std::string& varName);                                         // Get player var directly from SQL DB
void  SetCharVar(uint32 charId, const std::string& varName, int32 value, const sol::object& expiry); // Set player var in SQL DB using charId
void  ClearCharVarFromAll(const std::string& varName);                                               // Deletes a specific player variable from all players
void  Terminate();                                                                                   // Logs off all characters and terminates the server

int32 GetTextIDVariable(uint16 ZoneID, const char* variable); // Load the value of the TextID variable of the specified zone
bool  IsContentEnabled(const std::string& content);

void OnGameDay(CZone* PZone);
void OnGameHour(CZone* PZone);
void OnZoneWeatherChange(uint16 zoneId, Weather weather);
void OnTOTDChange(uint16 ZoneID, uint8 TOTD);

void OnGameIn(CCharEntity* PChar, bool zoning);
void OnZoneIn(CCharEntity* PChar);
void OnZoneOut(CCharEntity* PChar);
void AfterZoneIn(CBaseEntity* PChar);
void OnZoneInitialize(uint16 ZoneID);
void OnZoneTick(CZone* PZone);

// SINGLEPLAYER BEGIN
// Per-char bot AI tick. Fires from CCharEntity::PostTick when m_botMode != Off.
// botMode is the BotMode enum value as uint8 (1 = CombatOnly, 2 = Full).
void OnBotTick(CCharEntity* PChar, timer::time_point tick, uint8 botMode);

// Command dispatch from the 0x176 packet handler into the bot_ai Lua module.
// `command` is a short uppercase identifier (e.g., "ATTACK", "DISENGAGE").
// `arg` carries an opcode-specific numeric payload (target ID, etc.).
void OnBotCommand(CCharEntity* PMain, const std::string& command, uint32 arg);
void OnBotFinish(CCharEntity* PMain);
void OnBotSummonTrusts(CCharEntity* PMain);
void OnBotSetHealMode(CCharEntity* PMain, bool on, const std::string& botName);
void OnBotSetAddControlMode(CCharEntity* PMain, const std::string& botName, uint8 mode);
void OnBotSetStunMode(CCharEntity* PMain, uint8 mode);
void OnBotSetMultiEngageMode(CCharEntity* PMain, uint8 mode);
void OnBotSetPullerPaused(CCharEntity* PMain, uint8 paused);
// Per-bot THF utility-RA cadence in seconds. 0 = Off (no RA throws).
// Driven by the Status tab combo on THF cards.
void OnBotSetThfRaDelay(CCharEntity* PMain, const std::string& botName, uint8 delaySec);
// OnBotSetNmMode retired — `is_nm` is now always engine-autodetect.
// Role AI policy — alliance-wide per-role item-usage settings driven by the
// Role AI tab. role: 0=tank/1=melee/2=heal/3=rdm/4=nuke,
// type: 0=hp/1=mp/2=status, mode: 0=off/1=nm-only/2=always.
void OnRoleAiSetMode(CCharEntity* PMain, uint8 role, uint8 type, uint8 mode);
// Per-status checkbox under each role's Status section. statusKey is the
// canonical index into role_policy.STATUS_LIST (Lua-side).
void OnRoleAiSetStatusFlag(CCharEntity* PMain, uint8 role, uint8 statusKey, bool on);
void OnBotFireAllWs(CCharEntity* PMain);
void OnBotSetScThreshold(CCharEntity* PMain, uint8 which, uint8 value);
// Per-bot SA/TA scheduling mode. 0=Combined (current behavior — SA→TA→WS in
// one combo), 1=Split (alternate SA and TA across WSes so both fire over the
// 60s recast). Lua-side validates that botName belongs to PMain.
void OnBotSetSataMode(CCharEntity* PMain, const std::string& botName, uint8 mode);
void OnBotSetCasualNukeRotation(CCharEntity* PMain, const std::string& botName, uint8 value);
void OnBotSetCasualNukeMbMode(CCharEntity* PMain, const std::string& botName, uint8 mode);
// Nudge a bot ±1y along the vector toward its currently engaged target.
// direction: 0=forward (toward), 1=backward (away). Lua-side validates
// ownership + engagement; silent no-op otherwise.
void OnBotTankNudge(CCharEntity* PMain, const std::string& botName, uint8 direction);
// Snap a bot to the primary's current xyz. Used to recover a stuck tank
// or pass aggro at the primary's feet. Lua-side validates ownership;
// silent no-op otherwise.
void OnBotTankWalkToMe(CCharEntity* PMain, const std::string& botName);
// Set the alliance puller. Empty botName clears the selection. Lua-side
// validates that the bot belongs to PMain.
void OnBotSetPuller(CCharEntity* PMain, const std::string& botName);
// Set the puller's scan range (yalms from camp anchor). Server clamps to [5, 255].
void OnBotSetPullerRange(CCharEntity* PMain, uint8 rangeYalms);
// Set the puller's con range (min..max). 0=TW, 1=EP, 2=DC, 3=EM, 4=T, 5=VT, 6=IT.
void OnBotSetPullerConRange(CCharEntity* PMain, uint8 minCon, uint8 maxCon);
void OnBotSetPullerResumeMpp(CCharEntity* PMain, uint8 mpp);
// Request the list of unique mob names within 255y of the alliance camp anchor.
// Server scans, sorts by count, pushes S2C 0x1A3 PULLER_NEARBY_NAMES back.
void OnBotRequestPullerNames(CCharEntity* PMain);
// Apply the user's selected name filter for the puller. Empty list clears it.
void OnBotSetPullerNameFilter(CCharEntity* PMain, const std::vector<std::string>& names);
// Grant SIGNET to the primary + every owned headless. Each member's own
// nation/rank drives their individual duration formula (matches the gate-
// guard overseer path in scripts/globals/conquest.lua). Also strips any
// competing INFLUENCE-flagged effects (sigil/sanction) on each member first.
void OnBotGiveSignet(CCharEntity* PMain);
// Per-bot role_heal scope. 0=party (default — heal own party only),
// 1=allianceAssist (party + BLM-tier fallback on alliance), 2=allianceMain
// (WHM-tier cures + single-target -na widened to alliance). Lua-side
// validates botName belongs to PMain.
void OnBotSetHealScope(CCharEntity* PMain, const std::string& botName, uint8 mode);
// Alliance-wide headless aggro mode. 0=Off (trust-like, mobs ignore
// headless), 1=Full (mobs aggro headless like real players), 2=Engaged
// (invisible until the headless has a battle target, then vanilla rules).
// Replaces the old static singleplayer.HEADLESS_MOB_AGGRO setting. Lua
// dispatcher writes alliance.aggroMode and cascades each owned headless's
// m_aggroMode via the setAggroMode binding so the C++ aggro hot path
// stays branch-free.
void OnBotSetAggroMode(CCharEntity* PMain, uint8 mode);
// Primary issues a one-shot action command at a specific headless. Dispatched
// to xi.singleplayer.bots.ai_command.dispatch which validates ownership, queues
// the command on the bot's per-bot pendingCommand slot, and lets the next AI
// tick fire it. Acks come back as printToPlayer chat messages.
void OnBotIssueCommand(CCharEntity* PMain, const std::string& botName,
                       const std::string& actionKind, const std::string& actionName,
                       uint32 targetId);
void OnBotScPause(CCharEntity* PMain, uint8 scId, bool paused);

// 0x176 SYNC_QUESTS / SYNC_MISSIONS entry points (#178 — account-wide cascade).
// Collect every linked headless owned by PMain, hand the list to the Lua
// xi.singleplayer.bots.bots_progression_cascade.sync_quests / sync_missions function, then push an S2C 0x1A3
// SYNC_ACK back to PMain with the count so the addon UI can clear its
// "in-flight" guard. Kind bits in the ACK: 0 = quests, 1 = missions.
void OnBotSyncQuests(CCharEntity* PMain);
void OnBotSyncMissions(CCharEntity* PMain);
// Cascade primary's teleport bitfields (all TELEPORT_TYPE values) onto each
// owned headless. Mirrors the quest/mission sync hooks; replies with S2C
// 0x1A3 SYNC_ACK kind=2.
void OnBotSyncTeleports(CCharEntity* PMain);
// Per-bot BRD song-roster override. slot0..slot3 are uint16 spell IDs in
// the order: front_minuet, front_madrigal, back_ballad_a, back_ballad_b.
// 0 = "auto" sentinel (role_brd falls through to best_tier for that slot).
void OnBotSetBrdSongRoster(CCharEntity* PMain, const std::string& botName,
                           uint16 slot0, uint16 slot1, uint16 slot2, uint16 slot3);

// Per-bot SMN avatar dropdown selection. avatarSpellId is the summon spell
// the bot auto-resummons after release / death. 0 = "auto" sentinel
// (role_smn falls back to Carbuncle).
void OnBotSetSmnAvatar(CCharEntity* PMain, const std::string& botName, uint16 avatarSpellId);

// 0x191 SET_AUTOSKILL entry point. Routes to xi.singleplayer.bots.skillup.set_skillup_for_bot
// which writes the runtime override table and starts/stops the skill-up loop
// on the named bot. Authorized iff target is the requester or a headless owned
// by them — checked in Lua against PSession->parentCharId.
void OnSetAutoskill(CCharEntity* PMain, const std::string& botName, uint8 mode, const std::vector<uint16>& spellIds);

// 0x193 LIST_AUTOSKILL entry point. Walks every active xi.singleplayer.bots.skillup override
// owned by the requester and fires a 0x192 AUTOSKILL_STATE for each so the
// addon can populate its UI cache on load.
void OnListAutoskill(CCharEntity* PMain);

// Role assignment for a specific char (0x176 SET_ROLE).
void OnBotSetRole(CCharEntity* PBot, uint8 role);

// 0x176 SET_FORMATION subcommand entry point. Kind: 0 = battle, 1 = walking.
// Name: formation identifier (e.g. "default", "camp", "column", "role").
// Applies to the primary's xi.singleplayer.bots.primary[charId] state; trickles down to
// every bot via xi.singleplayer.bots.ai_formation during their movement tick.
void OnBotSetFormation(CCharEntity* PPrimary, uint8 kind, const std::string& name);

// 0x175 spawn entry point. Resolves to xi.singleplayer.bots.bots_spawn_from_config(player, configName)
// on the Lua side, which reads singleplayer/config/alliance/<name>.json
// and drives synthetic session creation, party formation, and trust queuing.
void OnBotSpawnFromConfig(CCharEntity* PChar, const std::string& configName);
// 0x176 UPDATE_CONFIG entry point. Routes to the diff-based update
// (bots_spawn.update_alliance_diff) which computes the partition against
// the running alliance and applies the minimum mutation. Falls back to a
// full despawn+respawn internally for cases the diff can't handle.
void OnBotUpdateAllianceConfig(CCharEntity* PChar, const std::string& configName);

// Fired right before a headless bot is torn down (destroyHeadlessForParent /
// destroyHeadlessByCharId), while PChar is still valid. Lets the Lua AI
// modules wipe per-bot state tables so they don't leak across spawn/despawn.
void OnBotDespawn(CCharEntity* PChar);

// 0x17d use-food entry point. Resolves to xi.singleplayer.bots.item.use_food_from_config
// which reads singleplayer/config/food/<name>.json (char-name → food
// item name) and fires bot:useItem on each linked headless.
void OnUseFoodFromConfig(CCharEntity* PChar, const std::string& configName);
// AutoLot group assignment from the primary char's addon. Runtime state only —
// applies on the live entity (primary or owned headless); silently no-ops if
// charName isn't currently a spawned PC. See ai_lot.set_assignment_for_char.
void OnSetLotAssignment(CCharEntity* PMain, const std::string& charName, const std::string& groupName, bool on);

// Lua-callable: fetch a config file body + its mtime from the server's
// in-memory cache. Returns (body: string|nil, mtime: int). Consumers that
// cache parsed/derived state alongside the raw body use the mtime as a
// freshness key — store the mtime when caching, compare on each lookup,
// re-derive when mtime advances. The watcher poll keeps the cache fresh
// against external edits within ~2 s; addon CRUD writes through the
// loopback HTTP config server (config_http_server.cpp) update the cache
// atomically via configcache::putAndPersist before the response returns.
auto GetServerConfig(const std::string& category, const std::string& name) -> std::tuple<sol::object, int64_t>;

// 0x176 AUTOLOT namespace entry points. The addon's Lot List action edits a
// per-(primary, item_id) → set-of-bots structure inside xi.singleplayer.bots.ai_lot. Each
// listed bot will lot drops of itemId until they have one in inventory.
void OnLotListAdd(CCharEntity* PChar, uint32 itemId, const std::string& botName);
void OnLotListRemove(CCharEntity* PChar, uint32 itemId, const std::string& botName);
void OnLotListClear(CCharEntity* PChar, uint32 itemId);

// Universal action-result hook. Fires once per finalized action_t (regardless
// of category: melee/WS/magic/JA/ranged/mob_skill/etc.) from the BATTLE2 packet
// ctor. Routes to xi.singleplayer.bots.onActionResult on the Lua side with the actor entity
// and a flattened table of the action's targets / results so bot_dps and
// future damage-side consumers can categorize without scattered PAI listeners.
// (action_t is already fwd-declared in global namespace above.)
void OnActionResult(const action_t& action);

// Fires from CMobSkillState constructor at the start of a mob TP move windup.
// Provides the actual cast time so Lua-side bot AI (ai_magic.lua) can set its
// stun/bash interrupt windows to the precise mob WS duration instead of a
// conservative constant. Called BEFORE damage resolution; listeners get the
// full windup to react.
void OnMobSkillStart(CBaseEntity* PActor, timer::duration castTime);

// Server → primary client packet helpers used by the bot_ai Lua module.
// `BotPushLog` corresponds to the 0x179 LOG_MESSAGE event — bot AI chatter that
// should render in the addon's autoutil.log on the client, not the server log.
// `BotPushState` corresponds to the 0x178 state update (per-bot HP/MP/role/target).
// Both target the primary char's queue so the addon displays them.
// First arg is the Lua-side CLuaBaseEntity wrapper (sol2 can't auto-marshal
// it across to CCharEntity*); the impl downcasts inside.
void BotPushLog(CLuaBaseEntity* PLuaPrimary, const std::string& tag, const std::string& msg);
void BotPushState(CLuaBaseEntity* PLuaPrimary, uint8 stateType, sol::table payload);

// 0x17C per-bot DPS push. categories is a Lua table list of 6 entries, each
// shaped { damage = u32, hits = u16, misses = u16 } in the canonical order
// {melee, ranged, ws, magic, burst, ja}. Missing entries default to zeros.
void BotPushDps(CLuaBaseEntity* PLuaPrimary, uint32 botCharId, bool isFinal, uint32 totalDamage, uint32 activeMs, sol::table categories);

// 0x191 per-party status push (autostatus.lua, ~5s cadence). `partyNumber` is
// 1..3 (party slot inside the alliance). `members` is a Lua list whose entries
// are { charId = u32, effects = { effectId, effectId, ... } }. Effects are
// silently truncated at GP_SERV_COMMAND_PARTY_STATUS::kMaxEffectsPerBot.
void PushPartyStatus(CLuaBaseEntity* PLuaPrimary, uint8 partyNumber, sol::table members);
// SINGLEPLAYER END

void OnTriggerAreaEnter(CCharEntity* PChar, const std::unique_ptr<ITriggerArea>& PTriggerArea); // when player enters a trigger area in a zone
void OnTriggerAreaLeave(CCharEntity* PChar, const std::unique_ptr<ITriggerArea>& PTriggerArea); // when player leaves a trigger area in a zone

void OnTransportEvent(CCharEntity* PChar, uint16 prevZoneId, uint16 transportId);
void OnTimeTrigger(CNpcEntity* PNpc, uint8 triggerID);
void OnConquestUpdate(CZone* PZone, ConquestUpdate type, uint8 influence, uint8 owner, uint8 ranking, bool isConquestAlliance); // conquest update (hourly or tally)

void OnServerStart();
void OnJSTMidnight();
void OnTimeServerTick();

int32 OnTrigger(CCharEntity* PChar, CBaseEntity* PNpc);
int32 OnEventUpdate(CCharEntity* PChar, uint16 eventID, uint32 result);   // triggered when game triggers event update during cutscene
int32 OnEventUpdate(CCharEntity* PChar, const std::string& updateString); // triggered when game triggers event update during cutscene
int32 OnEventFinish(CCharEntity* PChar, uint16 eventID, uint32 result);
void  OnTrade(CCharEntity* PChar, CBaseEntity* PNpc);

void OnNpcSpawn(CBaseEntity* PNpc); // triggers when a patrol npc spawns

void OnEffectGain(CBattleEntity* PEntity, CStatusEffect* StatusEffect);
void OnEffectTick(CBattleEntity* PEntity, CStatusEffect* StatusEffect);
void OnEffectLose(CBattleEntity* PEntity, CStatusEffect* StatusEffect);

void OnAttachmentEquip(CBattleEntity* PEntity, const CItemPuppet* attachment);
void OnAttachmentUnequip(CBattleEntity* PEntity, const CItemPuppet* attachment);
void OnManeuverGain(CBattleEntity* PEntity, const CItemPuppet* attachment, uint8 maneuvers);
void OnManeuverLose(CBattleEntity* PEntity, const CItemPuppet* attachment, uint8 maneuvers);
void OnUpdateAttachment(CBattleEntity* PEntity, const CItemPuppet* attachment, uint8 maneuvers);

int32 OnItemUse(CBaseEntity* PUser, CBaseEntity* PTarget, CItem* PItem, action_t& action);
auto  OnItemCheck(CBaseEntity* PTarget, CItem* PItem, CBaseEntity* PCaster = nullptr) -> std::tuple<int32, int32, int32>;
void  OnItemDrop(CBaseEntity* PUser, CItem* PItem, IsRecycleBin recycleBin = IsRecycleBin::No);
void  OnItemEquip(CBaseEntity* PUser, CItem* PItem);
void  OnItemUnequip(CBaseEntity* PUser, CItem* PItem);
void  CheckForGearSet(CBaseEntity* PTarget);

int32 OnMagicCastingCheck(CBaseEntity* PChar, CBaseEntity* PTarget, CSpell* PSpell);
int32 OnSpellCast(CBattleEntity* PCaster, CBattleEntity* PTarget, CSpell* PSpell);
void  OnSpellPrecast(CBattleEntity* PCaster, CSpell* PSpell);
void  OnSpellCastStart(CBattleEntity* PCaster, CBattleEntity* PTarget, CSpell* PSpell);
void  OnSpellInterrupted(CBattleEntity* PCaster, CSpell* PSpell);
auto  OnMobSpellChoose(CBattleEntity* PCaster, CBattleEntity* PTarget, Maybe<SpellID> startingSpellId) -> std::tuple<Maybe<SpellID>, Maybe<CBattleEntity*>>;
void  OnMagicHit(CBattleEntity* PCaster, CBattleEntity* PTarget, CSpell* PSpell);
void  OnWeaponskillHit(CBattleEntity* PMob, CBaseEntity* PAttacker, uint16 PWeaponskill);
bool  OnTrustSpellCastCheckBattlefieldTrusts(CBattleEntity* PCaster); // Triggered if spell is a trust spell during onCast to determine to interrupt spell or not

void OnMobInitialize(CBaseEntity* PMob);
void ApplyMixins(CBaseEntity* PMob);
void ApplyZoneMixins(CBaseEntity* PMob);
auto OnMobSpawnCheck(CBaseEntity* PMob) -> int32;
void OnMobSpawn(CBaseEntity* PMob);
void OnMobRoamAction(CBaseEntity* PMob); // triggers when event mob is ready for a custom roam action
void OnMobRoam(CBaseEntity* PMob);
void OnMobEngage(CBaseEntity* PMob, CBaseEntity* PTarget);
void OnMobDisengage(CBaseEntity* PMob);
void OnMobFollow(CBaseEntity* PMob, CBaseEntity* PTarget);
void OnMobUnfollow(CBaseEntity* PMob, CBaseEntity* PTarget);
void OnMobFight(CBaseEntity* PMob, CBaseEntity* PTarget);
void OnCriticalHit(CBattleEntity* PMob, CBattleEntity* PAttacker);
void OnMobDeath(CBaseEntity* PMob, CBaseEntity* PKiller);
void OnMobDespawn(CBaseEntity* PMob);

void OnPlayerAbilityUse(CBaseEntity* PMob, CBaseEntity* PPlayer, CAbility* PAbility); // when a player uses an ability and mob is in notoriety container

void OnPetLevelRestriction(CBaseEntity* PMob);

void OnPath(CBaseEntity* PEntity);
void OnPathPoint(CBaseEntity* PEntity);
void OnPathComplete(CBaseEntity* PEntity);

int32 OnBattlefieldHandlerInitialize(CZone* PZone);
void  OnBattlefieldInitialize(CBattlefield* PBattlefield); // what to do when initialising battlefield, battlefield:setLocalVar("lootId") here for any which have loot
void  OnBattlefieldTick(CBattlefield* PBattlefield);
void  OnBattlefieldStatusChange(CBattlefield* PBattlefield);

void OnBattlefieldEnter(CCharEntity* PChar, CBattlefield* PBattlefield);
void OnBattlefieldLeave(CCharEntity* PChar, CBattlefield* PBattlefield, uint8 LeaveCode); // see battlefield.h BATTLEFIELD_LEAVE_CODE
void OnBattlefieldKick(CCharEntity* PChar);

void OnBattlefieldRegister(CCharEntity* PChar, CBattlefield* PBattlefield);
void OnBattlefieldDestroy(CBattlefield* PBattlefield);

uint16 OnMobMobskillChoose(CBattleEntity* PMob, CBattleEntity* PTarget, uint16 chosenSkillId);
int32  OnMobWeaponSkill(CBaseEntity* PMob, CBaseEntity* PTarget, CMobSkill* PMobSkill, action_t* action);
int32  OnMobSkillCheck(CBaseEntity* PChar, CBaseEntity* PMob, CMobSkill* PMobSkill); // triggers before mob weapon skill is used, returns 0 if the move is valid
auto   OnMobSkillTarget(CBattleEntity* PTarget, CBaseEntity* PMob, CMobSkill* PMobSkill) -> CBattleEntity*;
auto   OnMobSkillReadyTime(CBattleEntity* PTarget, CBaseEntity* PMob, CMobSkill* PMobSkill) -> Maybe<timer::duration>;
void   OnMobSkillFinalize(CBaseEntity* PMob, CMobSkill* PMobSkill); // triggers when mob skill state cleanup runs
int32  OnAutomatonAbilityCheck(CBaseEntity* PChar, CAutomatonEntity* PAutomaton, CMobSkill* PMobSkill);
int32  OnAutomatonAbility(CBaseEntity* PTarget, CBaseEntity* PMob, CMobSkill* PMobSkill, CBaseEntity* PMobMaster, action_t* action);

auto GetMonstrosityLuaTable(CCharEntity* PChar) -> sol::table;
void SetMonstrosityLuaTable(CCharEntity* PChar, sol::table data);
void OnMonstrosityUpdate(CCharEntity* PChar);
void OnMonstrosityReturnToEntrance(CCharEntity* PChar);

int32 OnAbilityCheck(CBaseEntity* PChar, CBaseEntity* PTarget, CAbility* PAbility, CBaseEntity** PMsgTarget);
int32 OnPetAbility(CBaseEntity* PTarget, CBaseEntity* PMob, CMobSkill* PMobSkill, CBaseEntity* PPetMaster, action_t* action);
int32 OnPetAbility(CBaseEntity* PTarget, CPetEntity* PPet, CPetSkill* PMobSkill, CBaseEntity* PPetMaster, action_t* action);                                                                // triggers when pet uses an ability, specialized for pets
auto  OnUseWeaponSkill(CBattleEntity* PUser, CBaseEntity* PMob, CWeaponSkill* wskill, uint16 tp, bool primary, action_t& action, CBattleEntity* taChar) -> std::tuple<int32, uint8, uint8>; // returns: damage, tphits landed, extra hits landed
int32 OnUseAbility(CBattleEntity* PUser, CBattleEntity* PTarget, CAbility* PAbility, action_t* action);
int32 OnSteal(CBattleEntity* PChar, CBattleEntity* PTarget, CAbility* PAbility, action_t* action);

bool OnCanUseSpell(CBattleEntity* PChar, CSpell* Spell); // triggers when CanUseSpell is invoked on spell.cpp for PCs only

auto GetCachedInstanceScript(uint16 instanceId) -> sol::table;

void  OnInstanceZoneIn(CCharEntity* PChar, CInstance* PInstance);
void  AfterInstanceRegister(CBaseEntity* PChar);                             // triggers after a character is registered and zoned into an instance (the first time)
int32 OnInstanceLoadFailed(CZone* PZone);                                    // triggers when an instance load is failed (ie. instance no longer exists)
void  OnInstanceTimeUpdate(CZone* PZone, CInstance* PInstance, uint32 time); // triggers every second for an instance
void  OnInstanceFailure(CInstance* PInstance);                               // triggers when an instance is failed
void  OnInstanceCreatedCallback(CCharEntity* PChar, CInstance* PInstance);   // triggers when an instance is created (per character - waiting outside for entry)
void  OnInstanceCreated(CInstance* PInstance);                               // triggers when an instance is created (instance setup)
void  OnInstanceProgressUpdate(CInstance* PInstance);
void  OnInstanceStageChange(CInstance* PInstance);
void  OnInstanceComplete(CInstance* PInstance);

uint32 GetMobRespawnTime(uint32 mobid);
void   DisallowRespawn(uint32 mobid, bool allowRespawn);

std::string GetServerMessage(uint8 language);               // Get the message to be delivered to player on first zone in of a session
auto        GetRecentFishers(uint16 minutes) -> sol::table; // returns a list of recently active fishers (that fished in the last specified minutes)

void  OnAdditionalEffect(CBattleEntity* PAttacker, CBattleEntity* PDefender, action_result_t* Action, int32 damage);                                      // for mobs with additional effects
void  OnSpikesDamage(CBattleEntity* PDefender, CBattleEntity* PAttacker, action_result_t* Action, int32 damage);                                          // for mobs with spikes
int32 OnItemAdditionalEffect(CBattleEntity* PAttacker, CBattleEntity* PDefender, CItemWeapon* PItem, action_result_t* Action, int32 baseAttackDamage);    // for items with additional effects defined in a script
int32 additionalEffectAttack(CBattleEntity* PAttacker, CBattleEntity* PDefender, CItemWeapon* PItem, action_result_t* Action, int32 baseAttackDamage);    // for items with additional effects
void  additionalEffectSpikes(CBattleEntity* PDefender, CBattleEntity* PAttacker, CItemEquipment* PItem, action_result_t* Action, int32 baseAttackDamage); // for armor with spikes

auto NearLocation(const sol::table& table, float radius, float theta) -> sol::table;
auto GetFurthestValidPosition(CLuaBaseEntity* fromTarget, float distance, float theta) -> sol::table;

void OnPlayerDeath(CCharEntity* PChar);
void OnPlayerLevelUp(CCharEntity* PChar);
// Fires from CCharEntity::Raise() after the revive completes. Single funnel
// for both real-player Accept (0x01A RaiseMenu) and the bot auto-accept Lua
// binding — both go through Raise().
void OnPlayerRaise(CCharEntity* PChar);
// synthResult: 1=success, 2=HQ, 3=HQ2, 4=HQ3 (matches the SYNTHESIS_*
// enum). Fired after a synth completes successfully (any tier). FAIL path
// doesn't go through here.
void OnSynthFinish(CCharEntity* PChar, uint8 synthResult);
void OnPlayerLevelDown(CCharEntity* PChar);
void OnPlayerMount(CCharEntity* PChar);
void OnPlayerEmote(CCharEntity* PChar, Emote EmoteID);
void OnPlayerVolunteer(CCharEntity* PChar, const std::string& text);

bool OnChocoboDig(CCharEntity* PChar);

// Utility method: checks for and loads a lua function for events
auto LoadEventScript(CCharEntity* PChar, const char* functionName) -> sol::function;

uint16 GetDespoilDebuff(uint16 itemId); // Ask the database for an effectId based on Item despoiled (returns 0 if not in db)

void OnFurniturePlaced(CCharEntity* PChar, CItemFurnishing* itemId);
void OnFurnitureRemoved(CCharEntity* PChar, CItemFurnishing* itemId);

uint16 SelectDailyItem(CLuaBaseEntity* PLuaBaseEntity, uint8 dial);

auto SetCustomMenuContext(CCharEntity* PChar, sol::table table) -> std::string;
bool HasCustomMenuContext(CCharEntity* PChar);
void HandleCustomMenu(CCharEntity* PChar, const std::string& selection);

// Retrive the first itemId that matches a name
uint16 GetItemIDByName(const std::string& name);
auto   SendItemToDeliveryBox(const std::string& playerName, uint16 itemId, uint32 quantity, const std::string& senderText) -> SendToDBoxReturnCode;

auto GenerateDynamicEntity(CZone* PZone, CInstance* PInstance, sol::table table) -> CBaseEntity*;

// Fishing Contest
auto GetFishingContest() -> sol::table;
void InitNewFishingContest();
void SetContestParameters(uint16 fishId, uint8 measure, uint8 criteria);
void ProgressFishingContest();
void InitializeFishingContestSystem();

template <typename... Targs>
int32 invokeBattlefieldEvent(uint16 battlefieldId, const std::string& eventName, Targs... args);

auto GetSynergyRecipeByID(uint32 id) -> sol::table;
auto GetSynergyRecipeByTrade(CLuaTradeContainer luaTradeContainer) -> sol::table;

}; // namespace luautils

// template impl
template <typename... Targs>
int32 luautils::invokeBattlefieldEvent(uint16 battlefieldId, const std::string& eventName, Targs... args)
{
    // Calls the Battlefield event through the interaction object if it can find it
    sol::table contents = lua["xi"]["battlefield"]["contents"];
    if (!contents.valid())
    {
        return -1;
    }

    auto battlefield = contents[battlefieldId];
    if (!battlefield.valid())
    {
        return -1;
    }

    auto content = battlefield.get<sol::table>();
    auto handler = content[eventName];
    if (!handler.valid())
    {
        return -1;
    }

    auto result = handler.get<sol::protected_function>()(content, args...);
    if (!result.valid())
    {
        sol::error err = result;
        ShowError("luautils::%s: %s", eventName, err.what());
        return -1;
    }

    return 0;
}

#endif // _LUAUTILS_H -
