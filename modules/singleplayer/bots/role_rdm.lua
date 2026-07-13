-----------------------------------
-- Server-side port of the client-side library
--
-- role_rdm is the RDM hybrid (enfeeble + refresh/haste + emergency cure) role.
-- Same callback shape as the other auto*-role addons. Function order mirrors
-- role_rdm.lua.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('role_rdm')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.rdm = xi.singleplayer.bots.rdm or {}
local role_rdm = xi.singleplayer.bots.rdm

-----------------------------------
-- 1. on_load
-----------------------------------
function role_rdm.on_load(bot)
end

-----------------------------------
function role_rdm.tick(bot)
    if xi.singleplayer.bots.ai_util.is_force_rested(bot) then return end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.tick then xi.singleplayer.bots.ai_equip_swap.tick(bot) end
    if xi.singleplayer.bots.magic.process_pre_cast_checks(bot) then return end

    -- RDM picks cure tier based on whether a WHM is present
    local cureTier = xi.singleplayer.bots.magic.no_whm(bot)
                  and xi.singleplayer.bots.magic.get_cure_tier(bot)
                  or xi.singleplayer.bots.magic.get_blm_cure_tier(bot)

    local primary      = bot:isHeadless() and GetPlayerByID(bot:getParentCharId()) or bot
    local activeTarget = xi.singleplayer.bots.magic.combat_active(primary)

    local magicState = xi.singleplayer.bots.alliance.bot[bot:getID()]
    local nukeUntilDead = magicState and magicState.nukeUntilDead or false
    local stunWindowOpen = (xi.singleplayer.bots.alliance.stunWindowUntilMs or 0)
                         > xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    local log = function(msg) xi.singleplayer.bots.ai_util.log(bot, 'AutoRdm', msg) end

    -- Heal scope toggle - matches role_heal. Per-bot, set via the AutoBots
    -- status-tab "Heal" dropdown (0x176 SET_HEAL_SCOPE):
    --   'party'          (default) - own-party cures only
    --   'allianceMain'   - WHM-tier alliance fallback (P1 + status removal)
    --   'allianceAssist' - BLM-tier alliance Cure_P1 fallback only
    -- Replaces the legacy BOT_CURE_PARTY_ONLY settings flag (removed).
    local state              = xi.singleplayer.bots.ensure_bot(bot:getID())
    local healScope          = state.healScope or 'party'
    local allianceCureTier   = xi.singleplayer.bots.magic.get_alliance_cure_tier(bot)
    local allianceBlmCureTier= xi.singleplayer.bots.magic.get_alliance_blm_cure_tier(bot)

    -- TODO need new entry in this decision tree: RDM can proactively cast things like paralyze (but NOT dia) on sleeping adds, bottom half of priority list somewhere

    if activeTarget and stunWindowOpen and xi.singleplayer.bots.magic.can_stun(bot) then
        log('stun'); xi.singleplayer.bots.magic.stun(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.can_mb(bot) then
        log('can_mb'); xi.singleplayer.bots.magic.cast_mb(bot)
    elseif xi.singleplayer.bots.magic.sleeping_whm(bot) then
        log('sleeping_whm'); xi.singleplayer.bots.magic.wake_up_whm(bot)
    elseif xi.singleplayer.bots.magic.can_sleep_add(bot) then
        log('can_sleep_add'); xi.singleplayer.bots.magic.sleep_add(bot)
    elseif activeTarget and nukeUntilDead then
        log('nukeUntilDead'); xi.singleplayer.bots.magic.cast_casual_nuke(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.sc_is_close(bot) then
        log('sc_is_close')
    elseif cureTier == 'Curaga' and xi.singleplayer.bots.magic.can_cast_curaga(bot) then
        log('Curaga'); xi.singleplayer.bots.magic.cast_curaga(bot)
    elseif cureTier == 'Cure_P1' and xi.singleplayer.bots.magic.can_cast_cure(bot) then
        log('Cure_P1'); xi.singleplayer.bots.magic.cast_cure(bot)
    elseif healScope == 'allianceMain' and allianceCureTier == 'Cure_P1' and xi.singleplayer.bots.magic.can_cast_cure(bot) then
        -- Own party didn't need a Cure_P1; alliance-wide WHM-tier fallback.
        log('alliance_main_Cure_P1'); xi.singleplayer.bots.magic.cast_alliance_cure(bot)
    elseif healScope == 'allianceAssist' and allianceBlmCureTier == 'Cure_P1' and xi.singleplayer.bots.magic.can_cast_cure(bot) then
        log('alliance_assist_blm_Cure_P1'); xi.singleplayer.bots.magic.cast_alliance_cure(bot)
    elseif xi.singleplayer.bots.magic.can_clear_mage_rest_blocker(bot) then
        log('clear_mage_rest_blocker'); xi.singleplayer.bots.magic.clear_mage_rest_blocker(bot)
    elseif not activeTarget and xi.singleplayer.bots.magic.no_whm(bot) and xi.singleplayer.bots.magic.can_raise(bot) then
        log('can_raise');
        xi.singleplayer.bots.magic.cast_raise(bot);
    elseif not activeTarget and xi.singleplayer.bots.magic.can_raise_whm(bot) then
        log('cast_raise_whm');
        xi.singleplayer.bots.magic.cast_raise_whm(bot);
    elseif activeTarget and xi.singleplayer.bots.magic.can_dia(bot) then
        log('can_dia'); xi.singleplayer.bots.magic.cast_dia(bot)
    elseif activeTarget and not xi.singleplayer.bots.magic.hasted(bot) and xi.singleplayer.bots.magic.can_haste(bot) then
        log('can_haste_self'); xi.singleplayer.bots.magic.cast_haste(bot)
    elseif xi.singleplayer.bots.magic.can_refresh(bot) then
        log('can_refresh'); xi.singleplayer.bots.magic.cast_refresh(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.can_haste(bot) then
        log('can_haste'); xi.singleplayer.bots.magic.cast_haste(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.can_silence(bot) then
        log('can_silence'); xi.singleplayer.bots.magic.cast_silence(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.can_enfeeble(bot) then
        log('can_enfeeble'); xi.singleplayer.bots.magic.enfeeble(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.can_dispel(bot) then
        log('can_dispel'); xi.singleplayer.bots.magic.cast_dispel(bot)
    elseif xi.singleplayer.bots.magic.sleeping_members(bot) then
        log('sleeping_members'); xi.singleplayer.bots.magic.wake_up_members(bot)
    elseif xi.singleplayer.bots.magic.can_cure_high_priority_status(bot) then
        log('can_cure_high_priority_status'); xi.singleplayer.bots.magic.cure_high_priority_status(bot)
    elseif healScope == 'allianceMain' and xi.singleplayer.bots.magic.can_cure_alliance_high_priority_status(bot) then
        log('alliance_main_high_status'); xi.singleplayer.bots.magic.cure_alliance_high_priority_status(bot)
    elseif xi.singleplayer.bots.magic.can_cure_medium_priority_status(bot) then
        log('can_cure_medium_priority_status'); xi.singleplayer.bots.magic.cure_medium_priority_status(bot)
    elseif healScope == 'allianceMain' and xi.singleplayer.bots.magic.can_cure_alliance_medium_priority_status(bot) then
        log('alliance_main_medium_status'); xi.singleplayer.bots.magic.cure_alliance_medium_priority_status(bot)
    elseif xi.singleplayer.bots.ability.always_ability_is_up(bot) then
        log('always_ability_is_up'); xi.singleplayer.bots.ability.use_next_always_ability(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.no_blm(bot) and xi.singleplayer.bots.magic.can_blm_enfeeble(bot) then
        log('can_blm_enfeeble'); xi.singleplayer.bots.magic.blm_enfeeble(bot)
    elseif xi.singleplayer.bots.magic.can_cure_low_priority_status(bot) then
        log('can_cure_low_priority_status'); xi.singleplayer.bots.magic.cure_low_priority_status(bot)
    elseif healScope == 'allianceMain' and xi.singleplayer.bots.magic.can_cure_alliance_low_priority_status(bot) then
        log('alliance_main_low_status'); xi.singleplayer.bots.magic.cure_alliance_low_priority_status(bot)
    elseif not activeTarget and xi.singleplayer.bots.magic.can_buff_self(bot) then
        log('can_buff_self'); xi.singleplayer.bots.magic.buff_self(bot)
    elseif xi.singleplayer.bots.magic.can_use_food(bot) then
        log('can_use_food'); xi.singleplayer.bots.magic.use_food(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.can_leech(bot) then
        log('can_leech'); xi.singleplayer.bots.magic.cast_leech(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.can_enfeeble_add(bot) then
        log('can_enfeeble_add'); xi.singleplayer.bots.magic.cast_enfeeble_add(bot)
    elseif activeTarget and xi.singleplayer.bots.magic.casual_nuke_is_up(bot) then
        log('casual_nuke_is_up'); xi.singleplayer.bots.magic.cast_casual_nuke(bot)
    end
end

return m
