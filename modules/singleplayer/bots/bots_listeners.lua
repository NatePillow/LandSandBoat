-----------------------------------
-- Bot action-listener registration
--
-- Centralizes the wiring of bot_magic / bot_ability / bot_item check_for_*
-- handlers to the server's existing PAI EventHandler events. Called from
-- bot_ai when a bot spawns (or whenever the role activates).
--
-- Events used (already emitted by server-side state files):
--   MAGIC_START          (caster, target, spell, action)
--   MAGIC_USE            (caster, target, spell, action)    — cast finished
--   MAGIC_INTERRUPTED    (caster, target, spell, action)
--   MAGIC_STATE_EXIT     (caster, spell)
--   WEAPONSKILL_USE      (actor, target, skill, spent, action, damage)
--   WEAPONSKILL_STATE_EXIT (actor, skillId)
--   ABILITY_START        (actor, ability)
--   ABILITY_USE          (actor, target, ability, action)
--   ABILITY_STATE_EXIT   (actor, ability)
--   RANGE_START          (actor, action)
--   RANGE_STATE_EXIT     (actor, target, action)
--
-- Mob death / assist target-change / "getting attacked" events don't have
-- direct bot-listener equivalents — those flow through bot_ai's tick polling
-- (cheap; runs once per 1s PostTick anyway).
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('bots_listeners')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.bots_listeners = xi.singleplayer.bots.bots_listeners or {}
local bots_listeners = xi.singleplayer.bots.bots_listeners

-- Tracks which bots have listeners registered (avoid duplicate addListener calls)
bots_listeners.registered = bots_listeners.registered or {}

-----------------------------------
-- Register all PAI event listeners for a bot
-----------------------------------
function bots_listeners.register(bot)
    if bot == nil then return end
    local id = bot:getID()
    if bots_listeners.registered[id] then return end
    bots_listeners.registered[id] = true

    -- ---------- Magic ----------
    -- MAGIC_START hookup GONE: check_for_casting only acts on the 'finish' /
    -- 'interrupt' phases — wiring it for 'start' was a no-op call per spell
    -- start. MAGIC_STATE_EXIT hookup GONE: was an empty stub "for symmetry"
    -- with no body; gear-swap idle is owned by ai_equip_swap's own listener.

    bot:addListener('MAGIC_USE', 'BOT_AI_MAGIC_USE', function(caster, target, spell, action)
        local spellId = spell and spell.getID and spell:getID() or 0
        if xi.singleplayer.bots.magic and xi.singleplayer.bots.magic.check_for_casting then
            xi.singleplayer.bots.magic.check_for_casting(caster, 'finish', spellId)
        end
        -- Stun lands → close the alliance-level stun window.
        if xi.singleplayer.bots.magic and xi.singleplayer.bots.magic.check_for_stun and spellId == xi.magic.spell.STUN and target then
            xi.singleplayer.bots.magic.check_for_stun(caster, caster:getName())
        end
        -- Sleep cast finished (landed, missed, or resisted) → clear the
        -- in-flight reservation so the next picker pass can re-target this
        -- mob if it's still awake.
        if target and xi.singleplayer.bots.magic
           and xi.singleplayer.bots.magic.is_sleep_spell
           and xi.singleplayer.bots.magic.is_sleep_spell(spellId) then
            xi.singleplayer.bots.magic.clear_sleep_reservation(target:getID())
        end
        -- Cure cast finished (landed/missed) → drop this caster's claim; the
        -- victim's HP now reflects the heal, so the ledger no longer projects it.
        if target and xi.singleplayer.bots.magic
           and xi.singleplayer.bots.magic.is_cure_spell
           and xi.singleplayer.bots.magic.is_cure_spell(spellId) then
            xi.singleplayer.bots.magic.clear_cure_reservation(target:getID(), caster:getID())
        end
        -- SC close detection lives on the onActionResult chokepoint instead —
        -- CLuaAction has no scType getter; the addEffectMessage is per-result
        -- inside the action_t, which onActionResult exposes as a Lua table.
    end)

    bot:addListener('MAGIC_INTERRUPTED', 'BOT_AI_MAGIC_INT', function(caster, target, spell, action)
        local spellId = spell and spell.getID and spell:getID() or 0
        if xi.singleplayer.bots.magic and xi.singleplayer.bots.magic.check_for_casting then
            xi.singleplayer.bots.magic.check_for_casting(caster, 'interrupt', 0)
        end
        -- Cast interrupted → reservation on that mob is no longer valid;
        -- free it immediately so another sleeper can pick it up next tick.
        if target and xi.singleplayer.bots.magic
           and xi.singleplayer.bots.magic.is_sleep_spell
           and xi.singleplayer.bots.magic.is_sleep_spell(spellId) then
            xi.singleplayer.bots.magic.clear_sleep_reservation(target:getID())
        end
        -- Cure interrupted → free this caster's claim immediately so another
        -- healer can re-target the (still-low) victim on the next tick.
        if target and xi.singleplayer.bots.magic
           and xi.singleplayer.bots.magic.is_cure_spell
           and xi.singleplayer.bots.magic.is_cure_spell(spellId) then
            xi.singleplayer.bots.magic.clear_cure_reservation(target:getID(), caster:getID())
        end
    end)

    -- ---------- Weapon skill ----------
    -- SC pair coordination is engine-driven via EFFECT_SKILLCHAIN on the mob
    -- (read by ai_ability.sc_close_window_start_ms et al). No per-bot listener.
    --
    -- WS_STATE_EXIT / ABILITY_STATE_EXIT / RANGE_STATE_EXIT idle-gear swaps
    -- are owned by ai_equip_swap.register_listeners (single responsibility — the
    -- equip module decides gear lifecycle). Don't re-register them here.

    -- ---------- Job ability ----------
    -- Chi Blast fires as the engage opener and is single-use per fight: the
    -- "fire chi blast on tick" flag stays sticky until cleared here, otherwise
    -- the bot re-tries every tick mid-fight even though the ability is on recast.
    bot:addListener('ABILITY_USE', 'BOT_AI_ABILITY_USE', function(actor, target, ability, action)
        local abilityId = ability and ability.getID and ability:getID() or 0
        if abilityId == xi.jobAbility.CHI_BLAST
           and xi.singleplayer.bots.melee and xi.singleplayer.bots.melee.clear_chi_blast_flag then
            xi.singleplayer.bots.melee.clear_chi_blast_flag(actor)
        end
    end)
end

-----------------------------------
-- Unregister listeners for a bot (called on cascade cleanup)
-----------------------------------
function bots_listeners.unregister(bot)
    if bot == nil then return end
    local id = bot:getID()
    if not bots_listeners.registered[id] then return end
    bots_listeners.registered[id] = nil

    if bot.removeListener == nil then return end
    bot:removeListener('BOT_AI_MAGIC_USE')
    bot:removeListener('BOT_AI_MAGIC_INT')
    bot:removeListener('BOT_AI_ABILITY_USE')
end

-----------------------------------
-- Bot teardown dispatcher. Fired from C++ luautils::OnBotDespawn while the
-- entity is still valid, just before charutils::removeCharFromZone. Drops
-- the consolidated alliance.bot[id] scratch in one shot (#221) plus the
-- few peripheral state tables that aren't part of that consolidation
-- (ai_equip_swap, ai_item poison cache, bots_dps actor stats).
-----------------------------------
m:addOverride('xi.singleplayer.bots.onBotDespawn', function(bot)
    if super then super(bot) end
    if bot == nil then return end
    local id = bot:getID()

    -- Equip the gearlock set BEFORE state teardown so the gear the bot logs
    -- back in wearing matches the user's intended "park" set, not whatever
    -- post-cast / post-WS / mid-swap state the AI happened to leave them in.
    -- Order matters: ai_equip_swap.destroy_state below nukes the parsed XML
    -- cache, so equip_gearlock has to run while the cache is still alive.
    -- bot:equipItem inside equip_section applies synchronously, and the C++
    -- path runs charutils::removeCharFromZone AFTER this handler returns, so
    -- the DB persist reflects the gearlock equip. No-op if the bot's XML
    -- has no <gearlock> section.
    if bot.isHeadless and bot:isHeadless()
       and xi.singleplayer.bots.ai_equip_swap
       and xi.singleplayer.bots.ai_equip_swap.equip_gearlock then
        xi.singleplayer.bots.ai_equip_swap.equip_gearlock(bot)
    end

    bots_listeners.unregister(bot)
    if xi.singleplayer.bots.alliance and xi.singleplayer.bots.alliance.bot then
        xi.singleplayer.bots.alliance.bot[id] = nil
    end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.destroy_state then xi.singleplayer.bots.ai_equip_swap.destroy_state(id) end
    if xi.singleplayer.bots.bots_dps     and xi.singleplayer.bots.bots_dps.destroy_state then xi.singleplayer.bots.bots_dps.destroy_state(id) end
end)

-----------------------------------
-----------------------------------
-- Tick-time polling for events without direct PAI listeners. Called from
-- xi.singleplayer.bots.onBotTick at the AI scheduler cadence (~400ms).
--   - mob death: alliance.allianceTarget points to a dead entity
--   - auto-populate alliance.allianceTarget when nothing is commanded
--     (assist-engaged → assist's target; else worst-victim threat)
-----------------------------------
function bots_listeners.poll(bot)
    -- Auto-accept raise menu on headless. No client to click Accept, so a
    -- WHM-cast Raise on a dead headless would otherwise leave them sitting
    -- in CDeathState with the menu flag set forever. hasRaiseTractorMenu
    -- naturally clears once accepted; the call is a no-op when no raise is
    -- pending. Runs ahead of mob-death sweep so a freshly-revived bot can
    -- participate in the rest of this tick's logic. Primary is excluded —
    -- they should keep the manual choice to accept or decline.
    if bot.isHeadless and bot:isHeadless()
       and bot.hasRaiseTractorMenu and bot:hasRaiseTractorMenu()
       and bot.acceptRaise then
        bot:acceptRaise()
    end

    -- Mob death detection — sweep alliance.allianceTarget and notify the
    -- per-module handlers whenever it's gone or at zero HP.
    local seen      = {}
    local notify    = function(deadId)
        if deadId == 0 or seen[deadId] then return end
        seen[deadId] = true
        -- Port-bug fix (#194): clear alliance.allianceTarget when its mob dies.
        -- Without this clear, downstream gates (combat_active, role decision
        -- trees) treat a long-dead mob's stale ID as the active fight target
        -- — produced the "RDM casts Haste long after mob died" symptom.
        if xi.singleplayer.bots.get_alliance_target_id() == deadId then
            xi.singleplayer.bots.set_alliance_target(0)
        end
        if xi.singleplayer.bots.magic and xi.singleplayer.bots.magic.check_for_target_death then
            xi.singleplayer.bots.magic.check_for_target_death(bot, deadId)
        end
        -- ai_ability.check_for_target_death GONE (#228): no state to clean
        -- up; idlegear re-eval happens via the engine DISENGAGE listener.

        -- #208 resist-tracker cleanup. Drops every tracked bot's counters
        -- for this mob ID so a re-pop starts fresh. ai_resist's stats are
        -- alliance-wide (not per-bot in scope here), so one call covers
        -- all bots — the loop's bot arg is just our trigger.
        if xi.singleplayer.bots.ai_resist
           and xi.singleplayer.bots.ai_resist.clear_for_mob then
            xi.singleplayer.bots.ai_resist.clear_for_mob(deadId)
        end
    end
    local check     = function(deadId)
        if deadId == 0 or seen[deadId] then return end
        local mob = GetEntityByID(deadId)
        if mob == nil or mob:getHP() <= 0 then notify(deadId) end
    end

    check(xi.singleplayer.bots.get_alliance_target_id())

    -- Auto-populate alliance.allianceTarget when nothing's commanded. No-op
    -- when allianceTarget != 0 — a player command always wins.
    if xi.singleplayer.bots.threat and xi.singleplayer.bots.threat.ensure_alliance_target then
        xi.singleplayer.bots.threat.ensure_alliance_target(bot)
    end
end

return m
