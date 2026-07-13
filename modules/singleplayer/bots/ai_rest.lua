-----------------------------------
-- Per-headless auto-rest behaviour.
--
-- ai_rest owns two things:
--   1. The player override (Heal On/Off button — highest priority).
--   2. Camp-passive auto-rest (fires when the override isn't active).
--
-- Override — heal_override='force_on' (Heal On button): stay seated
--   until cleared or combat starts. Combat preempts because the engine
--   refuses HEALING while engaged.
--
-- Camp-passive sit — alliance in camp formation, primary not fighting,
--   no awake adds. Casters + PLDs + DRK sit regardless of HP/MP so
--   they're already resting when the next pull lands. Stand-up is
--   delegated to the role-specific rest managers so we reuse their
--   existing MP-topoff thresholds:
--     * process_pre_cast_checks in ai_magic — mages
--         (MP-topoff / SC-close / urgent-cure paths)
--     * role_tank — PLDs (MP-topoff)
--
--   Who sits in camp:
--     * All mage roles (Healer / Nuker / Rdm / Brd / Smn)
--     * Role.Tank PLD (heavy MP use: Flash / Cures / Enlight etc.)
--     * Role.Melee DRK (Souleater / Absorbs / Weapon Bash all draw on MP)
--
--   Who stands in camp (sitting is visual noise for jobs whose
--   in-combat MP use doesn't warrant a topoff):
--     * Role.Tank NIN (main-tank NIN)
--     * All other Role.Melee jobs (WAR / MNK / THF / RNG / SAM / DRG /
--       BST / PUP / DNC / RUN, plus NIN off-tank)
--
-- The Heal On/Off buttons (0x176 AUTOBOTS SET_HEAL_MODE) drive the
-- override:
--   Heal On  → heal_override='force_on'. Bot stays seated.
--   Heal Off → heal_override=nil, strip HEALING once. Auto-rest resumes;
--              if camp-passive is active the bot re-sits next tick, which
--              is intended — Heal Off releases the lock, not the logic.
--
-- The SET_HEAL_MODE packet carries an optional bot name; empty -> apply
-- to every owned headless, non-empty -> apply to that single bot only.
-- See set_alliance_heal_mode below for the dispatch.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_rest')

xi              = xi or {}
xi.singleplayer.bots.ai_rest    = xi.singleplayer.bots.ai_rest or {}
local ai_rest  = xi.singleplayer.bots.ai_rest

-- Sit/stand flicker prevention (#210). After ai_move stamps lastMovedMs on
-- the shared bot state, ai_rest refuses to re-add HEALING for this many ms.
-- 2.5s is a few ticks — enough to absorb a small followee drift without
-- the bot trying to sit again, but not so long the bot stays standing for
-- ages after the assist parks.
local REST_GRACE_MS     = 2500

local function ms_now()
    return math.floor(os.time() * 1000 + (os.clock() % 1.0) * 1000)
end

-- Release any live SMN pet before sitting the master. Perpetuation drains
-- MP while HEALING is active, so seating a SMN with a pet out is a dead-
-- end — MP never recovers. Returns true when a release was queued this
-- tick; caller bails so ai_rest re-evaluates next tick with no pet in
-- the picture. Guarded on the smn module being loaded.
local function release_pet_before_sit(bot)
    local ai_util = xi.singleplayer.bots.ai_util
    local smn = xi.singleplayer.bots.smn
    if ai_util == nil or ai_util.is_smn == nil then return false end
    if not ai_util.is_smn(bot) then return false end
    if smn == nil or smn.has_pet == nil or smn.release_pet == nil then return false end
    if not smn.has_pet(bot) then return false end
    smn.release_pet(bot)
    return true
end

local function tick_one(bot)
    local s = xi.singleplayer.bots.ensure_bot(bot:getID())

    -- Player override takes precedence. While 'force_on' is set, camp-
    -- passive doesn't run — the user explicitly asked for seated, so no
    -- role gates, no thresholds, no flicker guard. Combat still preempts
    -- because the engine refuses HEALING during engagement.
    if s.heal_override == 'force_on' then
        if bot:isEngaged() then
            if bot:hasStatusEffect(xi.effect.HEALING) then
                bot:delStatusEffect(xi.effect.HEALING)
            end
        elseif not bot:hasStatusEffect(xi.effect.HEALING) then
            -- SMN with pet out: release first, sit next tick. Keeps
            -- perpetuation from draining MP faster than HEALING adds it.
            if release_pet_before_sit(bot) then return end
            bot:addStatusEffect(xi.effect.HEALING, {
                origin = bot,
                tick   = xi.settings.map.HEALING_TICK_DELAY,
                icon   = 0,
                silent = true,
            })
            s.lastHealingAddMs = ms_now()
        end
        return
    end

    -- Engaged → stand up (combat takes precedence over resting).
    if bot:isEngaged() then
        if bot:hasStatusEffect(xi.effect.HEALING) then
            bot:delStatusEffect(xi.effect.HEALING)
        end
        return
    end

    -- Camp-passive: alliance is settled in camp formation, primary isn't
    -- fighting anything, no awake adds on us.
    --
    -- Only MP-relevant jobs participate: all caster roles (Healer /
    -- Nuker / Rdm / Brd / Smn), PLD tanks (heavy MP use for Flash /
    -- Cures / Enlight etc.), and DRK melees (Souleater / Absorbs /
    -- Weapon Bash all draw on MP). Other tanks (NIN) and other melees
    -- stay standing — sitting is visual noise for jobs whose in-combat
    -- MP use doesn't warrant a camp topoff.
    --
    -- Stand-up from camp-passive is delegated to the role-specific rest
    -- managers (process_pre_cast_checks for mages, role_tank for PLDs)
    -- so we reuse their existing MP-topoff thresholds.
    local ai_util  = xi.singleplayer.bots.ai_util
    local magic    = xi.singleplayer.bots.magic
    local alliance = xi.singleplayer.bots.alliance
    local primary  = bot:isHeadless() and GetPlayerByID(bot:getParentCharId()) or bot
    local Role     = xi.singleplayer.bots.Role
    local job      = ai_util and ai_util.jobs and ai_util.jobs[bot:getMainJob()] or nil
    local role     = s.role
    local restsInCamp =
        role == Role.Healer or role == Role.Nuker or role == Role.Rdm
        or role == Role.Brd    or role == Role.Smn
        or (role == Role.Tank  and job == 'PLD')
        or (role == Role.Melee and job == 'DRK')
    local inCampPassive =
        restsInCamp
        and alliance ~= nil
        and alliance.walkingFormation == 'camp'
        and ai_util and ai_util.combat_active and not ai_util.combat_active(primary)
        and magic and magic.get_count_of_awake_adds
            and magic.get_count_of_awake_adds(bot) == 0

    -- Camp-passive MP gate: don't re-sit a nearly-full-MP mage. Combined
    -- with ai_magic.process_pre_cast_checks' "MP > 95 stand up" branch
    -- (and role_tank's PLD equivalent), this gives hysteresis with a 15%
    -- deadband so mages sit through most of their MP recovery but don't
    -- flicker at the top:
    --   MP < 80% → sit (camp-passive triggers this branch)
    --   MP > 95% → stand (role tick stops rest; here we refuse to re-add
    --                     HEALING so it stays standing)
    --   80–95%  → whatever state you're in, stay put
    local mpPct       = ai_util.current_mp_percent(bot)
    local mpNeedsRest = mpPct < 80
    if inCampPassive and not bot:hasStatusEffect(xi.effect.HEALING) and mpNeedsRest then
        -- Same-tick flicker guard: if ai_move just stepped this bot,
        -- don't immediately re-sit. Lets the move complete cleanly
        -- and avoids the sit/stand visual oscillation when the
        -- followee is parked right at the rest-comfort boundary.
        local lastMoved = s.lastMovedMs or 0
        local now = ms_now()
        if lastMoved > 0 and (now - lastMoved) < REST_GRACE_MS then
            return
        end
        -- SMN with pet out: release first, sit next tick.
        if release_pet_before_sit(bot) then return end
        bot:addStatusEffect(xi.effect.HEALING, {
            origin = bot,
            tick   = xi.settings.map.HEALING_TICK_DELAY,
            icon   = 0,
            silent = true,
        })
        s.lastHealingAddMs = now
    end
end

-- Called from 0x176 AUTOBOTS SET_HEAL_MODE via luautils::OnBotSetHealMode.
--
-- Targeting:
--   botName == '' or nil -> apply to EVERY headless owned by primary
--                           (alliance-wide). This is the "Heal On/Off"
--                           one-click button behavior.
--   botName non-empty    -> apply to that single owned headless only.
--                           No-op if the named bot doesn't exist or is
--                           owned by a different primary.
--
-- Behavior per affected bot:
--   on=true  -> heal_override='force_on'. Bot stays seated until cleared.
--   on=false -> heal_override=nil, strip HEALING once. Auto-rest resumes:
--               if camp-passive is active the bot re-sits next tick.
--
-- Replaces the prior (on, mages_only) signature. The mages-only filter was
-- a narrow special case with no remaining UI consumer; callers that want a
-- per-role subset now build the list client-side and emit one packet per bot.
function ai_rest.set_alliance_heal_mode(primary, on, botName)
    if primary == nil then return end
    local primaryId = primary:getID()
    local target    = (type(botName) == 'string' and botName ~= '') and botName or nil

    local function apply(member)
        local s = xi.singleplayer.bots.ensure_bot(member:getID())
        if on then
            s.heal_override = 'force_on'
        else
            s.heal_override = nil
            if member:hasStatusEffect(xi.effect.HEALING) then
                member:delStatusEffect(xi.effect.HEALING)
            end
        end
    end

    local count = 0
    for _, member in ipairs(primary:getAlliance() or {}) do
        if member.isHeadless and member:isHeadless()
           and member.getParentCharId and member:getParentCharId() == primaryId
           and (target == nil or member:getName() == target)
        then
            apply(member)
            count = count + 1
            if target ~= nil then break end  -- single-bot fast exit
        end
    end

    if target ~= nil and count == 0 then
        printf(string.format('ai_rest.set_alliance_heal_mode: no owned bot "%s"', target))
    else
        printf(string.format('ai_rest.set_alliance_heal_mode: %d bot(s) -> heal=%s%s',
            count, tostring(on),
            target and string.format(' (target=%s)', target) or ' (all)'))
    end
end

m:addOverride('xi.singleplayer.bots.onBotTick', function(player, botMode)
    super(player, botMode)
    if player ~= nil and player.isHeadless and player:isHeadless() then
        tick_one(player)
    end
end)

return m
