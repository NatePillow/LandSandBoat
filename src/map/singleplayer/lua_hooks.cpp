/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

// Out-of-line definitions for the singleplayer-fork luautils:: hook functions
// (OnBotTick, OnBotFinish, OnBotSummonTrusts, OnGetConfigContent, OnLot*, etc.).
// Declarations stay in lua/luautils.h (wrapped with SINGLEPLAYER markers) but
// the bodies live here so upstream luautils.cpp keeps its vanilla footprint.

#include "lua/luautils.h"
#include "lua/lua_baseentity.h"

#include "common/logging.h"
#include "common/timer.h"
#include "common/utils.h"

#include "action/action.h"
#include "battlefield_handler.h"
#include "config_cache.h"
#include "entities/charentity.h"
#include "entities/mobentity.h"
#include "items/item_weapon.h"
#include "map_session.h"
#include "map_session_container.h"
#include "packets/basic.h"
#include "packets/char_status.h"
#include "packets/char_sync.h"
#include "packets/s2c/0x017_chat_std.h"
#include "packets/s2c/0x150_server_ident.h"
#include "packets/s2c/0x178_headless_state.h"
#include "packets/s2c/0x179_headless_event.h"
#include "packets/s2c/0x17c_dps_update.h"
#include "packets/s2c/0x191_party_status.h"
#include "packets/s2c/0x192_autoskill_state.h"
#include "packets/s2c/0x1a3_sync_ack.h"
#include "status_effect_container.h"

#include "utils/charutils.h"
#include "utils/zoneutils.h"

#include <algorithm>
#include <sstream>

namespace luautils
{
void OnBotTick(CCharEntity* PChar, timer::time_point tick, uint8 botMode)
{
    TracyZoneScoped;

    // Forwards to xi.singleplayer.bots.onBotTick if defined. The module is set up in Phase 3;
    // calling this before the module exists is a no-op (callGlobal silently skips
    // when the path is undefined).
    callGlobal<void>("xi.singleplayer.bots.onBotTick", PChar, botMode);
}

void OnBotCommand(CCharEntity* PMain, const std::string& command, uint32 arg)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.onCommand", PMain, command, arg);
}

void OnBotFinish(CCharEntity* PMain)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.bots_spawn.finish_alliance", PMain);
}

void OnBotDespawn(CCharEntity* PChar)
{
    TracyZoneScoped;
    if (PChar == nullptr) { return; }
    callGlobal<void>("xi.singleplayer.bots.onBotDespawn", PChar);
}

void OnBotSummonTrusts(CCharEntity* PMain)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.bots_spawn.summon_trusts_for_alliance", PMain);
}

void OnBotSetHealMode(CCharEntity* PMain, bool on, const std::string& botName)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ai_rest.set_alliance_heal_mode", PMain, on, botName);
}


void OnBotSetAddControlMode(CCharEntity* PMain, const std::string& botName, uint8 mode)
{
    TracyZoneScoped;
    // Map the wire-byte mode to the Lua string ai_ability.set_add_control_mode
    // expects. Unknown bytes coerce to 'provoke' so a malformed packet can't
    // wedge the bot in an undefined state.
    const char* modeStr = "provoke";
    if (mode == 1) { modeStr = "flash"; }
    else if (mode == 2) { modeStr = "both"; }
    callGlobal<void>("xi.singleplayer.bots.ability.set_add_control_mode", PMain, botName, modeStr);
}

void OnBotSetStunMode(CCharEntity* PMain, uint8 mode)
{
    TracyZoneScoped;
    // Alliance-wide setting. Unknown bytes coerce to 'always' (the legacy
    // default value of BOT_STUN_PERSIST_UNTIL_FIRED).
    const char* modeStr = (mode == 1) ? "window" : "always";
    callGlobal<void>("xi.singleplayer.bots.magic.set_alliance_stun_mode", PMain, modeStr);
}

void OnBotSetMultiEngageMode(CCharEntity* PMain, uint8 mode)
{
    TracyZoneScoped;
    // Alliance-wide multi-engagement toggle (#173). 0 = single-mob legacy
    // (whole alliance funnels onto allianceTarget), 1 = per-party mode (each
    // of the 3 alliance sub-parties fights its own mob). The Lua side handles
    // seeding all 3 partyAssistTargetId slots from allianceTarget on the
    // false→true transition, and clears per-party state on true→false.
    const bool on = (mode != 0);
    callGlobal<void>("xi.singleplayer.bots.set_multi_engage_mode", PMain, on);
}

void OnBotSetPullerPaused(CCharEntity* PMain, uint8 paused)
{
    TracyZoneScoped;
    // Puller Start/Stop toggle. Paused only gates the IDLE→SCOUTING
    // transition; an in-flight pull (SCOUTING/PULLING/RETURNING/HANDOFF)
    // finishes naturally. Fresh set_puller defaults to paused=true.
    const bool on = (paused != 0);
    callGlobal<void>("xi.singleplayer.bots.ai_puller.set_paused", PMain, on);
}

void OnBotSetThfRaDelay(CCharEntity* PMain, const std::string& botName, uint8 delaySec)
{
    TracyZoneScoped;
    // Per-bot THF cadence. Lua handler writes to alliance.bot[id].thfRaDelay
    // (already exists as state, just newly user-controlled). 0 = Off.
    callGlobal<void>("xi.singleplayer.bots.melee.set_thf_ra_delay", PMain, botName, delaySec);
}

// OnBotSetNmMode retired — `is_nm` is now always engine-autodetect.

void OnRoleAiSetMode(CCharEntity* PMain, uint8 role, uint8 type, uint8 mode)
{
    TracyZoneScoped;
    // Alliance-wide. Lua side validates ranges and ignores unknown values so
    // a malformed packet can't wedge policy state. Policy state lives on
    // ai_item (not a standalone role_policy module — role_* file names are
    // reserved for AI tick decision loops).
    callGlobal<void>("xi.singleplayer.bots.item.set_role_ai_mode", PMain, role, type, mode);
}

void OnRoleAiSetStatusFlag(CCharEntity* PMain, uint8 role, uint8 statusKey, bool on)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.item.set_role_ai_status_flag", PMain, role, statusKey, on);
}

void OnBotFireAllWs(CCharEntity* PMain)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ability.fire_all_ws", PMain);
}

void OnBotIssueCommand(CCharEntity* PMain, const std::string& botName,
                       const std::string& actionKind, const std::string& actionName,
                       uint32 targetId)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ai_command.dispatch",
                     PMain, botName, actionKind, actionName, targetId);
}

void OnBotSetSataMode(CCharEntity* PMain, const std::string& botName, uint8 mode)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ability.set_bot_sata_mode",
                     PMain, botName, mode);
}

void OnBotSetCasualNukeRotation(CCharEntity* PMain, const std::string& botName, uint8 value)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.magic.set_bot_casual_nuke_rotation",
                     PMain, botName, value);
}

void OnBotSetCasualNukeMbMode(CCharEntity* PMain, const std::string& botName, uint8 mode)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.magic.set_bot_casual_nuke_mb_mode",
                     PMain, botName, mode);
}

void OnBotTankNudge(CCharEntity* PMain, const std::string& botName, uint8 direction)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ai_move.tank_nudge",
                     PMain, botName, direction);
}

void OnBotTankWalkToMe(CCharEntity* PMain, const std::string& botName)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ai_move.tank_walk_to_me",
                     PMain, botName);
}

void OnBotSetPuller(CCharEntity* PMain, const std::string& botName)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ai_puller.set_puller", PMain, botName);
}

void OnBotSetPullerRange(CCharEntity* PMain, uint8 rangeYalms)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ai_puller.set_puller_range",
                     PMain, rangeYalms);
}

void OnBotSetPullerConRange(CCharEntity* PMain, uint8 minCon, uint8 maxCon)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ai_puller.set_puller_con_range",
                     PMain, minCon, maxCon);
}

void OnBotSetPullerResumeMpp(CCharEntity* PMain, uint8 mpp)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ai_puller.set_puller_resume_mpp",
                     PMain, mpp);
}

void OnBotRequestPullerNames(CCharEntity* PMain)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ai_puller.request_nearby_names", PMain);
}

void OnBotGiveSignet(CCharEntity* PMain)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.bots_spawn.give_signet_alliance", PMain);
}

void OnBotSetHealScope(CCharEntity* PMain, const std::string& botName, uint8 mode)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.magic.set_bot_heal_scope", PMain, botName, mode);
}

void OnBotSetAggroMode(CCharEntity* PMain, uint8 mode)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.bots_spawn.set_alliance_aggro_mode", PMain, mode);
}

void OnBotSetPullerNameFilter(CCharEntity* PMain, const std::vector<std::string>& names)
{
    TracyZoneScoped;
    sol::table tbl = lua.create_table();
    for (size_t i = 0; i < names.size(); ++i)
    {
        tbl[i + 1] = names[i];
    }
    callGlobal<void>("xi.singleplayer.bots.ai_puller.set_name_filter", PMain, tbl);
}

void OnBotSetScThreshold(CCharEntity* PMain, uint8 which, uint8 value)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ability.set_alliance_sc_threshold", PMain, which, value);
}

void OnBotScPause(CCharEntity* PMain, uint8 scId, bool paused)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ability.set_alliance_pause", PMain, scId, paused);
}

namespace
{
    // Build a sol::table of every headless owned by PMain, indexed 1..N for Lua ipairs.
    // Used as the `targets` argument to xi.singleplayer.bots.bots_progression_cascade.sync_{quests,missions}.
    sol::table collectOwnedHeadless(CCharEntity* PMain)
    {
        sol::table targets = lua.create_table();
        int        idx     = 0;
        mapsessions::get().forEachOwnedHeadless(PMain->id, [&](CCharEntity* PBot)
        {
            ++idx;
            targets[idx] = CLuaBaseEntity(PBot);
        });
        return targets;
    }
} // namespace

void OnBotSyncQuests(CCharEntity* PMain)
{
    TracyZoneScoped;
    if (PMain == nullptr) { return; }
    const sol::table targets = collectOwnedHeadless(PMain);
    const int        count   = callGlobal<int>("xi.singleplayer.bots.bots_progression_cascade.sync_quests", PMain, targets);
    // S2C 0x1A3 SYNC_ACK kind=0 (quests). Addon uses this to clear the
    // in-flight guard on its Sync Quests button.
    PMain->pushPacket<GP_SERV_COMMAND_SYNC_ACK>(static_cast<uint8>(0), static_cast<uint32>(count));
}

void OnBotSyncMissions(CCharEntity* PMain)
{
    TracyZoneScoped;
    if (PMain == nullptr) { return; }
    const sol::table targets = collectOwnedHeadless(PMain);
    const int        count   = callGlobal<int>("xi.singleplayer.bots.bots_progression_cascade.sync_missions", PMain, targets);
    PMain->pushPacket<GP_SERV_COMMAND_SYNC_ACK>(static_cast<uint8>(1), static_cast<uint32>(count));
}

void OnBotSyncTeleports(CCharEntity* PMain)
{
    TracyZoneScoped;
    if (PMain == nullptr) { return; }
    const sol::table targets = collectOwnedHeadless(PMain);
    const int        count   = callGlobal<int>("xi.singleplayer.bots.bots_progression_cascade.sync_teleports", PMain, targets);
    // SYNC_ACK kind=2 (third sync category after quests/missions).
    PMain->pushPacket<GP_SERV_COMMAND_SYNC_ACK>(static_cast<uint8>(2), static_cast<uint32>(count));
}

void OnBotSetBrdSongRoster(CCharEntity* PMain, const std::string& botName,
                           uint16 slot0, uint16 slot1, uint16 slot2, uint16 slot3)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.brd.set_song_roster",
                     PMain, botName, slot0, slot1, slot2, slot3);
}

void OnBotSetSmnAvatar(CCharEntity* PMain, const std::string& botName, uint16 avatarSpellId)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.smn.set_avatar",
                     PMain, botName, avatarSpellId);
}

void OnSetAutoskill(CCharEntity* PMain, const std::string& botName, uint8 mode, const std::vector<uint16>& spellIds)
{
    TracyZoneScoped;
    if (PMain == nullptr)
    {
        return;
    }
    // Marshal the spell ID vector to a Lua array so xi.singleplayer.bots.skillup receives a
    // proper 1-indexed table.
    sol::table tbl = lua.create_table();
    for (size_t i = 0; i < spellIds.size(); ++i)
    {
        tbl[i + 1] = spellIds[i];
    }
    callGlobal<void>("xi.singleplayer.bots.skillup.set_skillup_for_bot", PMain, botName, mode, tbl);
    // Echo the new state back so every subscribed addon (autoskill, autobots)
    // can update its local cache. Server may have refused (target not owned),
    // in which case the Lua side has already left state untouched and the
    // echo reflects whatever the requester asked for — the request and the
    // applied state can diverge silently; callers shouldn't depend on this
    // packet for hard validation.
    PMain->pushPacket<GP_SERV_COMMAND_AUTOSKILL_STATE>(botName, mode);
}

void OnListAutoskill(CCharEntity* PMain)
{
    TracyZoneScoped;
    if (PMain == nullptr)
    {
        return;
    }
    callGlobal<void>("xi.singleplayer.bots.skillup.push_skillup_state_to", PMain);
}

void OnBotSetRole(CCharEntity* PBot, uint8 role)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.onSetRole", PBot, role);
}

void OnBotSetFormation(CCharEntity* PPrimary, uint8 kind, const std::string& name)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ai_formation.on_set_formation", PPrimary, kind, name);
}

void OnBotUpdateAllianceConfig(CCharEntity* PChar, const std::string& configName)
{
    TracyZoneScoped;
    // Lua side computes the diff against the running alliance and applies
    // it; falls back internally to a full despawn+respawn if the diff
    // can't handle the case cleanly.
    callGlobal<void>("xi.singleplayer.bots.bots_spawn.update_alliance_diff",
                     PChar, configName);
}

void OnBotSpawnFromConfig(CCharEntity* PChar, const std::string& configName)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.bots_spawn_from_config", PChar, configName);
}

void OnUseFoodFromConfig(CCharEntity* PChar, const std::string& configName)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.item.use_food_from_config", PChar, configName);
}

void OnSetLotAssignment(CCharEntity* PMain, const std::string& charName, const std::string& groupName, bool on)
{
    TracyZoneScoped;
    callGlobal<void>("xi.singleplayer.bots.ai_lot.set_assignment_for_char", charName, groupName, on);
}

// Lua-side read of a cached config body + its mtime. Used by ai_equip_swap.load
// to mtime-check-on-read against the configcache (which the HTTP PUT handler
// writes through), so equip-set edits made by the addon land for the next
// gear swap without explicit invalidation plumbing.
auto GetServerConfig(const std::string& category, const std::string& name) -> std::tuple<sol::object, int64_t>
{
    TracyZoneScoped;
    const auto* entry = singleplayer::configcache::get(category, name);
    if (entry == nullptr)
    {
        return { sol::lua_nil, 0 };
    }
    return { sol::make_object(lua, entry->body), entry->mtime };
}

void OnLotListAdd(CCharEntity* PChar, uint32 itemId, const std::string& botName)
{
    TracyZoneScoped;
    if (PChar == nullptr)
    {
        return;
    }
    callGlobal<void>("xi.singleplayer.bots.ai_lot.lot_list_add", PChar, itemId, botName);
}

void OnLotListRemove(CCharEntity* PChar, uint32 itemId, const std::string& botName)
{
    TracyZoneScoped;
    if (PChar == nullptr)
    {
        return;
    }
    callGlobal<void>("xi.singleplayer.bots.ai_lot.lot_list_remove", PChar->id, itemId, botName);
}

void OnLotListClear(CCharEntity* PChar, uint32 itemId)
{
    TracyZoneScoped;
    if (PChar == nullptr)
    {
        return;
    }
    callGlobal<void>("xi.singleplayer.bots.ai_lot.lot_list_clear", PChar->id, itemId);
}

// Resolve a Lua CLuaBaseEntity wrapper to the underlying CCharEntity*, or
// nullptr if the entity is missing or isn't a char. Used by the three Bot*
// push helpers below — Lua calls them with the wrapper, sol2 can't directly
// marshal that across the wrapper boundary to CCharEntity*.
static auto asCharEntity(CLuaBaseEntity* PLua) -> CCharEntity*
{
    if (PLua == nullptr)
    {
        return nullptr;
    }
    return dynamic_cast<CCharEntity*>(PLua->GetBaseEntity());
}

void BotPushLog(CLuaBaseEntity* PLuaPrimary, const std::string& tag, const std::string& msg)
{
    auto* PPrimary = asCharEntity(PLuaPrimary);
    if (PPrimary == nullptr)
    {
        return;
    }

    // Payload layout matches 0x179 LOG_MESSAGE: Tag[16] + Message[44].
    std::array<char, 60> payload{};
    const auto           tagLen = std::min(tag.size(), sizeof("123456789012345") - 1); // 15 chars + NUL
    const auto           msgLen = std::min(msg.size(), static_cast<size_t>(43));
    std::memcpy(payload.data(), tag.data(), tagLen);
    std::memcpy(payload.data() + 16, msg.data(), msgLen);

    PPrimary->pushPacket<GP_SERV_COMMAND_HEADLESS_EVENT>(static_cast<uint8>(0x01), payload.data(), payload.size());
}

void BotPushState(CLuaBaseEntity* PLuaPrimary, uint8 stateType, sol::table payload)
{
    auto* PPrimary = asCharEntity(PLuaPrimary);
    if (PPrimary == nullptr)
    {
        return;
    }

    std::array<uint8_t, 8> bytes{};
    size_t                 i = 0;
    for (const auto& [key, val] : payload)
    {
        if (i >= bytes.size())
        {
            break;
        }
        bytes[i++] = static_cast<uint8_t>(val.as<uint32_t>() & 0xFFu);
    }

    PPrimary->pushPacket<GP_SERV_COMMAND_HEADLESS_STATE>(stateType, bytes.data(), bytes.size());
}

void PushPartyStatus(CLuaBaseEntity* PLuaPrimary, uint8 partyNumber, sol::table members)
{
    auto* PPrimary = asCharEntity(PLuaPrimary);
    if (PPrimary == nullptr)
    {
        return;
    }

    // members: array of {
    //   name = string,
    //   race = u8, face = u8,             -- portrait keys for the addon
    //   expCurrent = u32, expToNext = u32, -- main-job EXP for the progress bar
    //   effects = { effectId, effectId, ... },
    // }
    using Member = GP_SERV_COMMAND_PARTY_STATUS::Member;
    std::vector<Member> entries;
    entries.reserve(GP_SERV_COMMAND_PARTY_STATUS::kMaxEntries);

    for (const auto& [k, v] : members)
    {
        if (entries.size() >= GP_SERV_COMMAND_PARTY_STATUS::kMaxEntries)
        {
            break;
        }
        sol::table  entry = v.as<sol::table>();
        std::string name  = entry.get_or<std::string>("name", "");
        if (name.empty())
        {
            continue;
        }

        Member m;
        m.Name       = std::move(name);
        m.Race       = entry.get_or<uint8_t>("race", 0);
        m.Face       = entry.get_or<uint8_t>("face", 0);
        m.ExpCurrent = entry.get_or<uint32_t>("expCurrent", 0);
        m.ExpToNext  = entry.get_or<uint32_t>("expToNext", 0);

        sol::object effsObj = entry["effects"];
        if (effsObj.valid() && effsObj.is<sol::table>())
        {
            sol::table effs = effsObj.as<sol::table>();
            for (const auto& [_, e] : effs)
            {
                if (m.Effects.size() >= GP_SERV_COMMAND_PARTY_STATUS::kMaxEffectsPerBot)
                {
                    break;
                }
                m.Effects.push_back(static_cast<uint16_t>(e.as<uint32_t>()));
            }
        }

        entries.emplace_back(std::move(m));
    }

    PPrimary->pushPacket<GP_SERV_COMMAND_PARTY_STATUS>(partyNumber, entries);
}

void OnActionResult(const action_t& action)
{
    TracyZoneScoped;

    // Fast path: bail before doing any Lua work if no dispatcher is registered.
    sol::object dispatcher = lua["xi"]["singleplayer"]["bots"]["onActionResult"];
    if (!dispatcher.valid() || !dispatcher.is<sol::function>())
    {
        return;
    }

    CBaseEntity* PActor = zoneutils::GetEntity(action.actorId);
    if (PActor == nullptr)
    {
        return;
    }

    // Build a compact Lua table of the action's damage-bearing fields. Mirrors
    // the action_t struct shape but only includes what damage trackers need.
    sol::table tbl = lua.create_table();
    tbl["actorId"]    = action.actorId;
    tbl["actiontype"] = static_cast<uint8_t>(action.actiontype);
    tbl["actionid"]   = action.actionid;

    sol::table targets = lua.create_table();
    int        ti      = 1;
    for (const auto& target : action.targets)
    {
        sol::table targetTbl = lua.create_table();
        targetTbl["actorId"] = target.actorId;

        sol::table resultsTbl = lua.create_table();
        int        ri         = 1;
        for (const auto& result : target.results)
        {
            sol::table rt          = lua.create_table();
            rt["param"]            = result.param;
            rt["messageID"]        = static_cast<uint16_t>(result.messageID);
            rt["spikesParam"]      = result.spikesParam;
            rt["spikesMessage"]    = static_cast<uint16_t>(result.spikesMessage);
            rt["addEffectParam"]   = result.addEffectParam;
            rt["addEffectMessage"] = static_cast<uint16_t>(result.addEffectMessage);
            resultsTbl[ri++]       = rt;
        }
        targetTbl["results"] = resultsTbl;

        targets[ti++] = targetTbl;
    }
    tbl["targets"] = targets;

    callGlobal<void>("xi.singleplayer.bots.onActionResult", PActor, tbl);
}

void OnMobSkillStart(CBaseEntity* PActor, timer::duration castTime)
{
    TracyZoneScoped;

    sol::object dispatcher = lua["xi"]["singleplayer"]["bots"]["onMobSkillStart"];
    if (!dispatcher.valid() || !dispatcher.is<sol::function>())
    {
        return;
    }

    if (PActor == nullptr)
    {
        return;
    }

    auto castTimeMs = static_cast<int32>(std::chrono::duration_cast<std::chrono::milliseconds>(castTime).count());
    callGlobal<void>("xi.singleplayer.bots.onMobSkillStart", PActor, castTimeMs);
}

void BotPushDps(CLuaBaseEntity* PLuaPrimary, uint32 botCharId, bool isFinal, uint32 totalDamage, uint32 activeMs, sol::table categories)
{
    auto* PPrimary = asCharEntity(PLuaPrimary);
    if (PPrimary == nullptr)
    {
        return;
    }

    GP_SERV_COMMAND_DPS_UPDATE::CategoryStats cats[GP_SERV_COMMAND_DPS_UPDATE::kCategoryCount]{};

    // Lua-side passes a 1-indexed array of 6 tables; map to fixed C array.
    for (uint8_t i = 0; i < GP_SERV_COMMAND_DPS_UPDATE::kCategoryCount; ++i)
    {
        sol::object entry = categories[i + 1];
        if (!entry.valid() || !entry.is<sol::table>())
        {
            continue;
        }
        sol::table   t      = entry.as<sol::table>();
        sol::object  dmg    = t["damage"];
        sol::object  hits   = t["hits"];
        sol::object  misses = t["misses"];
        cats[i].Damage = (dmg.valid() && dmg.is<uint32_t>()) ? dmg.as<uint32_t>() : 0;
        cats[i].Hits   = (hits.valid() && hits.is<uint16_t>()) ? hits.as<uint16_t>() : 0;
        cats[i].Misses = (misses.valid() && misses.is<uint16_t>()) ? misses.as<uint16_t>() : 0;
    }

    PPrimary->pushPacket<GP_SERV_COMMAND_DPS_UPDATE>(botCharId, isFinal, totalDamage, activeMs, cats);
}

}; // namespace luautils
