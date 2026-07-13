-----------------------------------
-- Server-side AI: job ability + weapon skill + ranged attack decision logic.
-- Ported from client-side. All ability/spell IDs use xi.jobAbility.* /
-- xi.magic.spell.* named constants.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_ability')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.ability = xi.singleplayer.bots.ability or {}
local ai_ability = xi.singleplayer.bots.ability

ai_ability.jobs = { 'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN' }

-- Abilities that target a mob rather than self (preserved from ai_ability)
ai_ability.targetAbilities = {
    'Jump', 'High Jump', 'Super Jump', 'Steal', 'Mug',
    'Provoke', 'Shield Bash', 'Weapon Bash',
}

-- Per-job default ability rotation buckets. Port of the client-side library.
--     oncePerSC : fired once per skillchain window
--     everySC   : fired before every skillchain
--     always    : fired whenever recast is up (stance/buff abilities)
--     defense   : fired in reactive defense ticks (block/parry helpers)
ai_ability.defaultAbilityByJob = {
    ['WAR'] = { oncePerSC = { 'Berserk', 'Aggressor' }, everySC = { 'Warcry' },                            always = {},                              defense = {} },
    ['MNK'] = { oncePerSC = { 'Berserk' },              everySC = { 'Focus', 'Footwork', 'Warcry' },       always = {},                              defense = { 'Dodge' } },
    ['DRK'] = { oncePerSC = { 'Berserk', 'Souleater' }, everySC = { 'Last Resort', 'Warcry' },             always = {},                              defense = {} },
    ['SAM'] = { oncePerSC = { 'Berserk' },              everySC = { 'Warcry' },                            always = { 'Hasso', 'Seigan' },           defense = { 'Third Eye' } },
    ['NIN'] = { oncePerSC = { 'Berserk' },              everySC = { 'Warcry' },                            always = {},                              defense = {} },
    ['DRG'] = { oncePerSC = { 'Berserk' },              everySC = { 'Warcry' },                            always = { 'Jump' },                      defense = { 'High Jump' } },
    ['THF'] = { oncePerSC = {},                         everySC = {},                                      always = { 'Mug' },                       defense = {} },
    ['RNG'] = { oncePerSC = {},                         everySC = { 'Sharpshot' },                         always = { 'Velocity Shot' },             defense = {} },
    ['WHM'] = { oncePerSC = {},                         everySC = {},                                      always = { 'Afflatus Solace' },           defense = {} },
    ['BLM'] = { oncePerSC = {},                         everySC = {},                                      always = {},                              defense = {} },
    ['RDM'] = { oncePerSC = {},                         everySC = {},                                      always = {},                              defense = {} },
    ['PLD'] = { oncePerSC = {},                         everySC = { 'Warcry' },                            always = { 'Defender', 'Majesty' },       defense = {} },
    ['BST'] = { oncePerSC = {},                         everySC = {},                                      always = {},                              defense = {} },
    ['BRD'] = { oncePerSC = {},                         everySC = {},                                      always = {},                              defense = {} },
    ['SMN'] = { oncePerSC = {},                         everySC = {},                                      always = {},                              defense = {} },
    ['BLU'] = { oncePerSC = {},                         everySC = {},                                      always = {},                              defense = {} },
    ['COR'] = { oncePerSC = {},                         everySC = {},                                      always = {},                              defense = {} },
    ['PUP'] = { oncePerSC = {},                         everySC = {},                                      always = {},                              defense = {} },
    ['DNC'] = { oncePerSC = {},                         everySC = {},                                      always = {},                              defense = {} },
    ['SCH'] = { oncePerSC = {},                         everySC = {},                                      always = {},                              defense = {} },
    ['GEO'] = { oncePerSC = {},                         everySC = {},                                      always = {},                              defense = {} },
    ['RUN'] = { oncePerSC = {},                         everySC = {},                                      always = {},                              defense = {} },
}

-- Per-bot scratch lives on alliance.bot[charId] (consolidated #221). Thin
-- accessor preserves the local getState() name used throughout this file.
local function getState(bot)
    return xi.singleplayer.bots.ensure_bot(bot:getID())
end

-- destroy_state is no longer per-module; alliance.bot[id] = nil at despawn
-- clears all per-bot scratch in one shot (handled by bots_listeners).

-----------------------------------
-- Engine-side EFFECT_SKILLCHAIN reads. The engine sets this status on the
-- mob on every WS land (battleutils.cpp:3458+):
--   * tier == 0 : opener-pending. getPower() encodes the opener WS's SC
--                 properties as primary | (secondary<<4) | (tertiary<<8).
--                 The mob is chainable from 3s to 10s after getStartTimeMs().
--   * tier  > 0 : closed SC active. getPower() = single SKILLCHAIN_ELEMENT.
--                 MB window = getStartTimeMs() .. +getDuration() (10s).
--
-- Replaces five bot-side fields previously written by check_for_sc /
-- check_for_sc_close action listeners. getStartTimeMs is bound in
-- lua_statuseffect.cpp:88 to avoid 1s quantization on the 3s close window.
-----------------------------------

-- DB stores WS names as snake_case lowercase ('penta_thrust') but the JSON
-- configs use display form ('Penta Thrust'). The C++ binding is a strict
-- string compare, so display names always miss. Try the raw input first
-- (no-op when already snake_case) and fall back to a normalized lookup.
local function normalize_ws_name(s)
    if s == nil then return nil end
    local n = s:lower():gsub("'", "")
    n = n:gsub("[^%w]", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
    return n
end

function ai_ability.resolve_ws_id(name)
    if name == nil or name == '' or GetWeaponskillByName == nil then return 0 end
    local id = GetWeaponskillByName(name) or 0
    if id ~= 0 then return id end
    local normalized = normalize_ws_name(name)
    if normalized == nil or normalized == name then return 0 end
    return GetWeaponskillByName(normalized) or 0
end

-- "Is the pending opener ours?" Compares engine getPower() decoded bits
-- against our configured opener WS's SC properties.
local function sc_opener_matches_our_pair(bot, sc)
    local openerName = ai_ability.get_opening_ws(bot)
    if openerName == nil or openerName == '' then return false end
    local wsId = ai_ability.resolve_ws_id(openerName)
    if wsId == 0 then return false end
    local props = GetWeaponskillProperties(wsId)
    if props == nil then return false end
    local power = sc:getPower()
    return  props.primary   == bit.band(power, 0xF)
        and props.secondary == bit.band(bit.rshift(power, 4), 0xF)
        and props.tertiary  == bit.band(bit.rshift(power, 8), 0xF)
end

function ai_ability.sc_effect(bot)
    local target = xi.singleplayer.bots.ai_util.assist_target(bot)
    if target == nil or target.getStatusEffect == nil then return nil end
    return target:getStatusEffect(xi.effect.SKILLCHAIN)
end

-- ms-since-epoch when this bot's closer WS becomes eligible. 0 when no
-- opener is pending or the pending opener belongs to another pair.
function ai_ability.sc_close_window_start_ms(bot)
    local sc = ai_ability.sc_effect(bot)
    if sc == nil or sc:getTier() ~= 0 then return 0 end
    if not sc_opener_matches_our_pair(bot, sc) then return 0 end
    return sc:getStartTimeMs() + 3000
end

-- ms-since-epoch when the MB window closes. 0 if no closed SC.
function ai_ability.mb_window_close_ms(bot)
    local sc = ai_ability.sc_effect(bot)
    if sc == nil or sc:getTier() == 0 then return 0 end
    return sc:getStartTimeMs() + sc:getDuration()
end

-- True when an opener-pending SC was started by some other pair.
function ai_ability.other_sc_active(bot)
    local sc = ai_ability.sc_effect(bot)
    if sc == nil or sc:getTier() ~= 0 then return false end
    return not sc_opener_matches_our_pair(bot, sc)
end

-- Active SC element (SKILLCHAIN_ELEMENT enum value) when a closed SC is up,
-- else 0. Used by ai_magic for MB element selection.
function ai_ability.active_sc_type(bot)
    local sc = ai_ability.sc_effect(bot)
    if sc == nil or sc:getTier() == 0 then return 0 end
    return sc:getPower()
end

-----------------------------------
-- Ability name → ID resolution
--
-- Original built a name→ability map from libs/job_abilities.lua at addon load.
-- Server-side we use xi.jobAbility named constants. This table covers every
-- ability ai_ability references by name; add to it as new abilities ship.
-----------------------------------
ai_ability.idByName = {
    ['Sneak Attack']    = xi.jobAbility.SNEAK_ATTACK,
    ['Trick Attack']    = xi.jobAbility.TRICK_ATTACK,
    ['Boost']           = xi.jobAbility.BOOST,
    ['Chi Blast']       = xi.jobAbility.CHI_BLAST,
    ['Chakra']          = xi.jobAbility.CHAKRA,
    ['Spirit Link']     = xi.jobAbility.SPIRIT_LINK,
    ['Call Wyvern']     = xi.jobAbility.CALL_WYVERN,
    ['Barrage']         = xi.jobAbility.BARRAGE,
    ['Elemental Seal']  = xi.jobAbility.ELEMENTAL_SEAL,
    ['Provoke']         = xi.jobAbility.PROVOKE,
    ['Shield Bash']     = xi.jobAbility.SHIELD_BASH,
    ['Sentinel']        = xi.jobAbility.SENTINEL,
    ['Holy Circle']     = xi.jobAbility.HOLY_CIRCLE,
    ['Ancient Circle']  = xi.jobAbility.ANCIENT_CIRCLE,
    ['Arcane Circle']   = xi.jobAbility.ARCANE_CIRCLE,
    ['Warding Circle']  = xi.jobAbility.WARDING_CIRCLE,
    ['Rampart']         = xi.jobAbility.RAMPART,
    ['Weapon Bash']     = xi.jobAbility.WEAPON_BASH,
    ['Jump']            = xi.jobAbility.JUMP,
    ['High Jump']       = xi.jobAbility.HIGH_JUMP,
    ['Super Jump']      = xi.jobAbility.SUPER_JUMP,
    -- Generic rotation abilities (defaultAbilityByJob references). Without
    -- these, get_next_ability silently no-ops every tick since get_ability_id
    -- returns nil. SATA / Provoke etc. above have dedicated paths and were
    -- working before this gap was discovered.
    ['Berserk']         = xi.jobAbility.BERSERK,
    ['Aggressor']       = xi.jobAbility.AGGRESSOR,
    ['Warcry']          = xi.jobAbility.WARCRY,
    ['Defender']        = xi.jobAbility.DEFENDER,
    ['Majesty']         = xi.jobAbility.MAJESTY,
    ['Focus']           = xi.jobAbility.FOCUS,
    ['Footwork']        = xi.jobAbility.FOOTWORK,
    ['Hasso']           = xi.jobAbility.HASSO,
    ['Seigan']          = xi.jobAbility.SEIGAN,
    ['Third Eye']       = xi.jobAbility.THIRD_EYE,
    ['Souleater']       = xi.jobAbility.SOULEATER,
    ['Last Resort']     = xi.jobAbility.LAST_RESORT,
    ['Mug']             = xi.jobAbility.MUG,
    ['Sharpshot']       = xi.jobAbility.SHARPSHOT,
    ['Velocity Shot']   = xi.jobAbility.VELOCITY_SHOT,
    ['Afflatus Solace'] = xi.jobAbility.AFFLATUS_SOLACE,
    ['Dodge']           = xi.jobAbility.DODGE,
    ['Pianissimo']      = xi.jobAbility.PIANISSIMO,
}

ai_ability.nameById = {}
for name, id in pairs(ai_ability.idByName) do ai_ability.nameById[id] = name end

-----------------------------------
-- 1. is_nm
-----------------------------------
-- Composite "is this fight high-stakes" check. Replaces the manual
-- `cfg.nm` JSON flag with engine-derived truth. Covers:
--   * mob:isNM()                   — NOTORIOUS bit (sky/sea/ground gods,
--                                    Jailers, Maat-class BCNMs, open-world
--                                    HNMs).
--   * primary:getBattlefieldID()>-1 — BCNM/ENM/KSNM/Limbus/Salvage,
--                                    including BATTLEFIELD-only mobs that
--                                    don't carry NOTORIOUS (e.g. Bahamut).
--   * primary:isInDynamis()        — entire zone, no per-mob check.
-- Auto-clears when the alliance leaves the fight; no manual config flag.
-- See bots.lua TODO at the `nm` field for the trivial-NM caveat.
function ai_ability.is_nm(bot)
    -- Pure engine-derived check — Dynamis OR battlefield OR notoriety:isNM.
    -- The old tri-state alliance flag (Off/On/Auto) was retired; the manual
    -- override was redundant with Role AI's per-role mode toggles and the
    -- force-on path was a niche dev tool.
    local A = xi.singleplayer.bots.alliance
    local primary = (A and A.mainEntity) or GetPlayerByID(bot:getParentCharId())
    if primary == nil then return false end
    if primary.isInDynamis and primary:isInDynamis() then return true end
    if primary.getBattlefieldID and primary:getBattlefieldID() > -1 then return true end
    if primary.getNotorietyList then
        for _, mob in ipairs(primary:getNotorietyList() or {}) do
            if mob.isNM and mob:isNM() then return true end
        end
    end
    return false
end

-- Called from 0x176 AUTOBOTS SET_SATA_MODE via luautils::OnBotSetSataMode.
-- Per-bot. Mode values:
--   0 = combined (default — SA→TA→WS in one combo)
--   1 = split    (alternate SA and TA across consecutive WSes)
--   2 = saonly   (only ever use SA; TA never fires)
-- Out-of-range modes clamp to combined. Ownership check (parent matches
-- primary) gates the mutation.
local SATA_MODE_BY_VALUE = { [0] = 'combined', [1] = 'split', [2] = 'saonly' }
function ai_ability.set_bot_sata_mode(primary, botName, mode)
    if primary == nil or botName == nil or botName == '' then return end
    local target = botName:lower()
    local primaryId = primary:getID()
    -- A bot is "owned" if it's the primary themselves OR a headless whose
    -- parentCharId == primaryId. Previously this only accepted headless,
    -- so the primary's own SATA config silently failed with a "no owned
    -- headless" log even when they're an SA/TA-eligible job.
    local function is_owned(m)
        if m == primary then return true end
        if m.isHeadless and m:isHeadless()
           and m.getParentCharId and m:getParentCharId() == primaryId then
            return true
        end
        return false
    end
    for _, member in ipairs(primary:getAlliance() or {}) do
        if is_owned(member) and member:getName():lower() == target then
            local s = xi.singleplayer.bots.ensure_bot(member:getID())
            local newMode = SATA_MODE_BY_VALUE[tonumber(mode) or -1] or 'combined'
            s.sataMode = newMode
            -- Reset the alternation cursor whenever the mode changes so the
            -- next WS starts fresh rather than inheriting state from a
            -- previous run in a different mode.
            s.selectedSata = nil
            printf(string.format('ai_ability.set_bot_sata_mode: %s -> %s',
                member:getName(), newMode))
            return
        end
    end
    printf(string.format('ai_ability.set_bot_sata_mode: no owned bot "%s"', tostring(botName)))
end

-- Called from 0x176 AUTOBOTS SET_SC_THRESHOLD via luautils::OnBotSetScThreshold.
-- which: 0 = scStartHP, 1 = scStopHP, 2 = scNoMoreHP.
-- value clamps to [0, 100]. No relation check between thresholds — the user
-- can configure overlapping/inverted values and the gates handle whatever
-- they get (overlaps just mean the gate is permanently true or false).
function ai_ability.set_alliance_sc_threshold(primary, which, value)
    if xi.singleplayer.bots.alliance == nil then return end
    which = tonumber(which) or -1
    value = tonumber(value) or 0
    if value < 0   then value = 0   end
    if value > 100 then value = 100 end
    local field = ({[0] = 'scStartHP', [1] = 'scStopHP', [2] = 'scNoMoreHP'})[which]
    if field == nil then return end
    xi.singleplayer.bots.alliance[field] = value
    printf(string.format('ai_ability.set_alliance_sc_threshold: %s -> %d', field, value))
end

-- Called from 0x176 AUTOBOTS FIRE_ALL_WS via luautils::OnBotFireAllWs.
-- Force-fire each linked bot's configured WS now. Bypasses SC opener/closer,
-- MB-window, should_close_sc, and should_use_ability gates that the AI tick
-- normally consults. Engine still rejects below 1000 TP, not engaged, etc.
-- so we don't burn cycles dispatching obvious no-ops — skip those at the
-- Lua layer and log a single summary.
function ai_ability.fire_all_ws(primary)
    if primary == nil then return end
    local primaryId = primary:getID()
    local fired, skipped = 0, 0
    local function try_fire(bot)
        if bot == nil then return end
        if not (bot.isEngaged and bot:isEngaged()) then skipped = skipped + 1; return end
        if (bot.getTP and bot:getTP() or 0) < 1000 then skipped = skipped + 1; return end
        local wsName = ai_ability.get_ws(bot)
        if wsName == nil or wsName == '' then skipped = skipped + 1; return end
        ai_ability.use_ws(bot, wsName)
        fired = fired + 1
    end
    try_fire(primary)
    for _, member in ipairs(primary:getAlliance() or {}) do
        if member.isHeadless and member:isHeadless()
           and member.getParentCharId and member:getParentCharId() == primaryId
        then
            try_fire(member)
        end
    end
    printf(string.format('ai_ability.fire_all_ws: fired=%d skipped=%d for %s',
        fired, skipped, primary:getName()))
end

-----------------------------------
-- 2. get_assist
-----------------------------------
-- Returns the assist's NAME. Kept name-returning for compat with the
-- callsites that compare against bot:getName(); for entity access use
-- xi.singleplayer.bots.get_assist_entity().
function ai_ability.get_assist(_)
    local assist = xi.singleplayer.bots.get_assist_entity()
    return assist and assist:getName() or nil
end

-----------------------------------
-- 3. get_ws
--    Returns this bot's configured WS name (open / close / assist / solo).
-----------------------------------
function ai_ability.get_ws(bot)
    -- alliance.solo / alliance.sc are charId-keyed (built at load by bots_spawn).
    -- Tank's WS lives on alliance.solo[assistCharId] (folded in at spawn), so a
    -- single solo lookup serves both regular solo bots AND the tank.
    local id   = bot:getID()
    local solo = xi.singleplayer.bots.alliance and xi.singleplayer.bots.alliance.solo
    if solo and solo[id] then return solo[id] end
    for _, pair in ipairs(ai_ability.sc_pairs()) do
        if pair.openCharId  == id then return pair.openWS  end
        if pair.closeCharId == id then return pair.closeWS end
    end
    return nil
end

-----------------------------------
-- SC pair accessors (alliance.sc is the runtime array of pair objects, each
-- { openCharId, openName, openWS, closeCharId, closeName, closeWS, priority },
-- built by bots_spawn at load from the cfg.sc disk array).
-----------------------------------
function ai_ability.sc_pairs()
    return (xi.singleplayer.bots.alliance and xi.singleplayer.bots.alliance.sc) or {}
end

local function pair_as_opener(id)
    for _, p in ipairs(ai_ability.sc_pairs()) do
        if p.openCharId == id then return p end
    end
    return nil
end
local function pair_as_closer(id)
    for _, p in ipairs(ai_ability.sc_pairs()) do
        if p.closeCharId == id then return p end
    end
    return nil
end

-----------------------------------
-- 4. no_sc — true when the alliance has no SC pairs configured at all.
-----------------------------------
function ai_ability.no_sc(_)
    return #ai_ability.sc_pairs() == 0
end

-----------------------------------
-- 5. is_second_sc — true when this bot belongs to a pair beyond the first.
-----------------------------------
function ai_ability.is_second_sc(bot)
    local id = bot:getID()
    for i, p in ipairs(ai_ability.sc_pairs()) do
        if (p.openCharId == id or p.closeCharId == id) then
            return i > 1
        end
    end
    return false
end

-----------------------------------
-- 6. is_opener
-----------------------------------
function ai_ability.is_opener(bot)
    return pair_as_opener(bot:getID()) ~= nil
end

-----------------------------------
-- 7. get_opener
-----------------------------------
function ai_ability.get_opener(bot)
    local p = pair_as_closer(bot:getID())
    return p and p.openName or nil
end

-----------------------------------
-- 8. get_opening_ws
-----------------------------------
function ai_ability.get_opening_ws(bot)
    local p = pair_as_closer(bot:getID())
    return p and p.openWS or nil
end

-----------------------------------
-- 10. is_closer
-----------------------------------
function ai_ability.is_closer(bot)
    return pair_as_closer(bot:getID()) ~= nil
end

-----------------------------------
-- 11. get_closer
-----------------------------------
function ai_ability.get_closer(bot)
    local p = pair_as_opener(bot:getID())
    return p and p.closeName or nil
end

-----------------------------------
-- 12. get_closer_tp
-----------------------------------
function ai_ability.get_closer_tp(bot)
    local p = pair_as_opener(bot:getID())
    if p == nil then return 0 end
    for _, member in ipairs(bot:getAlliance() or {}) do
        if member:getID() == p.closeCharId and member:getZone() == bot:getZone() then
            return member:getTP()
        end
    end
    return 0
end

-----------------------------------
-- 14. is_solo — true when bot is not assigned to any SC pair.
-----------------------------------
function ai_ability.is_solo(bot)
    local id = bot:getID()
    return pair_as_opener(id) == nil and pair_as_closer(id) == nil
end

-----------------------------------
-- 15. gather_tp_values — returns an array of { open, close } TP per pair.
-----------------------------------
function ai_ability.gather_tp_values(bot)
    local pairs_ = ai_ability.sc_pairs()
    local out    = {}
    for i = 1, #pairs_ do out[i] = { open = 0, close = 0 } end
    for _, member in ipairs(bot:getAlliance() or {}) do
        local mid = member:getID()
        for i, p in ipairs(pairs_) do
            if p.openCharId  == mid then out[i].open  = member:getTP() end
            if p.closeCharId == mid then out[i].close = member:getTP() end
        end
    end
    return out
end

-----------------------------------
-- 16. first_sc_close — first pair has both ends >850 TP (ready to fire SC).
-----------------------------------
function ai_ability.first_sc_close(bot)
    local tp = ai_ability.gather_tp_values(bot)
    return tp[1] ~= nil and tp[1].open > 850 and tp[1].close > 850
end

-----------------------------------
-- 16b. higher_priority_close — true when any pair with a LOWER ARRAY
--      INDEX than this bot's pair has both ends >850 TP, i.e. is about
--      to fire and we should hold off.
--
-- "Priority" only seeds the INITIAL ordering of alliance.sc at spawn
-- (bots_spawn sorts by cfg.priority once, then the .priority field is
-- never read again). At runtime, position in alliance.sc IS the effective
-- priority: index 1 fires first, then index 2, etc. fan_rotate_sc_on_close
-- moves a fired closer's pair to the BACK of the array, so the next pair
-- naturally rotates into the front slot. Round-robin across N pairs.
--
-- Mirrors the original Ashita addon's SC2-waits-for-SC1 staggering and
-- generalizes it: pair at index 2 waits on index 1, pair 3 on 1+2, etc.
--
-- Returns false for solo bots and for the front-of-array pair (no one
-- ahead of them).
-----------------------------------
function ai_ability.higher_priority_close(bot)
    local pairs_ = ai_ability.sc_pairs()
    if #pairs_ == 0 then return false end
    local id = bot:getID()
    local myIdx
    for i, p in ipairs(pairs_) do
        if p.openCharId == id or p.closeCharId == id then myIdx = i; break end
    end
    if myIdx == nil or myIdx == 1 then return false end
    local tp = ai_ability.gather_tp_values(bot)
    for i = 1, myIdx - 1 do
        if tp[i] ~= nil and tp[i].open > 850 and tp[i].close > 850 then return true end
    end
    return false
end

-----------------------------------
-- 17. both_close_sc — every configured pair has both ends >900 TP.
-----------------------------------
function ai_ability.both_close_sc(bot)
    local tp = ai_ability.gather_tp_values(bot)
    if #tp == 0 then return false end
    for _, p in ipairs(tp) do
        if p.open <= 900 or p.close <= 900 then return false end
    end
    return true
end

-----------------------------------
-- 18. no_close_sc — every configured pair has both ends <850 TP.
-----------------------------------
function ai_ability.no_close_sc(bot)
    local tp = ai_ability.gather_tp_values(bot)
    if #tp == 0 then return true end
    for _, p in ipairs(tp) do
        if p.open >= 850 or p.close >= 850 then return false end
    end
    return true
end

-----------------------------------
-- 18b. WS-firing decision predicates. Shared by role_melee + role_tank so
-- both can drive SC opener / closer / solo WS off the same logic. Pure
-- predicates: they decide "should this bot fire a WS right now?" but the
-- caller picks how to fire (role_melee bundles SATA/Boost first via its
-- local use_weapon_skill; role_tank just calls use_ws directly).
-----------------------------------

-- is_sc_paused: true when the SC pair this bot belongs to has been paused
-- (per-bot scratch state.sc_paused[pairIdx]). User-driven pause flag from
-- the addon UI — applies to anyone in an SC pair, including a tank.
function ai_ability.is_sc_paused(bot)
    local state = xi.singleplayer.bots.ensure_bot(bot:getID())
    if state.sc_paused == nil then return false end
    local id = bot:getID()
    for i, p in ipairs(ai_ability.sc_pairs()) do
        if p.openCharId == id or p.closeCharId == id then
            return state.sc_paused[i] == true
        end
    end
    return false
end

-- set_alliance_pause: called from 0x176 AUTOBOTS SC_PAUSE via luautils::
-- OnBotScPause. Walks every headless owned by this primary and flips the
-- per-bot sc_paused[scId] flag. scId 0 = all pairs, n>0 = nth pair in
-- alliance.sc. Role-agnostic — tanks-as-SC-participants share this writer
-- (#225); the is_sc_paused reader above keys on pair membership not role.
function ai_ability.set_alliance_pause(primary, scId, paused)
    if primary == nil then return end
    local primaryId = primary:getID()
    local pairCount = #ai_ability.sc_pairs()
    local count = 0
    for _, member in ipairs(primary:getAlliance() or {}) do
        if member.isHeadless and member:isHeadless()
           and member.getParentCharId and member:getParentCharId() == primaryId
        then
            local s = xi.singleplayer.bots.ensure_bot(member:getID())
            s.sc_paused = s.sc_paused or {}
            if scId == 0 then
                for i = 1, pairCount do s.sc_paused[i] = paused end
            else
                s.sc_paused[scId] = paused
            end
            count = count + 1
        end
    end
    printf(string.format('ai_ability.set_alliance_pause: scId=%d paused=%s applied to %d bot(s) of %s',
        scId, tostring(paused), count, primary:getName()))
end

-- target_in_melee_range: server-authoritative range gate using the same
-- formula the C++ attack pipeline uses (bot.hitbox + 2.0 + target.hitbox).
function ai_ability.target_in_melee_range(bot)
    local target = bot:getTarget()
    if target == nil then return false end
    return bot:checkDistance(target) <= bot:getMeleeRange(target)
end

-- can_weaponskill: shared TP + SATA + range gate. SATA wait is THF-only
-- (handled by ai_ability.wait_for_sata); other jobs always pass that arm.
function ai_ability.wait_for_sata(bot)
    local state = xi.singleplayer.bots.ensure_bot(bot:getID())
    if state.sataInProgress then return false end
    if xi.singleplayer.bots.ai_util.is_job(bot, 'THF') then
        local mainJobLevel = bot.getMainLvl and bot:getMainLvl() or 0
        if mainJobLevel >= 15 then
            if state.sataMode == 'split' then
                return not ai_ability.can_use_sneak_attack(bot) and not ai_ability.can_use_trick_attack(bot)
            elseif state.sataMode == 'saonly' then
                return not ai_ability.can_use_sneak_attack(bot)
            else
                if mainJobLevel >= 30 then
                    return not ai_ability.can_use_sata(bot)
                else
                    return not ai_ability.can_use_sneak_attack(bot)
                end
            end
        end
    end
    return false
end

function ai_ability.can_weaponskill(bot)
    return bot:getTP() > 999
        and not ai_ability.wait_for_sata(bot)
        and ai_ability.target_in_melee_range(bot)
end

-- Wall-clock ms-since-epoch — must match the scale of engine-supplied
-- timestamps (sc:getStartTimeMs(), etc). `os.clock()` is CPU time since
-- process start (~10^7 scale) and is NOT comparable to epoch ms (~10^12);
-- using it here previously meant the `_ms_now() > scCloseStart` comparison
-- was always false and the closer never fired its WS.
local function _ms_now() return xi.singleplayer.bots.ai_util.get_ms_since_epoch() end

-- should_close_sc: is_closer + close window open + not paused. The 1-tick
-- post-window grace is handled by the caller; we just answer "are we
-- inside the open window now?".
function ai_ability.should_close_sc(bot)
    if not ai_ability.is_closer(bot) then return false end
    if ai_ability.is_sc_paused(bot) then return false end
    local scCloseStart = ai_ability.sc_close_window_start_ms(bot)
    if scCloseStart <= 0 then return false end
    return _ms_now() > scCloseStart
end

-- should_open_sc: is_opener + can_weaponskill + closer ready + valid mob HP
-- + no higher-priority SC pair already firing. NM gating widens the HP
-- envelope (5-98 vs 25-95) since NMs reward more chains over their lifespan.
function ai_ability.should_open_sc(bot)
    -- TRIAGE (#SC2-not-firing): closure that logs the blocking gate once per
    -- 3s for openers with TP > 999. Fires raw printf (bypasses BOT_AI_CHAT_LOG
    -- gate) — this is targeted debugging for SC2-not-firing, remove once
    -- root-caused. is_second_sc-only so we don't flood on healthy SC1.
    local _state = xi.singleplayer.bots.ensure_bot and xi.singleplayer.bots.ensure_bot(bot:getID()) or nil
    local function blocked(reason)
        if _state ~= nil and ai_ability.is_second_sc(bot) then
            local now = _ms_now()
            if (now - (_state.scOpenerTriageMs or 0)) > 3000 and (bot:getTP() or 0) > 999 then
                printf('[sc2-triage] %s: %s (tp=%d closerTp=%d)',
                    bot:getName(), reason, bot:getTP() or 0, ai_ability.get_closer_tp(bot))
                _state.scOpenerTriageMs = now
            end
        end
        return false
    end

    if not ai_ability.is_opener(bot) then return false end
    if ai_ability.is_sc_paused(bot) then return blocked('is_sc_paused') end
    if not ai_ability.can_weaponskill(bot) then return blocked('!can_weaponskill (tp/sata/range)') end
    if ai_ability.get_closer_tp(bot) <= 999 then return blocked('closer tp <= 999') end

    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return blocked('no current mob target') end
    -- NM gating replaced by runtime-tunable scStartHP / scStopHP (alliance.*).
    -- Closer ignores these gates entirely — if the opener fires below scStopHP
    -- (which it can if HP drops mid-cast), the closer still closes.
    local A        = xi.singleplayer.bots.alliance
    local upperHP  = (A and A.scStartHP)  or 95
    local lowerHP  = (A and A.scStopHP)   or 10
    local hpp      = target:getHPP()
    if hpp <= lowerHP then return blocked('mob hpp <= scStopHP') end
    if hpp >= upperHP then return blocked('mob hpp >= scStartHP') end

    local mbWindowEnd = ai_ability.mb_window_close_ms(bot)
    if _ms_now() <= mbWindowEnd then return blocked('mb window open') end
    if ai_ability.other_sc_active(bot) then return blocked('other_sc_active') end
    if ai_ability.higher_priority_close(bot) then return blocked('higher_priority_close') end
    return true
end

-- should_solo_ws: is_solo (not in any SC pair) + can_weaponskill + timing
-- gates. Wide path when alliance has no SC at all; otherwise wait for
-- MB window to close + no close-imminent SC (or rescue-fire on very low HP).
function ai_ability.should_solo_ws(bot)
    if not ai_ability.is_solo(bot) then return false end
    if not ai_ability.can_weaponskill(bot) then return false end
    if ai_ability.no_sc(bot) then return true end

    local target = xi.singleplayer.bots.get_current_mob_target()
    local hpp    = target and target:getHPP() or 100
    -- NM gating replaced by runtime-tunable scNoMoreHP (alliance.*).
    -- Mob's down to this HP%, no more SCs will open — solo melees fire WS
    -- now instead of waiting on the MB window.
    local A        = xi.singleplayer.bots.alliance
    local rescueHP = (A and A.scNoMoreHP) or 8

    local mbWindowEnd = ai_ability.mb_window_close_ms(bot)
    local mbNotActive = _ms_now() > mbWindowEnd
    local scNotClose  = ai_ability.no_close_sc(bot)
    local lowHp       = ai_ability.both_close_sc(bot) and hpp < rescueHP
    return mbNotActive and (scNotClose or lowHp)
end

-----------------------------------
-- 19. get_current_job
-----------------------------------
function ai_ability.get_current_job(bot)
    return ai_ability.jobs[bot:getMainJob()]
end

-----------------------------------
-- 20. is_offensive_ability
-----------------------------------
function ai_ability.is_offensive_ability(bot, abilityName)
    return xi.singleplayer.bots.ai_util.table_contains(ai_ability.targetAbilities, abilityName)
end

-----------------------------------
-- 21. get_ability_id
-----------------------------------
function ai_ability.get_ability_id(abilityName)
    return ai_ability.idByName[abilityName]
end

-----------------------------------
-- 22. get_ability_name
-----------------------------------
function ai_ability.get_ability_name(abilityId)
    return ai_ability.nameById[abilityId]
end

-----------------------------------
-- 23. get_ability_recast_id
--     Server-side: most abilities use their own ID as the recast ID; the few
--     exceptions are in xi.recastID (BLOODPACT_*, PHANTOM_ROLL, etc.).
-----------------------------------
function ai_ability.get_ability_recast_id(abilityName)
    return ai_ability.idByName[abilityName]  -- ability id == recast id for standard JAs
end

-----------------------------------
-- 24. get_ability_status_id
--     Maps the ability to the status effect it applies (e.g. Sneak Attack →
--     EFFECT_SNEAK_ATTACK). For ones that don't apply a status, returns nil.
--
--     Boost is intentionally absent: it's the one JA we use where re-firing
--     while the effect is up is correct behavior — every cast bumps the
--     boost stack, and there's no point at which we want to stop. Recast
--     (~15s) is the SOLE throttle. Original ffxi-ashita addon worked this
--     way; the port mistakenly mapped Boost here, which locked it after
--     the first fire until the 3-minute effect expired. Letting
--     ability_is_active return false for Boost lets it fire forever once
--     off cooldown.
-----------------------------------
ai_ability.statusByAbility = {
    ['Sneak Attack']   = xi.effect.SNEAK_ATTACK,
    ['Trick Attack']   = xi.effect.TRICK_ATTACK,
    ['Elemental Seal'] = xi.effect.ELEMENTAL_SEAL,
    ['Sentinel']       = xi.effect.SENTINEL,
    ['Rampart']        = xi.effect.RAMPART,
    -- Status-effect-bearing rotation abilities. Without these mapped here,
    -- ability_is_active returns false even when the effect is up, so the
    -- generic picker re-fires the ability on cooldown — wastes a JA window
    -- (e.g. Berserk lasts 3 min but the picker tries again every recast).
    -- All entries use jobAbility name = effect name (verified against
    -- scripts/enum/effect.lua).
    ['Berserk']        = xi.effect.BERSERK,
    ['Aggressor']      = xi.effect.AGGRESSOR,
    ['Warcry']         = xi.effect.WARCRY,
    ['Defender']       = xi.effect.DEFENDER,
    ['Majesty']        = xi.effect.MAJESTY,
    ['Focus']          = xi.effect.FOCUS,
    ['Footwork']       = xi.effect.FOOTWORK,
    ['Hasso']          = xi.effect.HASSO,
    ['Seigan']         = xi.effect.SEIGAN,
    ['Third Eye']      = xi.effect.THIRD_EYE,
    ['Souleater']      = xi.effect.SOULEATER,
    ['Last Resort']    = xi.effect.LAST_RESORT,
    ['Sharpshot']      = xi.effect.SHARPSHOT,
    ['Velocity Shot']  = xi.effect.VELOCITY_SHOT,
    ['Afflatus Solace'] = xi.effect.AFFLATUS_SOLACE,
    ['Dodge']          = xi.effect.DODGE,
    -- Mug intentionally absent — it's a one-shot enemy interaction with no
    -- self-status; the picker's recast check is the sole throttle. Same
    -- pattern as Boost above.
}
function ai_ability.get_ability_status_id(abilityName)
    return ai_ability.statusByAbility[abilityName]
end

-----------------------------------
-- 25. ability_is_active
-----------------------------------
function ai_ability.ability_is_active(bot, abilityName)
    local statusId = ai_ability.get_ability_status_id(abilityName)
    if statusId == nil then return false end
    return bot:hasStatusEffect(statusId)
end

-----------------------------------
-- 25a. JA range — engine-derived helpers
--
-- Mirrors ai_magic.spell_range (#192): GetAbility(id):getRange() reads from
-- abilities.sql (column 14) — the engine's authoritative range for each JA.
-- Self-buff JAs (Berserk, Aggressor, Hasso, Boost, etc.) have range=0 in
-- the data → no range gate, always in-range.
--
-- Pickers filter out abilities the bot can't reach so we don't fire Jump
-- from 12y when the engine cap is 8 (DRG's freeze symptom) or lock
-- is_busy_actioning for 4s while still out of effective range.
--
-- A small safety shave (mirrors spells' SPELL_RANGE_SAFETY_SHAVE) keeps
-- bots from firing at the exact edge of range where the mob's micro-
-- movement can put them just-out-of-range by the time the action lands.
-----------------------------------
local JA_RANGE_SAFETY_SHAVE = 1.0
local JA_RANGE_FLOOR        = 3.0  -- never shave below this; melee-class abilities

-- Returns the engine-supplied range for the ability, shaved for safety,
-- or 0 when the engine reports no range (self/area-on-self buffs).
function ai_ability.ja_range(_, abilityName)
    local abilityId = ai_ability.get_ability_id(abilityName)
    if abilityId == nil then return 0 end
    local PAb = GetAbility and GetAbility(abilityId) or nil
    if PAb == nil or PAb.getRange == nil then return 0 end
    local raw = PAb:getRange() or 0
    if raw <= 0 then return 0 end
    local shaved = raw - JA_RANGE_SAFETY_SHAVE
    if shaved < JA_RANGE_FLOOR then shaved = JA_RANGE_FLOOR end
    return shaved
end

-- True when the JA is reachable on the current engaged target — or the
-- engine reports range=0 (self-buff). Pickers call this AFTER the
-- recast/known checks since the engine lookup is the heaviest step.
function ai_ability.ja_in_range(bot, abilityName)
    local r = ai_ability.ja_range(bot, abilityName)
    if r <= 0 then return true end  -- self-buff, no gate
    local mobId = xi.singleplayer.bots.get_alliance_target_id()
    if mobId == 0 then
        -- No engaged mob → offensive JA has no target. Defer the question;
        -- treat as in-range so buff JAs queued pre-engage aren't blocked.
        return true
    end
    local target = GetEntityByID(mobId)
    if target == nil then return true end
    return bot:checkDistance(target) <= r
end

-----------------------------------
-- 26. get_next_ability
--     Walks an ability name list, returns the first whose status isn't active
--     and that's off recast AND that the bot is in range to use.
-----------------------------------
function ai_ability.get_next_ability(bot, abilityTbl)
    for _, abilityName in ipairs(abilityTbl) do
        if not ai_ability.ability_is_active(bot, abilityName) then
            local abilityId = ai_ability.get_ability_id(abilityName)
            if abilityId and bot.hasJobAbility and bot:hasJobAbility(abilityId) then
                -- hasRecast indexes by RECAST id, not ability id. For Provoke
                -- (abilityId 35) the recast id is 5; passing 35 to hasRecast
                -- always returns false even when the JA is on cooldown.
                local PAb     = GetAbility and GetAbility(abilityId) or nil
                local recastId = PAb and PAb:getRecastID() or abilityId
                if not bot:hasRecast(xi.recast.ABILITY, recastId)
                   and ai_ability.ja_in_range(bot, abilityName) then
                    return abilityName
                end
            end
        end
    end
    return nil
end

-----------------------------------
-- Ability-config lookup. Returns the per-job rotation buckets from
-- ai_ability.defaultAbilityByJob (ported from autoability_config.lua).
-----------------------------------
local function get_ability_config(_)
    return ai_ability.defaultAbilityByJob
end

-----------------------------------
-- 27. get_next_before_sc_ability
-----------------------------------
function ai_ability.get_next_before_sc_ability(bot)
    local cfg = get_ability_config(bot)[ai_ability.get_current_job(bot)]
    if cfg == nil then return nil end
    return ai_ability.get_next_ability(bot, cfg.oncePerSC or {})
end

-----------------------------------
-- 28. get_next_sc_ability
-----------------------------------
function ai_ability.get_next_sc_ability(bot)
    local cfg = get_ability_config(bot)[ai_ability.get_current_job(bot)]
    if cfg == nil then return nil end
    return ai_ability.get_next_ability(bot, cfg.everySC or {})
end

-----------------------------------
-- 29. get_next_always_ability
-----------------------------------
function ai_ability.get_next_always_ability(bot)
    local cfg = get_ability_config(bot)[ai_ability.get_current_job(bot)]
    if cfg == nil then return nil end
    return ai_ability.get_next_ability(bot, cfg.always or {})
end

-----------------------------------
-- 30. always_ability_is_up
-----------------------------------
function ai_ability.always_ability_is_up(bot)
    return ai_ability.get_next_always_ability(bot) ~= nil
end

-----------------------------------
-- 31. use_next_always_ability
-----------------------------------
function ai_ability.use_next_always_ability(bot)
    local ability = ai_ability.get_next_always_ability(bot)
    if ability ~= nil then
        ai_ability.use_ability(bot, ability, ai_ability.is_offensive_ability(bot, ability))
    end
end

-----------------------------------
-- 32. get_next_defense_ability
-----------------------------------
function ai_ability.get_next_defense_ability(bot)
    local cfg = get_ability_config(bot)[ai_ability.get_current_job(bot)]
    if cfg == nil then return nil end
    return ai_ability.get_next_ability(bot, cfg.defense or {})
end

-----------------------------------
-- 33. use_ability
-----------------------------------
function ai_ability.use_ability(bot, abilityName, isOffensive)
    if abilityName == nil then return end
    local abilityId = ai_ability.get_ability_id(abilityName)
    if abilityId == nil then return end
    local target = bot
    if isOffensive then
        target = xi.singleplayer.bots.get_current_mob_target() or bot
    end
    if target == nil then return end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_jobability then xi.singleplayer.bots.ai_equip_swap.equip_jobability(bot, abilityId) end
    bot:useJobAbility(abilityId, target)
end

-----------------------------------
-- 34. use_ability_on
-----------------------------------
function ai_ability.use_ability_on(bot, abilityName, targetServerId)
    if abilityName == nil or targetServerId == nil then return end
    local target = GetEntityByID(targetServerId)
    if target == nil then return end
    local abilityId = ai_ability.get_ability_id(abilityName)
    if abilityId == nil then return end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_jobability then xi.singleplayer.bots.ai_equip_swap.equip_jobability(bot, abilityId) end
    bot:useJobAbility(abilityId, target)
end

-----------------------------------
-- 35. have_ability
-----------------------------------
function ai_ability.have_ability(bot, abilityName)
    return ai_ability.get_next_ability(bot, { abilityName }) ~= nil
end

-- 35a. ability_off_recast
--   Same idea as have_ability but SKIPS the ja_in_range gate. Use this when
--   you want to queue an ability for later — the queue dispatch (e.g.
--   role_melee.lua's Chi Blast deferred fire) has its own range check at the
--   actual cast site. have_ability's range gate would refuse to queue
--   Chi Blast while a melee is sprinting toward the mob from 20y away,
--   blocking the pre-engage damage burst entirely.
function ai_ability.ability_off_recast(bot, abilityName)
    if ai_ability.ability_is_active(bot, abilityName) then return false end
    local abilityId = ai_ability.get_ability_id(abilityName)
    if not abilityId or not bot.hasJobAbility or not bot:hasJobAbility(abilityId) then
        return false
    end
    local PAb      = GetAbility and GetAbility(abilityId) or nil
    local recastId = PAb and PAb:getRecastID() or abilityId
    return not bot:hasRecast(xi.recast.ABILITY, recastId)
end

-----------------------------------
-- 36-65: Per-ability can_use_X / use_X wrappers (preserve every name verbatim)
-----------------------------------
-- have_ability is now ability-availability driven (mj level + sj level + the
-- main-only flag), so these wrappers don't need a separate job gate. A char
-- with MNK/sub gets Boost; a non-THF main but THF/sub gets Sneak Attack.
function ai_ability.can_use_sneak_attack(bot)    return ai_ability.have_ability(bot, 'Sneak Attack')    end
function ai_ability.use_sneak_attack(bot)        ai_ability.use_ability(bot, 'Sneak Attack', false)    end
function ai_ability.can_use_trick_attack(bot)    return ai_ability.have_ability(bot, 'Trick Attack')    end
function ai_ability.use_trick_attack(bot)        ai_ability.use_ability(bot, 'Trick Attack', false)    end
function ai_ability.can_use_sata(bot)            return ai_ability.can_use_sneak_attack(bot) and ai_ability.can_use_trick_attack(bot) end
function ai_ability.can_use_boost(bot)           return ai_ability.have_ability(bot, 'Boost')           end
function ai_ability.use_boost(bot)               ai_ability.use_ability(bot, 'Boost', false)           end
function ai_ability.can_use_chi_blast(bot)       return ai_ability.have_ability(bot, 'Chi Blast')       end
function ai_ability.use_chi_blast(bot)           ai_ability.use_ability(bot, 'Chi Blast', true)        end
function ai_ability.can_use_chakra(bot)          return ai_ability.have_ability(bot, 'Chakra')          end
function ai_ability.use_chakra(bot)              ai_ability.use_ability(bot, 'Chakra', false)          end
function ai_ability.can_use_spirit_link(bot)     return ai_ability.have_ability(bot, 'Spirit Link')     end
function ai_ability.use_spirit_link(bot)         ai_ability.use_ability(bot, 'Spirit Link', false)     end
function ai_ability.can_use_call_wyvern(bot)     return ai_ability.have_ability(bot, 'Call Wyvern')     end
function ai_ability.use_call_wyvern(bot)         ai_ability.use_ability(bot, 'Call Wyvern', false)     end
function ai_ability.can_use_barrage(bot)         return ai_ability.have_ability(bot, 'Barrage')         end
function ai_ability.use_barrage(bot)             ai_ability.use_ability(bot, 'Barrage', false)         end
function ai_ability.can_use_elemental_seal(bot)  return ai_ability.have_ability(bot, 'Elemental Seal')  end
function ai_ability.use_elemental_seal(bot)      ai_ability.use_ability(bot, 'Elemental Seal', false)  end
function ai_ability.can_use_provoke(bot)         return ai_ability.have_ability(bot, 'Provoke')         end
function ai_ability.use_provoke(bot)             ai_ability.use_ability(bot, 'Provoke', true)          end
function ai_ability.can_use_shield_bash(bot)     return ai_ability.have_ability(bot, 'Shield Bash')     end
function ai_ability.use_shield_bash(bot)         ai_ability.use_ability(bot, 'Shield Bash', true)      end
-- Pianissimo: self-target JA (isOffensive=false) that makes the BRD's next
-- song single-target. 5s recast, so it weaves freely between songs.
function ai_ability.can_use_pianissimo(bot)      return ai_ability.have_ability(bot, 'Pianissimo')      end
function ai_ability.use_pianissimo(bot)          ai_ability.use_ability(bot, 'Pianissimo', false)      end

-----------------------------------
-- 60-64. active_target_is_type / is_undead / is_dragon / is_arcana / is_demon
-----------------------------------
function ai_ability.active_target_is_type(bot, typeName)
    local target = xi.singleplayer.bots.ai_util.assist_target(bot)
    if target == nil then return false end
    local eco = target.getEcosystem and target:getEcosystem() or 0
    if typeName == 'Undead' then return eco == xi.ecosystem.UNDEAD end
    if typeName == 'Dragon' then return eco == xi.ecosystem.DRAGON end
    if typeName == 'Arcana' then return eco == xi.ecosystem.ARCANA end
    if typeName == 'Demon'  then return eco == xi.ecosystem.DEMON  end
    return false
end
function ai_ability.active_target_is_undead(bot)  return ai_ability.active_target_is_type(bot, 'Undead') end
function ai_ability.active_target_is_dragon(bot)  return ai_ability.active_target_is_type(bot, 'Dragon') end
function ai_ability.active_target_is_arcana(bot)  return ai_ability.active_target_is_type(bot, 'Arcana') end
function ai_ability.active_target_is_demon(bot)   return ai_ability.active_target_is_type(bot, 'Demon')  end

-----------------------------------
-- 65-76. PLD circle abilities / Rampart / Weapon Bash
-----------------------------------
function ai_ability.can_use_sentinel(bot)         return ai_ability.have_ability(bot, 'Sentinel')         end
function ai_ability.use_sentinel(bot)             ai_ability.use_ability(bot, 'Sentinel', false)         end
function ai_ability.can_use_holy_circle(bot)      return ai_ability.have_ability(bot, 'Holy Circle')      end
function ai_ability.use_holy_circle(bot)          ai_ability.use_ability(bot, 'Holy Circle', false)      end
function ai_ability.can_use_ancient_circle(bot)   return ai_ability.have_ability(bot, 'Ancient Circle')   end
function ai_ability.use_ancient_circle(bot)       ai_ability.use_ability(bot, 'Ancient Circle', false)   end
function ai_ability.can_use_arcane_circle(bot)    return ai_ability.have_ability(bot, 'Arcane Circle')    end
function ai_ability.use_arcane_circle(bot)        ai_ability.use_ability(bot, 'Arcane Circle', false)    end
function ai_ability.can_use_warding_circle(bot)   return ai_ability.have_ability(bot, 'Warding Circle')   end
function ai_ability.use_warding_circle(bot)       ai_ability.use_ability(bot, 'Warding Circle', false)   end
function ai_ability.can_use_rampart(bot)          return ai_ability.have_ability(bot, 'Rampart')          end
function ai_ability.use_rampart(bot)              ai_ability.use_ability(bot, 'Rampart', false)          end
function ai_ability.can_use_weapon_bash(bot)      return ai_ability.have_ability(bot, 'Weapon Bash')      end
function ai_ability.use_weapon_bash(bot)          ai_ability.use_ability(bot, 'Weapon Bash', true)       end

-----------------------------------
-- 77-78. stun_ability_is_up / use_stun_ability
-----------------------------------
local stunAbilities = { 'Shield Bash', 'Weapon Bash' }

function ai_ability.stun_ability_is_up(bot)
    return ai_ability.get_next_ability(bot, stunAbilities) ~= nil
end

function ai_ability.use_stun_ability(bot)
    local abilityName = ai_ability.get_next_ability(bot, stunAbilities)
    if abilityName ~= nil then ai_ability.use_ability(bot, abilityName, true) end
end

-----------------------------------
-- Multi-tank Provoke rotation gate. Returns true when THIS bot is allowed
-- to fire main-mob Provoke NOW under the alliance's rotation schedule.
--
-- With N tanks in scope (party or alliance depending on multiEngageMode),
-- the group's aggregate Provoke cadence is 30/N seconds. Between fires,
-- no tank should burn its own recast — spacing them out ensures hate stays
-- refreshed for the full 30s window rather than 3-tanks-blowing-recasts-
-- at-t=0 then 30s of silence.
--
-- Single-tank scope: always open (interval = 30s, matches individual recast).
--
-- Tiebreak: if two tanks come off recast within the same alliance tick,
-- only the lowest charId fires this tick — the other waits one tick and
-- re-evaluates. Bounded stall (single tick) and deterministic.
--
-- Add-Provoke bypasses this gate entirely (urgency wins).
-----------------------------------
local function provoke_rotation_open(bot)
    local A = xi.singleplayer.bots.alliance
    if A == nil then return true end
    local tanks = xi.singleplayer.bots.ai_util.tanks_in_scope(bot)
    if #tanks <= 1 then return true end
    local slot = A.multiEngageMode and xi.singleplayer.bots.get_party_slot(bot) or 1
    local interval = 30000 / #tanks
    A.lastProvokeAtMs = A.lastProvokeAtMs or { 0, 0, 0 }
    local last = A.lastProvokeAtMs[slot] or 0
    local now  = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    if now < last + interval then return false end
    -- Same-tick tiebreak: lowest charId with Provoke off recast wins.
    local myId = bot:getID()
    for _, t in ipairs(tanks) do
        if t:getID() < myId and ai_ability.ability_off_recast(t, 'Provoke') then
            return false
        end
    end
    return true
end

-----------------------------------
-- 80. provoke_is_up — true when this bot should fire Provoke this tick.
-- Add branch is checked first and BYPASSES rotation (peel urgency wins).
-- Main-mob branch is gated by provoke_rotation_open so multi-tank scopes
-- stagger fires across the 30/N-second window.
-----------------------------------
function ai_ability.provoke_is_up(bot)
    -- have_ability bundles off-recast + ja_in_range + ability availability,
    -- so it's the baseline gate.
    if not ai_ability.have_ability(bot, 'Provoke') then return false end
    -- Add-peel branch: peelable add exists → fire Provoke immediately, no
    -- rotation. Existing tier-check coordination in ai_threat prevents
    -- double-voking (after Provoke lands, mob's target is a tank/high-melee
    -- and it stops being peelable).
    local threat = xi.singleplayer.bots.threat.peelable_for(bot)
    if threat ~= nil then return true end
    -- Main-mob branch: gate on multi-tank rotation.
    local target = xi.singleplayer.bots.get_current_mob_target(bot)
    if target == nil then return false end
    return provoke_rotation_open(bot)
end

-----------------------------------
-- 81. can_provoke_add — true when there's a peelable add AND this bot is
--                      the picked provoker (HP%-sorted pool).
-----------------------------------
function ai_ability.can_provoke_add(bot)
    if xi.singleplayer.bots.threat.peelable_for(bot) == nil then return false end
    local threat = xi.singleplayer.bots.threat.peelable_for(bot)
    return xi.singleplayer.bots.pool and xi.singleplayer.bots.pool.am_i_provoker(bot, threat.mob)
end

-----------------------------------
-- 82. provoke_target — Provoke the current commanded mob. Writes the
-- multi-tank rotation timestamp for this bot's scope so the next tank in
-- the rotation waits 30/N seconds before its own fire. Only the main-mob
-- branch stamps; add-Provoke bypasses rotation.
-----------------------------------
function ai_ability.provoke_target(bot)
    local A = xi.singleplayer.bots.alliance
    if A ~= nil then
        local slot = A.multiEngageMode and xi.singleplayer.bots.get_party_slot(bot) or 1
        A.lastProvokeAtMs = A.lastProvokeAtMs or { 0, 0, 0 }
        A.lastProvokeAtMs[slot] = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    end
    ai_ability.use_ability(bot, 'Provoke', true)
end

-----------------------------------
-- 83. provoke_add
-----------------------------------
function ai_ability.provoke_add(bot)
    local threat = xi.singleplayer.bots.threat.peelable_for(bot)
    if threat ~= nil then
        ai_ability.use_ability_on(bot, 'Provoke', threat.mob:getID())
    end
end

-----------------------------------
-- 84. can_provoke_target — true when the alliance target slipped off-tank
--      AND this bot is the picked provoker.
--
-- "Off-tank" here means: the alliance target's current victim is a
-- MELEE_LOW (HP < 25%) or MAGE — someone who genuinely can't soak the
-- swing. Healthy melees (≥50%) and medium melees (25-50%) are NOT
-- triggers; they can hold hate while the tank pulls it back. Tier
-- classification comes from ai_threat.member_tier.
--
-- The tier-based redirect is intentionally narrower than the add-peeling
-- logic (ai_threat.should_peel for tank peels anything off-tank). Adds
-- are a different question; we'd happily peel a healthy melee back to
-- the tank for an ADD that's free-targeting. But for the COMMANDED mob
-- bouncing around the melee line, intervention is only needed when the
-- victim genuinely can't take it.
-----------------------------------
function ai_ability.can_provoke_target(bot)
    local target = xi.singleplayer.bots.threat and xi.singleplayer.bots.threat.alliance_target(bot)
    if target == nil or not target.isEngaged or not target:isEngaged() then return false end
    local victim = target.getTarget and target:getTarget() or nil
    if victim == nil then return false end
    local victimTier = xi.singleplayer.bots.threat.member_tier(victim)
    if victimTier ~= xi.singleplayer.bots.threat.TIER_MELEE_LOW
       and victimTier ~= xi.singleplayer.bots.threat.TIER_MAGE then
        return false
    end
    return xi.singleplayer.bots.pool and xi.singleplayer.bots.pool.am_i_provoker(bot, target)
end

-----------------------------------
-- 85. provoke_main_target — Provoke the alliance target (resolved live).
-----------------------------------
function ai_ability.provoke_main_target(bot)
    local target = xi.singleplayer.bots.threat and xi.singleplayer.bots.threat.alliance_target(bot)
    if target ~= nil then ai_ability.use_ability_on(bot, 'Provoke', target:getID()) end
end

-----------------------------------
-- 86. provoke
-----------------------------------
function ai_ability.provoke(bot)
    if xi.singleplayer.bots.threat.peelable_for(bot) == nil then
        ai_ability.provoke_target(bot)
    else
        ai_ability.provoke_add(bot)
    end
end

-----------------------------------
-- 86b. should_use_provoke - gate for the add-control mode toggle.
--
-- Returns true when the tank's current Provoke call SHOULD fire. Always
-- allowed for the main alliance target. For peelable adds, only allowed
-- when the bot's addControlMode is 'provoke' or 'both' - in 'flash' mode
-- the role tick falls through to the Flash-on-add branch instead.
--
-- Read on every role_tank.tick to gate the existing provoke_is_up branch;
-- no other call site uses it.
-----------------------------------
function ai_ability.should_use_provoke(bot)
    if xi.singleplayer.bots.threat == nil
       or xi.singleplayer.bots.threat.peelable_for == nil then
        return true
    end
    local peelable = xi.singleplayer.bots.threat.peelable_for(bot)
    if peelable == nil then return true end
    local s    = xi.singleplayer.bots.alliance and xi.singleplayer.bots.alliance.bot[bot:getID()]
    local mode = (s and s.addControlMode) or 'provoke'
    return mode == 'provoke' or mode == 'both'
end

-----------------------------------
-- 86c. set_add_control_mode - settor called by luautils::OnBotSetAddControlMode.
--
-- Walks the requesting primary's owned headless, finds the named bot, writes
-- the mode into alliance.bot[id].addControlMode. Silently no-ops on unknown
-- name / cross-primary / invalid mode so a malformed packet can't break the
-- alliance state.
-----------------------------------
function ai_ability.set_add_control_mode(primary, botName, mode)
    if primary == nil or botName == nil or botName == '' then return end
    if mode ~= 'provoke' and mode ~= 'flash' and mode ~= 'both' then return end
    local primaryId = primary:getID()
    local target    = botName:lower()
    -- A bot is "owned" if it's the primary themselves (PLD primary can be the
    -- tank too) OR a headless whose parentCharId == primaryId. The old gate
    -- only accepted headless, so the primary's own add-control toggle silently
    -- failed with "no owned bot" even when they're PLD-eligible.
    local function is_owned(m)
        if m == primary then return true end
        if m.isHeadless and m:isHeadless()
           and m.getParentCharId and m:getParentCharId() == primaryId then
            return true
        end
        return false
    end
    for _, member in ipairs(primary:getAlliance() or {}) do
        if is_owned(member) and member:getName():lower() == target then
            local s = xi.singleplayer.bots.ensure_bot(member:getID())
            s.addControlMode = mode
            printf(string.format('ai_ability.set_add_control_mode: %s -> %s', member:getName(), mode))
            return
        end
    end
    printf(string.format('ai_ability.set_add_control_mode: no owned bot "%s"', botName))
end

-----------------------------------
-- 87. use_ws
--     Original looked up WS by name in skills[3] (weapon-skill resource table).
--     Server-side: use bot:weaponSkill(wsId, target). The wsId lookup uses an
--     embedded local table (subset of common WSes — extend as needed).
-----------------------------------
-- Name → ID resolution goes through the GetWeaponskillByName C++ binding,
-- which searches the server's authoritative weapon-skill list. Single source
-- of truth; stays in sync with sql/weapon_skills.sql.
function ai_ability.use_ws(bot, wsName)
    local log = (xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.log) or function() end
    if wsName == nil or wsName == '' then
        log(bot, 'AutoWS', 'skip: no WS configured for current job')
        return
    end
    -- bot:weaponSkill requires the bot to actually be engaged on the target.
    -- Prefer the bot's own engagement (bot:getTarget()) over the alliance
    -- target — they can diverge when a bot is on an add while the alliance
    -- is still locked onto the original target. Original Ashita's addon ran
    -- on the bot's client, so it implicitly used the bot's own target; the
    -- port lost that and was passing the wrong entity, which the server
    -- rejects silently.
    local target = bot.getTarget and bot:getTarget() or nil
    local fellBack = false
    if target == nil then
        target = xi.singleplayer.bots.get_current_mob_target()
        if target == nil then
            log(bot, 'AutoWS', string.format('skip ws=%s: bot has no target AND allianceTarget=0', wsName))
            return
        end
        fellBack = true
    end
    if target == nil then
        log(bot, 'AutoWS', string.format('skip ws=%s: target id resolved nil', wsName))
        return
    end
    local wsId = ai_ability.resolve_ws_id(wsName)
    if wsId == 0 then
        log(bot, 'AutoWS', string.format('skip ws=%s: not found', wsName))
        return
    end

    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_weaponskill then xi.singleplayer.bots.ai_equip_swap.equip_weaponskill(bot, wsId) end
    bot:weaponSkill(wsId, target)
end

-----------------------------------
-- 88. ranged_attack
-----------------------------------
function ai_ability.ranged_attack(bot)
    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_preranged then xi.singleplayer.bots.ai_equip_swap.equip_preranged(bot) end
    bot:rangedAttack(target)
end

-----------------------------------
-- Packet-handler ports (converted to event-hook signatures; wired from bot_ai)
-----------------------------------

-- 92. check_for_getting_attacked
function ai_ability.check_for_getting_attacked(bot, actorId, targetId)
    if actorId == targetId then return end
    local partyIds = {}
    for _, m in ipairs(bot:getAlliance() or {}) do table.insert(partyIds, m:getID()) end
    if not xi.singleplayer.bots.ai_util.table_contains(partyIds, actorId) and bot:getID() == targetId then
        local ability = ai_ability.get_next_defense_ability(bot)
        if ability ~= nil then ai_ability.use_ability(bot, ability, ai_ability.is_offensive_ability(bot, ability)) end
    end
end

-- 93. bash_is_up / bash — the bash window is set by onMobSkillStart when
--      a mob starts a castable move; the bash pool picks whichever eligible
--      bot (PLD Shield Bash or DRK Weapon Bash) should fire the interrupt.
--      bash_is_up returns true when THIS bot is the picked basher and the
--      window is still open. bash re-picks (pool query is pure), closes
--      the window, and fires. If the picked bot is busy this tick the
--      pool filter excludes them and bash_is_up returns false — the
--      window stays open and next tick tries the next-best picker.
function ai_ability.bash_is_up(bot)
    if bot == nil then return false end
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil then return false end
    local now_ms = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    if (alliance.bashWindowUntilMs or 0) <= now_ms then return false end
    local mob = xi.singleplayer.bots.ai_util.assist_target(bot)
    if mob == nil then return false end
    local pool = xi.singleplayer.bots.pool
    return pool ~= nil and pool.am_i_basher(bot, mob) ~= false
end

function ai_ability.bash(bot)
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil then return end
    local mob = xi.singleplayer.bots.ai_util.assist_target(bot)
    if mob == nil then return end
    local pool = xi.singleplayer.bots.pool
    local ability = pool and pool.am_i_basher(bot, mob)
    if not ability then return end
    alliance.bashWindowUntilMs = 0  -- close window: we're firing
    ai_ability.use_ability(bot, ability, true)
end

-- "Bot is being attacked" detection. Walks each (actor → target) pair in
-- the action and fans out check_for_getting_attacked (ability + magic
-- flavors) to the targeted bot when the actor is hostile. The "active
-- target is hitting non-tank" branch is GONE — that fed the activeTargets
-- cache which has been replaced by runtime tier derivation (#228).
-- Same upstream signal the original client-side addon parsed out of the
-- 0x28 packet (actor + target IDs), observed at the broadcast chokepoint.
local function fan_getting_attacked(actor, action)
    if action == nil or action.targets == nil or actor == nil then return end
    if not actor:isMob() then return end
    local actorId = actor:getID()
    for _, target in ipairs(action.targets) do
        local targetId = target.actorId or 0
        if targetId ~= 0 and targetId ~= actorId then
            local bot = GetPlayerByID(targetId)
            if bot ~= nil and xi.singleplayer.bots.alliance.bot[targetId] ~= nil then
                ai_ability.check_for_getting_attacked(bot, actorId, targetId)
                if xi.singleplayer.bots.magic and xi.singleplayer.bots.magic.check_for_getting_attacked then
                    xi.singleplayer.bots.magic.check_for_getting_attacked(bot)
                end
            end
        end
    end
end

-- SC pair rotation: after a configured closer fires their configured closeWS,
-- move that pair to the end of alliance.sc[]. Combined with higher_priority_close
-- (which makes higher-index pairs wait on lower-index pairs being ready), this
-- gives round-robin pair scheduling: each pair gets first refusal in its slot,
-- then moves to the back after firing. If the front pair can't fire, the next
-- pair gets to go — natural skip-ahead.
local SKILL_FINISH_CMD_NO_FOR_SC = 3

local function fan_rotate_sc_on_close(actor, action)
    if action == nil or action.actiontype ~= SKILL_FINISH_CMD_NO_FOR_SC then return end
    if actor == nil then return end
    local pairs_ = ai_ability.sc_pairs()
    if #pairs_ <= 1 then return end
    local actorId = actor:getID()
    local pairIdx
    for i, p in ipairs(pairs_) do
        if p.closeCharId == actorId then pairIdx = i; break end
    end
    if pairIdx == nil then return end
    local p = pairs_[pairIdx]
    local expectedWsId = ai_ability.resolve_ws_id(p.closeWS)
    if expectedWsId == 0 or expectedWsId ~= (action.actionid or 0) then return end
    table.remove(pairs_, pairIdx)
    table.insert(pairs_, p)
    printf('[AutoSC] rotated pair %s/%s to back of alliance.sc', p.openName, p.closeName)
end

m:addOverride('xi.singleplayer.bots.onActionResult', function(actor, action)
    super(actor, action)
    fan_getting_attacked(actor, action)
    fan_rotate_sc_on_close(actor, action)
end)

-----------------------------------
-- process_pre_ability_checks
--   Mirror of ai_magic.process_pre_cast_checks, for the physical-DD roles
--   (tank / melee). One shared entry point handles hard-skip gates plus
--   the Role AI policy item branches in HP → Status → MP priority order.
--   Returns true iff the role tick should bail this frame (either a hard
--   skip fired or an item was consumed). Caller pattern:
--
--     function role_tank.tick(bot)
--         if xi.singleplayer.bots.ability.process_pre_ability_checks(bot) then return end
--         ...existing cascade...
--     end
--
--   Not yet wired into role_tank / role_melee — those still run their
--   inline potent-poison / HP<10% potion branches. Wiring is a follow-up
--   that adds this call at the top of each tick and (later) deletes the
--   inline equivalents.
-----------------------------------
function ai_ability.process_pre_ability_checks(bot)
    -- Hard skips. Reuses ai_magic.is_casting since the cast-state check
    -- is the same regardless of role family.
    if xi.singleplayer.bots.magic.is_casting(bot)
       or xi.singleplayer.bots.ai_util.has_neutralizing_effect(bot)
       or xi.singleplayer.bots.ai_util.is_dead(bot)
       or xi.singleplayer.bots.ai_util.weakened(bot) then
        return true
    end

    -- Role AI policy item branches. Priority: HP → Status → MP. HP first
    -- because a dying tank/melee can't fight; status second because a
    -- silenced/paralyzed bot's other abilities still resolve fine (no
    -- cast guard); MP last because melee MP items only matter for the
    -- DRK/BLU subset and are the least time-sensitive.
    if xi.singleplayer.bots.item.try_hp_item(bot)     then return true end
    if xi.singleplayer.bots.item.try_status_item(bot) then return true end
    if xi.singleplayer.bots.item.try_mp_item(bot)     then return true end

    return false
end

return m
