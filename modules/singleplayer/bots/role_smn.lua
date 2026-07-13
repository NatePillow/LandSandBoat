-----------------------------------
-- role_smn
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('role_smn')

xi              = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.smn = xi.singleplayer.bots.smn or {}
local role_smn = xi.singleplayer.bots.smn

local AVATAR_RAGE_LIST = {
    [xi.magic.spell.CARBUNCLE] = {
        xi.jobAbility.METEORITE,
        xi.jobAbility.POISON_NAILS,
    },
    [xi.magic.spell.IFRIT] = {
        xi.jobAbility.METEOR_STRIKE,
        xi.jobAbility.FLAMING_CRUSH,
        xi.jobAbility.DOUBLE_PUNCH,
        xi.jobAbility.BURNING_STRIKE,
        xi.jobAbility.PUNCH,
    },
    [xi.magic.spell.TITAN] = {
        xi.jobAbility.GEOCRUSH,
        xi.jobAbility.MOUNTAIN_BUSTER,
        xi.jobAbility.MEGALITH_THROW,
        xi.jobAbility.ROCK_BUSTER,
    },
    [xi.magic.spell.LEVIATHAN] = {
        xi.jobAbility.GRAND_FALL,
        xi.jobAbility.SPINNING_DIVE,
        xi.jobAbility.BARRACUDA_DIVE,
    },
    [xi.magic.spell.GARUDA] = {
        xi.jobAbility.PREDATOR_CLAWS,
        xi.jobAbility.WIND_BLADE,
        xi.jobAbility.CLAW,
    },
    [xi.magic.spell.SHIVA] = {
        xi.jobAbility.HEAVENLY_STRIKE,
        xi.jobAbility.DOUBLE_SLAP,
        xi.jobAbility.AXE_KICK,
    },
    [xi.magic.spell.RAMUH] = {
        xi.jobAbility.CHAOTIC_STRIKE,
        xi.jobAbility.SHOCK_STRIKE,
        xi.jobAbility.THUNDERSPARK,
    },
    [xi.magic.spell.FENRIR] = {
        xi.jobAbility.ECLIPSE_BITE,
        xi.jobAbility.MOONLIT_CHARGE,
        xi.jobAbility.CRESCENT_FANG,
    },
    -- Diabolos: no v1 stub Rages; picker returns nil, plain Rage skips.
}

local AVATAR_MB_RAGE_LIST = {
    [xi.magic.spell.IFRIT] = {
        xi.jobAbility.FIRE_IV,
    },
    [xi.magic.spell.TITAN] = {
        xi.jobAbility.STONE_IV,
        xi.jobAbility.STONE_II,
    },
    [xi.magic.spell.LEVIATHAN] = {
        xi.jobAbility.WATER_IV,
        xi.jobAbility.WATER_II,
    },
    [xi.magic.spell.GARUDA] = {
        xi.jobAbility.AERO_IV,
        xi.jobAbility.AERO_II,
    },
    [xi.magic.spell.SHIVA] = {
        xi.jobAbility.BLIZZARD_IV,
        xi.jobAbility.BLIZZARD_II,
    },
    [xi.magic.spell.RAMUH] = {
        xi.jobAbility.THUNDER_IV,
        xi.jobAbility.THUNDERSPARK,  -- magic dmg + stun, not hybrid
        xi.jobAbility.THUNDER_II,
    },
    -- Carbuncle / Fenrir / Diabolos omitted — no MB-eligible rages.
}

local WARD_SKIP_COVERAGE_COUNT = 3

local AVATAR_MB_ELEMENT = {
    [xi.magic.spell.IFRIT]     = 'Fire',
    [xi.magic.spell.SHIVA]     = 'Blizzard',
    [xi.magic.spell.GARUDA]    = 'Aero',
    [xi.magic.spell.TITAN]     = 'Stone',
    [xi.magic.spell.RAMUH]     = 'Thunder',
    [xi.magic.spell.LEVIATHAN] = 'Water',
}

local SPRING_WATER_STATUS_EFFECTS = {
    xi.effect.BLINDNESS,
    xi.effect.POISON,
    xi.effect.PARALYSIS,
    xi.effect.DISEASE,
    xi.effect.PETRIFICATION,
    xi.effect.SILENCE,
    xi.effect.SLOW,
}

local ELEMENT_TO_AVATAR = {
    [xi.element.FIRE]  = xi.magic.spell.IFRIT,
    [xi.element.ICE]   = xi.magic.spell.SHIVA,
    [xi.element.WIND]  = xi.magic.spell.GARUDA,
    [xi.element.EARTH] = xi.magic.spell.TITAN,
    [xi.element.WATER] = xi.magic.spell.LEVIATHAN,
}

local SDT_MOD_BY_ELEMENT = {
    [xi.element.FIRE]    = xi.mod.FIRE_SDT,
    [xi.element.ICE]     = xi.mod.ICE_SDT,
    [xi.element.WIND]    = xi.mod.WIND_SDT,
    [xi.element.EARTH]   = xi.mod.EARTH_SDT,
    [xi.element.THUNDER] = xi.mod.THUNDER_SDT,
    [xi.element.WATER]   = xi.mod.WATER_SDT,
}

local DEFAULT_SOLO_AVATAR    = xi.magic.spell.GARUDA
local AUTOSWAP_THRESHOLD_PCT = 20

function role_smn.has_pet(bot)
    return bot.getPet and bot:getPet() ~= nil or false
end

local function bot_knows_summon(bot, spellId)
    if spellId == nil or spellId == 0 then return false end
    if bot.hasSpell == nil or not bot:hasSpell(spellId) then return false end
    if bot.canUseSpell ~= nil and not bot:canUseSpell(spellId) then return false end
    return true
end

local function count_party_with_effect(bot, effectId)
    local n = 0
    for _, member in ipairs(xi.singleplayer.bots.magic.get_party_members(bot)) do
        if member:getHPP() > 0 and xi.singleplayer.bots.magic.is_effect_active(member, effectId) then
            n = n + 1
        end
    end
    return n
end

local function party_coverage_threshold(bot)
    return math.min(WARD_SKIP_COVERAGE_COUNT, #xi.singleplayer.bots.magic.get_party_members(bot))
end

function role_smn.bp_rage_off_recast(bot)
    return not bot:hasRecast(xi.recast.ABILITY, xi.recastID.BLOODPACT_RAGE)
end

function role_smn.bp_ward_off_recast(bot)
    return not bot:hasRecast(xi.recast.ABILITY, xi.recastID.BLOODPACT_WARD)
end

local function can_use_ward_ability(bot, avatarSpell, effectId)
    if not role_smn.bp_ward_off_recast(bot) then return false end
    if not bot_knows_summon(bot, avatarSpell) then return false end
    if count_party_with_effect(bot, effectId) >= party_coverage_threshold(bot) then return false end
    return true
end

local function ensure_pet_and_cast(bot, targetSpell, abilityId, castTarget)
    castTarget = castTarget or bot
    if role_smn.has_pet(bot) and role_smn.current_pet_avatar_spell(bot) == targetSpell then
        bot:useJobAbility(abilityId, castTarget)
        return true
    end
    if role_smn.has_pet(bot) then
        role_smn.release_pet(bot)
        return true
    end
    return role_smn.cast_summon_avatar(bot, targetSpell)
end

local function cast_ward_ability(bot, bpId, avatarSpell, castTarget)
    return ensure_pet_and_cast(bot, avatarSpell, bpId, castTarget)
end

-- derive_main_from_sc — smart-mode main-avatar derivation. Walks all
-- SC pairs in alliance.sc[], sums each pair's MB element list into a
-- frequency table, picks the highest-frequency element that maps to
-- an avatar the bot actually knows. Tiebreak by first-appearance in
-- the config order.
--
-- Handles multi-element SCs (Distortion → {Water, Ice}) naturally
-- because pair_mb_elements returns the whole list. That's why e.g.
-- Distortion + Reverberation pick Water (2 pairs) instead of Ice
-- (1 pair) — the frequency counts capture the overlap.
local function derive_main_from_sc(bot)
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil or alliance.sc == nil or #alliance.sc == 0 then return nil end

    local elementCount = {}
    for _, pair in ipairs(alliance.sc) do
        for _, el in ipairs(xi.singleplayer.bots.magic.pair_mb_elements(pair) or {}) do
            elementCount[el] = (elementCount[el] or 0) + 1
        end
    end

    -- Walk pairs in order to preserve tiebreak. Only consider elements
    -- whose avatar is known to this bot — un-knowable elements can't
    -- be MB'd anyway.
    local bestAvatar, bestCount = nil, 0
    for _, pair in ipairs(alliance.sc) do
        for _, el in ipairs(xi.singleplayer.bots.magic.pair_mb_elements(pair) or {}) do
            local avatarSpell = ELEMENT_TO_AVATAR[el]
            if avatarSpell and bot_knows_summon(bot, avatarSpell)
               and elementCount[el] > bestCount then
                bestAvatar = avatarSpell
                bestCount  = elementCount[el]
            end
        end
    end
    return bestAvatar
end

function role_smn.get_selected_avatar_spell(bot)
    local state = xi.singleplayer.bots.get_bot_state(bot)
    if state.smnAvatarSpellId ~= nil and state.smnAvatarSpellId ~= 0 then
        return state.smnAvatarSpellId
    end
    -- Smart mode: derive main from alliance SC config; fall back to
    -- best_solo (mob weakness / weather) when no SCs are configured.
    local mainFromSc = derive_main_from_sc(bot)
    if mainFromSc ~= nil then return mainFromSc end
    return role_smn.best_solo_avatar(bot)
end

function role_smn.best_solo_avatar(bot)
    local target = xi.singleplayer.bots.get_current_mob_target()
    local defaultAvatar = bot_knows_summon(bot, DEFAULT_SOLO_AVATAR)
                          and DEFAULT_SOLO_AVATAR or nil

    if target == nil then
        if defaultAvatar ~= nil then return defaultAvatar end
    end

    local weather  = (target ~= nil and target.getWeather) and target:getWeather() or 0
    local elemData = xi.data and xi.data.element or nil

    local bestAvatar = defaultAvatar
    local bestScore  = AUTOSWAP_THRESHOLD_PCT - 1  -- strictly-greater compare

    for elemId, avatarSpell in pairs(ELEMENT_TO_AVATAR) do
        if bot_knows_summon(bot, avatarSpell) and target ~= nil then
            local score = 0
            local sdtMod = SDT_MOD_BY_ELEMENT[elemId]
            local sdt    = (sdtMod ~= nil and target.getMod) and target:getMod(sdtMod) or 100
            if sdt > 100 then score = score + (sdt - 100) end
            if elemData ~= nil and weather ~= 0 then
                local single = elemData.getAssociatedSingleWeather and elemData.getAssociatedSingleWeather(elemId) or nil
                local double = elemData.getAssociatedDoubleWeather and elemData.getAssociatedDoubleWeather(elemId) or nil
                if weather == single then score = score + 10 end
                if weather == double then score = score + 25 end
            end
            if score >= AUTOSWAP_THRESHOLD_PCT and score > bestScore then
                bestAvatar = avatarSpell
                bestScore  = score
            end
        end
    end

    if bestAvatar ~= nil then return bestAvatar end

    -- Neither Garuda nor a scored candidate available (unusual — implies
    -- a very-low-level SMN or one with unlearned summons). Fall back to
    -- the first known avatar candidate.
    for _, avatarSpell in pairs(ELEMENT_TO_AVATAR) do
        if bot_knows_summon(bot, avatarSpell) then return avatarSpell end
    end
    -- Last-resort: Carbuncle. SMN's earliest summon — every SMN gets
    -- it via job unlock. If somehow even THIS isn't known, the summon
    -- cast fails silently downstream, and role_smn falls through to
    -- whm_cascade — SMN plays as pure /WHM this fight.
    return xi.magic.spell.CARBUNCLE
end

local PET_NAME_TO_SPELL = {
    ['Carbuncle']     = xi.magic.spell.CARBUNCLE,
    ['Fenrir']        = xi.magic.spell.FENRIR,
    ['Ifrit']         = xi.magic.spell.IFRIT,
    ['Titan']         = xi.magic.spell.TITAN,
    ['Leviathan']     = xi.magic.spell.LEVIATHAN,
    ['Garuda']        = xi.magic.spell.GARUDA,
    ['Shiva']         = xi.magic.spell.SHIVA,
    ['Ramuh']         = xi.magic.spell.RAMUH,
    ['Diabolos']      = xi.magic.spell.DIABOLOS,
    -- Spirits (for Elemental Siphon flow; current_pet_avatar_spell
    -- needs to recognize them so ensure_pet_and_cast can compare
    -- targetSpell against the currently-out pet uniformly).
    ['FireSpirit']    = xi.magic.spell.FIRE_SPIRIT,
    ['IceSpirit']     = xi.magic.spell.ICE_SPIRIT,
    ['AirSpirit']     = xi.magic.spell.AIR_SPIRIT,
    ['EarthSpirit']   = xi.magic.spell.EARTH_SPIRIT,
    ['ThunderSpirit'] = xi.magic.spell.THUNDER_SPIRIT,
    ['WaterSpirit']   = xi.magic.spell.WATER_SPIRIT,
    ['LightSpirit']   = xi.magic.spell.LIGHT_SPIRIT,
    ['DarkSpirit']    = xi.magic.spell.DARK_SPIRIT,
}

function role_smn.current_pet_avatar_spell(bot)
    local pet = bot.getPet and bot:getPet() or nil
    if pet == nil or pet.getName == nil then return 0 end
    return PET_NAME_TO_SPELL[pet:getName()] or 0
end


function role_smn.desired_mb_avatar(bot, pendingElements)
    if pendingElements == nil then return nil end
    for _, elem in ipairs(pendingElements) do
        local avatar = ELEMENT_TO_AVATAR[elem]
        if avatar ~= nil and bot_knows_summon(bot, avatar) then return avatar end
    end
    return nil
end

function role_smn.can_summon_avatar(bot)
    if role_smn.has_pet(bot) then return false end
    local spellId = role_smn.get_selected_avatar_spell(bot)
    return xi.singleplayer.bots.magic.spell_is_up(bot, spellId, false)
end

function role_smn.cast_summon_avatar(bot, forcedSpellId)
    local spellId = forcedSpellId or role_smn.get_selected_avatar_spell(bot)
    return xi.singleplayer.bots.magic.cast_party_spell(bot, spellId, bot)
end

function role_smn.release_pet(bot)
    if xi.singleplayer.bots.ability.have_ability(bot, 'Release') then
        xi.singleplayer.bots.ability.use_ability(bot, 'Release', false)
    end
end

function role_smn.ensure_pet_engaged(bot, target)
    if target == nil then return end
    local pet = bot.getPet and bot:getPet() or nil
    if pet == nil then return end
    local cur = pet.getTarget and pet:getTarget() or nil
    if cur ~= nil and cur.getID and cur:getID() == target:getID() then return end
    bot:petAttack(target)
end

function role_smn.next_rage_bp(bot)
    local list = AVATAR_RAGE_LIST[role_smn.current_pet_avatar_spell(bot)]
    if list == nil then return nil end
    for _, bpId in ipairs(list) do
        if bot:hasJobAbility(bpId) then return bpId end
    end
    return nil
end

function role_smn.next_mb_rage_bp(bot)
    local list = AVATAR_MB_RAGE_LIST[role_smn.current_pet_avatar_spell(bot)]
    if list == nil then return nil end
    for _, bpId in ipairs(list) do
        if bot:hasJobAbility(bpId) then return bpId end
    end
    return nil
end

-- is_effectively_solo — SMN-specific "should I fire plain Rage on
-- cooldown?" test. True whenever MB isn't achievable with the current
-- setup, so plain Rage isn't wasting a slot that MB would use.
--
-- Cases:
--   * alliance.sc empty                           → true (nothing to MB)
--   * Dropdown hard-lock (smnAvatarSpellId set):
--       - dropdown avatar's element in any SC's MB list → false (hold)
--       - dropdown avatar has no MB element / no match  → true (fire plain)
--   * Smart mode (dropdown blank):
--       - some known avatar's element matches any SC's MB list → false
--       - no known avatar can MB (e.g. Thunder SC + no Ramuh)  → true
function role_smn.is_effectively_solo(bot)
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil or alliance.sc == nil or #alliance.sc == 0 then return true end

    -- Union of MB elements across all configured SC pairs.
    local scElements = {}
    for _, pair in ipairs(alliance.sc) do
        for _, el in ipairs(xi.singleplayer.bots.magic.pair_mb_elements(pair) or {}) do
            scElements[el] = true
        end
    end
    if next(scElements) == nil then return true end

    local state = xi.singleplayer.bots.get_bot_state(bot)
    if state.smnAvatarSpellId ~= nil and state.smnAvatarSpellId ~= 0 then
        -- Hard-lock: only the dropdown avatar counts.
        local avatarEl = AVATAR_MB_ELEMENT[state.smnAvatarSpellId]
        return not (avatarEl and scElements[avatarEl])
    end
    -- Smart mode: any known avatar.
    for avatarSpell, avatarEl in pairs(AVATAR_MB_ELEMENT) do
        if bot_knows_summon(bot, avatarSpell) and scElements[avatarEl] then
            return false
        end
    end
    return true
end

-- Elemental Siphon — MP recovery drawn from a summoned spirit. Engine
-- requires a spirit (Fire..Dark Spirit petId range) to be out; an avatar
-- like Ifrit or Garuda causes onAbilityCheck to fail. Uses the shared
-- ensure_pet_and_cast for the release-avatar → summon-spirit → cast
-- flow.
--
-- SIPHON_SPIRIT_SPELL is the spirit we auto-summon. Fire Spirit is the
-- default: cheapest and unlocked earliest. A day/weather-matched spirit
-- would give a larger MP payback via calculateDayAndWeather in the
-- Siphon script — future improvement.
local SIPHON_SPIRIT_SPELL = xi.magic.spell.FIRE_SPIRIT

function role_smn.can_use_elemental_siphon(bot)
    if xi.singleplayer.bots.ai_util.current_mp_percent(bot) >= 30 then return false end
    if not xi.singleplayer.bots.ability.have_ability(bot, 'Elemental Siphon') then return false end
    if not bot_knows_summon(bot, SIPHON_SPIRIT_SPELL) then return false end
    return true
end

function role_smn.cast_elemental_siphon(bot)
    return ensure_pet_and_cast(bot, SIPHON_SPIRIT_SPELL, xi.jobAbility.ELEMENTAL_SIPHON, bot)
end

function role_smn.can_use_rage(bot)
    if not role_smn.has_pet(bot) then return false end
    if not role_smn.bp_rage_off_recast(bot) then return false end
    -- Hold plain Rage when MB is achievable — can_mb_rage will fire it
    -- inside the MB window instead of burning it on a non-MB hit.
    if not role_smn.is_effectively_solo(bot) then return false end
    return role_smn.next_rage_bp(bot) ~= nil
end

-- can_revert_to_main / cast_revert_to_main — auto-swap back to the main
-- avatar after a temporary Ward/Siphon detour. When we're on the wrong
-- pet and no higher-priority branch wants a swap, release; the next
-- tick's can_summon_avatar fires the main via get_selected_avatar_spell.
--
-- Positioned near the bottom of the cascade so any priority action
-- (MB, Ward, Rage, cure) can use the wrong-pet-out-right-now productively
-- before we spend the ~10s revert.
function role_smn.can_revert_to_main(bot)
    if not role_smn.has_pet(bot) then return false end
    return role_smn.current_pet_avatar_spell(bot) ~= role_smn.get_selected_avatar_spell(bot)
end

function role_smn.cast_revert_to_main(bot)
    role_smn.release_pet(bot)
end

function role_smn.can_mb_rage(bot)
    if not role_smn.bp_rage_off_recast(bot) then return false end

    -- Phase 1 / 3 — pending SC with a viable target avatar.
    local pending = xi.singleplayer.bots.magic.detect_pending_mb(bot)
    if pending ~= nil then
        return role_smn.desired_mb_avatar(bot, pending) ~= nil
    end

    -- Phase 2 — window open + current avatar can fire an MB-eligible BP
    -- within the remaining window.
    if not role_smn.has_pet(bot) then return false end
    local mbCloseMs = xi.singleplayer.bots.ability.mb_window_close_ms(bot)
    if mbCloseMs == 0 then return false end
    local now = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    if now > mbCloseMs then return false end
    local avatarEl = AVATAR_MB_ELEMENT[role_smn.current_pet_avatar_spell(bot)]
    if avatarEl == nil then return false end
    local scElements = xi.singleplayer.bots.magic.sc_mb_elements_for(bot)
    if scElements == nil then return false end
    local elementMatch = false
    for _, family in ipairs(scElements) do
        if family == avatarEl then elementMatch = true; break end
    end
    if not elementMatch then return false end
    local bpId = role_smn.next_mb_rage_bp(bot)
    if bpId == nil then return false end
    local ability = GetAbility and GetAbility(bpId) or nil
    if ability == nil or ability.getCastTime == nil then return false end
    local castMs = ability:getCastTime() or 0
    return now + castMs <= mbCloseMs
end

function role_smn.cast_mb_rage(bot)
    local pending = xi.singleplayer.bots.magic.detect_pending_mb(bot)
    if pending ~= nil then
        local desired = role_smn.desired_mb_avatar(bot, pending)
        if desired == nil then return false end
        if role_smn.current_pet_avatar_spell(bot) == desired then
            return true -- Phase 3: wait for window.
        end
        if role_smn.has_pet(bot) then
            role_smn.release_pet(bot)
            return true
        end
        return role_smn.cast_summon_avatar(bot, desired)
    end

    local bpId = role_smn.next_mb_rage_bp(bot)
    if bpId == nil then return false end
    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return false end
    bot:useJobAbility(bpId, target)
    return true
end

function role_smn.can_use_spring_water(bot)
    if not role_smn.bp_ward_off_recast(bot) then return false end
    if not bot_knows_summon(bot, xi.magic.spell.LEVIATHAN) then return false end
    local checked   = 0
    local afflicted = 0
    for _, m in ipairs(xi.singleplayer.bots.magic.get_party_members(bot)) do
        if m:getHPP() > 0 then
            checked = checked + 1
            for _, effId in ipairs(SPRING_WATER_STATUS_EFFECTS) do
                if xi.singleplayer.bots.magic.is_effect_active(m, effId) then
                    afflicted = afflicted + 1
                    break
                end
            end
        end
    end
    return checked > 0 and checked == afflicted
end
function role_smn.cast_spring_water(bot)
    return cast_ward_ability(bot, xi.jobAbility.SPRING_WATER, xi.magic.spell.LEVIATHAN)
end

function role_smn.can_use_hastega(bot)
    return can_use_ward_ability(bot, xi.magic.spell.GARUDA, xi.effect.HASTE)
end
function role_smn.cast_hastega(bot)
    return cast_ward_ability(bot, xi.jobAbility.HASTEGA, xi.magic.spell.GARUDA)
end

function role_smn.can_use_lunar_roar(bot)
    if not role_smn.bp_ward_off_recast(bot) then return false end
    if not bot_knows_summon(bot, xi.magic.spell.FENRIR) then return false end
    return xi.singleplayer.bots.get_current_mob_target() ~= nil
end
function role_smn.cast_lunar_roar(bot)
    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return false end
    return cast_ward_ability(bot, xi.jobAbility.LUNAR_ROAR, xi.magic.spell.FENRIR, target)
end

function role_smn.can_use_ecliptic_howl(bot)
    return can_use_ward_ability(bot, xi.magic.spell.FENRIR, xi.effect.ACCURACY_BOOST)
end
function role_smn.cast_ecliptic_howl(bot)
    return cast_ward_ability(bot, xi.jobAbility.ECLIPTIC_HOWL, xi.magic.spell.FENRIR)
end

function role_smn.can_use_ecliptic_growl(bot)
    return can_use_ward_ability(bot, xi.magic.spell.FENRIR, xi.effect.STR_BOOST)
end
function role_smn.cast_ecliptic_growl(bot)
    return cast_ward_ability(bot, xi.jobAbility.ECLIPTIC_GROWL, xi.magic.spell.FENRIR)
end

function role_smn.can_use_dream_shroud(bot)
    return can_use_ward_ability(bot, xi.magic.spell.DIABOLOS, xi.effect.MAGIC_ATK_BOOST)
end
function role_smn.cast_dream_shroud(bot)
    return cast_ward_ability(bot, xi.jobAbility.DREAM_SHROUD, xi.magic.spell.DIABOLOS)
end

function role_smn.can_use_earthen_ward(bot)
    return can_use_ward_ability(bot, xi.magic.spell.TITAN, xi.effect.STONESKIN)
end
function role_smn.cast_earthen_ward(bot)
    return cast_ward_ability(bot, xi.jobAbility.EARTHEN_WARD, xi.magic.spell.TITAN)
end

function role_smn.can_use_aerial_armor(bot)
    return can_use_ward_ability(bot, xi.magic.spell.GARUDA, xi.effect.BLINK)
end
function role_smn.cast_aerial_armor(bot)
    return cast_ward_ability(bot, xi.jobAbility.AERIAL_ARMOR, xi.magic.spell.GARUDA)
end

function role_smn.can_use_lightning_armor(bot)
    return can_use_ward_ability(bot, xi.magic.spell.RAMUH, xi.effect.SHOCK_SPIKES)
end
function role_smn.cast_lightning_armor(bot)
    return cast_ward_ability(bot, xi.jobAbility.LIGHTNING_ARMOR, xi.magic.spell.RAMUH)
end

function role_smn.can_use_frost_armor(bot)
    if count_party_with_effect(bot, xi.effect.SHOCK_SPIKES) >= 1 then return false end
    return can_use_ward_ability(bot, xi.magic.spell.SHIVA, xi.effect.ICE_SPIKES)
end
function role_smn.cast_frost_armor(bot)
    return cast_ward_ability(bot, xi.jobAbility.FROST_ARMOR, xi.magic.spell.SHIVA)
end

function role_smn.can_use_rolling_thunder(bot)
    return can_use_ward_ability(bot, xi.magic.spell.RAMUH, xi.effect.ENTHUNDER)
end
function role_smn.cast_rolling_thunder(bot)
    return cast_ward_ability(bot, xi.jobAbility.ROLLING_THUNDER, xi.magic.spell.RAMUH)
end

function role_smn.can_use_lunar_cry(bot)
    if not role_smn.bp_ward_off_recast(bot) then return false end
    if not bot_knows_summon(bot, xi.magic.spell.FENRIR) then return false end
    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return false end
    if target.hasStatusEffect ~= nil
       and target:hasStatusEffect(xi.effect.ACCURACY_DOWN)
       and target:hasStatusEffect(xi.effect.EVASION_DOWN) then
        return false
    end
    return true
end
function role_smn.cast_lunar_cry(bot)
    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return false end
    return cast_ward_ability(bot, xi.jobAbility.LUNAR_CRY, xi.magic.spell.FENRIR, target)
end

function role_smn.can_use_crimson_howl(bot)
    return can_use_ward_ability(bot, xi.magic.spell.IFRIT, xi.effect.WARCRY)
end
function role_smn.cast_crimson_howl(bot)
    return cast_ward_ability(bot, xi.jobAbility.CRIMSON_HOWL, xi.magic.spell.IFRIT)
end

function role_smn.can_use_noctoshield(bot)
    return can_use_ward_ability(bot, xi.magic.spell.DIABOLOS, xi.effect.PHALANX)
end
function role_smn.cast_noctoshield(bot)
    return cast_ward_ability(bot, xi.jobAbility.NOCTOSHIELD, xi.magic.spell.DIABOLOS)
end

function role_smn.can_use_shining_ruby(bot)
    if count_party_with_effect(bot, xi.effect.PHALANX) >= 1 then return false end
    return can_use_ward_ability(bot, xi.magic.spell.CARBUNCLE, xi.effect.SHINING_RUBY)
end
function role_smn.cast_shining_ruby(bot)
    return cast_ward_ability(bot, xi.jobAbility.SHINING_RUBY, xi.magic.spell.CARBUNCLE)
end

function role_smn.cast_next_rage(bot)
    local bpId = role_smn.next_rage_bp(bot)
    if bpId == nil then return false end
    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return false end
    bot:useJobAbility(bpId, target)
    return true
end

function role_smn.set_avatar(primary, botName, spellId)
    if primary == nil or botName == nil or spellId == nil then return end
    for _, member in ipairs(primary:getAlliance() or {}) do
        if member:getName() == botName then
            local state = xi.singleplayer.bots.get_bot_state(member)
            state.smnAvatarSpellId = spellId
            printf('role_smn.set_avatar: %s -> %d', botName, spellId)
            return
        end
    end
    printf('role_smn.set_avatar: no owned bot "%s"', tostring(botName))
end

local function count_party_role(bot, role_enum)
    local n = 0
    local alliance_bot = xi.singleplayer.bots.alliance.bot
    for _, member in ipairs(xi.singleplayer.bots.magic.get_party_members(bot)) do
        local s = alliance_bot[member:getID()]
        if s ~= nil and s.role == role_enum then n = n + 1 end
    end
    return n
end

local function party_has_nin_tank(bot)
    local alliance_bot = xi.singleplayer.bots.alliance.bot
    local jobs = xi.singleplayer.bots.ai_util.jobs
    for _, member in ipairs(xi.singleplayer.bots.magic.get_party_members(bot)) do
        local s = alliance_bot[member:getID()]
        if s ~= nil and s.role == xi.singleplayer.bots.Role.Tank
           and jobs[member:getMainJob()] == 'NIN' then
            return true
        end
    end
    return false
end

function role_smn.on_load(bot)
end

function role_smn.tick(bot)
    if xi.singleplayer.bots.ai_util.is_force_rested(bot) then return end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.tick then
        xi.singleplayer.bots.ai_equip_swap.tick(bot);
    end
    if xi.singleplayer.bots.magic.process_pre_cast_checks(bot) then return end

    local ctx = xi.singleplayer.bots.magic.build_whm_ctx(bot, 'AutoSMN')

    local Role         = xi.singleplayer.bots.Role
    local meleePresent = count_party_role(bot, Role.Melee) >= 2
    local nukerPresent = count_party_role(bot, Role.Nuker) >= 2
    local haveNinTank  = party_has_nin_tank(bot)
    local buffedTarget = ctx.activeTarget ~= nil
                         and xi.singleplayer.bots.magic.dispellable_buff_count(ctx.activeTarget) >= 2

    if role_smn.can_use_elemental_siphon(bot) then
        ctx.log('elemental-siphon');
        role_smn.cast_elemental_siphon(bot);
    elseif ctx.activeTarget then
        if role_smn.has_pet(bot) then
            role_smn.ensure_pet_engaged(bot, ctx.activeTarget);
        end

        if role_smn.can_mb_rage(bot) then
            ctx.log('mb');
            role_smn.cast_mb_rage(bot);
        elseif xi.singleplayer.bots.magic.sc_is_close(bot) then
            ctx.log('sc_is_close');
        elseif role_smn.can_use_spring_water(bot) then
            ctx.log('spring-water');
            role_smn.cast_spring_water(bot);
        elseif xi.singleplayer.bots.magic.no_rdm(bot) and role_smn.can_use_hastega(bot) then
            ctx.log('hastega');
            role_smn.cast_hastega(bot);
        elseif buffedTarget and role_smn.can_use_lunar_roar(bot) then
            ctx.log('lunar-roar');
            role_smn.cast_lunar_roar(bot);
        elseif role_smn.can_use_ecliptic_growl(bot) then
            ctx.log('ecliptic-growl');
            role_smn.cast_ecliptic_growl(bot);
        elseif (meleePresent or haveNinTank) and role_smn.can_use_ecliptic_howl(bot) then
            ctx.log('ecliptic-howl');
            role_smn.cast_ecliptic_howl(bot);
        elseif nukerPresent and role_smn.can_use_dream_shroud(bot) then
            ctx.log('dream-shroud');
            role_smn.cast_dream_shroud(bot);
        elseif (meleePresent or haveNinTank) and role_smn.can_use_lunar_cry(bot) then
            ctx.log('lunar-cry');
            role_smn.cast_lunar_cry(bot);
        elseif meleePresent and role_smn.can_use_crimson_howl(bot) then
            ctx.log('crimson-howl');
            role_smn.cast_crimson_howl(bot);
        elseif role_smn.can_use_noctoshield(bot) then
            ctx.log('noctoshield');
            role_smn.cast_noctoshield(bot);
        elseif role_smn.can_use_shining_ruby(bot) then
            ctx.log('shining-ruby');
            role_smn.cast_shining_ruby(bot);
        elseif role_smn.can_summon_avatar(bot) then
            ctx.log('summon');
            role_smn.cast_summon_avatar(bot);
        elseif role_smn.can_use_rage(bot) then
            ctx.log('rage');
            role_smn.cast_next_rage(bot);
        elseif role_smn.can_revert_to_main(bot) then
            ctx.log('revert-to-main');
            role_smn.cast_revert_to_main(bot);
        else
            xi.singleplayer.bots.magic.whm_cascade(bot, ctx);
        end
    elseif not ctx.activeTarget then
        if role_smn.can_use_earthen_ward(bot) then
            ctx.log('earthen-ward');
            role_smn.cast_earthen_ward(bot);
        elseif not haveNinTank and role_smn.can_use_aerial_armor(bot) then
            ctx.log('aerial-armor');
            role_smn.cast_aerial_armor(bot);
        elseif role_smn.can_use_lightning_armor(bot) then
            ctx.log('lightning-armor');
            role_smn.cast_lightning_armor(bot);
        elseif role_smn.can_use_frost_armor(bot) then
            ctx.log('frost-armor');
            role_smn.cast_frost_armor(bot);
        elseif role_smn.can_use_rolling_thunder(bot) then
            ctx.log('rolling-thunder');
            role_smn.cast_rolling_thunder(bot);
        elseif role_smn.can_summon_avatar(bot) then
            ctx.log('summon');
            role_smn.cast_summon_avatar(bot);
        elseif role_smn.can_revert_to_main(bot) then
            ctx.log('revert-to-main');
            role_smn.cast_revert_to_main(bot);
        else
            xi.singleplayer.bots.magic.whm_cascade(bot, ctx);
        end
    end
end

return m
