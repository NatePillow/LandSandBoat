-----------------------------------
-- Server-side port of the client-side library
--
-- Per-character DPS tracker (main char + every headless bot) pushed to the
-- primary client via S2C 0x17C every 2s while the *assist is in combat*.
-- Mages never engage and the primary may not be hitting either, so we gate
-- the push on the assist's combat state — that's the alliance's anchor.
--
-- Single dispatcher: xi.singleplayer.bots.onActionResult fires from C++ in the BATTLE2
-- packet ctor (the universal action chokepoint, 45 call sites all funnel
-- through it). Replaces the three scattered WEAPONSKILL_USE / MAGIC_USE /
-- ABILITY_USE listeners — closes melee, ranged, spike, and add-effect gaps.
--
-- Categories (canonical packet order; matches client-side):
--   1 melee  2 ranged  3 ws  4 magic  5 burst  6 ja
-- Spikes are credited to the TARGET (the one with spikes effect on) since
-- it's their reflected damage. Add-effect damage credits the same category
-- as the parent action (e.g., enspell damage on a swing → CAT_MELEE).
--
-- Active fight time accumulates while alliance_in_combat() is true (driven by
-- assist:isEngaged() + alliance.allianceTarget hysteresis from autoai's ATTACK/DISENGAGE
-- commands). No timeout — explicit signal replaces the legacy client-side
-- IDLE_GAP_MS gap-clipping.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('bots_dps')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.bots_dps = xi.singleplayer.bots.bots_dps or {}
local bots_dps = xi.singleplayer.bots.bots_dps

-- Push cadence to the addon while fight is active.
local PUSH_INTERVAL_MS  = 2000

-- Minimum fight duration credited when a whole fight (engage -> kill ->
-- disengage) happens inside one tick gap — an instant kill on a weak mob. No
-- real active segment gets timed in that case, so without a floor dps would be
-- damage / ~0 = 0. ~1s is a reasonable stand-in for a one-shot engagement.
local MIN_FIGHT_MS      = 1000

-- Category indices (1-based, matches packet category order)
local CAT_MELEE  = 1
local CAT_RANGED = 2
local CAT_WS     = 3
local CAT_MAGIC  = 4
local CAT_BURST  = 5
local CAT_JA     = 6
local CAT_COUNT  = 6

-- xi.action.category values → CAT_*
local ACTION_TO_CATEGORY = {
    [xi.action.category.BASIC_ATTACK]          = CAT_MELEE,
    [xi.action.category.RANGED_FINISH]         = CAT_RANGED,
    [xi.action.category.WEAPONSKILL_FINISH]    = CAT_WS,
    [xi.action.category.MAGIC_FINISH]          = CAT_MAGIC,
    [xi.action.category.JOBABILITY_FINISH]     = CAT_JA,
}

-- MsgBasic IDs that flag the magic result as a magic burst
local MB_MSG_IDS = { [252] = true, [274] = true }

-----------------------------------
-- Per-bot state. state[charId] = {
--   categories[1..6] = { damage, hits, misses }
--   totalDamage
--   combatStartedMs : timestamp of the current combat enter, or 0 when idle
--   combatActiveMs  : accumulated active fight time across previous segments
--   lastPushMs      : last 0x17C send time
--   wasAllianceInCombat : combat-state edge tracker (for final push)
-- }
-----------------------------------
bots_dps.state = bots_dps.state or {}

function bots_dps.destroy_state(botId)
    bots_dps.state[botId] = nil
end


local function new_stat() return { damage = 0, hits = 0, misses = 0 } end

local function ensure_state(charId)
    local s = bots_dps.state[charId]
    if s == nil then
        s = {
            categories          = {},
            totalDamage         = 0,
            combatStartedMs     = 0,
            combatActiveMs      = 0,
            lastPushMs          = 0,
            lastPushedTotal     = 0,      -- totalDamage as of the last push()
            wasAllianceInCombat = false,
        }
        for i = 1, CAT_COUNT do s.categories[i] = new_stat() end
        bots_dps.state[charId] = s
    end
    return s
end

-----------------------------------
-- Bump a category by damage. Misses register only the miss counter (damage=0).
-- Active fight time is driven entirely by alliance_in_combat() edges in
-- on_tick now — record_hit no longer touches timing state.
-----------------------------------
local function record_hit(s, category, damage)
    if damage <= 0 then
        s.categories[category].misses = s.categories[category].misses + 1
        return
    end

    s.categories[category].damage = s.categories[category].damage + damage
    s.categories[category].hits   = s.categories[category].hits + 1
    s.totalDamage                 = s.totalDamage + damage
end

-- Active time = sum of completed combat segments + the in-flight segment if
-- alliance is currently in combat. combatStartedMs == 0 means idle.
local function elapsed_ms(s)
    if s.combatStartedMs == 0 then return s.combatActiveMs end
    return s.combatActiveMs + (xi.singleplayer.bots.ai_util.get_ms_since_epoch() - s.combatStartedMs)
end

function bots_dps.reset(charId)
    bots_dps.state[charId] = nil
end

-----------------------------------
-- Universal action result dispatcher. Called from C++ once per finalized
-- action_t (in the BATTLE2 packet ctor). Routes by actiontype, sums damage
-- across all targets/results, handles spikes and add-effects.
--
-- Skips actions by non-tracked actors (mobs, etc.) — task #54 will widen
-- this to include mob actors for incoming-DPS tracking.
-----------------------------------
m:addOverride('xi.singleplayer.bots.onActionResult', function(actor, action)
    super(actor, action)
    if actor == nil or action == nil then return end

    local actorId = actor:getID()
    local s = bots_dps.state[actorId]
    if s == nil then return end

    -- Magic uses a per-result lookup since each result might or might not be
    -- a magic burst; cache the base category and override per-result.
    local baseCat = ACTION_TO_CATEGORY[action.actiontype]
    if baseCat == nil then return end

    local targets = action.targets
    if targets == nil then return end

    for _, target in ipairs(targets) do
        local results = target.results
        if results ~= nil then
            for _, result in ipairs(results) do
                local param           = result.param or 0
                local messageID       = result.messageID or 0
                local spikesParam     = result.spikesParam or 0
                local addEffectParam  = result.addEffectParam or 0

                -- Main damage (or miss) for the actor
                local cat = baseCat
                if baseCat == CAT_MAGIC and MB_MSG_IDS[messageID] then
                    cat = CAT_BURST
                end
                record_hit(s, cat, param)

                -- Add-effect damage stacks into the same category as the main
                -- action (e.g., enspell extra damage on a melee swing).
                if addEffectParam > 0 then
                    s.categories[cat].damage = s.categories[cat].damage + addEffectParam
                    s.totalDamage            = s.totalDamage + addEffectParam
                end

                -- Spikes: damage REFLECTED BACK to the actor by the target.
                -- Credit to the TARGET's state (they're the one whose spikes
                -- effect dealt it). Only counts if the target is being tracked.
                if spikesParam > 0 then
                    local targetState = bots_dps.state[target.actorId]
                    if targetState ~= nil then
                        -- Treat as a 'melee' category contribution since spikes
                        -- are reactive defensive damage during melee combat —
                        -- client-side lumped these under a separate 'sp' bucket
                        -- which we collapse into CAT_MELEE here for the per-
                        -- bot 6-category packet shape. (Could split into a
                        -- 7th category later if needed.)
                        targetState.categories[CAT_MELEE].damage = targetState.categories[CAT_MELEE].damage + spikesParam
                        targetState.totalDamage                  = targetState.totalDamage + spikesParam
                    end
                end
            end
        end
    end
end)

-----------------------------------
-- Combat-state gate: derived from the *assist's* engagement state, not the
-- bot's own (mages never engage) and not the primary's (primary may not be
-- attacking). The assist is the alliance's melee anchor — its combat state
-- is the authoritative "is the alliance fighting" signal.
-----------------------------------
local function alliance_in_combat(primary)
    if primary == nil then return false end
    local assist = xi.singleplayer.bots.get_assist_entity() or primary
    if assist:isEngaged() then return true end
    if xi.singleplayer.bots.get_alliance_target_id() ~= 0 then return true end
    return false
end

-----------------------------------
-- Push the current snapshot to the primary client. isFinal=true marks the
-- disengage summary so the addon knows the fight ended.
-----------------------------------
local function push(charId, primary, isFinal)
    local s = ensure_state(charId)
    BotPushDps(
        primary,
        charId,
        isFinal,
        s.totalDamage,
        elapsed_ms(s),
        s.categories
    )
    s.lastPushMs      = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    s.lastPushedTotal = s.totalDamage
end

-----------------------------------
-- Per-char tick. Determines push cadence relative to alliance combat state.
-- Tracks BOTH the main char and headless bots — main char's tick fires on
-- the same OnBotTick path when their botMode != Off.
-----------------------------------
local function on_tick(char)
    local primary
    local parentId = char:getParentCharId()
    if parentId == 0 then
        primary = char
    else
        primary = GetPlayerByID(parentId)
        if primary == nil then return end
    end

    local charId = char:getID()
    local s = ensure_state(charId)
    local inCombat = alliance_in_combat(primary)
    local now = xi.singleplayer.bots.ai_util.get_ms_since_epoch()

    if inCombat then
        if not s.wasAllianceInCombat then
            -- Combat edge enter: open a new active-time segment.
            s.combatStartedMs = now
            push(charId, primary, false)  -- fight just started — fresh baseline
        elseif (now - s.lastPushMs) >= PUSH_INTERVAL_MS then
            push(charId, primary, false)
        end
    else
        if s.wasAllianceInCombat then
            -- Combat edge exit: close the active-time segment so elapsed_ms
            -- freezes at the final summary. push() reads in-flight time, so
            -- flush BEFORE pushing so the final value matches what's frozen.
            if s.combatStartedMs ~= 0 then
                s.combatActiveMs  = s.combatActiveMs + (now - s.combatStartedMs)
                s.combatStartedMs = 0
            end
            push(charId, primary, true)   -- final summary, then go silent
        elseif s.totalDamage > s.lastPushedTotal then
            -- Damage landed since the last push but no combat edge was ever
            -- sampled: the whole fight (engage -> kill -> disengage) happened
            -- between two ~400ms ticks — a one-hit kill on a weak mob. Credit a
            -- minimum fight duration so dps isn't damage/0, then flush. Without
            -- this the recorded damage sits unpushed forever and the addon shows
            -- 0 dps / 0 dmg when fighting only instant-kill enemies.
            s.combatActiveMs = s.combatActiveMs + MIN_FIGHT_MS
            push(charId, primary, true)
        end
    end
    s.wasAllianceInCombat = inCombat
end

-----------------------------------
-- Wire into the per-char tick. State is allocated lazily on first tick;
-- the dispatcher early-returns for actors with no state, so unrelated
-- entity actions (mobs etc.) cost only a hash lookup.
-----------------------------------
m:addOverride('xi.singleplayer.bots.onBotTick', function(player, botMode)
    super(player, botMode)
    if player == nil then return end
    ensure_state(player:getID())
    on_tick(player)
end)

return m
