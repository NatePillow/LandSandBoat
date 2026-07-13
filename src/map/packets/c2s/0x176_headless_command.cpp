/*
===========================================================================

  Copyright (c) 2026 Single Player Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "0x176_headless_command.h"

#include "ai/ai_container.h"
#include "entities/charentity.h"
#include "lua/luautils.h"
#include "map_session_container.h"
#include "status_effect.h"
#include "status_effect_container.h"
#include "utils/charutils.h"
#include "utils/zoneutils.h"
#include "zone.h"

#include "common/logging.h"

#include <cstring>
#include <string>

namespace
{
    constexpr uint8 NS_AUTOBOTS = 0x01;

    namespace AutobotsSub
    {
        constexpr uint8 SET_BOT_MODE   = 0x01;
        constexpr uint8 ATTACK         = 0x02;
        constexpr uint8 DISENGAGE      = 0x03;
        constexpr uint8 SET_ROLE       = 0x04;
        constexpr uint8 DESPAWN_ALL    = 0x05;
        constexpr uint8 FINISH         = 0x06;
        constexpr uint8 SET_HEAL_MODE  = 0x07;
        constexpr uint8 UPDATE_CONFIG  = 0x08;
        constexpr uint8 SUMMON_TRUSTS  = 0x09;
        constexpr uint8 SC_PAUSE          = 0x0A;
        constexpr uint8 SET_ALLIANCE_MODE = 0x0B;
        constexpr uint8 SPAWN_DEAD        = 0x0C;
        constexpr uint8 SET_FORMATION     = 0x0D;
        constexpr uint8 SYNC_QUESTS       = 0x0E;
        constexpr uint8 SYNC_MISSIONS     = 0x0F;
        constexpr uint8 TANK_WALK_TO_ME   = 0x10;
        constexpr uint8 FIRE_ALL_WS       = 0x11;
        constexpr uint8 SET_SC_THRESHOLD  = 0x12;
        constexpr uint8 SET_SATA_MODE     = 0x13;
        constexpr uint8 TANK_NUDGE        = 0x14;
        constexpr uint8 SET_PULLER        = 0x15;
        constexpr uint8 SET_PULLER_RANGE  = 0x16;
        constexpr uint8 SET_PULLER_CON_RANGE = 0x17;
        constexpr uint8 REQUEST_PULLER_NAMES = 0x18;
        constexpr uint8 GIVE_SIGNET          = 0x19;
        constexpr uint8 SET_HEAL_SCOPE       = 0x1A;
        constexpr uint8 SET_AGGRO_MODE       = 0x1B;
        // 0x1C REQUEST_BOT_STATE retired — bot state now flows via the
        // loopback HTTP server's GET /bot-state?for=<name> endpoint. The
        // server publishes the snapshot to a thread-safe cache every
        // onBotTick (~400ms); the addon polls/fetches on unlock. Opcode
        // is reserved for reuse.
        constexpr uint8 SET_ADD_CONTROL_MODE = 0x1D;
        constexpr uint8 SET_STUN_MODE        = 0x1E;
        constexpr uint8 SET_THF_RA_DELAY     = 0x1F;
        constexpr uint8 SET_ROLE_AI_MODE     = 0x20;
        constexpr uint8 SET_ROLE_STATUS_FLAG = 0x21;
        constexpr uint8 SYNC_TELEPORTS       = 0x22;
        constexpr uint8 SET_BRD_SONG_ROSTER  = 0x23;
        constexpr uint8 SET_SMN_AVATAR       = 0x24;
        constexpr uint8 SET_MULTI_ENGAGE_MODE = 0x25;
        constexpr uint8 SET_PULLER_PAUSED     = 0x26;
        constexpr uint8 SET_PULLER_RESUME_MPP = 0x27;
        constexpr uint8 SET_CASUAL_NUKE_ROTATION = 0x28;
        constexpr uint8 SET_CASUAL_NUKE_MB_MODE  = 0x29;
    }

    auto safeName(const char* buf, size_t maxLen) -> std::string
    {
        return std::string(buf, strnlen(buf, maxLen));
    }
} // namespace

auto GP_CLI_COMMAND_HEADLESS_COMMAND::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar);
}

void GP_CLI_COMMAND_HEADLESS_COMMAND::process(MapSession* PSession, CCharEntity* PChar) const
{
    if (Namespace != NS_AUTOBOTS)
    {
        // Other namespaces reserved — drop silently for forward compat.
        return;
    }

    switch (Subcommand)
    {
        case AutobotsSub::SET_BOT_MODE:
        {
            // Payload layout: char Name[11] + uint8 Mode
            // If Name is empty, target is the requesting char (main char self-toggle).
            const std::string name = safeName(reinterpret_cast<const char*>(Payload), 11);
            const uint8       mode = Payload[11];

            CCharEntity* target = name.empty() ? PChar : zoneutils::GetCharByName(name);
            if (target == nullptr)
            {
                return;
            }

            if (mode > static_cast<uint8>(BotMode::MovementOnly))
            {
                return;
            }

            target->m_botMode = static_cast<BotMode>(mode);
            ShowDebug(fmt::format("Bot mode {} set on '{}'", static_cast<int>(mode), target->getName()));
        }
        break;

        case AutobotsSub::ATTACK:
        {
            // Payload layout: uint32 TargetId (little-endian); rest reserved.
            // Forwards to Lua dispatcher which will route to assist + melee bots.
            uint32 targetId = 0;
            std::memcpy(&targetId, Payload, sizeof(uint32));

            luautils::OnBotCommand(PChar, "ATTACK", targetId);
        }
        break;

        case AutobotsSub::DISENGAGE:
        {
            luautils::OnBotCommand(PChar, "DISENGAGE", 0);
        }
        break;

        case AutobotsSub::DESPAWN_ALL:
        {
            // No payload. Despawn every headless owned by this primary.
            const uint32 count = mapsessions::get().destroyHeadlessForParent(PChar->id);
            ShowDebug(fmt::format("DESPAWN_ALL: removed {} headless session(s) for '{}'", count, PChar->getName()));
        }
        break;

        case AutobotsSub::FINISH:
        {
            // No payload. Flag every headless owned by this primary that has a
            // magic state to nuke-until-dead (handled in autospawn.lua).
            luautils::OnBotFinish(PChar);
        }
        break;

        case AutobotsSub::SUMMON_TRUSTS:
        {
            // No payload. Per-party leader fires summonTrustDirect on each
            // trust listed in the active alliance config. Direct spawn (no
            // cast time) but still validates: has spell + not duplicated +
            // recast inactive.
            luautils::OnBotSummonTrusts(PChar);
        }
        break;

        case AutobotsSub::SC_PAUSE:
        {
            // Payload: uint8 sc_id (0=both, 1=sc1, 2=sc2) + uint8 paused (0/1).
            // Flips xi.singleplayer.bots.melee.state[<bot>].sc1_paused / sc2_paused for every
            // headless owned by this primary. Replaces the legacy 0x151/0x152
            // SC:PAUSE relay path.
            const uint8 scId   = Payload[0];
            const uint8 paused = Payload[1];
            luautils::OnBotScPause(PChar, scId, paused != 0);
        }
        break;

        case AutobotsSub::SET_ALLIANCE_MODE:
        {
            // Payload: uint8 mode (0=Off, 1=CombatOnly, 2=Full).
            // Flip every owned headless's m_botMode without despawning. Used
            // by AutoBots "Start Actions" / "Stop Actions" buttons so the user
            // can pause+resume bot AI cheaply (vs spawn/despawn churn).
            const uint8 mode = Payload[0];
            const uint32 count = mapsessions::get().setBotModeForOwnedBots(PChar->id, mode);
            ShowDebug(fmt::format("SET_ALLIANCE_MODE: mode={} applied to {} headless of '{}'",
                                  static_cast<int>(mode), count, PChar->getName()));
        }
        break;

        case AutobotsSub::SET_HEAL_MODE:
        {
            // Payload: uint8 on (0=off, 1=on) + char Name[10] + uint8 reserved.
            // Empty Name string -> apply to every owned headless (alliance-wide).
            // Non-empty Name string -> apply to that single owned bot.
            // Replaces the prior mages_only flag; the mages-only filter was a
            // narrow special case that no UI consumed after the Controls-tab
            // refactor, and the new per-bot dispatch generalizes it cleanly
            // (callers can build their own per-role selection sets client-side
            // and emit one packet per bot).
            const uint8       on   = Payload[0];
            const std::string name = safeName(reinterpret_cast<const char*>(Payload) + 1, 10);
            luautils::OnBotSetHealMode(PChar, on != 0, name);
        }
        break;

        case AutobotsSub::UPDATE_CONFIG:
        {
            // Payload: char ConfigName[12] — switch the running alliance to a
            // new config. Routes to the Lua diff path (bots_spawn.update_alliance_diff)
            // which computes DROP / ADD / KEEP_RESHAPE against the running
            // alliance and applies the minimum mutation. The Lua side falls
            // back to a full despawn+respawn internally if it hits a case the
            // diff can't handle cleanly (party count change, primary's party
            // assignment changing, etc.) — no C++ branching needed here.
            const std::string configName = safeName(reinterpret_cast<const char*>(Payload), 12);
            if (configName.empty())
            {
                return;
            }
            ShowDebug(fmt::format("UPDATE_CONFIG: dispatching diff for '{}'", configName));
            luautils::OnBotUpdateAllianceConfig(PChar, configName);
        }
        break;

        case AutobotsSub::SPAWN_DEAD:
        {
            // No payload. For every headless owned by this primary that is
            // currently dead (health.hp == 0), simulate the "homepoint →
            // /welcome" sequence in one tick: apply the standard death XP
            // loss, restore HP/MP, apply EFFECT_WEAKNESS, clear the death
            // timestamp, snap into primary's zone + position. End state
            // matches retail: bot alive at primary, weakened, with the
            // proper XP loss applied. Skips the moveHeadlessToPrimaryZone
            // bot-unfriendly-zone filter — explicit user request to bring
            // the bots wherever the primary currently is.
            uint32 revivedCount = 0;
            CZone* primaryZone  = PChar->loc.zone;
            mapsessions::get().forEachOwnedHeadless(PChar->id, [&](CCharEntity* PBot)
            {
                if (PBot->health.hp != 0)
                {
                    return;
                }

                // Retail death cost: 8% of next-level XP at <=lv67, flat 2400 above.
                charutils::DelExperiencePoints(PBot, 0.0f, 0);

                PBot->health.hp = PBot->GetMaxHP();
                PBot->health.mp = PBot->GetMaxMP();
                PBot->SetDeathTime(timer::time_point::min());
                PBot->animation = ANIMATION_NONE;
                PBot->status    = STATUS_TYPE::NORMAL;

                // Exit CDeathState. battleentity.cpp:3295 pushed CDeathState
                // onto the PAI stack when HP hit 0; it stays for the 60-min
                // homepoint timer unless raised. Without this call SPAWN_DEAD
                // restores HP but leaves the death state on top — its
                // CanChangeState() returns false so every action attempt
                // (cast, JA, WS, engage) is silently rejected. Symptom: bots
                // look alive but freeze; role tick gates evaluate true but
                // nothing fires. Accept_Raise mirrors CCharEntity::Raise: it
                // marks the state as accepted, after which Update pops it on
                // the next tick > 2s later.
                if (PBot->PAI)
                {
                    PBot->PAI->Accept_Raise();
                }

                // Homepoint is a fresh start, not a raise — mirror
                // charutils::HomePoint and *remove* Weakness if any was
                // lingering (e.g. from a raise that didn't finish before
                // the bot died again). DelStatusEffectSilent is no-op when
                // the effect isn't present, so unconditional is safe.
                PBot->StatusEffectContainer->DelStatusEffectSilent(EFFECT_WEAKNESS);
                PBot->StatusEffectContainer->DelStatusEffectSilent(EFFECT_LEVEL_SYNC);

                // Zone/position snap: in-process Decrease+Increase if the
                // bot was stranded in a different zone, otherwise just snap
                // position. Mirrors moveBotIntoSenderZone from the instance
                // enter handler; bypasses the bot-unfriendly-zone filter
                // since the user is explicitly asking to revive here.
                if (primaryZone != nullptr)
                {
                    if (PBot->loc.zone != primaryZone)
                    {
                        if (PBot->loc.zone != nullptr)
                        {
                            PBot->loc.zone->DecreaseZoneCounter(PBot);
                        }
                        PBot->loc.destination = primaryZone->GetID();
                        PBot->loc.p           = PChar->loc.p;
                        // SINGLEPLAYER: loc.zoning field removed upstream — auto-managed now.
                        primaryZone->IncreaseZoneCounter(PBot);
                        mapsessions::persistHeadlessPosZone(PBot); // keep chars.pos_zone in sync with the hop
                        PBot->clearPacketList();
                    }
                    else
                    {
                        PBot->loc.p = PChar->loc.p;
                    }
                }

                PBot->updatemask |= UPDATE_HP;
                ++revivedCount;
            });
            ShowDebug(fmt::format("SPAWN_DEAD: revived {} headless of '{}'", revivedCount, PChar->getName()));
        }
        break;

        case AutobotsSub::SET_ROLE:
        {
            // Payload layout: char Name[10] + uint8 Role + uint8 padding
            const std::string name = safeName(reinterpret_cast<const char*>(Payload), 10);
            const uint8       role = Payload[10];

            if (name.empty())
            {
                return;
            }

            CCharEntity* target = zoneutils::GetCharByName(name);
            if (target == nullptr)
            {
                return;
            }

            luautils::OnBotSetRole(target, role);
        }
        break;

        case AutobotsSub::SET_FORMATION:
        {
            // Payload layout: uint8 Kind (0=battle, 1=walking) + char Name[11]
            // Affects the requesting char's primary state. Battle/walking
            // are tracked independently — addon UI sends two separate
            // SET_FORMATION packets when switching, one per kind.
            const uint8       kind = Payload[0];
            const std::string name = safeName(reinterpret_cast<const char*>(Payload + 1), 11);
            if (name.empty())
            {
                return;
            }
            luautils::OnBotSetFormation(PChar, kind, name);
        }
        break;

        case AutobotsSub::SYNC_QUESTS:
        {
            // No payload. Cascade primary's completed quests onto every linked
            // headless via xi.singleplayer.bots.bots_progression_cascade.sync_quests. Server replies with
            // S2C 0x1A3 SYNC_ACK so the addon clears its in-flight guard.
            luautils::OnBotSyncQuests(PChar);
        }
        break;

        case AutobotsSub::SYNC_MISSIONS:
        {
            // No payload. Same as SYNC_QUESTS but for nation/expansion missions.
            luautils::OnBotSyncMissions(PChar);
        }
        break;

        // SET_NM_MODE (0x10) retired — `is_nm` is now always engine-autodetect
        // (Dynamis OR battlefield OR mob:isNM()). Opcode available for reuse.

        case AutobotsSub::FIRE_ALL_WS:
        {
            // No payload. Force-fire every linked bot's configured WS NOW —
            // skip the SC opener/closer/MB-window gates the AI normally
            // imposes. Each bot must still pass the engine's own checks
            // (engaged on a target, >= 1000 TP, WS unlocked).
            luautils::OnBotFireAllWs(PChar);
        }
        break;

        case AutobotsSub::SET_SC_THRESHOLD:
        {
            // Payload: uint8 Which (0=Start, 1=Stop, 2=NoMore) + uint8 Value (0..100).
            // Lua side clamps Value to [0,100]; rejects unknown Which.
            const uint8 which = Payload[0];
            const uint8 value = Payload[1];
            luautils::OnBotSetScThreshold(PChar, which, value);
        }
        break;

        case AutobotsSub::SET_SATA_MODE:
        {
            // Payload: char Name[11] + uint8 Mode (0=Combined, 1=Split). The Lua
            // side rejects bot names that don't belong to the requesting primary.
            const std::string name = safeName(reinterpret_cast<const char*>(Payload), 11);
            const uint8       mode = Payload[11];
            luautils::OnBotSetSataMode(PChar, name, mode);
        }
        break;

        case AutobotsSub::SET_CASUAL_NUKE_ROTATION:
        {
            // Payload: char Name[11] + uint8 Rotation (1..6 spells, 0 = All).
            const std::string name  = safeName(reinterpret_cast<const char*>(Payload), 11);
            const uint8       value = Payload[11];
            luautils::OnBotSetCasualNukeRotation(PChar, name, value);
        }
        break;

        case AutobotsSub::SET_CASUAL_NUKE_MB_MODE:
        {
            // Payload: char Name[11] + uint8 Mode (0 = exclude, 1 = include).
            const std::string name = safeName(reinterpret_cast<const char*>(Payload), 11);
            const uint8       mode = Payload[11];
            luautils::OnBotSetCasualNukeMbMode(PChar, name, mode);
        }
        break;

        case AutobotsSub::TANK_NUDGE:
        {
            // Payload: char Name[11] + uint8 Direction (0=forward, 1=backward).
            // Snaps the named bot ±1y along the vector toward its current engaged
            // target. No-op if the bot isn't engaged, isn't owned by the primary,
            // or has no target. Lua side does all validation.
            const std::string name      = safeName(reinterpret_cast<const char*>(Payload), 11);
            const uint8       direction = Payload[11];
            luautils::OnBotTankNudge(PChar, name, direction);
        }
        break;

        case AutobotsSub::TANK_WALK_TO_ME:
        {
            // Payload: char Name[11]. Snaps the named bot to the primary's
            // current xyz. Used to recover a stuck/out-of-position tank or to
            // pass aggro at the primary's feet. Same caveat as TANK_NUDGE:
            // next ai_move tick may reposition the bot per its role.
            const std::string name = safeName(reinterpret_cast<const char*>(Payload), 11);
            luautils::OnBotTankWalkToMe(PChar, name);
        }
        break;

        case AutobotsSub::SET_PULLER:
        {
            // Payload: char Name[11]. Empty name clears the puller selection
            // (alliance.pullerCharId = 0). Server resolves name → charId in Lua
            // and validates ownership.
            const std::string name = safeName(reinterpret_cast<const char*>(Payload), 11);
            luautils::OnBotSetPuller(PChar, name);
        }
        break;

        case AutobotsSub::SET_PULLER_RANGE:
        {
            // Payload: uint8 RangeYalms (0..255). Lua setter clamps to
            // [5, 255] — full uint8 range, so players can do absurd
            // zone-spanning pulls if they want.
            const uint8 range = Payload[0];
            luautils::OnBotSetPullerRange(PChar, range);
        }
        break;

        case AutobotsSub::SET_PULLER_CON_RANGE:
        {
            // Payload: uint8 MinCon + uint8 MaxCon. Both correspond to
            // EXPCHAIN values (0=TW, 1=EP, 2=DC, 3=EM, 4=T, 5=VT, 6=IT).
            // Lua clamps each to [0,6] and swaps if min > max.
            const uint8 minCon = Payload[0];
            const uint8 maxCon = Payload[1];
            luautils::OnBotSetPullerConRange(PChar, minCon, maxCon);
        }
        break;

        case AutobotsSub::SET_PULLER_RESUME_MPP:
        {
            // Payload: uint8 Mpp (0..100) — minimum heal-role MP% before the
            // puller resumes pulling the next mob. Lua clamps to [0, 100].
            const uint8 mpp = Payload[0];
            luautils::OnBotSetPullerResumeMpp(PChar, mpp);
        }
        break;

        case AutobotsSub::REQUEST_PULLER_NAMES:
        {
            // No payload. Server scans within 255y of alliance.campAnchor,
            // groups mobs by name, sorts top 20 by count, pushes S2C 0x1A3.
            luautils::OnBotRequestPullerNames(PChar);
        }
        break;

        case AutobotsSub::GIVE_SIGNET:
        {
            // No payload. Cascades the standard nation-guard signet grant
            // (xi.conquest.overseerOnEventFinish path) to the primary + every
            // owned headless. Each member's own nation/rank drive their
            // individual duration formula, matching "as though they had
            // talked to their own nation's guard."
            luautils::OnBotGiveSignet(PChar);
        }
        break;

        case AutobotsSub::SET_HEAL_SCOPE:
        {
            // Payload: char Name[11] + uint8 Mode (0=party / 1=allianceAssist /
            // 2=allianceMain). Per-bot healing-scope toggle for role_heal.
            // Lua side validates ownership and ignores other-primary bots.
            const std::string name = safeName(reinterpret_cast<const char*>(Payload), 11);
            const uint8       mode = Payload[11];
            luautils::OnBotSetHealScope(PChar, name, mode);
        }
        break;

        case AutobotsSub::SET_AGGRO_MODE:
        {
            // Payload: uint8 Mode (0=Off / 1=Full / 2=Engaged). Alliance-wide
            // setting — replaces the old static singleplayer.HEADLESS_MOB_AGGRO.
            // Lua side cascades to every owned headless's m_aggroMode (via the
            // setAggroMode binding) so shouldSkipMobAggro picks it up on the
            // next aggro tick without a Lua roundtrip.
            const uint8 mode = Payload[0];
            luautils::OnBotSetAggroMode(PChar, mode);
        }
        break;

        case AutobotsSub::SET_ADD_CONTROL_MODE:
        {
            // Payload: char Name[10] + uint8 Mode (0=provoke, 1=flash, 2=both).
            // PLD-only per-bot tank toggle: decides which tool the bot uses
            // on peelable adds. Eligibility (job + has Flash) is enforced
            // client-side before the dropdown renders, so the server just
            // trusts the name + mode and writes the per-bot state.
            const std::string name = safeName(reinterpret_cast<const char*>(Payload), 10);
            const uint8       mode = Payload[10];
            luautils::OnBotSetAddControlMode(PChar, name, mode);
        }
        break;

        case AutobotsSub::SET_STUN_MODE:
        {
            // Payload: uint8 Mode (0=always, 1=window). Alliance-wide setting -
            // decides whether the stun interrupt window stays open until a
            // stunner fires ('always', default) or strictly tracks the mob's
            // actual WS castTime ('window'). Replaces the legacy
            // BOT_STUN_PERSIST_UNTIL_FIRED settings flag.
            const uint8 mode = Payload[0];
            luautils::OnBotSetStunMode(PChar, mode);
        }
        break;

        case AutobotsSub::SET_MULTI_ENGAGE_MODE:
        {
            // Payload: uint8 Mode (0=off/single-engage legacy, 1=on/per-party
            // targets). Alliance-wide setting (#173). When flipped from 0→1,
            // the Lua side seeds all 3 partyAssistTargetId slots from the
            // current alliance target. When flipped 1→0, per-party state is
            // cleared and alliance reverts to single-mob behavior.
            const uint8 mode = Payload[0];
            luautils::OnBotSetMultiEngageMode(PChar, mode);
        }
        break;

        case AutobotsSub::SET_PULLER_PAUSED:
        {
            // Payload: uint8 Paused (0=running, 1=paused). Alliance-wide toggle
            // gating puller's IDLE→SCOUTING transition. Doesn't cancel a pull
            // already in flight (SCOUTING/PULLING/RETURNING/HANDOFF continue
            // until natural completion). Fresh set_puller assignments start
            // paused by default; user hits Start to begin pulling.
            const uint8 paused = Payload[0];
            luautils::OnBotSetPullerPaused(PChar, paused);
        }
        break;

        case AutobotsSub::SET_THF_RA_DELAY:
        {
            // Payload: char Name[10] + uint8 DelaySec. THF-specific cadence
            // for the utility ranged-attack throw (Bully timing on a slow
            // RA). Was hardcoded to 15s in role_melee state; now exposed on
            // the Status card combo. 0 = "Off" (THF skips RA entirely).
            // Eligibility (job + level) is enforced client-side before the
            // dropdown renders, so the server just trusts the name + delay
            // and writes the per-bot state.
            const std::string name = safeName(reinterpret_cast<const char*>(Payload), 10);
            const uint8       sec  = Payload[10];
            luautils::OnBotSetThfRaDelay(PChar, name, sec);
        }
        break;

        case AutobotsSub::SET_ROLE_AI_MODE:
        {
            // Payload: uint8 Role + uint8 Type + uint8 Mode. Role-AI policy
            // setter — alliance-wide, 5 roles × 3 types matrix.
            //   Role: 0=tank, 1=melee, 2=heal, 3=rdm, 4=nuke
            //   Type: 0=hp, 1=mp, 2=status
            //   Mode: 0=off, 1=nm-only, 2=always
            // Lua handler validates ranges and writes
            // xi.singleplayer.bots.alliance.rolePolicy[role][type] = mode.
            const uint8 role = Payload[0];
            const uint8 type = Payload[1];
            const uint8 mode = Payload[2];
            luautils::OnRoleAiSetMode(PChar, role, type, mode);
        }
        break;

        case AutobotsSub::SET_ROLE_STATUS_FLAG:
        {
            // Payload: uint8 Role + uint8 StatusKey + uint8 On. Per-status
            // checkbox under each role's Status section. StatusKey is the
            // index into the role_policy.STATUS_LIST table (Lua side owns
            // the canonical list).
            const uint8 role      = Payload[0];
            const uint8 statusKey = Payload[1];
            const uint8 on        = Payload[2];
            luautils::OnRoleAiSetStatusFlag(PChar, role, statusKey, on != 0);
        }
        break;

        case AutobotsSub::SYNC_TELEPORTS:
        {
            // No payload. Mirrors Sync Quests / Sync Missions: cascade
            // primary's full teleport bitfields (all 13 TELEPORT_TYPE
            // values — homepoints, survival guides, waypoints, eschan,
            // abyssea conflux, runic portal, past maw, campaign, outposts)
            // onto every linked headless. Server replies with S2C 0x1A3
            // SYNC_ACK kind=2 so the addon clears its in-flight guard.
            luautils::OnBotSyncTeleports(PChar);
        }
        break;

        case AutobotsSub::SET_BRD_SONG_ROSTER:
        {
            // Payload layout (uses the bumped 32-byte Payload[] from this
            // packet — older 12-byte payload couldn't fit 4 uint16s + name):
            //   char Name[10]            : bytes  0-9   target BRD bot
            //   uint8 Reserved[2]        : bytes 10-11  padding to align uint16s
            //   uint16 Slot0SpellId      : bytes 12-13  front_minuet override
            //   uint16 Slot1SpellId      : bytes 14-15  front_madrigal override
            //   uint16 Slot2SpellId      : bytes 16-17  back_ballad_a override
            //   uint16 Slot3SpellId      : bytes 18-19  back_ballad_b override
            // Spell ID 0 = "auto" sentinel → role_brd falls through to its
            // existing best_tier() logic for that slot.
            const std::string name = safeName(reinterpret_cast<const char*>(Payload), 10);
            const uint16      s0   = static_cast<uint16>(Payload[12]) | (static_cast<uint16>(Payload[13]) << 8);
            const uint16      s1   = static_cast<uint16>(Payload[14]) | (static_cast<uint16>(Payload[15]) << 8);
            const uint16      s2   = static_cast<uint16>(Payload[16]) | (static_cast<uint16>(Payload[17]) << 8);
            const uint16      s3   = static_cast<uint16>(Payload[18]) | (static_cast<uint16>(Payload[19]) << 8);
            luautils::OnBotSetBrdSongRoster(PChar, name, s0, s1, s2, s3);
        }
        break;

        case AutobotsSub::SET_SMN_AVATAR:
        {
            // Payload layout (uses the 32-byte Payload[]):
            //   char   Name[10]      : bytes  0-9   target SMN bot
            //   uint8  Reserved[2]   : bytes 10-11  padding
            //   uint16 AvatarSpellId : bytes 12-13  summon spell ID
            // Spell ID 0 = "auto" sentinel → role_smn falls back to Carbuncle.
            const std::string name     = safeName(reinterpret_cast<const char*>(Payload), 10);
            const uint16      spellId  = static_cast<uint16>(Payload[12]) | (static_cast<uint16>(Payload[13]) << 8);
            luautils::OnBotSetSmnAvatar(PChar, name, spellId);
        }
        break;

        default:
            ShowDebug(fmt::format("HEADLESS_COMMAND: unknown AUTOBOTS subcommand 0x{:02x}", Subcommand));
            break;
    }
}
