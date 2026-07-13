-----------------------------------
-- Player-issued one-shot commands to a specific headless.
--
-- Wire: C2S 0x1A0 BOT_COMMAND → luautils::OnBotIssueCommand → dispatch() here.
-- Storage: alliance.bot[botId].pendingCommand = { kind, name, targetId, queuedAtMs }
--          Single-slot per bot, last-write-wins. Stale-cleared at 30s.
-- Tick:   bots.runCombatTick calls try_fire(bot, state) before role dispatch.
--         If pendingCommand fires this tick, role tick is skipped.
--
-- Verbs:
--   "ma"   spell name → cast on target (or self if targetId == 0)
--   "ja"   ability name → use on target (or self)
--   "ws"   WS name → fire WS at bot's current engagement target
--   "ra"   ranged attack at target
--   "item" item name → use on target (or self)
--
-- Acks: primary:printToPlayer(...) on terminal outcomes only. Queued waits are
-- silent so chat doesn't fill with "waiting…" lines while the bot finishes a
-- prior action.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_command')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.ai_command = xi.singleplayer.bots.ai_command or {}
local ai_command = xi.singleplayer.bots.ai_command

local COMMAND_TTL_MS = 30 * 1000

local function ms_now()
    return xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.get_ms_since_epoch()
        or math.floor(os.time() * 1000)
end

-- Find a headless owned by `primary` whose name matches (case-insensitive).
local function find_owned_bot(primary, botName)
    if primary == nil or botName == nil or botName == '' then return nil end
    local target = botName:lower()
    local primaryId = primary:getID()
    for _, member in ipairs(primary:getAlliance() or {}) do
        if member.isHeadless and member:isHeadless()
           and member.getParentCharId and member:getParentCharId() == primaryId
           and member:getName():lower() == target
        then
            return member
        end
    end
    return nil
end

-- Resolve a spell name into a spell id by walking xi.magic.spell. Accepts
-- display form ("Cure VI") or DB form ("cure_vi"); both normalize to the
-- xi.magic.spell key "CURE_VI".
local function resolve_spell_id(name)
    if name == nil or name == '' then return 0 end
    local key = name:upper():gsub('[ %-]', '_')
    if xi.magic == nil or xi.magic.spell == nil then return 0 end
    local id = xi.magic.spell[key]
    return (type(id) == 'number') and id or 0
end

-- Ability name → id via the existing ai_ability map, plus a fallback walk of
-- xi.jobAbility for anything the AI doesn't already enumerate.
local function resolve_ability_id(name)
    if name == nil or name == '' then return 0 end
    local ab = xi.singleplayer.bots.ability
    if ab and ab.get_ability_id then
        local id = ab.get_ability_id(name)
        if id and id > 0 then return id end
    end
    local key = name:upper():gsub('[ %-]', '_')
    if xi.jobAbility and xi.jobAbility[key] then return xi.jobAbility[key] end
    return 0
end

-- Item name → id. The same normalization the food picker uses works here —
-- lowercase + spaces to underscores matches item_basic.name.
local function resolve_item_id(name)
    if name == nil or name == '' then return 0 end
    local lookup = name:lower():gsub(' ', '_')
    return (GetItemIDByName and GetItemIDByName(lookup)) or 0
end

-- Resolve target: 0 sentinel → bot itself; non-zero → entity by ID.
local function resolve_target(bot, targetId)
    if targetId == 0 or targetId == nil then return bot end
    local e = GetEntityByID(targetId)
    return e
end

-- ============================================================
-- Dispatch (called from luautils::OnBotIssueCommand)
-- ============================================================
function ai_command.dispatch(primary, botName, kind, name, targetId)
    if primary == nil then return end
    local bot = find_owned_bot(primary, botName or '')
    if bot == nil then
        primary:printToPlayer(string.format('bot command: no headless named "%s"', tostring(botName)))
        return
    end
    local s = xi.singleplayer.bots.ensure_bot(bot:getID())
    s.pendingCommand = {
        kind       = (kind or ''):lower(),
        name       = name or '',
        targetId   = targetId or 0,
        queuedAtMs = ms_now(),
        primaryId  = primary:getID(),
    }
end

-- ============================================================
-- Firing — called from bots.runCombatTick, returns true if the command
-- consumed this tick (caller should skip the role tick).
-- ============================================================
local kindHandlers = {}

-- Wrap an action so the caller sends an ack to the primary on terminal outcomes.
local function ack(primary, bot, msg)
    if primary == nil then return end
    primary:printToPlayer(string.format('%s: %s', bot:getName(), msg))
end

local function get_primary(cmd)
    return GetPlayerByID(cmd.primaryId or 0)
end

-- ma — cast spell on target (or self)
kindHandlers.ma = function(bot, cmd)
    local primary = get_primary(cmd)
    local spellId = resolve_spell_id(cmd.name)
    if spellId == 0 then
        ack(primary, bot, string.format('unknown spell "%s"', cmd.name))
        return 'discard'
    end
    if not bot:hasSpell(spellId) then
        ack(primary, bot, string.format("doesn't know %s", cmd.name))
        return 'discard'
    end
    if bot.canUseSpell and not bot:canUseSpell(spellId) then
        ack(primary, bot, string.format("can't cast %s right now", cmd.name))
        return 'discard'
    end
    if bot:hasRecast(xi.recast.MAGIC, spellId) then
        return 'wait'
    end
    local target = resolve_target(bot, cmd.targetId)
    if target == nil then
        ack(primary, bot, 'target gone')
        return 'discard'
    end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_premagic then
        xi.singleplayer.bots.ai_equip_swap.equip_premagic(bot, spellId)
    end
    bot:castSpell(spellId, target)
    ack(primary, bot, string.format('casting %s on %s', cmd.name, target:getName()))
    return 'fired'
end

-- ja — use job ability on target (or self)
kindHandlers.ja = function(bot, cmd)
    local primary = get_primary(cmd)
    local abilityId = resolve_ability_id(cmd.name)
    if abilityId == 0 then
        ack(primary, bot, string.format('unknown ability "%s"', cmd.name))
        return 'discard'
    end
    if not bot:hasJobAbility(abilityId) then
        ack(primary, bot, string.format("doesn't have %s", cmd.name))
        return 'discard'
    end
    local PAb = GetAbility and GetAbility(abilityId) or nil
    local recastId = PAb and PAb:getRecastID() or abilityId
    if bot:hasRecast(xi.recast.ABILITY, recastId) then
        return 'wait'
    end
    local target = resolve_target(bot, cmd.targetId)
    if target == nil then
        ack(primary, bot, 'target gone')
        return 'discard'
    end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_jobability then
        xi.singleplayer.bots.ai_equip_swap.equip_jobability(bot, abilityId)
    end
    bot:useJobAbility(abilityId, target)
    ack(primary, bot, string.format('using %s on %s', cmd.name, target:getName()))
    return 'fired'
end

-- ws — fire WS at bot's current engagement
kindHandlers.ws = function(bot, cmd)
    local primary = get_primary(cmd)
    if not bot:isEngaged() then
        ack(primary, bot, 'not engaged')
        return 'discard'
    end
    if (bot:getTP() or 0) < 1000 then
        return 'wait'
    end
    if xi.singleplayer.bots.ability and xi.singleplayer.bots.ability.use_ws then
        xi.singleplayer.bots.ability.use_ws(bot, cmd.name)
        ack(primary, bot, string.format('weaponskill: %s', cmd.name))
        return 'fired'
    end
    return 'discard'
end

-- ra — ranged attack on target. Routes through ai_ability.ranged_attack so
-- the equip_preranged gear swap fires (Snapshot / Velocity Shot / etc.) before
-- the engine's CRangeState consumes the delay calc. Direct bot:rangedAttack
-- would skip that and shoot in whatever the bot was wearing.
kindHandlers.ra = function(bot, cmd)
    local primary = get_primary(cmd)
    local target = resolve_target(bot, cmd.targetId)
    if target == nil then
        ack(primary, bot, 'target gone')
        return 'discard'
    end
    if bot.isBotRangedAttacking and bot:isBotRangedAttacking() then
        return 'wait'
    end
    -- ai_ability.ranged_attack reads the alliance target internally; for the
    -- /bot path we want the user-specified target instead. Equip + fire inline.
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_preranged then
        xi.singleplayer.bots.ai_equip_swap.equip_preranged(bot)
    end
    bot:rangedAttack(target)
    ack(primary, bot, string.format('ranged attack on %s', target:getName()))
    return 'fired'
end

-- item — use named item on target
kindHandlers.item = function(bot, cmd)
    local primary = get_primary(cmd)
    local itemId = resolve_item_id(cmd.name)
    if itemId == 0 then
        ack(primary, bot, string.format('unknown item "%s"', cmd.name))
        return 'discard'
    end
    local target = resolve_target(bot, cmd.targetId)
    if target == nil then
        ack(primary, bot, 'target gone')
        return 'discard'
    end
    -- Reuse the existing item-firer (handles container/slot resolution).
    if xi.singleplayer.bots.item and xi.singleplayer.bots.item.use_item_by_id then
        local ok = xi.singleplayer.bots.item.use_item_by_id(bot, itemId, target)
        if ok then
            ack(primary, bot, string.format('using %s', cmd.name))
            return 'fired'
        else
            ack(primary, bot, string.format("doesn't have %s", cmd.name))
            return 'discard'
        end
    end
    ack(primary, bot, 'item path unavailable')
    return 'discard'
end

-- Called from bots.runCombatTick. Returns true iff a command fired or terminally
-- failed THIS tick — caller skips role tick in that case.
function ai_command.try_fire(bot, state)
    if state == nil then return false end
    local cmd = state.pendingCommand
    if cmd == nil then return false end

    -- TTL expiry
    if (ms_now() - (cmd.queuedAtMs or 0)) > COMMAND_TTL_MS then
        local primary = get_primary(cmd)
        ack(primary, bot, 'never got to act')
        state.pendingCommand = nil
        return false  -- TTL discard doesn't consume the tick
    end

    -- Bot mid-action → wait this tick (don't touch pendingCommand)
    if xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.is_busy_actioning
       and xi.singleplayer.bots.ai_util.is_busy_actioning(bot) then
        return false  -- AI tick can run; bot will just no-op since it's already busy
    end

    local handler = kindHandlers[cmd.kind]
    if handler == nil then
        local primary = get_primary(cmd)
        ack(primary, bot, string.format('unknown verb "%s"', tostring(cmd.kind)))
        state.pendingCommand = nil
        return false
    end

    local result = handler(bot, cmd)
    if result == 'fired' then
        state.pendingCommand = nil
        return true  -- consume this tick; bot is now in a new action state
    elseif result == 'discard' then
        state.pendingCommand = nil
        return false
    end
    -- 'wait' → leave cmd in place, fall through to AI tick
    return false
end

return m
