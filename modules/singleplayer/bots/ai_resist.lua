-----------------------------------
-- ai_resist (#208) — smart back-off for high-resist mobs after N failed
-- enfeebles. Tracks (bot, mob, spell) resist counters via onActionResult
-- and blacklists spell × mob pairs once consecutive failures reach a
-- threshold.
--
-- WHY THIS EXISTS:
--   The engine's resist-rank mods (Mod::SILENCE_RES_RANK, etc.) only
--   adjust LANDING PROBABILITY — they aren't a hard reject. So a bot
--   facing a Silence-immune NM will happily keep throwing Silence at it
--   forever, burning MP and recast clock. Same pattern for Sleep / Slow /
--   Paralyze / Bind / Blind. We need a Lua-side back-off that detects the
--   resistance behaviorally and stops re-casting.
--
-- DESIGN DECISIONS (locked unless empirical evidence shows otherwise):
--   * Scope: per-bot per-mob per-spell. Different bots may roll differently
--     (Macc gear, INT/MND, level), so the failure shouldn't taint other
--     bots' attempts.
--   * Threshold: 3 consecutive failures. Lower would over-react to
--     unlucky streaks on landable spells; higher means the bot wastes
--     more MP before giving up.
--   * Counter is RESET on a successful land, not just decayed. A spell
--     that occasionally lands stays in the rotation forever.
--   * Mob death clears all bots' counters for that mob — re-pop is fresh.
--   * Bot disengage / target switch does NOT clear — mob may return.
--   * Zone change: alliance state wipes naturally on resummon, no explicit
--     handling here.
--   * No UI in v1. Logging only. The autobots Status tab could surface
--     blacklisted spells later but that's #208 follow-up.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_resist')

xi              = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.ai_resist = xi.singleplayer.bots.ai_resist or {}

local ai_resist = xi.singleplayer.bots.ai_resist

-- After this many consecutive resists / no-effects on the same (mob, spell)
-- the spell is blacklisted for that pair until the mob dies (or until the
-- spell lands once on this mob via another path — which can't happen if we
-- never cast it again, so practically: until the mob dies).
ai_resist.RESIST_THRESHOLD = 3

-- Result messageIDs from src/map/enums/msg_basic.h that indicate the spell
-- failed to land or had no effect on the target. Successful damage / debuff
-- application uses other message IDs (varies by spell family).
local RESIST_MESSAGES = {
    [75]  = true,  -- MagicNoEffect       — <caster>'s <spell> has no effect on <target>
    [85]  = true,  -- MagicResisted        — <target> resists the spell
    [283] = true,  -- TargetNoEffect       — No effect on <target>
    [284] = true,  -- MagicResistedTarget  — <target> resists the effects of the spell
    [655] = true,  -- MagicCompleteResist  — <target> completely resists the spell
}

-- Lazy-init resistance state on the bot's alliance scratch. Keyed by
-- mobId → spellId → consecutive-failure count.
local function ensure_map(bot)
    if bot == nil or bot.getID == nil then return nil end
    local A = xi.singleplayer.bots.alliance
    if A == nil or A.bot == nil then return nil end
    local s = A.bot[bot:getID()]
    if s == nil then return nil end
    s.resistMap = s.resistMap or {}
    return s.resistMap
end

-- Public: should the bot skip this spell against this mob right now?
-- Returns true iff the (bot, mob, spell) failure counter has hit the
-- threshold. Callers (ai_magic.spell_is_up) treat true as "spell
-- effectively unavailable" and fall through to the next candidate.
function ai_resist.should_skip(bot, spellId, mobId)
    if mobId == nil or mobId == 0 or spellId == nil then return false end
    local map = ensure_map(bot)
    if map == nil then return false end
    local mobMap = map[mobId]
    if mobMap == nil then return false end
    return (mobMap[spellId] or 0) >= ai_resist.RESIST_THRESHOLD
end

-- Public: record an attempt's outcome. `succeeded == true` clears the
-- counter for that (mob, spell). `succeeded == false` bumps it; logs once
-- on the transition that pushes it to the threshold.
function ai_resist.record_result(bot, spellId, mobId, succeeded)
    if mobId == nil or mobId == 0 or spellId == nil then return end
    local map = ensure_map(bot)
    if map == nil then return end
    if succeeded then
        if map[mobId] then map[mobId][spellId] = 0 end
        return
    end
    map[mobId] = map[mobId] or {}
    local prev = map[mobId][spellId] or 0
    map[mobId][spellId] = prev + 1
    -- Log once on the rising edge that triggers blacklist. Subsequent
    -- failures (which won't happen since the spell is now skipped) would
    -- otherwise spam.
    if prev + 1 == ai_resist.RESIST_THRESHOLD then
        printf('[ai_resist] %s: blacklisted spell %d on mob %d after %d failure(s)',
            bot:getName(), spellId, mobId, ai_resist.RESIST_THRESHOLD)
    end
end

-- Public: clear every tracked bot's counter for `mobId`. Called by
-- bots_listeners when a tracked mob dies — we don't want stale counters
-- persisting into a re-pop of the same mob ID.
function ai_resist.clear_for_mob(mobId)
    if mobId == nil or mobId == 0 then return end
    local A = xi.singleplayer.bots.alliance
    if A == nil or A.bot == nil then return end
    for _, s in pairs(A.bot) do
        if s.resistMap then s.resistMap[mobId] = nil end
    end
end

-----------------------------------
-- Result hook. Filter to magic-finish category, walk targets/results,
-- classify by messageID. A given action target carries multiple results
-- (main + spike + add-effect); we count "landed" if ANY result indicates
-- a normal hit and "resisted" only if EVERY result is a resist/no-effect.
-- This avoids penalizing a hit-but-spike-resist or partial-land path.
-----------------------------------
m:addOverride('xi.singleplayer.bots.onActionResult', function(actor, action)
    super(actor, action)
    if actor == nil or action == nil then return end
    if action.actiontype ~= xi.action.category.MAGIC_FINISH then return end
    local spellId = action.actionid
    if spellId == nil then return end

    for _, target in ipairs(action.targets or {}) do
        local mobId = target.actorId
        if mobId ~= nil and mobId ~= 0 then
            local anyLanded   = false
            local anyResisted = false
            for _, result in ipairs(target.results or {}) do
                if RESIST_MESSAGES[result.messageID] then
                    anyResisted = true
                else
                    anyLanded = true
                end
            end
            if anyLanded then
                ai_resist.record_result(actor, spellId, mobId, true)
            elseif anyResisted then
                ai_resist.record_result(actor, spellId, mobId, false)
            end
        end
    end
end)

return m
