-----------------------------------
-- Server-side skill-up role. Drives one of two loops while the bot is engaged:
--   "magic"   : cycles a per-bot spell list, casting each as it leaves recast;
--               successful finishes rotate the spell to the back of the queue.
--   "ranged"  : fires a ranged attack at the bot's current target whenever
--               isBotRangedAttacking() reports idle.
--
-- start_magic / start_ranged refuse to activate against an idle bot (return
-- false). The tick body re-checks isEngaged so a mid-fight disengage parks
-- the loop until combat resumes. Already-in-flight casts/shots are skipped.
--
-- Runtime config comes from 0x191 SET_AUTOSKILL via the automog Skill tab,
-- dispatched into role_skillup.set_skillup_for_bot below.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('role_skillup')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.skillup = xi.singleplayer.bots.skillup or {}
local role_skillup = xi.singleplayer.bots.skillup

-- No internal throttle: the server-side AI scheduler ticks role bodies every
-- kLogicUpdateInterval (400ms, map_constants.h). Magic mode self-paces via
-- per-spell recast (next_castable_spell filters hasRecast); ranged mode
-- self-paces via bot:isBotRangedAttacking(). A second poll gate on top of
-- those would only delay our first reaction to a freshly-ready action.
--
-- No default rotation — automog's Skill tab always ships an explicit spell
-- list (the picker enforces non-empty Magic mode). A bot with empty rotation
-- no-ops every tick.

-- Per-bot scratch lives on alliance.bot[charId] (#221).
local function get_state(bot)
    return xi.singleplayer.bots.ensure_bot(bot:getID())
end

-----------------------------------
-- Public API — driven by automog UI / 0x176 dispatch (task #45).
-----------------------------------
-- Returns false if the bot isn't engaged; both start_magic and start_ranged
-- refuse to activate against an idle bot so misuse is loud.
--
-- Skillup is a real role now (Role.Skillup). Start/stop set the bot's role
-- via the canonical onSetRole entry point — the role-module activation
-- framework handles state.active for us. We additionally save the prior role
-- on start so stop() can restore it, preserving the user-expected
-- "turn skillup off and resume what I was doing" behavior from the
-- pre-role-promotion override era.
function role_skillup.start_magic(bot, spellIds)
    if not bot:isEngaged() then return false end
    local botState = xi.singleplayer.bots.get_bot_state(bot)
    local priorRole = botState.role
    xi.singleplayer.bots.onSetRole(bot, xi.singleplayer.bots.Role.Skillup)

    local s = get_state(bot)
    if priorRole ~= xi.singleplayer.bots.Role.Skillup then
        s.priorRole = priorRole
    end
    s.mode         = 'magic'
    s.rotation     = {}
    s.currentIndex = 1
    if type(spellIds) == 'table' then
        for _, id in ipairs(spellIds) do
            if type(id) == 'number' and id > 0 then
                table.insert(s.rotation, id)
            end
        end
    end
    return true
end

function role_skillup.start_ranged(bot)
    if not bot:isEngaged() then return false end
    local botState = xi.singleplayer.bots.get_bot_state(bot)
    local priorRole = botState.role
    xi.singleplayer.bots.onSetRole(bot, xi.singleplayer.bots.Role.Skillup)

    local s = get_state(bot)
    if priorRole ~= xi.singleplayer.bots.Role.Skillup then
        s.priorRole = priorRole
    end
    s.mode = 'ranged'
    return true
end

function role_skillup.stop(bot)
    local s = get_state(bot)
    local priorRole = s.priorRole or xi.singleplayer.bots.Role.Idle
    s.priorRole = nil
    s.mode      = nil
    xi.singleplayer.bots.onSetRole(bot, priorRole)
end

-----------------------------------
-- Called from 0x193 LIST_AUTOSKILL via luautils::OnListAutoskill. Re-emits the
-- AUTOSKILL_STATE packet for every bot owned by the requester whose role is
-- Skillup. Used by the role_skillup and autobots addons on load to populate their
-- caches without polling.
-----------------------------------
function role_skillup.push_skillup_state_to(primary)
    if primary == nil then return end
    local primaryId = primary:getID()
    local count = 0
    for _, member in ipairs(primary:getAlliance() or {}) do
        local s = xi.singleplayer.bots.alliance.bot[member:getID()]
        local memberState = xi.singleplayer.bots.get_bot_state(member)
        if s ~= nil and memberState.role == xi.singleplayer.bots.Role.Skillup then
            local owned = (member.getName and member:getName() == primary:getName())
                       or (member.isHeadless and member:isHeadless()
                           and member.getParentCharId and member:getParentCharId() == primaryId)
            if owned then
                local mode = (s.mode == 'ranged') and 1 or 2
                primary:pushAutoskillState(member:getName(), mode)
                count = count + 1
            end
        end
    end
    -- Only log when there's something interesting to report; the no-skillup
    -- case fires every ident heartbeat (~1Hz) and floods the server log otherwise.
    if count > 0 then
        printf(string.format('role_skillup.push_skillup_state_to: re-pushed %d skillup state(s) to %s',
            count, primary:getName()))
    end
end

-----------------------------------
-- Packet-driven entry point (0x191 SET_AUTOSKILL via luautils::OnSetAutoskill).
-- The requesting primary asks to flip a bot's Skillup role on/off and (for
-- mode=2) configures the magic rotation. Ownership: primary themselves OR a
-- headless owned by them. Mode: 0=Off (restore prior role), 1=RA, 2=Magic.
-----------------------------------
function role_skillup.set_skillup_for_bot(primary, botName, mode, spellIdsTbl)
    if primary == nil or botName == nil or botName == '' then return end

    -- Find the target. Allow primary themselves OR a headless owned by them.
    local target = nil
    if botName == primary:getName() then
        target = primary
    else
        for _, m in ipairs(primary:getAlliance() or {}) do
            if m.getName and m:getName() == botName then
                local ok = m.isHeadless and m:isHeadless()
                          and m.getParentCharId and m:getParentCharId() == primary:getID()
                if ok then target = m end
                break
            end
        end
    end
    if target == nil then
        printf(string.format("role_skillup.set_skillup_for_bot: '%s' not owned by '%s'", botName, primary:getName()))
        return
    end

    if mode == 0 then
        role_skillup.stop(target)
        return
    end

    if mode == 1 then
        role_skillup.start_ranged(target)
    elseif mode == 2 then
        local ids = {}
        if type(spellIdsTbl) == 'table' then
            for _, v in ipairs(spellIdsTbl) do
                if type(v) == 'number' and v > 0 then table.insert(ids, v) end
            end
        end
        role_skillup.start_magic(target, ids)
    end
end

-----------------------------------
-- Rotate the current spell to the back of the queue (called after a
-- successful cast — same semantics as client-side cycle_spell). Internal.
-----------------------------------
local function advance_rotation(s)
    local id = s.rotation[s.currentIndex]
    if id == nil then return end
    table.remove(s.rotation, s.currentIndex)
    table.insert(s.rotation, id)
    -- currentIndex stays at 1 so the next tick tries the new front of queue.
    s.currentIndex = 1
end

-----------------------------------
-- Pick the next "up" spell (not on recast). Internal.
-----------------------------------
local function next_castable_spell(bot, s)
    if #s.rotation == 0 then return nil end
    for i = 1, #s.rotation do
        local idx     = ((s.currentIndex - 1 + (i - 1)) % #s.rotation) + 1
        local spellId = s.rotation[idx]
        if not bot:hasRecast(xi.recast.MAGIC, spellId) then
            s.currentIndex = idx
            return spellId
        end
    end
    return nil
end

-----------------------------------
-- Per-bot tick body: invoked from runCombatTick via the Skillup role
-- dispatch. Self-paces via per-spell recast (magic) or
-- isBotRangedAttacking() (ranged); no extra throttle on top of the 400ms
-- server logic tick.
-----------------------------------
local function on_tick(bot)
    local s = get_state(bot)

    if not bot:isEngaged() then return end
    if bot:isBotCasting() or bot:isBotRangedAttacking() then return end

    if s.mode == 'magic' then
        local spellId = next_castable_spell(bot, s)
        if spellId ~= nil then
            -- Target: Cure/Bar* aim at self; everything else at current target.
            local meta   = GetSpellMetaByID(spellId) or {}
            local name   = meta.name or ''
            local target = bot
            if name ~= 'Cure' and not name:find('^Bar') then
                target = bot:getTarget()
            end
            if target ~= nil then
                bot:castSpell(spellId, target)
            end
        end
    elseif s.mode == 'ranged' then
        -- isBotRangedAttacking() gate above already prevents back-to-back fires
        -- while an attack is in flight; the action pipeline's natural recast
        -- handles spacing. Fire as soon as the previous shot finishes.
        local target = bot:getTarget()
        if target ~= nil then
            bot:rangedAttack(target)
        end
    end
end

-----------------------------------
-- Cast-finish + interrupt detection via PAI events on the bot itself (same
-- wiring as bots_listeners.lua). Magic finish advances the rotation;
-- interrupt leaves the index alone so the same spell is retried next tick.
-----------------------------------
local function register_listeners(bot)
    local id = bot:getID()
    bot:addListener('MAGIC_USE', 'BOT_SKILL_FINISH_' .. id, function(caster, target, spell, action)
        local s = xi.singleplayer.bots.alliance.bot[caster:getID()]
        if s == nil or s.mode ~= 'magic' then return end
        advance_rotation(s)
    end)
    bot:addListener('MAGIC_INTERRUPTED', 'BOT_SKILL_INT_' .. id, function(caster, target, spell, action)
        local s = xi.singleplayer.bots.alliance.bot[caster:getID()]
        if s == nil or s.mode ~= 'magic' then return end
        -- Leave currentIndex untouched so the same spell is retried on the
        -- next tick (client-side behavior).
    end)
end

local function unregister_listeners(bot)
    if bot == nil or bot.removeListener == nil then return end
    local id = bot:getID()
    bot:removeListener('BOT_SKILL_FINISH_' .. id)
    bot:removeListener('BOT_SKILL_INT_' .. id)
end

-----------------------------------
-- Role tick. Dispatched from runCombatTick when the bot's role is Skillup.
-- Listeners attach lazily on first tick (addListener dedupes by identifier).
-----------------------------------
function role_skillup.tick(bot)
    if bot == nil then return end
    if xi.singleplayer.bots.ai_util.is_force_rested(bot) then return end
    local s = xi.singleplayer.bots.alliance.bot[bot:getID()]
    if s == nil then
        register_listeners(bot)
    end
    on_tick(bot)
end

return m
