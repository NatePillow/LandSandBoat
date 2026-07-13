-----------------------------------
-- Server-side port of the client-side library
--
-- role_tank was the PLD-focused tank role. Same callback structure as role_heal:
--   load / incoming_packet / outgoing_packet / render / command
-- plus one helper `should_ws()`.
--
-- Server-side decision flow lives in role_tank.tick(bot), called from bot_ai for
-- TANK-role bots. Function order mirrors role_tank.lua.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('role_tank')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.tank = xi.singleplayer.bots.tank or {}
local role_tank = xi.singleplayer.bots.tank

-----------------------------------
-- 1. on_load
-----------------------------------
function role_tank.on_load(bot)
end

-----------------------------------
function role_tank.tick(bot)
    if xi.singleplayer.bots.ai_util.is_force_rested(bot) then return end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.tick then xi.singleplayer.bots.ai_equip_swap.tick(bot) end

    if xi.singleplayer.bots.ability.process_pre_ability_checks
       and xi.singleplayer.bots.ability.process_pre_ability_checks(bot) then
        return
    end

    local log = function(msg) xi.singleplayer.bots.ai_util.log(bot, 'AutoTank', msg) end

    local engaged = bot.isEngaged and bot:isEngaged() or false

    if not engaged then
        -- Commanded engage: alliance.allianceTarget drives the tank to swing
        -- on the main mob. When there's no commanded target, fall through
        -- to peel detection. Camp leash: refuse to engage a target that's
        -- outside camp radius — force it to come to us (or force the puller
        -- to drag it in). Without this, the tank runs 50+y out of camp to
        -- engage a slow / casting mob.
        local allianceTarget = xi.singleplayer.bots.threat.alliance_target(bot)
        if allianceTarget ~= nil and not xi.singleplayer.bots.ai_formation.entity_outside_camp_leash(allianceTarget) then
            if xi.singleplayer.bots.ai_util.is_resting(bot) then xi.singleplayer.bots.ai_util.stop_rest(bot) end
            log('alliance-target engage'); bot:engage(allianceTarget:getTargID())
            return
        end

        local threat = xi.singleplayer.bots.threat.peelable_for(bot)
        local peelTooFar = threat and xi.singleplayer.bots.ai_formation.entity_outside_camp_leash(threat.mob)
        if threat ~= nil and not peelTooFar and xi.singleplayer.bots.ai_util.is_resting(bot) then
            log('peelable stop_rest'); xi.singleplayer.bots.ai_util.stop_rest(bot)
        elseif threat ~= nil and not peelTooFar then
            log('peelable engage'); bot:engage(threat.mob:getTargID())
        elseif xi.singleplayer.bots.ai_util.is_nin(bot) and xi.singleplayer.bots.magic.can_cast_utsusemi(bot) then
            log('nin idle utsusemi'); xi.singleplayer.bots.magic.cast_utsusemi(bot)
        elseif xi.singleplayer.bots.ai_util.is_pld(bot) and xi.singleplayer.bots.ai_util.current_mp_percent(bot) < 20 and xi.singleplayer.bots.ai_util.can_rest(bot) and not xi.singleplayer.bots.ai_util.is_resting(bot) then
            log('can_rest'); xi.singleplayer.bots.ai_util.start_rest(bot)
        elseif xi.singleplayer.bots.ai_util.current_mp_percent(bot) > 95 and xi.singleplayer.bots.ai_util.is_resting(bot) then
            log('stop_rest'); xi.singleplayer.bots.ai_util.stop_rest(bot)
        end
        return
    end

    local hpp = bot:getHPP()
    local cureTier = xi.singleplayer.bots.magic.get_pld_cure_tier(bot)

    -- NIN tank: Utsusemi refresh → missing debuff (no RDM) → next wheel
    -- slot. All three gated by the 2s offensive-ninjutsu pacing gap so
    -- autoattacks land in between. Falls through to the PLD cascade
    -- when none fire — has_ability gates skip PLD-only branches naturally.
    -- Shield Bash (bash_is_up/bash) leads the cascade — it's an interrupt
    -- window on mob casts, higher priority than any queued action.
    local ability = xi.singleplayer.bots.ability
    local magic   = xi.singleplayer.bots.magic
    local isNin   = xi.singleplayer.bots.ai_util.is_nin(bot)

    if ability.bash_is_up(bot) then
        log('bash'); ability.bash(bot)
    elseif isNin and magic.can_refresh_utsusemi(bot, true) then
        log('nin utsusemi'); magic.cast_utsusemi(bot)
    elseif xi.singleplayer.bots.magic.sleeping_whm(bot) then
        log('sleeping_whm'); xi.singleplayer.bots.magic.wake_up_whm(bot)
    elseif xi.singleplayer.bots.ability.always_ability_is_up(bot) then
        log('always_ability_is_up'); xi.singleplayer.bots.ability.use_next_always_ability(bot); return
    elseif xi.singleplayer.bots.ability.provoke_is_up(bot)
       and xi.singleplayer.bots.ability.should_use_provoke(bot) then
        -- should_use_provoke gates the add case on the per-bot
        -- addControlMode toggle: in 'flash' mode Provoke is skipped on
        -- peelable adds (still fires on main alliance target), and the
        -- flash_add_is_up branch below handles the add instead.
        log('provoke_is_up'); xi.singleplayer.bots.ability.provoke(bot)
    elseif xi.singleplayer.bots.threat.peelable_for(bot) ~= nil
       and xi.singleplayer.bots.ability.can_use_rampart(bot) then
        log('can_use_rampart'); xi.singleplayer.bots.ability.use_rampart(bot)
    elseif isNin and magic.can_cast_ninjitsu_debuff(bot) then
        log('nin debuff'); magic.cast_next_ninjitsu_debuff(bot)
    elseif isNin and magic.can_cast_ninjitsu_wheel(bot) then
        log('nin wheel'); magic.cast_next_ninjitsu_wheel(bot)
    elseif xi.singleplayer.bots.magic.flash_add_is_up(bot) then
        -- Flash directed at the peelable add (vs. the alliance target).
        -- Gated by addControlMode in {'flash', 'both'}; in 'provoke' mode
        -- this branch never fires and the regular flash_is_up below takes
        -- over on the main target.
        log('flash_add_is_up'); xi.singleplayer.bots.magic.flash_add(bot)
    elseif xi.singleplayer.bots.magic.flash_is_up(bot) then
        log('flash_is_up'); xi.singleplayer.bots.magic.flash(bot)
    elseif cureTier == 'Cure_P1' and xi.singleplayer.bots.magic.can_cast_pld_cure(bot) then
        log('Cure_P1'); xi.singleplayer.bots.magic.cast_pld_healing_spell(bot)
    elseif hpp < 80 and xi.singleplayer.bots.ability.can_use_sentinel(bot) then
        log('can_use_sentinel'); xi.singleplayer.bots.ability.use_sentinel(bot)
    elseif cureTier == 'Cure_P2' and xi.singleplayer.bots.magic.can_cast_pld_cure(bot) then
        log('Cure_P2'); xi.singleplayer.bots.magic.cast_pld_healing_spell(bot)
    elseif xi.singleplayer.bots.ability.active_target_is_undead(bot) and xi.singleplayer.bots.ability.can_use_holy_circle(bot) then
        log('can_use_holy_circle'); xi.singleplayer.bots.ability.use_holy_circle(bot)
    elseif cureTier == 'Cure_P3' and xi.singleplayer.bots.magic.can_cast_pld_cure(bot) then
        log('Cure_P3'); xi.singleplayer.bots.magic.cast_pld_healing_spell(bot)
    elseif cureTier == 'Cure_P4' and xi.singleplayer.bots.magic.can_cast_pld_cure(bot) then
        log('Cure_P4'); xi.singleplayer.bots.magic.cast_pld_healing_spell(bot)
    elseif xi.singleplayer.bots.ability.should_close_sc(bot) then
        log('sc-close'); xi.singleplayer.bots.ability.use_ws(bot, xi.singleplayer.bots.ability.get_ws(bot))
    elseif xi.singleplayer.bots.ability.should_open_sc(bot) then
        log('sc-open');  xi.singleplayer.bots.ability.use_ws(bot, xi.singleplayer.bots.ability.get_ws(bot))
    elseif xi.singleplayer.bots.ability.should_solo_ws(bot) then
        log('solo-ws');  xi.singleplayer.bots.ability.use_ws(bot, xi.singleplayer.bots.ability.get_ws(bot))
    end
end

return m
