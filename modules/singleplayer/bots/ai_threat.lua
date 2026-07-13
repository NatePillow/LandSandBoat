-----------------------------------
-- Alliance threat assessment. Recomputes from the engine on demand
-- (zone:getMobs(), mob:getTarget(), HPP) with a one-tick alliance-wide cache
-- in off_target_threats, so there's no long-lived bookkeeping to invalidate
-- when bots die/zone.
--
-- Replaces the old primary.activeAdds / ai_ability.state.newAdds-activeAdds
-- triplet, which was written from the action-listener fan-out and required
-- target-death cleanup. Add detection is a ZONE SCAN for engaged mobs targeting
-- an alliance member — NOT primary:getNotorietyList(), which only populates in
-- mutual combat and so missed mobs one-sidedly aggroing an idle party (see
-- off_target_threats). We project the priority chain onto that at decision time.
--
-- Priority chain (highest = peel from, lowest = peel onto):
--   1. tank
--   2. healthy melee  (HP >= 50%)
--   3. medium melee   (HP in 25-50%)
--   4. low-HP melee   (HP <  25%)
--   5. mage / support
--
-- Peel rule: each tier peels mobs off tiers strictly BELOW itself, with one
-- exception — a medium-HP melee won't peel off a low-HP melee (would take
-- a hit they can't afford), only off mages. This matches the original
-- discussion in autobots.lua.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_threat')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.threat = xi.singleplayer.bots.threat or {}
local ai_threat = xi.singleplayer.bots.threat

local TIER_TANK         = 1
local TIER_MELEE_HIGH   = 2
local TIER_MELEE_MED    = 3
local TIER_MELEE_LOW    = 4
local TIER_MAGE         = 5

ai_threat.TIER_TANK       = TIER_TANK
ai_threat.TIER_MELEE_HIGH = TIER_MELEE_HIGH
ai_threat.TIER_MELEE_MED  = TIER_MELEE_MED
ai_threat.TIER_MELEE_LOW  = TIER_MELEE_LOW
ai_threat.TIER_MAGE       = TIER_MAGE

-- Maps an alliance member (CCharEntity) to a priority tier. Uses roleMap when
-- the bot has an assigned role; falls back to job classification for the
-- primary (the human player) and any bot with no role yet.
function ai_threat.member_tier(member)
    if member == nil then return TIER_MAGE end
    local roleMap = xi.singleplayer.bots.alliance and xi.singleplayer.bots.alliance.roleMap or {}
    local role    = roleMap[member:getID()]
    local hpp     = member:getHPP()

    if role == xi.singleplayer.bots.Role.Tank then
        return TIER_TANK
    elseif role == xi.singleplayer.bots.Role.Melee then
        if hpp >= 50 then return TIER_MELEE_HIGH end
        if hpp >= 25 then return TIER_MELEE_MED  end
        return TIER_MELEE_LOW
    elseif role == xi.singleplayer.bots.Role.Healer
        or role == xi.singleplayer.bots.Role.Nuker
        or role == xi.singleplayer.bots.Role.Rdm
        or role == xi.singleplayer.bots.Role.Skillup
        or role == xi.singleplayer.bots.Role.Brd
        or role == xi.singleplayer.bots.Role.Smn then
        return TIER_MAGE
    end

    -- No role assigned (primary, idle bot, etc.) — classify by job.
    local job = xi.singleplayer.bots.ai_util.jobs[member:getMainJob()]
    if job == 'PLD' or job == 'NIN' or job == 'RUN' then
        return TIER_TANK
    elseif job == 'WAR' or job == 'MNK' or job == 'THF' or job == 'DRK'
        or job == 'BST' or job == 'SAM' or job == 'DRG' or job == 'BLU'
        or job == 'COR' or job == 'PUP' or job == 'DNC' then
        if hpp >= 50 then return TIER_MELEE_HIGH end
        if hpp >= 25 then return TIER_MELEE_MED  end
        return TIER_MELEE_LOW
    end
    return TIER_MAGE
end

function ai_threat.bot_tier(bot)
    return ai_threat.member_tier(bot)
end

-- Reads the singular alliance target id (xi.singleplayer.bots.alliance.allianceTarget).
local function alliance_target_id(_)
    return xi.singleplayer.bots.get_alliance_target_id and xi.singleplayer.bots.get_alliance_target_id() or 0
end

function ai_threat.alliance_target(bot)
    local id = alliance_target_id(bot)
    if id == 0 then return nil end
    return GetEntityByID(id)
end

-- Builds a serverId -> CCharEntity map of the bot's alliance, for fast
-- "is this mob's target one of ours?" lookups.
local function alliance_index(bot)
    local idx = {}
    for _, member in ipairs(bot:getAlliance() or {}) do
        idx[member:getID()] = member
    end
    return idx
end

-- Returns a list of { mob = ..., victim = ..., victimTier = ... } records for
-- every mob in the zone that's engaged and targeting an alliance member,
-- excluding the alliance target itself ("the main mob"). Filters: alive, not
-- asleep, engaged, battle target is in the alliance.
--
-- Uses a ZONE SCAN, not primary:getNotorietyList(): notoriety only populates
-- during MUTUAL combat, so a mob one-sidedly aggroing an idle party (especially
-- the human primary) never appeared on the list — confirmed via triage
-- 2026-07-11 (a Wraith engaged on the idle primary had notoCount=0 everywhere
-- but showed up in the zone scan). The scan catches engaged-on-ally regardless
-- of enmity bookkeeping, and also finds adds attacking a BOT (the old notoriety
-- path only ever read the primary's list, so bot-only adds were invisible too).
--
-- Cached alliance-wide for one tick: the result is identical for every bot in
-- the alliance and this is called per-bot (ensure_alliance_target + peelable_
-- for). Consumers only sort/read the list, never insert/remove, so sharing the
-- table is safe.
function ai_threat.off_target_threats(bot)
    local A   = xi.singleplayer.bots.alliance
    local now = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    if A and A._offThreats and (now - (A._offThreatsMs or 0)) < 250 then
        return A._offThreats
    end

    local allianceTargetId = alliance_target_id(bot)
    local allies = alliance_index(bot)
    local out    = {}
    local zone   = bot.getZone and bot:getZone()
    if zone and zone.getMobs then
        for _, mob in ipairs(zone:getMobs() or {}) do
            if mob ~= nil
               and mob:getID() ~= allianceTargetId
               and not mob:isDead()
               and not xi.singleplayer.bots.ai_util.is_asleep(mob)
               and mob:isEngaged() then
                local victim = mob.getTarget and mob:getTarget() or nil
                if victim ~= nil and allies[victim:getID()] ~= nil then
                    table.insert(out, {
                        mob        = mob,
                        victim     = victim,
                        victimTier = ai_threat.member_tier(victim),
                    })
                end
            end
        end
    end

    if A ~= nil then
        A._offThreats   = out
        A._offThreatsMs = now
    end
    return out
end

-- "Should I peel this threat?" — encodes the priority-chain rule:
--   tank          : peel anything not on the tank
--   healthy melee : peel mobs off medium melee, low melee, and mages
--   medium melee  : peel mobs off mages only (not low melee — they can't
--                   absorb the redirect)
--   low melee     : never peel (you'd die)
--   mage          : never peel
local function should_peel(botTier, victimTier)
    if botTier == TIER_TANK then
        return victimTier > TIER_TANK
    elseif botTier == TIER_MELEE_HIGH then
        return victimTier >= TIER_MELEE_MED
    elseif botTier == TIER_MELEE_MED then
        return victimTier == TIER_MAGE
    end
    return false
end

-- Returns the first off-target threat THIS bot should peel, or nil if none.
-- Sort order picks the most-vulnerable victim first (higher tier number =
-- weaker — we sort descending so mages-as-victims come first).
function ai_threat.peelable_for(bot)
    local botTier = ai_threat.bot_tier(bot)
    local threats = ai_threat.off_target_threats(bot)
    if #threats == 0 then return nil end

    table.sort(threats, function(a, b) return a.victimTier > b.victimTier end)
    for _, t in ipairs(threats) do
        if should_peel(botTier, t.victimTier) then return t end
    end
    return nil
end

-- Auto-populates alliance.allianceTarget when it's empty. Only writes when
-- allianceTarget == 0 — a player command always wins.
--
-- Two writers can set allianceTarget:
--   1. Player command (/be-attack) — the user picked the next pull.
--   2. Auto here — nothing was picked. Two sub-cases, in priority order:
--      (a) The assist character is engaged: their target IS the main mob.
--          Covers the "assist pulled something, fan out" case.
--      (b) A mob is swinging at the alliance: promote the threat with the
--          most-vulnerable victim (mage > low melee > medium > healthy >
--          tank) so adds going for back-line get focused first.
function ai_threat.ensure_alliance_target(bot)
    if xi.singleplayer.bots.alliance == nil then return end
    if (xi.singleplayer.bots.alliance.allianceTarget or 0) ~= 0 then return end

    local assist = xi.singleplayer.bots.get_assist_entity and xi.singleplayer.bots.get_assist_entity() or nil
    if assist ~= nil and assist:isEngaged() then
        local at = assist.getTarget and assist:getTarget() or nil
        if at ~= nil and not at:isDead() then
            xi.singleplayer.bots.alliance.allianceTarget = at:getID()
            return
        end
    end

    local threats = ai_threat.off_target_threats(bot)
    if #threats == 0 then return end
    table.sort(threats, function(a, b) return a.victimTier > b.victimTier end)
    xi.singleplayer.bots.alliance.allianceTarget = threats[1].mob:getID()
end

return m
