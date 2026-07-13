-----------------------------------
-- Server-side port of the client-side library
--
-- role_melee is the melee/DD role that drives skillchain opens and closes,
-- handles Sneak Attack/Trick Attack timing for THF, Utsusemi recasts for NIN,
-- chi blast for MNK, and ranged-attack pacing for RNG/COR/THF.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('role_melee')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.melee = xi.singleplayer.bots.melee or {}
local role_melee = xi.singleplayer.bots.melee

-- Per-bot scratch lives on alliance.bot[charId] (#221). The melee fields
-- (sc_paused, lastRaShotMs, thfRaDelay, chiBlastReadyForTarget, sataInProgress)
-- are part of the consolidated schema.
local function getState(bot)
    return xi.singleplayer.bots.ensure_bot(bot:getID())
end

-- is_sc_paused / target_in_melee_range / can_weaponskill / wait_for_sata /
-- should_open_sc / should_close_sc / should_solo_ws all live on ai_ability
-- now (shared with role_tank). Aliased here so the tick body reads cleanly.
local is_sc_paused = function(bot) return xi.singleplayer.bots.ability.is_sc_paused(bot) end

-----------------------------------
-- 3. use_weapon_skill
-----------------------------------
-- Pure pick for THF in split mode. Returns 'SA' | 'TA' | nil. No side effects:
-- doesn't fire abilities, doesn't mutate state. Caller commits state and
-- executes. nil = nothing to fire (already used SATA this WS, or neither
-- ability is off recast).
--
-- Per-WS gating uses state.sataInProgress: caller sets it true when committing
-- a pick, the WS-fire path clears it. Without that gate, tick N fires the
-- chosen SATA, tick N+1 finds the OTHER one off recast and fires it too — that
-- collapses Split into the same SA+TA-per-WS as Combined. The check at the top
-- of this function lives here so callers don't have to repeat it.
local function pick_split_sata(bot, state)
    if state.selectedSata ~= nil then
        return state.selectedSata
    end

    local saUp = xi.singleplayer.bots.ability.can_use_sneak_attack(bot)
    -- Capability check (have_ability), not main-job — matches the Combined
    -- branch. THF subs that have Trick Attack (subjob >= 30) alternate it in
    -- Split too, instead of it being silently main-job-gated out.
    local taUp = xi.singleplayer.bots.ability.can_use_trick_attack(bot)

    if not saUp and not taUp then
        state.selectedSata = nil
    elseif saUp and taUp then
        state.selectedSata = (state.lastSataUsed == 'SA') and 'TA' or 'SA'
    elseif saUp then
        state.selectedSata = 'SA'
    elseif taUp then
        state.selectedSata = 'TA'
    end
    return state.selectedSata;
end

local function use_weapon_skill(bot)
    local state = getState(bot)

    if xi.singleplayer.bots.ability.get_next_before_sc_ability(bot) ~= nil then
        local ability = xi.singleplayer.bots.ability.get_next_before_sc_ability(bot)
        if ability ~= nil then
            xi.singleplayer.bots.ability.use_ability(bot, ability, xi.singleplayer.bots.ability.is_offensive_ability(bot, ability))
        end
        return
    end

    -- SATA scheduling. Combined (default) preserves the original cascade:
    -- SA first if up, else TA. The full SA→TA→WS chain unfolds over multiple
    -- ticks since each call only fires one ability and recasts gate the next.
    -- Split alternates SA/TA across consecutive WSes so both fire over the
    -- 60s recast window — pick_split_sata returns 'SA'|'TA'|nil and the
    -- if-block here commits state and executes.
    if state.sataMode == 'split' then
        local pick = pick_split_sata(bot, state)
        if pick == 'SA' and xi.singleplayer.bots.ability.can_use_sneak_attack(bot) then
            state.sataInProgress = true
            xi.singleplayer.bots.ability.use_sneak_attack(bot)
            return
        elseif pick == 'TA' and xi.singleplayer.bots.ability.can_use_trick_attack(bot) then
            state.sataInProgress = true
            xi.singleplayer.bots.ability.use_trick_attack(bot)
            return
        end
        -- pick == nil: fall through to WS fire path below.
    elseif state.sataMode == 'saonly' then
        if xi.singleplayer.bots.ability.can_use_sneak_attack(bot) then
            state.sataInProgress = true
            xi.singleplayer.bots.ability.use_sneak_attack(bot)
            return
        end
    else
        if xi.singleplayer.bots.ability.can_use_sneak_attack(bot) then
            state.sataInProgress = true
            xi.singleplayer.bots.ability.use_sneak_attack(bot)
            return
        elseif xi.singleplayer.bots.ability.can_use_trick_attack(bot) then
            state.sataInProgress = true
            xi.singleplayer.bots.ability.use_trick_attack(bot)
            return
        end
    end

    if xi.singleplayer.bots.ability.can_use_boost(bot) then
        xi.singleplayer.bots.ability.use_boost(bot)
        return
    end

    xi.singleplayer.bots.ability.use_ws(bot, xi.singleplayer.bots.ability.get_ws(bot))
end

-----------------------------------
-- 4. should_use_ability
-----------------------------------
local function should_use_ability(bot)
    local tp = bot:getTP()
    local mbWindowEnd = xi.singleplayer.bots.ability.mb_window_close_ms(bot)
    local matchingRole = (xi.singleplayer.bots.ability.is_opener(bot) and not xi.singleplayer.bots.ability.is_second_sc(bot))
                      or xi.singleplayer.bots.ability.is_solo(bot)
                      or (xi.singleplayer.bots.ability.is_opener(bot) and xi.singleplayer.bots.ability.is_second_sc(bot) and xi.singleplayer.bots.ai_util.get_ms_since_epoch() > mbWindowEnd)
    return matchingRole and tp < 999 and tp > 850 and xi.singleplayer.bots.ability.get_next_sc_ability(bot) ~= nil
end

-----------------------------------
-- 5. should_use_always_ability
-----------------------------------
local function should_use_always_ability(bot)
    local tp = bot:getTP()
    local closerTp = xi.singleplayer.bots.ability.get_closer_tp(bot)
    return (tp < 850 or (not xi.singleplayer.bots.ability.is_solo(bot) and closerTp < 850))
        and xi.singleplayer.bots.ability.get_next_always_ability(bot) ~= nil
end

-- Aliases — implementations on ai_ability (shared with role_tank).
local should_start_sc = function(bot) return xi.singleplayer.bots.ability.should_open_sc(bot)  end
local should_solo_ws  = function(bot) return xi.singleplayer.bots.ability.should_solo_ws(bot)  end
local should_close_sc = function(bot) return xi.singleplayer.bots.ability.should_close_sc(bot) end

-----------------------------------
-- Utsusemi (Ninja shadow) — implementation lives in ai_magic so
-- role_tank and role_melee share the same overwrite-protection rules.
-- These thin shims keep the role_melee tick readable.
-----------------------------------
local function get_next_utsusemi(bot)
    return xi.singleplayer.bots.magic.get_next_utsusemi_spell(bot)
end

local function can_cast_utsusemi(bot)
    return xi.singleplayer.bots.magic.can_cast_utsusemi(bot)
end

local function cast_utsusemi(bot)
    xi.singleplayer.bots.magic.cast_utsusemi(bot)
end

-----------------------------------
-- 13. should_ra
--   RNG/COR: gate purely on PAI state. The C++ CRangeState handles the shot
--     cycle (aim → release → recover) authoritatively; while it's the active
--     state a shot is in flight and we must not fire another. As soon as the
--     PAI exits CRangeState the next shot is fair game — no equipment delay
--     metadata or lastShotMs bookkeeping needed.
--   THF: 15s deliberate utility cadence (interrupt casts / Bully timing), not
--     a weapon-delay derivation. Kept as-is.
-----------------------------------
local function should_ra(bot)
    if xi.singleplayer.bots.ai_util.is_job(bot, 'RNG') or xi.singleplayer.bots.ai_util.is_job(bot, 'COR') then
        return not bot:isBotRangedAttacking()
    elseif xi.singleplayer.bots.ai_util.is_job(bot, 'THF') then
        local state = getState(bot)
        -- thfRaDelay = 0 is the Status tab combo's "Off" — skip RA entirely.
        -- Vestigial `not is_nm(bot)` gate dropped along with the NM Mode UI
        -- toggle; the Status combo is now the canonical control here.
        if (state.thfRaDelay or 0) <= 0 then return false end
        return xi.singleplayer.bots.ai_util.get_ms_since_epoch() - state.lastRaShotMs >= state.thfRaDelay * 1000
    end
    return false
end

-----------------------------------
-- 14. shoot
-----------------------------------
local function shoot(bot)
    xi.singleplayer.bots.ability.ranged_attack(bot)
    local state = getState(bot)
    state.lastRaShotMs = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
end

-----------------------------------
-- 15. on_load
-----------------------------------
function role_melee.on_load(bot)
    -- Engine just pushed the bot into CWeaponSkillState — the SA→WS (or TA→WS,
    -- or combined SA→TA→WS) combo has actually landed. Clear the per-WS gate
    -- so the next 1000-TP WS can pick SATA fresh, even when the prior combo
    -- skipped use_weapon_skill's bottom WS-fire path (mob died mid-combo, bot
    -- died, role tick took a higher-priority branch, etc.).
    --
    -- bot:addListener replaces by id, so re-registration on a role flip is
    -- idempotent.
    bot:addListener('WEAPONSKILL_STATE_ENTER', 'BOT_ROLE_MELEE_WS_RESET', function(actor, wsId)
        local s = xi.singleplayer.bots.ensure_bot(actor:getID())
        s.sataInProgress = false
        s.lastSataUsed = s.selectedSata
        s.selectedSata = nil
    end)
end

-----------------------------------
-- 16. clear_chi_blast_flag
--     Wired from the per-self ABILITY_USE listener (bots_listeners) when bot
--     uses Chi Blast (ability id 82). Without this clear the tick's "fire
--     chi blast" branch keeps re-firing every tick while still engaged.
-----------------------------------
function role_melee.clear_chi_blast_flag(bot)
    local state = getState(bot)
    state.chiBlastReadyForTarget = nil
end

-----------------------------------
-- set_thf_ra_delay(primary, botName, delaySec)
--   Called from 0x176 AUTOBOTS SET_THF_RA_DELAY via OnBotSetThfRaDelay.
--   Per-bot — writes to alliance.bot[id].thfRaDelay. 0 = Off (THF skips
--   the utility RA entirely; should_ra returns false). Eligibility (job +
--   level) is enforced client-side before the dropdown renders, so the
--   server just trusts the name + delay after the ownership check.
-----------------------------------
function role_melee.set_thf_ra_delay(primary, botName, delaySec)
    if primary == nil or botName == nil or botName == '' then return end
    local target = botName:lower()
    local primaryId = primary:getID()
    local function is_owned(m)
        if m == primary then return true end
        if m.isHeadless and m:isHeadless()
           and m.getParentCharId and m:getParentCharId() == primaryId then
            return true
        end
        return false
    end
    delaySec = tonumber(delaySec) or 15
    if delaySec < 0 then delaySec = 0 end
    if delaySec > 240 then delaySec = 240 end
    for _, member in ipairs(primary:getAlliance() or {}) do
        if is_owned(member) and member:getName():lower() == target then
            local s = xi.singleplayer.bots.ensure_bot(member:getID())
            s.thfRaDelay = delaySec
            printf(string.format('role_melee.set_thf_ra_delay: %s -> %d s',
                member:getName(), delaySec))
            return
        end
    end
    printf(string.format('role_melee.set_thf_ra_delay: no owned bot "%s"', tostring(botName)))
end

-----------------------------------
function role_melee.tick(bot)
    if xi.singleplayer.bots.ai_util.is_force_rested(bot) then return end
    local state = getState(bot)

    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.tick then xi.singleplayer.bots.ai_equip_swap.tick(bot) end
    local log = function(msg) xi.singleplayer.bots.ai_util.log(bot, 'AutoSC', msg) end

    -- Role AI policy hard skips + item branches (HP → Status → MP). Returns
    -- true iff an item was consumed or a hard-skip fired; bail this tick in
    -- either case. process_pre_ability_checks also handles is_casting /
    -- neutralizing-effect / is_dead / weakened so no separate hard-skip
    -- block is needed below.
    if xi.singleplayer.bots.ability.process_pre_ability_checks
       and xi.singleplayer.bots.ability.process_pre_ability_checks(bot) then
        return
    end

    if state.chiBlastReadyForTarget ~= nil then
        log('chi_blast'); xi.singleplayer.bots.ability.use_chi_blast(bot); return
    end

    -- DRK Weapon Bash interrupt. Sits before the engaged/idle split so
    -- the window can fire regardless of engagement state. PLDs go through
    -- the same bash_is_up/bash pair from role_tank; the pool decides which
    -- eligible bot swings on any given window. Standalone `if` here (not
    -- merged into an elseif cascade) because the surrounding structure is
    -- engaged/idle-branched, not a single cascade.
    if xi.singleplayer.bots.ability.bash_is_up(bot) then
        log('bash');
        xi.singleplayer.bots.ability.bash(bot);
        return;
    end

    local engaged = bot.isEngaged and bot:isEngaged() or false

    if not engaged then
        local engageTarget = xi.singleplayer.bots.threat.alliance_target(bot)
        local threat       = engageTarget == nil and xi.singleplayer.bots.threat.peelable_for(bot) or nil
        if threat ~= nil then engageTarget = threat.mob end
        -- Camp leash: refuse to engage targets outside camp radius. Force
        -- the mob to come to camp (or force the puller to drag it in).
        if engageTarget ~= nil and xi.singleplayer.bots.ai_formation.entity_outside_camp_leash(engageTarget) then
            engageTarget = nil
        end
        if engageTarget ~= nil then
            local engageId = engageTarget:getID()
            if xi.singleplayer.bots.ability.can_use_chi_blast(bot) and engageId ~= state.chiBlastReadyForTarget then
                state.chiBlastReadyForTarget = engageId
            end
            bot:engage(engageTarget:getTargID())
        elseif xi.singleplayer.bots.ability.can_use_boost(bot) then
            log('can_use_boost'); xi.singleplayer.bots.ability.use_boost(bot)
        elseif get_next_utsusemi(bot) ~= nil and not xi.singleplayer.bots.item.have_shihei(bot) and xi.singleplayer.bots.item.have_shihei_toolbag(bot) then
            log('opening toolbag for shihei'); xi.singleplayer.bots.item.use_shihei_toolbag(bot)
        elseif can_cast_utsusemi(bot) then
            log('can_cast_utsusemi'); cast_utsusemi(bot)
        end
        return
    end

    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return end

    -- NIN off-tank: Utsusemi refresh → missing debuff (no RDM) → next
    -- wheel slot. Same dispatch as role_tank NIN but is_tank=false uses
    -- the defensive shadow threshold (refresh only at 0). Falls through
    -- to the SC/WS dispatch below when none fire.
    local magic = xi.singleplayer.bots.magic
    local isNin = xi.singleplayer.bots.ai_util.is_nin(bot)
    if isNin and magic.can_refresh_utsusemi(bot, false) then
        log('nin utsusemi'); magic.cast_utsusemi(bot); return
    elseif isNin and magic.can_cast_ninjitsu_debuff(bot) then
        log('nin debuff'); magic.cast_next_ninjitsu_debuff(bot); return
    elseif isNin and magic.can_cast_ninjitsu_wheel(bot) then
        log('nin wheel'); magic.cast_next_ninjitsu_wheel(bot); return
    end

    local hpp = bot:getHPP()
    local pet = bot.getPet and bot:getPet() or nil
    local petHPP = pet and pet:getHPP() or 0
    local targetHPP = target:getHPP()
    local tp = bot:getTP()

    local scCloseStart = xi.singleplayer.bots.ability.sc_close_window_start_ms(bot)

    -- wsUntilDead: set by bots_spawn.finish_alliance when the Finish button is
    -- clicked. While true, bypass SC opener/closer/MB-window gating entirely
    -- and force-fire WS whenever the bot has 1000+ TP and is engaged. Symmetric
    -- with role_nuke/role_rdm's nukeUntilDead. Cleared in
    -- ai_magic.check_for_target_death when the alliance target dies.
    if state.wsUntilDead
       and (bot.isEngaged and bot:isEngaged())
       and (bot:getTP() or 0) >= 1000 then
        log('wsUntilDead'); use_weapon_skill(bot)
    elseif should_close_sc(bot) then
        log('use_weapon_skill'); use_weapon_skill(bot)
    elseif xi.singleplayer.bots.ability.is_closer(bot) and scCloseStart > 0 and not is_sc_paused(bot)
       and xi.singleplayer.bots.ai_util.get_ms_since_epoch() < (scCloseStart - 1000) then
        local ability = xi.singleplayer.bots.ability.get_next_sc_ability(bot)
        if ability ~= nil then
            xi.singleplayer.bots.ability.use_ability(bot, ability, xi.singleplayer.bots.ability.is_offensive_ability(bot, ability))
        end
    elseif (xi.singleplayer.bots.ability.is_opener(bot) or xi.singleplayer.bots.ability.is_solo(bot)) and should_use_ability(bot) and not is_sc_paused(bot) then
        log('should_use_ability')
        local ability = xi.singleplayer.bots.ability.get_next_sc_ability(bot)
        if ability ~= nil then
            xi.singleplayer.bots.ability.use_ability(bot, ability, xi.singleplayer.bots.ability.is_offensive_ability(bot, ability))
        end
    elseif should_start_sc(bot) then
        log('should_start_sc'); use_weapon_skill(bot)
    elseif xi.singleplayer.bots.ability.can_provoke_add(bot) then
        log('can_provoke_add'); xi.singleplayer.bots.ability.provoke_add(bot)
    elseif xi.singleplayer.bots.ability.can_provoke_target(bot) then
        log('can_provoke_target'); xi.singleplayer.bots.ability.provoke_main_target(bot)
    elseif should_use_always_ability(bot) then
        log('should_use_always_ability')
        local ability = xi.singleplayer.bots.ability.get_next_always_ability(bot)
        if ability ~= nil then
            xi.singleplayer.bots.ability.use_ability(bot, ability, xi.singleplayer.bots.ability.is_offensive_ability(bot, ability))
        end
    elseif should_solo_ws(bot) then
        log('should_solo_ws'); use_weapon_skill(bot)
    elseif hpp > 0 and hpp < 70 and xi.singleplayer.bots.ability.can_use_chakra(bot) then
        log('can_use_chakra'); xi.singleplayer.bots.ability.use_chakra(bot)
    elseif petHPP > 0 and petHPP < 25 and xi.singleplayer.bots.ability.can_use_spirit_link(bot) then
        log('can_use_spirit_link'); xi.singleplayer.bots.ability.use_spirit_link(bot)
    elseif petHPP == 0 and xi.singleplayer.bots.ability.can_use_call_wyvern(bot) then
        log('can_use_call_wyvern'); xi.singleplayer.bots.ability.use_call_wyvern(bot)
    elseif tp < 800 and targetHPP > 50 and xi.singleplayer.bots.ability.can_use_barrage(bot) then
        log('can_use_barrage'); xi.singleplayer.bots.ability.use_barrage(bot)
    elseif xi.singleplayer.bots.ability.active_target_is_dragon(bot) and xi.singleplayer.bots.ability.can_use_ancient_circle(bot) then
        log('can_use_ancient_circle'); xi.singleplayer.bots.ability.use_ancient_circle(bot)
    elseif xi.singleplayer.bots.ability.active_target_is_arcana(bot) and xi.singleplayer.bots.ability.can_use_arcane_circle(bot) then
        log('can_use_arcane_circle'); xi.singleplayer.bots.ability.use_arcane_circle(bot)
    elseif xi.singleplayer.bots.ability.active_target_is_demon(bot) and xi.singleplayer.bots.ability.can_use_warding_circle(bot) then
        log('can_use_warding_circle'); xi.singleplayer.bots.ability.use_warding_circle(bot)
    elseif tp < 999 and should_ra(bot) then
        log('should_ra'); shoot(bot)
    end
end

return m
