-----------------------------------
-- Server-side port of the client-side library
--
-- role_nuke is the BLM-focused nuker role. Same callback shape as role_heal /
-- role_tank: load / incoming_packet / outgoing_packet / render / command.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('role_nuke')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.nuke = xi.singleplayer.bots.nuke or {}
local role_nuke = xi.singleplayer.bots.nuke

-----------------------------------
-- 1. on_load
-----------------------------------
function role_nuke.on_load(bot)
end

-----------------------------------
function role_nuke.tick(bot)
    if xi.singleplayer.bots.ai_util.is_force_rested(bot) then return end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.tick then xi.singleplayer.bots.ai_equip_swap.tick(bot) end
    if xi.singleplayer.bots.magic.process_pre_cast_checks(bot) then return end

    local cureTier = xi.singleplayer.bots.magic.get_blm_cure_tier(bot)

    local primary      = bot:isHeadless() and GetPlayerByID(bot:getParentCharId()) or bot
    local activeTarget = xi.singleplayer.bots.magic.combat_active(primary)

    local magicState = xi.singleplayer.bots.alliance.bot[bot:getID()]
    local nukeUntilDead = magicState and magicState.nukeUntilDead or false
    local stunWindowOpen = (xi.singleplayer.bots.alliance.stunWindowUntilMs or 0)
                         > xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    local log = function(msg) xi.singleplayer.bots.ai_util.log(bot, 'AutoNuke', msg) end

    if activeTarget and stunWindowOpen and xi.singleplayer.bots.magic.can_stun(bot) then
        log('stun'); xi.singleplayer.bots.magic.stun(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.can_mb(bot) then
        log('can_mb'); xi.singleplayer.bots.magic.cast_mb(bot)
    elseif activeTarget and nukeUntilDead then
        log('nukeUntilDead'); xi.singleplayer.bots.magic.cast_casual_nuke(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.sc_is_close(bot) then
        log('sc_is_close')
    elseif xi.singleplayer.bots.magic.can_clear_mage_rest_blocker(bot) then
        log('clear_mage_rest_blocker'); xi.singleplayer.bots.magic.clear_mage_rest_blocker(bot)
    elseif xi.singleplayer.bots.magic.sleeping_whm(bot) then
        log('sleeping_whm'); xi.singleplayer.bots.magic.wake_up_whm(bot)
    elseif cureTier == 'Curaga' and xi.singleplayer.bots.magic.can_cast_curaga(bot) then
        log('Curaga'); xi.singleplayer.bots.magic.cast_curaga(bot)
    elseif cureTier == 'Cure_P1' and xi.singleplayer.bots.magic.can_cast_cure(bot) then
        log('Cure_P1'); xi.singleplayer.bots.magic.cast_cure(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.no_rdm(bot) and xi.singleplayer.bots.magic.can_sleep_add(bot) then
        log('can_sleep_add'); xi.singleplayer.bots.magic.sleep_add(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.rdm_sleep_cooldown(bot) and xi.singleplayer.bots.magic.can_sleep_add(bot) then
        log('can_sleep_add with rdm'); xi.singleplayer.bots.magic.sleep_add(bot)
    elseif xi.singleplayer.bots.ability.always_ability_is_up(bot) then
        log('always_ability_is_up'); xi.singleplayer.bots.ability.use_next_always_ability(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.no_rdm(bot) and xi.singleplayer.bots.magic.can_enfeeble(bot) then
        log('can_enfeeble'); xi.singleplayer.bots.magic.enfeeble(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.can_blm_enfeeble(bot) then
        log('can_blm_enfeeble'); xi.singleplayer.bots.magic.blm_enfeeble(bot)
    elseif not activeTarget and xi.singleplayer.bots.magic.can_buff_self(bot) then
        log('can_buff_self'); xi.singleplayer.bots.magic.buff_self(bot)
    elseif xi.singleplayer.bots.magic.can_use_food(bot) then
        log('can_use_food'); xi.singleplayer.bots.magic.use_food(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.can_leech(bot) then
        log('can_leech'); xi.singleplayer.bots.magic.cast_leech(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.casual_nuke_is_up(bot) then
        log('casual_nuke_is_up'); xi.singleplayer.bots.magic.cast_casual_nuke(bot)
    end
end

return m
