-----------------------------------
-- Server-side AI: magic decision logic (cures, buffs, debuffs, nukes, rests,
-- shadows). Ported from client-side. Functions take a `bot` (CCharEntity) as
-- the operating subject; party/alliance iteration via bot:getParty() /
-- bot:getAlliance(); spell casts via entity:castSpell(spellId, target).
-- All spell + effect IDs use xi.magic.spell.* and xi.effect.* named constants.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_magic')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.magic = xi.singleplayer.bots.magic or {}
local ai_magic = xi.singleplayer.bots.magic

-----------------------------------
-- Job tables (preserved verbatim from ai_magic)
-----------------------------------
ai_magic.jobs              = { 'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN' }
ai_magic.mageJobs          = { 'WHM','BLM','RDM','BRD','SMN','SCH','GEO' }
ai_magic.casterJobs        = { 'WHM','NIN','PLD','RUN','SMN','RDM','BRD','BLU','SCH','GEO','DRK' }
ai_magic.restingCasterJobs = { 'WHM','BLM','SMN','RDM','BRD','SCH','GEO' }
ai_magic.meleeJobs         = { 'NIN','WAR','SAM','DRK','DRG','MNK','THF','RNG','BLU','COR','PUP','DNC' }
ai_magic.tankJobs          = { 'PLD','NIN','RUN' }
ai_magic.hasteMeleeJobs    = { 'NIN','WAR','SAM','DRK','DRG','MNK','THF','PUP','DNC' }
ai_magic.hasteCasterJobs   = { 'WHM','RDM' }
ai_magic.refreshAlwaysJobs = { 'RDM','PLD','RUN','WHM','BLM','SMN','SCH' }
ai_magic.refreshLowMPJobs  = { 'DRK','BRD','GEO','BLU' }

-- Per-bot scratch lives on alliance.bot[charId] (consolidated #221).
local function getState(bot)
    return xi.singleplayer.bots.ensure_bot(bot:getID())
end

ai_magic.get_alliance_members = function(bot) return bot:getAlliance() or {} end

ai_magic.get_party_members = function(bot) return bot:getParty() or {} end

ai_magic.get_member_by_name = function(bot, name)
    for _, member in ipairs(ai_magic.get_alliance_members(bot)) do
        if member:getName() == name then return member end
    end
    return nil
end

ai_magic.job_string = function(jobIdx) return ai_magic.jobs[jobIdx] end

ai_magic.is_effect_active = function(bot, effectId) return bot:hasStatusEffect(effectId) end

-- use_ether_allowed retired — ether use is now driven by ai_item.try_mp_item
-- (Role AI policy: Off / NM Only / Always), called from
-- ai_magic.process_pre_cast_checks before the rest cascade.

-----------------------------------
-- 3. get_assist
-----------------------------------
function ai_magic.get_assist(_)
    local assist = xi.singleplayer.bots.get_assist_entity()
    if assist == nil then return nil end
    return assist:getName()
end

-----------------------------------
-- 6. get_cast_time_in_seconds — base cast time from the spell table, not
-- the modified-by-fast-cast value. Used by can_mb to decide "would the
-- cast finish before the MB window closes?". Base time is the SAFE choice
-- there: actual cast time with Fast Cast / Composure is shorter, never
-- longer, so a spell that fits with base time will definitely fit with
-- the real cast. Falls back to 1s if the spell is unknown.
-----------------------------------
function ai_magic.get_cast_time_in_seconds(spellId)
    local spellInfo = GetSpell and GetSpell(spellId) or nil
    if spellInfo == nil or spellInfo.getCastTime == nil then return 1 end
    return spellInfo:getCastTime() / 1000
end

-----------------------------------
-- 12. partyHasJob
-----------------------------------
-- TODO the partyHasJob and the 4 funcs under that rely on it can be moved to ai_util
local function partyHasJob(bot, jobChar)
    for _, member in ipairs(ai_magic.get_alliance_members(bot)) do
        if ai_magic.job_string(member:getMainJob()) == jobChar then return true end
    end
    return false
end

function ai_magic.no_whm(bot) return not partyHasJob(bot, 'WHM') end

function ai_magic.no_blm(bot) return not partyHasJob(bot, 'BLM') end

function ai_magic.no_rdm(bot) return not partyHasJob(bot, 'RDM') end

function ai_magic.no_nin(bot) return not partyHasJob(bot, 'NIN') end

-----------------------------------
-- 15. cast_spell  — cast on the current mob target
-----------------------------------
function ai_magic.cast_spell(bot, spellId)
    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return false end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_premagic then xi.singleplayer.bots.ai_equip_swap.equip_premagic(bot, spellId) end
    bot:castSpell(spellId, target)
    ai_magic.note_cast(bot, target:getID(), spellId)
    return true
end

-----------------------------------
-- 16. cast_party_spell  — cast on a specific party member entity
--     (original took a numeric playerIndex; server-side we pass the entity)
-----------------------------------
function ai_magic.cast_party_spell(bot, spellId, member)
    if member == nil then return false end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_premagic then xi.singleplayer.bots.ai_equip_swap.equip_premagic(bot, spellId) end
    bot:castSpell(spellId, member)
    return true
end

-----------------------------------
-- 17. cast_melee_spell  — cast on the primary's selected target
-----------------------------------
function ai_magic.cast_melee_spell(bot, spellId)
    return ai_magic.cast_spell(bot, spellId)
end

-----------------------------------
-- 18. cast_spell_on  — cast on a specific server entity ID
-----------------------------------
function ai_magic.cast_spell_on(bot, spellId, targetId)
    local target = GetEntityByID(targetId)
    if target == nil then return false end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_premagic then xi.singleplayer.bots.ai_equip_swap.equip_premagic(bot, spellId) end
    bot:castSpell(spellId, target)
    return true
end

-----------------------------------
-- 19. has_spell
-----------------------------------
function ai_magic.has_spell(bot, spellId)
    return bot:hasSpell(spellId)
end

-----------------------------------
-- 20. spell_is_up
--     Equivalent to the original `recastTimer < 1` gate, with the addition
--     of the once-per-mob check used in offensive enfeebles.
-----------------------------------
-- Once-per-mob fire-and-forget lists. Matches original Ashita addon behavior:
-- when an offensive spell in the job's list has already been cast on the
-- active target, never cast it again on that mob (even if the effect wears
-- off). Other "already up" checks (Bar*, Refresh, Haste, etc.) live in their
-- own targeting helpers (get_valid_X_target / can_bar_spell) and use direct
-- entity hasStatusEffect queries, so they aren't gated here.
--
-- Tracked by spell ID, NOT effect ID, so tier upgrades work: POISON (220) and
-- POISON_II (221) are independent entries — casting POISON_II is allowed
-- after POISON has been logged.
ai_magic.oncePerMobSpells    = { xi.magic.spell.POISON, xi.magic.spell.POISON_II,
                                  xi.magic.spell.CHOKE,  xi.magic.spell.BLIND,
                                  xi.magic.spell.SLOW }
ai_magic.rdmOncePerMobSpells = { xi.magic.spell.POISON, xi.magic.spell.POISON_II,
                                  xi.magic.spell.CHOKE }

-- `target` (optional): the intended cast target. Used to key the oncePerMob
-- log against the ACTUAL mob being hit instead of alliance.allianceTarget.
-- Pass it when calling for an add (e.g. Sleep / Bind / Slow on a peeled mob)
-- so the log entry binds to the correct mob. When nil, falls back to
-- alliance.allianceTarget for back-compat with callers that don't know
-- the target yet (most ai_magic.can_cast_X gates).
function ai_magic.spell_is_up(bot, spellId, isOffensive, target)
    -- hasSpell only consults m_SpellList — it doesn't check the caster's
    -- main/sub-job level, status-effect gates (Tabula Rasa, SCH addendums,
    -- BLU spell-set), etc. So a /NIN24 with Utsusemi: Ni in their list
    -- previously looked "available" even though sub level 24 only allows
    -- Ichi. canUseSpell wraps spell::CanUseSpell which IS authoritative.
    if not bot:hasSpell(spellId) then return false end
    if bot.canUseSpell and not bot:canUseSpell(spellId) then return false end
    if bot:hasRecast(xi.recast.MAGIC, spellId) then return false end
    -- MP check. canUseSpell intentionally doesn't gate on MP (it checks job/
    -- level/trust requirements only). Without this, the bot picks a spell
    -- it can't afford, dispatches the cast, the server interrupts mid-cast,
    -- and the role tick re-picks the same unaffordable spell next tick —
    -- looping forever with no visible result. GetSpell returns a table with
    -- mpcost for the spell's MP cost (raw — buffs like Manafont aren't
    -- applied, so this is the worst-case requirement, which is fine here).
    -- GetSpell returns a CSpell userdata (not a table). My earlier attempt
    -- read `spellInfo.mpcost` which is nil on userdata — gate silently
    -- skipped, bot dispatched spells it couldn't afford (e.g. PLD with
    -- 64 MP casting Cure IV at 88 cost). Call the method instead.
    --
    -- Ninjutsu repurposes the spell_list.mp_cost column to store the required
    -- TOOL item ID (e.g. Shihei=1179 for Utsusemi). For SPELLGROUP_NINJUTSU
    -- the field is not MP at all — every Ninjutsu cast would gate-fail here
    -- since bot:getMP() < 1179 is almost always true. Tool presence is
    -- checked by the caller (e.g. role_melee.can_cast_utsusemi → have_shihei).
    local spellInfo = GetSpell and GetSpell(spellId) or nil
    if spellInfo and spellInfo.getMPCost and spellInfo.getSpellGroup
       and spellInfo:getSpellGroup() ~= xi.magic.spellGroup.NINJUTSU
       and bot:getMP() < spellInfo:getMPCost() then
        return false
    end
    -- Silenced bots can't cast any spell; fail closed here so every can_cast_*
    -- gate above short-circuits and the role tick falls through to items /
    -- abilities / movement.
    if xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.silenced(bot) then return false end

    -- Resist back-off (#208). Skip offensive spells we've been failing to
    -- land on this mob. ai_resist tracks per-(bot, mob, spell) consecutive
    -- failure counts via onActionResult; once the count hits the threshold
    -- (default 3) the spell is treated as unavailable until the mob dies.
    -- Defensive guard for module-load order: nil-check ai_resist itself.
    if isOffensive
       and xi.singleplayer.bots.ai_resist
       and xi.singleplayer.bots.ai_resist.should_skip then
        local mobId = (target ~= nil and target.getID and target:getID())
                      or xi.singleplayer.bots.get_alliance_target_id()
        if mobId ~= 0 and xi.singleplayer.bots.ai_resist.should_skip(bot, spellId, mobId) then
            return false
        end
    end

    -- Once-per-mob block: only applies to offensive spells in the active job's
    -- list, only when an active mob is being tracked, and only after this bot
    -- has logged a cast of this specific spell on that mob. spellLog is
    -- populated from the per-self MAGIC_USE listener via note_cast.
    if isOffensive then
        -- Key the once-per-mob check against the actual cast target if known.
        -- For per-spell pickers that pass `target` (e.g. ai_magic enfeebles on
        -- adds), this binds the spellLog entry to the right mob. For callers
        -- that don't know the target yet (most can_cast_X gates), fall back
        -- to alliance.allianceTarget so the existing "don't double-cast on
        -- the main mob" behavior holds. Sleep deliberately ISN'T in the
        -- oncePerMob list (we want re-sleeps), so it skips this branch by
        -- list membership regardless.
        local mobId = (target ~= nil and target.getID and target:getID())
                      or xi.singleplayer.bots.get_alliance_target_id()
        if mobId ~= 0 then
            local list = xi.singleplayer.bots.ai_util.is_job(bot, 'RDM')
                            and ai_magic.rdmOncePerMobSpells
                            or  ai_magic.oncePerMobSpells
            if xi.singleplayer.bots.ai_util.table_contains(list, spellId) then
                local state = getState(bot)
                local mobLog = state.spellLog[mobId]
                if mobLog and mobLog[spellId] then return false end
            end
        end
    end
    return true
end

-----------------------------------
-- 21. can_use_food
-----------------------------------
function ai_magic.can_use_food(bot)
    -- TODO from original.
    return false
end

-----------------------------------
-- 22. use_food
-----------------------------------
function ai_magic.use_food(bot)
    -- TODO from original.
end

-----------------------------------
-- 23. target_has_status
-----------------------------------
function ai_magic.target_has_status(bot, statusId)
    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return false end
    return target:hasStatusEffect(statusId)
end

-----------------------------------
-- 24a. Spell range helpers (#192)
--
-- Range awareness lives at the PICKER level, not the cast-dispatch level. If
-- we checked range only at dispatch, the role tick would re-enter the same
-- elseif branch every tick (picker still returns the out-of-range member,
-- gate is still true, dispatch fails) — looping forever instead of falling
-- through to something the bot can actually do (move closer, buff self, etc.).
--
-- So pickers accept an OPTIONAL `max_range` param; passing nil means "no
-- filter" (legacy backward-compat). Callers that want range gating pass
-- `ai_magic.spell_range(spellId)` (single-target spells) or
-- `ai_magic.aoe_radius(spellId)` (caster-centered AoEs like Curagas/Bars).
--
-- Both queries source from the engine via CLuaSpell::getRange / getRadius —
-- single source of truth, no static table to drift from the DB.
-----------------------------------
-- Conservative safety shave on single-target ranges to avoid the bot
-- casting at the edge of range where mob movement → interrupt is likely.
-- Shave 3y but floor at 3y so very short-range spells (BLU touches at 3y,
-- some BLU 5y breaths) keep a usable range. Self-only spells (range=0)
-- aren't range-gated against a target — picker callers skip the filter.
local SPELL_RANGE_SAFETY_SHAVE = 3
local SPELL_RANGE_FLOOR        = 3
-- Public so legacy can_cast_X gates can use it as a coarse fallback for
-- "find a target within standard party-spell range" without knowing the
-- specific spell. New code should prefer ai_magic.spell_range(spellId).
ai_magic.DEFAULT_SPELL_RANGE   = 21  -- canonical party magic range; used when GetSpell returns nothing or by callers without a specific spell
local DEFAULT_SPELL_RANGE      = ai_magic.DEFAULT_SPELL_RANGE
local DEFAULT_AOE_RADIUS       = 10  -- only used if GetSpell returns nothing

function ai_magic.spell_range(spellId)
    local spellInfo = GetSpell and GetSpell(spellId) or nil
    local raw = (spellInfo and spellInfo.getRange) and spellInfo:getRange() or DEFAULT_SPELL_RANGE
    if raw <= 0 then return raw end  -- 0 = self-only; caller should skip range filter
    local shaved = raw - SPELL_RANGE_SAFETY_SHAVE
    if shaved < SPELL_RANGE_FLOOR then shaved = SPELL_RANGE_FLOOR end
    return shaved
end

-- aoe_radius — distance from the CASTER's position within which a self-
-- centered AoE (Curaga, Protectra, Shellra, Bar) actually lands on a
-- party member. Used by Cure-type pickers to filter party members too
-- far from the caster to benefit. No safety shave: the engine's radius
-- is what it is, and AoEs aren't subject to "edge of range interrupt"
-- the way a directed cast is.
function ai_magic.aoe_radius(spellId)
    local spellInfo = GetSpell and GetSpell(spellId) or nil
    if spellInfo == nil or spellInfo.getRadius == nil then return DEFAULT_AOE_RADIUS end
    local r = spellInfo:getRadius()
    if r <= 0 then return DEFAULT_AOE_RADIUS end
    return r
end

-- True iff (bot, target) are within `yalms` (planar). nil target = false.
function ai_magic.in_range(bot, target, yalms)
    if bot == nil or target == nil or yalms == nil then return false end
    return bot:checkDistance(target) <= yalms
end

function ai_magic.combat_active(primary) return xi.singleplayer.bots.ai_util.combat_active(primary) end
function ai_magic.assist_target(bot)     return xi.singleplayer.bots.ai_util.assist_target(bot)     end

-- Return the assist's mob iff it's within `spellId`'s range AND alive.
-- Used by per-spell decision gates so an offensive cast doesn't loop when
-- the mob is just out of reach.
function ai_magic.current_mob_in_range(bot, spellId)
    local mob = ai_magic.assist_target(bot)
    if mob == nil then return false end
    return bot:checkDistance(mob) <= ai_magic.spell_range(spellId)
end

-- Shortcut: assist's mob within DEFAULT_SPELL_RANGE (21y). Used by can_X
-- predicates that fire ANY of several offensive spells against the mob —
-- nukes (24y) are conservatively gated to 21y for safety, while a tighter
-- gate (e.g. provoke at 14y) belongs in an ability-side check.
function ai_magic.mob_in_cast_range(bot)
    local mob = ai_magic.assist_target(bot)
    if mob == nil then return false end
    return bot:checkDistance(mob) <= ai_magic.DEFAULT_SPELL_RANGE
end

-----------------------------------
-- 25. is_casting
-----------------------------------
function ai_magic.is_casting(bot)
    return bot:isBotCasting()
end

-----------------------------------
-- 26. is_moving
-----------------------------------
-- Headless position sample is gated by RESAMPLE_MIN_MS so we don't redo
-- the (cheap but pointless) sample twice on the same AI tick when multiple
-- callers ask "is this bot moving?" within one tick (combat tick + cast
-- pre-check, etc.). 250ms < the AI scheduler's 400ms tick cadence, so each
-- new tick will always resample; same-tick callers reuse the cached delta.
local POS_RESAMPLE_MIN_MS = 250

function ai_magic.is_moving(bot)
    -- Real client: m_lastClientMoveInput is stamped by the 0x015 position
    -- heartbeat. Headless has no client input — sample position delta over a
    -- per-tick window instead.
    if not bot:isHeadless() then
        return bot:getLastClientMoveInputMs() < 500
    end
    local state = getState(bot)
    local now   = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    if state._lastPosSampleMs == nil or now - state._lastPosSampleMs > POS_RESAMPLE_MIN_MS then
        local x, z = bot:getXPos(), bot:getZPos()
        local prev = state._lastSampledPos or { x = x, z = z }
        state.moving = ((x - prev.x) ^ 2 + (z - prev.z) ^ 2) > 0.01
        state._lastSampledPos = { x = x, z = z }
        state._lastPosSampleMs = now
    end
    return state.moving
end

-----------------------------------
-- 27. get_first_buff
--     Returns first castable buff in the list whose status isn't already on.
--     Original `get_first_buff` returned nil if any earlier buff in the list
--     was already up; preserves the "spike spell" / "reraise" group semantic.
-----------------------------------
local spellToBuffEffect = {
    [xi.magic.spell.BLINK]        = xi.effect.BLINK,
    [xi.magic.spell.STONESKIN]    = xi.effect.STONESKIN,
    [xi.magic.spell.SHOCK_SPIKES] = xi.effect.SHOCK_SPIKES,
    [xi.magic.spell.ICE_SPIKES]   = xi.effect.ICE_SPIKES,
    [xi.magic.spell.BLAZE_SPIKES] = xi.effect.BLAZE_SPIKES,
}

-- Spell-id → mob-side status-effect-id for offensive debuffs gated by
-- checkStatus=true in get_next_spell. Without this, target_has_status was
-- being passed a SPELL id but interpreting it as a STATUS-EFFECT id, so the
-- effect lookup always returned false → Dia / Slow / Paralyze / Poison cast
-- every tick regardless of whether the effect was already up.
local spellToDebuffEffect = {
    [xi.magic.spell.DIA]          = xi.effect.DIA,
    [xi.magic.spell.DIA_II]       = xi.effect.DIA,
    [xi.magic.spell.DIA_III]      = xi.effect.DIA,
    [xi.magic.spell.BIO]          = xi.effect.BIO,
    [xi.magic.spell.BIO_II]       = xi.effect.BIO,
    [xi.magic.spell.BIO_III]      = xi.effect.BIO,
    [xi.magic.spell.POISON]       = xi.effect.POISON,
    [xi.magic.spell.POISON_II]    = xi.effect.POISON,
    [xi.magic.spell.CHOKE]        = xi.effect.CHOKE,
    [xi.magic.spell.BURN]         = xi.effect.BURN,
    [xi.magic.spell.FROST]        = xi.effect.FROST,
    [xi.magic.spell.RASP]         = xi.effect.RASP,
    [xi.magic.spell.DROWN]        = xi.effect.DROWN,
    [xi.magic.spell.SHOCK]        = xi.effect.SHOCK,
    [xi.magic.spell.BLIND]        = xi.effect.BLINDNESS,
    [xi.magic.spell.BLIND_II]     = xi.effect.BLINDNESS,
    [xi.magic.spell.SLOW]         = xi.effect.SLOW,
    [xi.magic.spell.SLOW_II]      = xi.effect.SLOW,
    [xi.magic.spell.PARALYZE]     = xi.effect.PARALYSIS,
    [xi.magic.spell.PARALYZE_II]  = xi.effect.PARALYSIS,
    [xi.magic.spell.SILENCE]      = xi.effect.SILENCE,
    [xi.magic.spell.ADDLE]        = xi.effect.ADDLE,
}
ai_magic.spellToDebuffEffect = spellToDebuffEffect

function ai_magic.get_first_buff(bot, buffs)
    for _, spellId in ipairs(buffs) do
        local statusId = spellToBuffEffect[spellId]
        if statusId and ai_magic.is_effect_active(bot, statusId) then
            return nil
        end
        if statusId and not ai_magic.is_effect_active(bot, statusId) and ai_magic.spell_is_up(bot, spellId, false) then
            return spellId
        end
    end
    return nil
end

-----------------------------------
-- 28. get_buff
--     Returns first castable buff whose status isn't on (no early-exit).
-----------------------------------
function ai_magic.get_buff(bot, buffs)
    for _, spellId in ipairs(buffs) do
        local statusId = spellToBuffEffect[spellId]
        if (statusId == nil or not ai_magic.is_effect_active(bot, statusId)) and ai_magic.spell_is_up(bot, spellId, false) then
            return spellId
        end
    end
    return nil
end

-----------------------------------
-- Self-buff lists (matching ai_magic's locals)
-----------------------------------
local selfBuffs  = { xi.magic.spell.BLINK, xi.magic.spell.STONESKIN }
local selfSpikes = { xi.magic.spell.SHOCK_SPIKES, xi.magic.spell.ICE_SPIKES, xi.magic.spell.BLAZE_SPIKES }
local reraises   = {}  -- empty in original

-----------------------------------
-- 29. can_buff_self
-----------------------------------
function ai_magic.can_buff_self(bot)
    return ai_magic.get_buff(bot, selfBuffs) ~= nil
        or ai_magic.get_first_buff(bot, selfSpikes) ~= nil
        or ai_magic.get_first_buff(bot, reraises) ~= nil
end

-----------------------------------
-- 30. buff_self
-----------------------------------
function ai_magic.buff_self(bot)
    local function premagic_then_cast(spellId, target)
        if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_premagic then xi.singleplayer.bots.ai_equip_swap.equip_premagic(bot, spellId) end
        bot:castSpell(spellId, target)
    end
    local buffSpell = ai_magic.get_buff(bot, selfBuffs)
    if buffSpell then
        premagic_then_cast(buffSpell, bot); return
    end
    local spikeSpell = ai_magic.get_first_buff(bot, selfSpikes)
    if spikeSpell then
        premagic_then_cast(spikeSpell, bot); return
    end
    local reraiseSpell = ai_magic.get_first_buff(bot, reraises)
    if reraiseSpell then
        premagic_then_cast(reraiseSpell, bot); return
    end
end

-----------------------------------
-- 32. sc_is_close — true when any configured SC pair is at full TP both ends
--                   and the mob has enough HP left to bother chaining.
-----------------------------------
function ai_magic.sc_is_close(bot)
    -- NM gating replaced by runtime-tunable scNoMoreHP (alliance.*).
    -- "Below this HP, no further SCs will open" — nukers / whm stop holding
    -- MP for an MB that's not coming.
    local A        = xi.singleplayer.bots.alliance
    local lowerHP  = (A and A.scNoMoreHP) or 8
    local mob      = xi.singleplayer.bots.get_current_mob_target()
    local targetHP = mob and mob:getHPP() or 100
    if targetHP <= lowerHP then return false end
    local tp = xi.singleplayer.bots.ability.gather_tp_values(bot)
    for _, p in ipairs(tp) do
        if p.open > 999 and p.close > 999 then return true end
    end
    return false
end

-----------------------------------
-- 33. get_player_with_lowest_hpp
-- Returns the lowest-HP member entity from the alliance (default) or this
-- bot's party only (when party_only=true).
--
-- ALLIANCE-scope is the default to match get_cure_tier (also alliance-scope).
-- If they diverged — tier alliance, picker party — the WHM would correctly
-- TRIGGER on an off-party low-HP member but then mis-TARGET the lowest in
-- their OWN party (likely already healthy) and spam-cure them while the
-- actual victim stays red. Bug seen as "WHM heals tank at full HP when
-- Freya in P2 is at 58%". Multiple-WHM coordination is approximate (both
-- WHMs may pick the same lowest target and double-cure), but better than
-- letting an off-party member bleed out.
--
-- party_only=true is for spells whose validTargets is restricted to PARTY
-- + SELF (Curaga, Regen, Reraise — engine rejects cross-party casts). The
-- caller is responsible for setting this on those paths; alliance-castable
-- spells (Cure, Raise, status removal) get the alliance scope.
--
-- max_range filters out members the caster can't reach (#192); nil = no filter.
-----------------------------------
function ai_magic.get_player_with_lowest_hpp(bot, max_range, party_only)
    local members = party_only and ai_magic.get_party_members(bot)
                                or ai_magic.get_alliance_members(bot)
    local lowest, lowestHpp = nil, 101
    for _, member in ipairs(members) do
        local hpp = member:getHPP()
        if hpp > 0 and hpp < lowestHpp
           and (max_range == nil or bot:checkDistance(member) <= max_range)
        then
            lowest, lowestHpp = member, hpp
        end
    end
    return lowest
end

-----------------------------------
-- 34. get_valid_regen_target
-----------------------------------
function ai_magic.get_valid_regen_target(bot, max_range)
    -- PARTY-scope: Regen's validTargets in sql/spell_list.sql is 3
    -- (SELF + PARTY only) — unlike Cure's 95 which includes ALLIANCE.
    -- Casting Regen on an off-party alliance member fails server-side,
    -- so the picker must stay party-scoped. An off-party member at
    -- 60–75% HP can't be Regen'd by this WHM — only their own party's
    -- healer (or a Cure when their HP drops below 60).
    local best, bestHpp = nil, 75
    for _, member in ipairs(ai_magic.get_party_members(bot)) do
        local hpp = member:getHPP()
        if hpp > 0 and hpp < 75 and not ai_magic.is_effect_active(member, xi.effect.REGEN)
           and (max_range == nil or bot:checkDistance(member) <= max_range)
        then
            if hpp < bestHpp then best, bestHpp = member, hpp end
        end
    end
    return best
end

-----------------------------------
-- 35. get_most_efficient_cure_spell
-----------------------------------
function ai_magic.get_most_efficient_cure_spell(member)
    local currentHP  = member:getHP()
    local currentHPP = member:getHPP()
    if currentHPP <= 0 then return xi.magic.spell.CURE end
    local maxHP   = currentHP / (currentHPP / 100)
    local missing = maxHP - currentHP
    if     missing <= 60   then return xi.magic.spell.CURE
    elseif missing <= 140  then return xi.magic.spell.CURE_II
    elseif missing <= 290  then return xi.magic.spell.CURE_III
    elseif missing <= 540  then return xi.magic.spell.CURE_IV
    elseif missing <= 750  then return xi.magic.spell.CURE_V
    else                        return xi.magic.spell.CURE_VI
    end
end

-----------------------------------
-- 36. get_cure_tier
-----------------------------------
function ai_magic.get_cure_tier(bot)
    -- Party-only scope: scans this bot's party for the lowest-HP member to
    -- decide tier. Avoids multi-WHM pile-on (everyone healing the same
    -- alliance member). Off-party members are that party's own healer's
    -- responsibility - or the dedicated alliance fallback in role_heal /
    -- role_rdm, gated by the per-bot healScope toggle ('allianceMain' /
    -- 'allianceAssist'). Curaga is naturally party-scoped too (engine
    -- validTargets=SELF+PARTY rejects cross-party).
    --
    -- (The legacy BOT_CURE_PARTY_ONLY settings flag was removed - this is
    -- now the universal default. The alliance variants below handle the
    -- broader scope when the user explicitly opts in per-bot.)
    local members = ai_magic.get_party_members(bot)
    local lowestHpp, under60 = 100, 0
    for _, member in ipairs(members) do
        local hpp = member:getHPP()
        if hpp > 0 then
            if hpp < lowestHpp then lowestHpp = hpp end
            if hpp < 60 then under60 = under60 + 1 end
        end
    end
    if under60   > 2  then return 'Curaga'  end
    if lowestHpp < 40 then return 'Cure_P1' end
    if lowestHpp < 60 then return 'Cure_P2' end
    if ai_magic.get_valid_regen_target(bot) ~= nil then return 'Regen' end
    return 'None'
end

-----------------------------------
-- 37. cast_healing_spell
-----------------------------------
function ai_magic.cast_healing_spell(bot, spellList)
    -- Party-only scope - matches get_cure_tier so the trigger and the pick
    -- agree (a party-only trigger picking from alliance would heal the wrong
    -- char). Alliance-scope cures live on the explicit cast_alliance_cure
    -- helper, dispatched from role_heal / role_rdm based on the per-bot
    -- healScope toggle. (Legacy BOT_CURE_PARTY_ONLY removed.)
    local target = ai_magic.get_player_with_lowest_hpp(bot, ai_magic.spell_range(xi.magic.spell.CURE), true)
    if target == nil then return end
    -- Prefer the "most efficient" tier (sized to the actual missing HP). If
    -- it's up, cast it and stop — server-side the cast queues; piling on the
    -- rest of the tier list right after is just redundant traffic the server
    -- drops, and from Lua's perspective looks like "log fires, no cast".
    local efficient = ai_magic.get_most_efficient_cure_spell(target)
    if ai_magic.spell_is_up(bot, efficient, false) then
        ai_magic.cast_party_spell(bot, efficient, target)
        return
    end
    -- Efficient pick unavailable (e.g. on recast); fall back to whatever
    -- the tier list yields first.
    for _, spellId in ipairs(spellList) do
        if ai_magic.spell_is_up(bot, spellId, false) then
            ai_magic.cast_party_spell(bot, spellId, target)
            return
        end
    end
end

-----------------------------------
-- 38. cast_regen_spell
-----------------------------------
function ai_magic.cast_regen_spell(bot, spellList)
    local target = ai_magic.get_valid_regen_target(bot, ai_magic.spell_range(xi.magic.spell.REGEN))
    if target == nil then return end
    for _, spellId in ipairs(spellList) do
        if ai_magic.spell_is_up(bot, spellId, false) then
            ai_magic.cast_party_spell(bot, spellId, target)
            return  -- one cast per tick; previously the loop fell through and
                    -- tried every tier in succession, which the server queues
                    -- as duplicates and silently drops.
        end
    end
end

-----------------------------------
-- Tier lists (used by 39-43, 59-60)
-----------------------------------
local curagaSpells = {
    xi.magic.spell.CURAGA_V, xi.magic.spell.CURAGA_IV, xi.magic.spell.CURAGA_III,
    xi.magic.spell.CURAGA_II, xi.magic.spell.CURAGA,
}
local cureSpells = {
    xi.magic.spell.CURE_VI, xi.magic.spell.CURE_V, xi.magic.spell.CURE_IV,
    xi.magic.spell.CURE_III, xi.magic.spell.CURE_II, xi.magic.spell.CURE,
}
local regenSpells = { xi.magic.spell.REGEN_III, xi.magic.spell.REGEN_II, xi.magic.spell.REGEN }

-----------------------------------
-- 39. get_next_curaga_spell
-----------------------------------
function ai_magic.get_next_curaga_spell(bot)
    return ai_magic.get_next_spell(bot, curagaSpells, false, false)
end

-----------------------------------
-- 40. can_cast_curaga
-----------------------------------
function ai_magic.can_cast_curaga(bot)
    return ai_magic.get_next_curaga_spell(bot) ~= nil
end

-----------------------------------
-- 41. cast_curaga
-----------------------------------
function ai_magic.cast_curaga(bot)
    local spellId = ai_magic.get_next_curaga_spell(bot)
    if spellId == nil then return end
    -- Curaga validTargets = SELF + PARTY (cross-party rejected by engine).
    -- Picker is party-scoped and range-limited to the spell's AoE radius
    -- (members outside the radius wouldn't benefit even if targeted).
    local target = ai_magic.get_player_with_lowest_hpp(bot, ai_magic.aoe_radius(spellId), true)
    if target == nil then return end
    ai_magic.cast_party_spell(bot, spellId, target)
end

-----------------------------------
-- 42. can_cast_cure
-----------------------------------
function ai_magic.can_cast_cure(bot)
    return ai_magic.get_next_spell(bot, cureSpells, false, false) ~= nil
end

-----------------------------------
-- 43. cast_cure
-----------------------------------
function ai_magic.cast_cure(bot)
    ai_magic.cast_healing_spell(bot, cureSpells)
end

-----------------------------------
-- Status priority lists (used by 44-62)
-----------------------------------
local highPriorityStatus = {
    xi.effect.PARALYSIS, xi.effect.SILENCE, xi.effect.CURSE_I, xi.effect.DOOM,
}
local mediumPriorityStatus = {
    xi.effect.PLAGUE, xi.effect.PETRIFICATION, xi.effect.SLOW, xi.effect.DIA,
    xi.effect.BLINDNESS, xi.effect.ACCURACY_DOWN, xi.effect.ATTACK_DOWN,
    xi.effect.EVASION_DOWN, xi.effect.DEFENSE_DOWN,
}
local lowPriorityStatus = {
    xi.effect.BIND, xi.effect.WEIGHT, xi.effect.POISON, xi.effect.DISEASE,
}

local statusJobMap = {
    [xi.effect.SILENCE]       = ai_magic.casterJobs,
    [xi.effect.BLINDNESS]     = ai_magic.meleeJobs,
    [xi.effect.DISEASE]       = ai_magic.restingCasterJobs,
    [xi.effect.DIA]           = ai_magic.tankJobs,
    [xi.effect.ACCURACY_DOWN] = ai_magic.meleeJobs,
    [xi.effect.ATTACK_DOWN]   = ai_magic.meleeJobs,
    [xi.effect.EVASION_DOWN]  = { 'NIN' },
    [xi.effect.DEFENSE_DOWN]  = ai_magic.tankJobs,
}

local buffIdToCureSpell = {
    [xi.effect.PARALYSIS]      = xi.magic.spell.PARALYNA,
    [xi.effect.SILENCE]        = xi.magic.spell.SILENA,
    [xi.effect.CURSE_I]        = xi.magic.spell.CURSNA,
    [xi.effect.DOOM]           = xi.magic.spell.CURSNA,
    [xi.effect.PLAGUE]         = xi.magic.spell.VIRUNA,
    [xi.effect.PETRIFICATION]  = xi.magic.spell.STONA,
    [xi.effect.SLOW]           = xi.magic.spell.HASTE,
    [xi.effect.DIA]            = xi.magic.spell.ERASE,
    [xi.effect.BLINDNESS]      = xi.magic.spell.BLINDNA,
    [xi.effect.ACCURACY_DOWN]  = xi.magic.spell.ERASE,
    [xi.effect.ATTACK_DOWN]    = xi.magic.spell.ERASE,
    [xi.effect.EVASION_DOWN]   = xi.magic.spell.ERASE,
    [xi.effect.DEFENSE_DOWN]   = xi.magic.spell.ERASE,
    [xi.effect.BIND]           = xi.magic.spell.ERASE,
    [xi.effect.WEIGHT]         = xi.magic.spell.ERASE,
    [xi.effect.POISON]         = xi.magic.spell.POISONA,
    [xi.effect.DISEASE]        = xi.magic.spell.VIRUNA,
}

-----------------------------------
-- 44. get_player_indices_for_status
--     Returns map of memberName → job-priority-index for members afflicted
--     with the given status, filtered to targetJobs.
-----------------------------------
function ai_magic.get_player_indices_for_status(bot, targetBuffId, targetJobs, max_range)
    targetJobs = targetJobs or ai_magic.jobs
    local out = {}
    for _, member in ipairs(ai_magic.get_alliance_members(bot)) do
        if member:getHPP() > 0 and ai_magic.is_effect_active(member, targetBuffId)
           and (max_range == nil or bot:checkDistance(member) <= max_range)
        then
            local jobString = ai_magic.job_string(member:getMainJob())
            local idx = xi.singleplayer.bots.ai_util.index_of(targetJobs, jobString)
            if idx then out[member:getName()] = idx end
        end
    end
    return out
end

-----------------------------------
-- 45. get_status_count_in_party
-----------------------------------
function ai_magic.get_status_count_in_party(bot, statusId)
    -- PARTY-scope: drives should_esuna (>2 triggers Esuna spam) and Curaga
    -- vs single Cure choice in wake_up_members. Both are party-relevant
    -- thresholds — Curaga is target-type Party, and Esuna's "party is
    -- overwhelmed" heuristic shouldn't fire because another party's tank
    -- is paralyzed.
    local count = 0
    for _, member in ipairs(ai_magic.get_party_members(bot)) do
        if ai_magic.is_effect_active(member, statusId) then count = count + 1 end
    end
    return count
end

-----------------------------------
-- 46. should_esuna
-----------------------------------
function ai_magic.should_esuna(bot, statusId)
    return ai_magic.get_status_count_in_party(bot, statusId) > 2
end

-----------------------------------
-- 47. get_player_with_status  (returns member entity)
-----------------------------------
function ai_magic.get_player_with_status(bot, statusId, max_range)
    for _, member in ipairs(ai_magic.get_alliance_members(bot)) do
        if member:getHPP() > 0 and ai_magic.is_effect_active(member, statusId)
           and (max_range == nil or bot:checkDistance(member) <= max_range)
        then
            return member
        end
    end
    return nil
end

-- Party-only variant. Erase (and any spell with validTargets that excludes
-- TARGET_PLAYER_ALLIANCE) is engine-rejected on alliance members. Wiki:
-- "Unlike -na spells, Erase can only be cast on party members." Spam without
-- this gate: bot finds an afflicted alliance member, casts Erase, engine
-- silently rejects, status persists, next tick same fail. Repeats until the
-- status naturally wears off.
function ai_magic.get_party_member_with_status(bot, statusId, max_range)
    for _, member in ipairs(ai_magic.get_party_members(bot)) do
        if member:getHPP() > 0 and ai_magic.is_effect_active(member, statusId)
           and (max_range == nil or bot:checkDistance(member) <= max_range)
        then
            return member
        end
    end
    return nil
end

-- Spells with validTargets that excludes TARGET_PLAYER_ALLIANCE — need
-- party-scope lookup. Source: sql/spell_list.sql `validTargets` column.
-- Erase = 3 (self+party only). -na spells = 91 (incl. alliance).
ai_magic.partyOnlyCureSpells = {
    [xi.magic.spell.ERASE] = true,
}

-----------------------------------
-- 48. party_has_status
-----------------------------------
function ai_magic.party_has_status(bot, buffIds)
    for _, member in ipairs(ai_magic.get_alliance_members(bot)) do
        if member:getHPP() > 0 then
            for _, id in ipairs(buffIds) do
                if ai_magic.is_effect_active(member, id) then return true end
            end
        end
    end
    return false
end

-----------------------------------
-- 49. find_status_cure
--     Returns (spellId, target) for the first castable priority cure.
-----------------------------------
function ai_magic.find_status_cure(bot, statusTbl, max_range)
    -- Party-only -na spell lookup. Alliance-scope status removal is fired
    -- explicitly from role_heal / role_rdm via the can_cure_alliance_*
    -- helpers, gated on the per-bot healScope toggle. Erase / Curaga and
    -- friends are always party-only by engine constraint (validTargets=3)
    -- regardless of mode. (Legacy BOT_CURE_PARTY_ONLY removed.)
    for _, statusId in ipairs(statusTbl) do
        local spellId = buffIdToCureSpell[statusId]
        if spellId then
            local target = ai_magic.get_party_member_with_status(bot, statusId, max_range)
            if target ~= nil and ai_magic.spell_is_up(bot, spellId, false) then
                return spellId, target
            end
        end
    end
    return nil, nil
end

-----------------------------------
-- 50. cure_status
-----------------------------------
function ai_magic.cure_status(bot, statusTbl)
    local spellId, target = ai_magic.find_status_cure(bot, statusTbl, ai_magic.DEFAULT_SPELL_RANGE)
    if spellId and target then return ai_magic.cast_party_spell(bot, spellId, target) end
    return false
end

-----------------------------------
-- 50b. Heal-scope setter + alliance-scope variants.
--      Per-bot toggle for role_heal.tick. Set via 0x176 SET_HEAL_SCOPE →
--      luautils::OnBotSetHealScope. Modes are 'party' (default), 'allianceAssist'
--      (party + BLM-tier alliance fallback), 'allianceMain' (WHM-tier + single-
--      target -na widened to alliance). Curaga / Erase / Protectra / Shellra
--      stay party-only because the engine targets reject cross-party.
-----------------------------------
local HEAL_SCOPE_BY_VALUE = { [0] = 'party', [1] = 'allianceAssist', [2] = 'allianceMain' }
function ai_magic.set_bot_heal_scope(primary, botName, mode)
    if primary == nil or botName == nil or botName == '' then return end
    local target = botName:lower()
    local primaryId = primary:getID()
    local function is_owned(m)
        if m == primary then return true end
        if m.isHeadless and m:isHeadless() and m.getParentCharId and m:getParentCharId() == primaryId then return true end
        return false
    end
    for _, member in ipairs(primary:getAlliance() or {}) do
        if is_owned(member) and member:getName():lower() == target then
            local s = xi.singleplayer.bots.ensure_bot(member:getID())
            local newMode = HEAL_SCOPE_BY_VALUE[tonumber(mode) or -1] or 'party'
            s.healScope = newMode
            printf(string.format('ai_magic.set_bot_heal_scope: %s -> %s', member:getName(), newMode))
            return
        end
    end
    printf(string.format('ai_magic.set_bot_heal_scope: no owned bot "%s"', tostring(botName)))
end

-- get_alliance_cure_tier: same thresholds as get_cure_tier but alliance-wide.
-- Curaga deliberately omitted from the tier (engine validTargets rejects
-- cross-party Curaga).
function ai_magic.get_alliance_cure_tier(bot)
    local lowestHpp = 100
    for _, member in ipairs(ai_magic.get_alliance_members(bot)) do
        local hpp = member:getHPP()
        if hpp > 0 and hpp < lowestHpp then lowestHpp = hpp end
    end
    if lowestHpp < 40 then return 'Cure_P1' end
    if lowestHpp < 60 then return 'Cure_P2' end
    return 'None'
end

-- Single-target Cure on lowest-HP alliance member. Mirrors party-side
-- cast_cure shape: callers gate on `allianceCureTier == 'Cure_P1'` /
-- 'Cure_P2' separately (so they can position each tier independently in
-- the role_heal cascade) and use the existing can_cast_cure for the
-- spell-availability check. cast_alliance_cure picks the most-efficient
-- Cure tier for the target's missing HP automatically.
function ai_magic.cast_alliance_cure(bot)
    local target = ai_magic.get_player_with_lowest_hpp(bot, ai_magic.spell_range(xi.magic.spell.CURE), false)
    if target == nil then return end
    local efficient = ai_magic.get_most_efficient_cure_spell(target)
    if efficient and ai_magic.spell_is_up(bot, efficient, false) then
        ai_magic.cast_party_spell(bot, efficient, target)
        return
    end
    for _, spellId in ipairs(cureSpells) do
        if ai_magic.spell_is_up(bot, spellId, false) then
            ai_magic.cast_party_spell(bot, spellId, target)
            return
        end
    end
end

-- Alliance-scope status removal. Mirrors find_status_cure but always uses the
-- alliance scan. partyOnlyCureSpells entries (Erase) are still respected so
-- those skip the alliance scan and stay party-only.
function ai_magic.find_alliance_status_cure(bot, statusTbl, max_range)
    for _, statusId in ipairs(statusTbl) do
        local spellId = buffIdToCureSpell[statusId]
        if spellId ~= nil then
            local target
            if ai_magic.partyOnlyCureSpells[spellId] then
                target = ai_magic.get_party_member_with_status(bot, statusId, max_range)
            else
                target = ai_magic.get_player_with_status(bot, statusId, max_range)
            end
            if target ~= nil and ai_magic.spell_is_up(bot, spellId, false) then
                return spellId, target
            end
        end
    end
    return nil, nil
end

function ai_magic.cure_alliance_status(bot, statusTbl)
    local spellId, target = ai_magic.find_alliance_status_cure(bot, statusTbl, ai_magic.DEFAULT_SPELL_RANGE)
    if spellId and target then return ai_magic.cast_party_spell(bot, spellId, target) end
    return false
end

-- Per-priority alliance status helpers — exact mirrors of the party-side
-- can_cure_X_priority_status / cure_X_priority_status pairs at lines 908-1015.
-- Each pair scopes to one of the three status lists (highPriorityStatus,
-- mediumPriorityStatus, lowPriorityStatus) so role_heal.tick can position
-- them independently in the cascade.
function ai_magic.can_cure_alliance_high_priority_status(bot)
    local s, _ = ai_magic.find_alliance_status_cure(bot, highPriorityStatus, ai_magic.DEFAULT_SPELL_RANGE)
    return s ~= nil
end

function ai_magic.cure_alliance_high_priority_status(bot)
    return ai_magic.cure_alliance_status(bot, highPriorityStatus)
end

function ai_magic.can_cure_alliance_medium_priority_status(bot)
    local s, _ = ai_magic.find_alliance_status_cure(bot, mediumPriorityStatus, ai_magic.DEFAULT_SPELL_RANGE)
    return s ~= nil
end

function ai_magic.cure_alliance_medium_priority_status(bot)
    return ai_magic.cure_alliance_status(bot, mediumPriorityStatus)
end

function ai_magic.can_cure_alliance_low_priority_status(bot)
    local s, _ = ai_magic.find_alliance_status_cure(bot, lowPriorityStatus, ai_magic.DEFAULT_SPELL_RANGE)
    return s ~= nil
end

function ai_magic.cure_alliance_low_priority_status(bot)
    return ai_magic.cure_alliance_status(bot, lowPriorityStatus)
end

-- BLM-tier alliance emergency cure for AllianceAssist mode. Tighter HP gate
-- (<30) than the WHM tier — last-resort backup when the alliance's own
-- healer is overwhelmed. Mirrors party-side get_blm_cure_tier shape: caller
-- gates on `allianceBlmCureTier == 'Cure_P1'` and the cast itself reuses
-- cast_alliance_cure (picks whichever Cure tier this bot has available).
function ai_magic.get_alliance_blm_cure_tier(bot)
    local lowestHpp = 100
    for _, member in ipairs(ai_magic.get_alliance_members(bot)) do
        local hpp = member:getHPP()
        if hpp > 0 and hpp < lowestHpp then lowestHpp = hpp end
    end
    if lowestHpp < 30 then return 'Cure_P1' end
    return 'None'
end

-----------------------------------
-- 51. can_cure_high_priority_status
-----------------------------------
function ai_magic.can_cure_high_priority_status(bot)
    local s, _ = ai_magic.find_status_cure(bot, highPriorityStatus, ai_magic.DEFAULT_SPELL_RANGE)
    return s ~= nil
end

-----------------------------------
-- 52. cure_high_priority_status
-----------------------------------
function ai_magic.cure_high_priority_status(bot) return ai_magic.cure_status(bot, highPriorityStatus) end

-----------------------------------
-- can_clear_mage_rest_blocker / clear_mage_rest_blocker
--   Out-of-combat priority slot used by role_heal / role_rdm / role_nuke.
--   Scans alliance for any mage-role bot (Healer / Rdm / Nuker) afflicted
--   with a status that blocks /heal on (Poison + Erase-curable DoTs +
--   Petrify); casts the corresponding cure if this bot knows it. Sleep is
--   intentionally excluded — wake_up_members handles those lower in the
--   cascade. Charm has no spell cure.
--
--   The map below mirrors ai_util.statusThatPreventRest, minus Sleep /
--   Charm. partyOnly tags Erase, which the engine rejects on alliance
--   targets (Erase's validTargets excludes TARGET_PLAYER_ALLIANCE).
--
--   "Mage role" is the bot's role enum (state.role), NOT main job — subjobs
--   often provide -na spells, so a melee/tank with /WHM could in theory
--   clear these on themselves, but per spec we only TARGET mage-role bots
--   to keep the scope tight. The caster bot doesn't need to be a mage role
--   itself; can_use_spell will filter.
-----------------------------------
local mageRestBlockerCures = {
    { effect = xi.effect.POISON,        spell = xi.magic.spell.POISONA, partyOnly = false },
    { effect = xi.effect.BIO,           spell = xi.magic.spell.ERASE,   partyOnly = true  },
    { effect = xi.effect.DIA,           spell = xi.magic.spell.ERASE,   partyOnly = true  },
    { effect = xi.effect.BURN,          spell = xi.magic.spell.ERASE,   partyOnly = true  },
    { effect = xi.effect.FROST,         spell = xi.magic.spell.ERASE,   partyOnly = true  },
    { effect = xi.effect.CHOKE,         spell = xi.magic.spell.ERASE,   partyOnly = true  },
    { effect = xi.effect.RASP,          spell = xi.magic.spell.ERASE,   partyOnly = true  },
    { effect = xi.effect.SHOCK,         spell = xi.magic.spell.ERASE,   partyOnly = true  },
    { effect = xi.effect.DROWN,         spell = xi.magic.spell.ERASE,   partyOnly = true  },
    { effect = xi.effect.PETRIFICATION, spell = xi.magic.spell.STONA,   partyOnly = false },
}

local function target_role_is_mage(memberId)
    local A = xi.singleplayer.bots.alliance
    if A == nil or A.bot == nil then return false end
    local s = A.bot[memberId]
    if s == nil then return false end
    local R = xi.singleplayer.bots.Role
    return s.role == R.Healer or s.role == R.Rdm or s.role == R.Nuker
end

local function mage_rest_clear_combat_safe(bot)
    local primary = bot:isHeadless() and GetPlayerByID(bot:getParentCharId()) or bot
    if ai_magic.combat_active(primary) ~= nil then return false end
    if xi.singleplayer.bots.threat and xi.singleplayer.bots.threat.peelable_for
       and xi.singleplayer.bots.threat.peelable_for(bot) ~= nil then return false end
    return true
end

-- Returns (memberEntity, spellId, effectId) or nil. Walks the map in
-- declaration order so Poison/Erase win over Petrify when both are
-- present (the multi-affliction case isn't expected often but matters
-- for determinism).
local function find_mage_rest_blocker_target(bot)
    if not mage_rest_clear_combat_safe(bot) then return nil end
    local botId = bot:getID()
    local partyIds = {}
    for _, pm in ipairs(ai_magic.get_party_members(bot)) do partyIds[pm:getID()] = true end

    for _, entry in ipairs(mageRestBlockerCures) do
        local pool = entry.partyOnly and ai_magic.get_party_members(bot)
                                      or ai_magic.get_alliance_members(bot)
        for _, member in ipairs(pool) do
            if member:getHPP() > 0
               and target_role_is_mage(member:getID())
               and ai_magic.is_effect_active(member, entry.effect)
               and ai_magic.spell_is_up(bot, entry.spell, false, member)
               and bot:checkDistance(member) <= ai_magic.DEFAULT_SPELL_RANGE then
                return member, entry.spell, entry.effect
            end
        end
    end
    return nil
end

function ai_magic.can_clear_mage_rest_blocker(bot)
    return find_mage_rest_blocker_target(bot) ~= nil
end

function ai_magic.clear_mage_rest_blocker(bot)
    local member, spellId, effectId = find_mage_rest_blocker_target(bot)
    if member == nil then return end
    xi.singleplayer.bots.ai_util.log(bot, 'AutoMage',
        string.format('clear_mage_rest_blocker: spell=%d on=%s effect=%d', spellId, member:getName(), effectId))
    ai_magic.cast_party_spell(bot, spellId, member)
end

-----------------------------------
-- 53. sleeping_members
-----------------------------------
local sleepStatusIds = { xi.effect.SLEEP_I, xi.effect.SLEEP_II }

function ai_magic.sleeping_members(bot)
    local count = 0
    for _, id in ipairs(sleepStatusIds) do
        count = count + ai_magic.get_status_count_in_party(bot, id)
    end
    if count <= 0 then return false end
    return (count > 2 and ai_magic.spell_is_up(bot, xi.magic.spell.CURAGA, false))
        or ai_magic.spell_is_up(bot, xi.magic.spell.CURE, false)
end

-----------------------------------
-- 54. wake_up_members
-----------------------------------
function ai_magic.wake_up_members(bot)
    local count, sleeper = 0, nil
    for _, id in ipairs(sleepStatusIds) do
        local c = ai_magic.get_status_count_in_party(bot, id)
        count = count + c
        if sleeper == nil then sleeper = ai_magic.get_player_with_status(bot, id) end
    end
    if count > 2 and ai_magic.spell_is_up(bot, xi.magic.spell.CURAGA, false) then
        return ai_magic.cast_party_spell(bot, xi.magic.spell.CURAGA, bot)
    end
    if sleeper and ai_magic.spell_is_up(bot, xi.magic.spell.CURE, false) then
        return ai_magic.cast_party_spell(bot, xi.magic.spell.CURE, sleeper)
    end
    return false
end

-----------------------------------
-- 55. sleeping_alliance
-----------------------------------
function ai_magic.sleeping_alliance(bot)
    if not ai_magic.spell_is_up(bot, xi.magic.spell.CURE, false) then return false end
    for _, member in ipairs(ai_magic.get_alliance_members(bot)) do
        for _, id in ipairs(sleepStatusIds) do
            if ai_magic.is_effect_active(member, id) then return true end
        end
    end
    return false
end

-----------------------------------
-- 56. wake_up_alliance
-----------------------------------
function ai_magic.wake_up_alliance(bot)
    for _, member in ipairs(ai_magic.get_alliance_members(bot)) do
        for _, id in ipairs(sleepStatusIds) do
            if ai_magic.is_effect_active(member, id) then
                return ai_magic.cast_party_spell(bot, xi.magic.spell.CURE, member)
            end
        end
    end
    return false
end

-----------------------------------
-- 57. can_cure_medium_priority_status
-----------------------------------
function ai_magic.can_cure_medium_priority_status(bot)
    local s, _ = ai_magic.find_status_cure(bot, mediumPriorityStatus, ai_magic.DEFAULT_SPELL_RANGE)
    return s ~= nil
end

-----------------------------------
-- 58. cure_medium_priority_status
-----------------------------------
function ai_magic.cure_medium_priority_status(bot) return ai_magic.cure_status(bot, mediumPriorityStatus) end

-----------------------------------
-- 59. can_cast_regen
-----------------------------------
function ai_magic.can_cast_regen(bot)
    if ai_magic.get_valid_regen_target(bot, ai_magic.spell_range(xi.magic.spell.REGEN)) == nil then return false end
    for _, spellId in ipairs(regenSpells) do
        if ai_magic.spell_is_up(bot, spellId, false) then return true end
    end
    return false
end

-----------------------------------
-- 60. cast_regen
-----------------------------------
function ai_magic.cast_regen(bot)
    ai_magic.cast_regen_spell(bot, regenSpells)
end

-----------------------------------
-- 61. can_cure_low_priority_status
-----------------------------------
function ai_magic.can_cure_low_priority_status(bot)
    local s, _ = ai_magic.find_status_cure(bot, lowPriorityStatus, ai_magic.DEFAULT_SPELL_RANGE)
    return s ~= nil
end

-----------------------------------
-- 62. cure_low_priority_status
-----------------------------------
function ai_magic.cure_low_priority_status(bot) return ai_magic.cure_status(bot, lowPriorityStatus) end

-----------------------------------
-- Party-AoE positioning helper.
--
-- For self-centered party-AoE spells (Protectra, Shellra, bar-X-ra) the
-- engine emanates the effect from the CASTER at aoe_radius(spellId). If
-- some party members are outside that radius (common when the mage is in
-- AoE battle formation, mages stand 15-17y from mob while party melees
-- are at 3-4y), the cast leaves them unbuffed.
--
-- Returns:
--   nil       — all missing-effect party members are already in AoE range,
--               or no party member is missing the effect; caller casts.
--   {x,y,z}   — a centroid position that the caster should walk to before
--               casting so more missing-effect members land inside the AoE.
--               Caller sets state.roleMovementTarget = <this>, defers the
--               cast one tick, and re-evaluates.
--
-- Centroid = arithmetic mean of missing-effect member positions. Majority
-- preference (per #275 spec): a lone far-away member doesn't drag the WHM
-- away from the cluster; they'll be picked up next tick if still missing.
-----------------------------------
function ai_magic.party_aoe_move_target(bot, spellId)
    if bot == nil or spellId == nil then return nil end
    if xi.spells == nil or xi.spells.enhancing == nil
       or xi.spells.enhancing.getEffectId == nil then
        return nil
    end
    local effId = xi.spells.enhancing.getEffectId(spellId)
    if effId == nil then return nil end
    local radius = ai_magic.aoe_radius(spellId)
    if radius == nil or radius <= 0 then return nil end

    -- Party members alive + missing the effect. Party (not alliance) —
    -- party-AoE spells are party-scope in FFXI.
    local missing = {}
    for _, m in ipairs(bot:getParty() or {}) do
        if m ~= nil and m:getHPP() > 0
           and not ai_magic.is_effect_active(m, effId)
        then
            table.insert(missing, m)
        end
    end
    if #missing == 0 then return nil end

    -- If every missing member is already inside the caster's AoE, no move.
    local anyOut = false
    for _, m in ipairs(missing) do
        if bot:checkDistance(m) > radius then anyOut = true; break end
    end
    if not anyOut then return nil end

    -- Compute centroid of missing members.
    local cx, cz = 0, 0
    for _, m in ipairs(missing) do
        cx = cx + m:getXPos(); cz = cz + m:getZPos()
    end
    return { x = cx / #missing, y = bot:getYPos(), z = cz / #missing }
end

-----------------------------------
-- Group buff lists
-----------------------------------
local protectraSpells = {
    xi.magic.spell.PROTECTRA_V, xi.magic.spell.PROTECTRA_IV, xi.magic.spell.PROTECTRA_III,
    xi.magic.spell.PROTECTRA_II, xi.magic.spell.PROTECTRA,
}
local shellraSpells = {
    xi.magic.spell.SHELLRA_V, xi.magic.spell.SHELLRA_IV, xi.magic.spell.SHELLRA_III,
    xi.magic.spell.SHELLRA_II, xi.magic.spell.SHELLRA,
}

-----------------------------------
-- 63. can_protectra
-----------------------------------
function ai_magic.can_protectra(bot)
    if ai_magic.is_effect_active(bot, xi.effect.PROTECT) then return false end
    for _, spellId in ipairs(protectraSpells) do
        if ai_magic.spell_is_up(bot, spellId, false) then return true end
    end
    return false
end

-----------------------------------
-- 64. can_shellra
-----------------------------------
function ai_magic.can_shellra(bot)
    if ai_magic.is_effect_active(bot, xi.effect.SHELL) then return false end
    for _, spellId in ipairs(shellraSpells) do
        if ai_magic.spell_is_up(bot, spellId, false) then return true end
    end
    return false
end

-----------------------------------
-- 65. can_protectra_or_shellra
-----------------------------------
function ai_magic.can_protectra_or_shellra(bot)
    return ai_magic.can_protectra(bot) or ai_magic.can_shellra(bot)
end

-----------------------------------
-- 66. cast_protectra_or_shellra — picks Protectra tier first, then Shellra.
-- Internally handles the party-AoE positioning problem via
-- party_aoe_move_target: when a missing-effect party member is outside the
-- spell's AoE radius, sets roleMovementTarget to the centroid of missing
-- members and defers the cast one tick. Mirrors the BRD try_refresh_song
-- pattern (walk-or-cast inside the branch; cascade doesn't see the move).
--
-- The self-status gate stays in can_protectra / can_shellra as-is (#Q4:
-- leave existing behavior alone) — so this branch only fires while the
-- bot itself lacks Protect/Shell. Party-status-driven refresh is deferred
-- to the idle-tick smart-refresh task.
-----------------------------------
function ai_magic.cast_protectra_or_shellra(bot)
    -- Pick the exact spell we'd cast this tick so we can look up AoE
    -- radius and effect ID against the right one.
    local spellId
    if ai_magic.can_protectra(bot) then
        for _, sid in ipairs(protectraSpells) do
            if ai_magic.spell_is_up(bot, sid, false) then spellId = sid; break end
        end
    end
    if spellId == nil and ai_magic.can_shellra(bot) then
        for _, sid in ipairs(shellraSpells) do
            if ai_magic.spell_is_up(bot, sid, false) then spellId = sid; break end
        end
    end
    if spellId == nil then return end
    local moveTo = ai_magic.party_aoe_move_target(bot, spellId)
    if moveTo ~= nil then
        local state = xi.singleplayer.bots.ensure_bot(bot:getID())
        state.roleMovementTarget = moveTo
        return
    end
    local equip = xi.singleplayer.bots.ai_equip_swap
    if equip and equip.equip_premagic then equip.equip_premagic(bot, spellId) end
    bot:castSpell(spellId, bot)
end

-----------------------------------
-- 67. get_bar_spell
--     Server-side: mob:getFamily() / mob:getEcosystem() give us the lookup
--     keys directly. bot_bar_spells.lua provides the family→spell + ecosystem→
--     spell mapping tables (data file, easily editable; no need for a monster
--     name DB port).
-----------------------------------
function ai_magic.get_bar_spell(bot, field, mob)
    if mob == nil or xi.singleplayer.bots.ai_bar_spells == nil then return nil end
    local spellId
    if field == 'bar_element' then
        spellId = xi.singleplayer.bots.ai_bar_spells.get_element(mob)
    else
        spellId = xi.singleplayer.bots.ai_bar_spells.get_status(mob)
    end
    if spellId == nil or spellId == 0 then return nil end
    if ai_magic.spell_is_up(bot, spellId, false) then return spellId end
    return nil
end

-----------------------------------
-- 68. get_bar_element_spell
-----------------------------------
function ai_magic.get_bar_element_spell(bot, mob) return ai_magic.get_bar_spell(bot, 'bar_element', mob) end

-----------------------------------
-- 69. get_bar_status_spell
-----------------------------------
function ai_magic.get_bar_status_spell(bot, mob) return ai_magic.get_bar_spell(bot, 'bar_status', mob) end

-----------------------------------
-- Bar-spell self-status gate helper: given a spell ID, does the bot lack
-- its resulting status effect? Skips nil spellIds (no mapping for this mob)
-- and gracefully returns false when getEffectId isn't reachable (upstream
-- accessor missing) so failures degrade to "don't cast" instead of casting
-- forever.
-----------------------------------
local function bot_needs_bar_effect(bot, spellId)
    if spellId == nil then return false end
    if xi.spells == nil or xi.spells.enhancing == nil
       or xi.spells.enhancing.getEffectId == nil then
        return false
    end
    local effId = xi.spells.enhancing.getEffectId(spellId)
    if effId == nil then return false end
    return not ai_magic.is_effect_active(bot, effId)
end

-----------------------------------
-- 70. can_bar_spell — true when there's an applicable bar spell for the
-- current mob AND the bot lacks the resulting effect. Self-status check
-- mirrors can_protectra / can_shellra: once the bot has the effect, this
-- returns false and the tick-spam stops. Runtime effect lookup via
-- xi.spells.enhancing.getEffectId — no hardcoded spell→effect map.
-----------------------------------
function ai_magic.can_bar_spell(bot)
    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return false end
    return bot_needs_bar_effect(bot, ai_magic.get_bar_element_spell(bot, target))
        or bot_needs_bar_effect(bot, ai_magic.get_bar_status_spell(bot, target))
end

-----------------------------------
-- 71. cast_bar_spell — element preferred, then status. Internally handles
-- the party-AoE positioning problem via party_aoe_move_target: when a
-- missing-effect party member is outside the spell's AoE radius, sets
-- roleMovementTarget to the centroid of missing members and defers the
-- cast one tick. Mirrors the BRD try_refresh_song pattern (walk-or-cast
-- inside the branch; cascade doesn't see the movement).
-----------------------------------
function ai_magic.cast_bar_spell(bot)
    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return end
    -- Pick the spell we'd cast this tick (element preferred).
    local spellId
    local elemSpell = ai_magic.get_bar_element_spell(bot, target)
    if bot_needs_bar_effect(bot, elemSpell) then
        spellId = elemSpell
    else
        local statSpell = ai_magic.get_bar_status_spell(bot, target)
        if bot_needs_bar_effect(bot, statSpell) then
            spellId = statSpell
        end
    end
    if spellId == nil then return end
    -- Move-or-cast: if the AoE won't reach missing-effect members, walk
    -- to the centroid this tick; next tick either casts (in range) or
    -- re-computes the centroid.
    local moveTo = ai_magic.party_aoe_move_target(bot, spellId)
    if moveTo ~= nil then
        local state = xi.singleplayer.bots.ensure_bot(bot:getID())
        state.roleMovementTarget = moveTo
        return
    end
    local equip = xi.singleplayer.bots.ai_equip_swap
    if equip and equip.equip_premagic then equip.equip_premagic(bot, spellId) end
    bot:castSpell(spellId, bot)
end

-----------------------------------
-- Raise tier list
-----------------------------------
local raiseSpells = {
    xi.magic.spell.ARISE, xi.magic.spell.RAISE_III, xi.magic.spell.RAISE_II, xi.magic.spell.RAISE,
}

-----------------------------------
-- 72. get_dead_member_index  (returns the member entity for parity with later usage)
-----------------------------------
function ai_magic.get_dead_member_index(bot, max_range)
    for _, member in ipairs(ai_magic.get_alliance_members(bot)) do
        -- Skip targets that already have an open raise/tractor dialog —
        -- they're "pending acceptance", not "needs a fresh cast." Without
        -- this filter, can_raise stays true while the dialog sits open
        -- (target is still dead until they click Accept), and the WHM
        -- re-casts Raise every tick (~400ms), spamming MP and chat. The
        -- engine's hasRaiseTractorMenu reads CCharEntity::m_hasRaiseTractorMenu
        -- which is set on cast land and cleared on accept/decline/timeout.
        local hasMenu = member.hasRaiseTractorMenu and member:hasRaiseTractorMenu() or false
        if member:getHPP() == 0
           and not hasMenu
           and (max_range == nil or bot:checkDistance(member) <= max_range)
        then
            return member
        end
    end
    return nil
end

-----------------------------------
-- 73. dead_members
-----------------------------------
function ai_magic.dead_members(bot) return ai_magic.get_dead_member_index(bot) ~= nil end

-----------------------------------
-- 74. can_raise
-----------------------------------
function ai_magic.can_raise(bot)
    -- #192: gate on having a KO'd member in Raise range, not just anywhere.
    if ai_magic.get_dead_member_index(bot, ai_magic.spell_range(xi.magic.spell.RAISE)) == nil then return false end
    for _, spellId in ipairs(raiseSpells) do
        if ai_magic.spell_is_up(bot, spellId, false) then return true end
    end
    return false
end

-----------------------------------
-- 75. cast_raise
-----------------------------------
function ai_magic.cast_raise(bot)
    -- #192: only pick a KO'd member that's actually in Raise range.
    local target = ai_magic.get_dead_member_index(bot, ai_magic.spell_range(xi.magic.spell.RAISE))
    if target == nil then
        printf(string.format('[AutoRaise] %s: cast_raise called but no dead member in range', bot:getName()))
        return
    end
    local tried = {}
    for _, spellId in ipairs(raiseSpells) do
        local up = ai_magic.spell_is_up(bot, spellId, false)
        table.insert(tried, string.format('%d=%s', spellId, tostring(up)))
        if up then
            printf(string.format('[AutoRaise] %s → spellId=%d target=%s targetHasMenu=%s',
                bot:getName(), spellId, target:getName(),
                tostring(target.hasRaiseTractorMenu and target:hasRaiseTractorMenu() or false)))
            return ai_magic.cast_party_spell(bot, spellId, target)
        end
    end
    printf(string.format('[AutoRaise] %s: no raise spell available. tried=[%s]', bot:getName(), table.concat(tried, ',')))
end

-----------------------------------
-- 75a. get_dead_whm_index
-----------------------------------
-- Same KO'd-and-in-range scan as get_dead_member_index, but restricted to
-- alliance members whose main job is WHM. Used to prioritize resurrecting the
-- healers first: WHM has the best raise spells, so getting a dead WHM back up
-- lets them take over raising everyone else.
function ai_magic.get_dead_whm_index(bot, max_range)
    for _, member in ipairs(ai_magic.get_alliance_members(bot)) do
        if ai_magic.job_string(member:getMainJob()) == 'WHM' then
            local hasMenu = member.hasRaiseTractorMenu and member:hasRaiseTractorMenu() or false
            if member:getHPP() == 0
               and not hasMenu
               and (max_range == nil or bot:checkDistance(member) <= max_range)
            then
                return member
            end
        end
    end
    return nil
end

-----------------------------------
-- 75b. can_raise_whm
-----------------------------------
-- True only when there is a dead WHM in Raise range and a raise spell is up.
function ai_magic.can_raise_whm(bot)
    if ai_magic.get_dead_whm_index(bot, ai_magic.spell_range(xi.magic.spell.RAISE)) == nil then return false end
    for _, spellId in ipairs(raiseSpells) do
        if ai_magic.spell_is_up(bot, spellId, false) then return true end
    end
    return false
end

-----------------------------------
-- 75c. cast_raise_whm
-----------------------------------
-- Raise only a dead WHM (best raise available), ignoring other dead members.
function ai_magic.cast_raise_whm(bot)
    local target = ai_magic.get_dead_whm_index(bot, ai_magic.spell_range(xi.magic.spell.RAISE))
    if target == nil then
        printf(string.format('[AutoRaise] %s: cast_raise_whm called but no dead WHM in range', bot:getName()))
        return
    end
    local tried = {}
    for _, spellId in ipairs(raiseSpells) do
        local up = ai_magic.spell_is_up(bot, spellId, false)
        table.insert(tried, string.format('%d=%s', spellId, tostring(up)))
        if up then
            printf(string.format('[AutoRaise] %s (WHM-first) → spellId=%d target=%s targetHasMenu=%s',
                bot:getName(), spellId, target:getName(),
                tostring(target.hasRaiseTractorMenu and target:hasRaiseTractorMenu() or false)))
            return ai_magic.cast_party_spell(bot, spellId, target)
        end
    end
    printf(string.format('[AutoRaise] %s: no raise spell available for WHM-first. tried=[%s]', bot:getName(), table.concat(tried, ',')))
end

-----------------------------------
-- Dia tier list
-----------------------------------
local diaSpells = { xi.magic.spell.DIA_III, xi.magic.spell.DIA_II, xi.magic.spell.DIA }

-----------------------------------
-- 76. get_next_dia
-----------------------------------
function ai_magic.get_next_dia(bot)
    return ai_magic.get_next_spell(bot, diaSpells, true, true)
end

-----------------------------------
-- 77. can_dia
-----------------------------------
function ai_magic.can_dia(bot) return ai_magic.mob_in_cast_range(bot) and ai_magic.get_next_dia(bot) ~= nil end

-----------------------------------
-- 78. cast_dia
-----------------------------------
function ai_magic.cast_dia(bot)
    local spellId = ai_magic.get_next_dia(bot)
    if spellId then return ai_magic.cast_spell(bot, spellId) end
end

-----------------------------------
-- WHM enfeebles + Banish list
-----------------------------------
local whmEnfeebleSpells = { xi.magic.spell.PARALYZE }
local casualWhmNukes    = { xi.magic.spell.BANISH }

-----------------------------------
-- 79. get_next_whm_enfeeble
-----------------------------------
function ai_magic.get_next_whm_enfeeble(bot)
    return ai_magic.get_next_spell(bot, whmEnfeebleSpells, true, true)
end

-----------------------------------
-- 80. can_whm_enfeeble
-----------------------------------
function ai_magic.can_whm_enfeeble(bot)
    if not ai_magic.mob_in_cast_range(bot) then return false end
    return ai_magic.get_next_dia(bot) ~= nil or ai_magic.get_next_whm_enfeeble(bot) ~= nil
end

-----------------------------------
-- 81. whm_enfeeble
-----------------------------------
function ai_magic.whm_enfeeble(bot)
    local spellId = ai_magic.get_next_dia(bot) or ai_magic.get_next_whm_enfeeble(bot)
    if spellId then return ai_magic.cast_spell(bot, spellId) end
end

-----------------------------------
-- 82. get_next_casual_whm_nuke
-----------------------------------
function ai_magic.get_next_casual_whm_nuke(bot)
    if bot:getMPP() < 70 then return nil end
    return ai_magic.get_next_spell(bot, casualWhmNukes, true, false)
end

-----------------------------------
-- 83. casual_whm_nuke_is_up
-----------------------------------
function ai_magic.casual_whm_nuke_is_up(bot)
    if not ai_magic.mob_in_cast_range(bot) then return false end
    local state = getState(bot)
    local delay = state.casualNukingDelay * 1000 * state.casualNukeDelayMultiple
    if xi.singleplayer.bots.ai_util.get_ms_since_epoch() < (state.lastCasualNukeEnd or 0) + delay then return false end
    state.casualNukeDelayMultiple = 1
    if not ai_magic.sc_is_close(bot) then return ai_magic.get_next_casual_whm_nuke(bot) ~= nil end
    local target = xi.singleplayer.bots.get_current_mob_target()
    local targetHPP = target and target:getHPP() or 100
    if ai_magic.sc_is_close(bot) and (targetHPP == nil or targetHPP > 20) then return false end
    return ai_magic.get_next_casual_whm_nuke(bot) ~= nil
end

-----------------------------------
-- 84. cast_casual_whm_nuke
-----------------------------------
function ai_magic.cast_casual_whm_nuke(bot)
    local spellId = ai_magic.get_next_casual_whm_nuke(bot)
    if spellId then
        local state = getState(bot)
        state.lastCasualNukeEnd = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
        return ai_magic.cast_spell(bot, spellId)
    end
end

-----------------------------------
-- 85. get_valid_refresh_target
-----------------------------------
function ai_magic.get_valid_refresh_target(bot)
    if not ai_magic.is_effect_active(bot, xi.effect.REFRESH) then return bot end
    local alwaysTarget, lowMPTarget = nil, nil
    local lastAlwaysIdx, lastLowMPIdx = math.huge, math.huge
    for _, member in ipairs(ai_magic.get_party_members(bot)) do
        if member:getHPP() > 0 and not ai_magic.is_effect_active(member, xi.effect.REFRESH) then
            local job = ai_magic.job_string(member:getMainJob())
            local mpp = member:getMPP()
            if xi.singleplayer.bots.ai_util.table_contains(ai_magic.refreshAlwaysJobs, job) and mpp < 90 then
                local idx = xi.singleplayer.bots.ai_util.index_of(ai_magic.refreshAlwaysJobs, job)
                if idx and idx < lastAlwaysIdx then lastAlwaysIdx = idx; alwaysTarget = member end
            elseif xi.singleplayer.bots.ai_util.table_contains(ai_magic.refreshLowMPJobs, job) and mpp < 40 then
                local idx = xi.singleplayer.bots.ai_util.index_of(ai_magic.refreshLowMPJobs, job)
                if idx and idx < lastLowMPIdx then lastLowMPIdx = idx; lowMPTarget = member end
            end
        end
    end
    return alwaysTarget or lowMPTarget
end

-----------------------------------
-- 86. can_refresh
-----------------------------------
function ai_magic.can_refresh(bot)
    return ai_magic.spell_is_up(bot, xi.magic.spell.REFRESH, false)
        and ai_magic.get_valid_refresh_target(bot) ~= nil
end

-----------------------------------
-- 87. cast_refresh
-----------------------------------
function ai_magic.cast_refresh(bot)
    local target = ai_magic.get_valid_refresh_target(bot)
    if target == nil then return end
    ai_magic.cast_party_spell(bot, xi.magic.spell.REFRESH, target)
end

-----------------------------------
-- 88. hasted
-----------------------------------
function ai_magic.hasted(bot) return ai_magic.is_effect_active(bot, xi.effect.HASTE) end

-----------------------------------
-- 89. get_valid_haste_target
-----------------------------------
function ai_magic.get_valid_haste_target(bot, max_range)
    if not ai_magic.is_effect_active(bot, xi.effect.HASTE) then return bot end
    local meleeTarget, mageTarget = nil, nil
    local lastMeleeIdx, lastMageIdx = math.huge, math.huge
    for _, member in ipairs(ai_magic.get_party_members(bot)) do
        if member:getHPP() > 0 and not ai_magic.is_effect_active(member, xi.effect.HASTE)
           and (max_range == nil or bot:checkDistance(member) <= max_range)
        then
            local job = ai_magic.job_string(member:getMainJob())
            if xi.singleplayer.bots.ai_util.table_contains(ai_magic.tankJobs, job) then
                return member
            elseif xi.singleplayer.bots.ai_util.table_contains(ai_magic.hasteMeleeJobs, job) then
                local idx = xi.singleplayer.bots.ai_util.index_of(ai_magic.hasteMeleeJobs, job)
                if idx and idx < lastMeleeIdx then lastMeleeIdx = idx; meleeTarget = member end
            elseif xi.singleplayer.bots.ai_util.table_contains(ai_magic.hasteCasterJobs, job) then
                local idx = xi.singleplayer.bots.ai_util.index_of(ai_magic.hasteCasterJobs, job)
                if idx and idx < lastMageIdx then lastMageIdx = idx; mageTarget = member end
            end
        end
    end
    return meleeTarget or mageTarget
end

-----------------------------------
-- 90. can_haste
-----------------------------------
function ai_magic.can_haste(bot)
    return ai_magic.spell_is_up(bot, xi.magic.spell.HASTE, false)
        and ai_magic.get_valid_haste_target(bot, ai_magic.spell_range(xi.magic.spell.HASTE)) ~= nil
end

-----------------------------------
-- 91. cast_haste
-----------------------------------
function ai_magic.cast_haste(bot)
    local target = ai_magic.get_valid_haste_target(bot, ai_magic.spell_range(xi.magic.spell.HASTE))
    if target == nil then return end
    ai_magic.cast_party_spell(bot, xi.magic.spell.HASTE, target)
end

-----------------------------------
-- RDM enfeeble list (used by 92-94)
-----------------------------------
local enfeebleSpells = { xi.magic.spell.PARALYZE, xi.magic.spell.SLOW, xi.magic.spell.BLIND }

-----------------------------------
-- 92. get_next_enfeeble
-----------------------------------
function ai_magic.get_next_enfeeble(bot)
    return ai_magic.get_next_spell(bot, enfeebleSpells, true, true)
end

-----------------------------------
-- 93. can_enfeeble
-----------------------------------
function ai_magic.can_enfeeble(bot) return ai_magic.mob_in_cast_range(bot) and ai_magic.get_next_enfeeble(bot) ~= nil end

-----------------------------------
-- 94. enfeeble
-----------------------------------
function ai_magic.enfeeble(bot)
    local spellId = ai_magic.get_next_enfeeble(bot)
    if spellId then ai_magic.cast_spell(bot, spellId) end
end

-----------------------------------
-- Sleep tier lists (used by 95-100)
-- Order: FOE_LULLABY_II (BRD), SLEEP_II, REPOSE (WHM), FOE_LULLABY (BRD), SLEEP
-----------------------------------
local sleepSpells = {
    xi.magic.spell.FOE_LULLABY_II,
    xi.magic.spell.SLEEP_II,
    xi.magic.spell.REPOSE,
    xi.magic.spell.FOE_LULLABY,
    xi.magic.spell.SLEEP,
}
-- AoE sleep cascade. Includes BRD's Horde Lullaby variants (#217 wiring) so
-- a BRD picked from brdSleepPool finds Horde Lullaby first when sleep_add
-- triggers the 3+-awake-adds branch. RDM/BLM continue to find SLEEPGA/II.
local sleepgaSpells = {
    xi.magic.spell.HORDE_LULLABY_II,
    xi.magic.spell.SLEEPGA_II,
    xi.magic.spell.HORDE_LULLABY,
    xi.magic.spell.SLEEPGA,
}

-- Set of every spell that puts mobs to sleep. Used by the in-flight target
-- reservation system (alliance.sleepInFlight): a started sleep cast writes
-- a reservation so the next-tick picker doesn't double-target the same add;
-- the MAGIC_USE / MAGIC_INTERRUPTED listeners clear the reservation by
-- looking up the spell id here.
local SLEEP_SPELL_SET = {}
for _, id in ipairs(sleepSpells)   do SLEEP_SPELL_SET[id] = true end
for _, id in ipairs(sleepgaSpells) do SLEEP_SPELL_SET[id] = true end

function ai_magic.is_sleep_spell(spellId)
    return SLEEP_SPELL_SET[spellId] == true
end

-- Reservation buffer past cast time. Covers engine latency + the 400ms
-- server tick gap before MAGIC_USE / MAGIC_INTERRUPTED listeners fire.
local SLEEP_RESERVATION_BUFFER_MS = 1500

local function reserve_sleep(targetId, spellId)
    if targetId == nil or targetId == 0 then return end
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil then return end
    alliance.sleepInFlight = alliance.sleepInFlight or {}
    local castMs = ai_magic.get_cast_time_in_seconds(spellId) * 1000
    local now    = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    alliance.sleepInFlight[targetId] = now + castMs + SLEEP_RESERVATION_BUFFER_MS
end

function ai_magic.clear_sleep_reservation(targetId)
    if targetId == nil or targetId == 0 then return end
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil or alliance.sleepInFlight == nil then return end
    alliance.sleepInFlight[targetId] = nil
end

-----------------------------------
-- 95. get_next_sleep_spell
-----------------------------------
function ai_magic.get_next_sleep_spell(bot)
    return ai_magic.get_next_spell(bot, sleepSpells, true, false)
end

-----------------------------------
-- 96. get_next_sleepga_spell
-----------------------------------
function ai_magic.get_next_sleepga_spell(bot)
    return ai_magic.get_next_spell(bot, sleepgaSpells, true, false)
end

-----------------------------------
-- 97. get_count_of_awake_adds
-----------------------------------
function ai_magic.get_count_of_awake_adds(bot)
    local primary = bot:isHeadless() and GetPlayerByID(bot:getParentCharId()) or bot
    if primary == nil or primary.getNotorietyList == nil then return 0 end
    local mainId = xi.singleplayer.bots.get_alliance_target_id()
    local count = 0
    for _, mob in ipairs(primary:getNotorietyList() or {}) do
        if mob:getID() ~= mainId
           and not xi.singleplayer.bots.ai_util.is_asleep(mob) then
            count = count + 1
        end
    end
    return count
end

-----------------------------------
-- 98. get_next_sleep_target
-----------------------------------
function ai_magic.get_next_sleep_target(bot)
    -- #196: pick a sleepable add that's in Sleep range of THIS caster, not
    -- the main mob. Adds don't become "the target" — they're add mobs and
    -- the assist is still engaged on the main pull. So range is bot→add,
    -- not bot→alliance.allianceTarget.
    --
    -- The "main mob" excluded is alliance.allianceTarget — the commanded
    -- fight target. In our single-engagement model the assist is always
    -- expected to be swinging on allianceTarget; anything else on the
    -- notoriety list is by definition an add. (When multi-engagement /
    -- per-party mobs land — #173 — this exclusion would need to widen to
    -- "any of the per-party commanded targets".)
    --
    -- alliance.sleepInFlight gates out mobs another sleeper is mid-casting
    -- on, so two sleepers can both pick adds this tick without colliding.
    -- Lazy prune: expired entries get cleared as we walk the notoriety list.
    local primary   = bot:isHeadless() and GetPlayerByID(bot:getParentCharId()) or bot
    if primary == nil or primary.getNotorietyList == nil then return nil end
    local mainMobId = xi.singleplayer.bots.get_alliance_target_id()
    local sleepRange = ai_magic.spell_range(xi.magic.spell.SLEEP)
    local alliance   = xi.singleplayer.bots.alliance
    local inFlight   = (alliance and alliance.sleepInFlight) or {}
    local now        = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    for _, mob in ipairs(primary:getNotorietyList() or {}) do
        local id = mob:getID()
        local reservedUntil = inFlight[id] or 0
        if reservedUntil > 0 and reservedUntil <= now then
            inFlight[id] = nil
            reservedUntil = 0
        end
        if id ~= mainMobId
           and reservedUntil == 0
           and not xi.singleplayer.bots.ai_util.is_asleep(mob)
           and not mob:isDead()
           and bot:checkDistance(mob) <= sleepRange
        then
            return id
        end
    end
    return nil
end

-----------------------------------
-- 99. can_sleep_add — true when this bot is the picked sleeper
--                    (rdmSleepPool first, then blmSleepPool fallback) AND
--                    has both a spell and a target ready. Pool selection
--                    ensures only one bot fires per tick window.
-----------------------------------
function ai_magic.can_sleep_add(bot)
    -- am_i_sleeper's eligibility filter already gates on any_sleep_spell_up
    -- (canUseSpell + recast + MP + silence + hasSpell) AND has_sleep_target_in_range
    -- AND not is_busy_actioning. Picker is the single source of truth — no need
    -- to re-check spell / target availability here.
    return xi.singleplayer.bots.pool ~= nil
       and xi.singleplayer.bots.pool.am_i_sleeper(bot)
end

-----------------------------------
-- 100. sleep_add
-----------------------------------
function ai_magic.sleep_add(bot)
    local awakeCount = ai_magic.get_count_of_awake_adds(bot)
    if awakeCount > 2 and ai_magic.get_next_sleepga_spell(bot) ~= nil then
        local spellId = ai_magic.get_next_sleepga_spell(bot)
        local targetId = ai_magic.get_next_sleep_target(bot)
        if targetId then
            local fired = ai_magic.cast_spell_on(bot, spellId, targetId)
            if fired then reserve_sleep(targetId, spellId) end
            return fired
        end
    end
    local spellId = ai_magic.get_next_sleep_spell(bot)
    local targetId = ai_magic.get_next_sleep_target(bot)
    if spellId and targetId then
        local fired = ai_magic.cast_spell_on(bot, spellId, targetId)
        if fired then reserve_sleep(targetId, spellId) end
        return fired
    end
end

-----------------------------------
-- 101. Silence — RDM enfeeble. Target = alliance main mob (assist_target),
-- like every other offensive predicate in this file.
-----------------------------------
function ai_magic.can_silence(bot)
    if not ai_magic.spell_is_up(bot, xi.magic.spell.SILENCE, true) then return false end
    if not ai_magic.current_mob_in_range(bot, xi.magic.spell.SILENCE) then return false end
    local target = xi.singleplayer.bots.get_current_mob_target()
    return target ~= nil
       and target.hasSpellList and target:hasSpellList()
       and not target:hasImmunity(xi.immunity.SILENCE)
       and not target:hasStatusEffect(xi.effect.SILENCE)
end

function ai_magic.cast_silence(bot)
    return ai_magic.cast_spell(bot, xi.magic.spell.SILENCE)
end

-----------------------------------
-- 102. Dispel family (DISPEL / MAGIC_FINALE) + shared buff counter.
--
-- Both spells target the alliance main mob (assist_target). Consumed by
-- role_rdm's Dispel branch, role_brd's Magic Finale branch, and by
-- role_smn.can_use_lunar_roar for its "target has enough buffs" gate.
--
-- DISPELLABLE_MOB_BUFFS is a curated subset of common mob-side buffs
-- Dispel-family effects strip. Engine has EFFECTFLAG_DISPELABLE which
-- isn't exposed to Lua, so this covers the majority of live cases.
-----------------------------------
local DISPELLABLE_MOB_BUFFS = {
    [xi.effect.HASTE]           = true,
    [xi.effect.ATTACK_BOOST]    = true,
    [xi.effect.DEFENSE_BOOST]   = true,
    [xi.effect.MAGIC_ATK_BOOST] = true,
    [xi.effect.MAGIC_DEF_BOOST] = true,
    [xi.effect.ACCURACY_BOOST]  = true,
    [xi.effect.EVASION_BOOST]   = true,
    [xi.effect.PROTECT]         = true,
    [xi.effect.SHELL]           = true,
    [xi.effect.STONESKIN]       = true,
    [xi.effect.BLINK]           = true,
    [xi.effect.PHALANX]         = true,
    [xi.effect.REGEN]           = true,
    [xi.effect.REFRESH]         = true,
}
ai_magic.DISPELLABLE_MOB_BUFFS = DISPELLABLE_MOB_BUFFS

function ai_magic.dispellable_buff_count(entity)
    if entity == nil or entity.getStatusEffects == nil then return 0 end
    local list = entity:getStatusEffects() or {}
    local n = 0
    for _, eff in ipairs(list) do
        local id = eff.getEffectType and eff:getEffectType() or 0
        if DISPELLABLE_MOB_BUFFS[id] then n = n + 1 end
    end
    return n
end

-- Shared "does the alliance main mob want a dispel-family cast" gate.
local function main_mob_has_dispellable(bot, spellId)
    if not ai_magic.spell_is_up(bot, spellId, true) then return false end
    if not ai_magic.current_mob_in_range(bot, spellId) then return false end
    local target = xi.singleplayer.bots.get_current_mob_target()
    return target ~= nil
       and not target:hasImmunity(xi.immunity.DISPEL)
       and ai_magic.dispellable_buff_count(target) >= 1
end

function ai_magic.can_dispel(bot)       return main_mob_has_dispellable(bot, xi.magic.spell.DISPEL)        end
function ai_magic.cast_dispel(bot)      return ai_magic.cast_spell(bot, xi.magic.spell.DISPEL)             end
function ai_magic.can_magic_finale(bot) return main_mob_has_dispellable(bot, xi.magic.spell.MAGIC_FINALE)  end
function ai_magic.cast_magic_finale(bot) return ai_magic.cast_spell(bot, xi.magic.spell.MAGIC_FINALE)      end

-----------------------------------
-- 103. BRD Elegy / Foe Requiem — enemy debuff songs targeting alliance
-- main mob. Each family has one status slot on the target and its own
-- immunity flag. Tier picker walks highest→lowest, returns the top spell
-- the bot has learned + off recast.
-----------------------------------
local BRD_ELEGY_TIERS = {
    xi.magic.spell.CARNAGE_ELEGY,      -- lvl 65
    xi.magic.spell.BATTLEFIELD_ELEGY,  -- lvl 45
}

local BRD_FOE_REQUIEM_TIERS = {
    xi.magic.spell.FOE_REQUIEM_VIII,   -- lvl 75
    xi.magic.spell.FOE_REQUIEM_VII,    -- lvl 65
    xi.magic.spell.FOE_REQUIEM_VI,     -- lvl 55
    xi.magic.spell.FOE_REQUIEM_V,      -- lvl 45
    xi.magic.spell.FOE_REQUIEM_IV,     -- lvl 35
    xi.magic.spell.FOE_REQUIEM_III,    -- lvl 25
    xi.magic.spell.FOE_REQUIEM_II,     -- lvl 15
    xi.magic.spell.FOE_REQUIEM,        -- lvl 5
}

local function pick_debuff_song_tier(bot, tiers)
    for _, spellId in ipairs(tiers) do
        if ai_magic.spell_is_up(bot, spellId, true) then return spellId end
    end
    return nil
end

-- Shared "main mob missing this song's effect" gate.
local function main_mob_needs_song(bot, spellId, effectId, immunityBit)
    if not ai_magic.current_mob_in_range(bot, spellId) then return false end
    local target = xi.singleplayer.bots.get_current_mob_target()
    return target ~= nil
       and not target:hasImmunity(immunityBit)
       and not target:hasStatusEffect(effectId)
end

function ai_magic.can_use_elegy(bot)
    local spellId = pick_debuff_song_tier(bot, BRD_ELEGY_TIERS)
    if spellId == nil then return false end
    return main_mob_needs_song(bot, spellId, xi.effect.ELEGY, xi.immunity.ELEGY)
end

function ai_magic.cast_elegy(bot)
    local spellId = pick_debuff_song_tier(bot, BRD_ELEGY_TIERS)
    if spellId then ai_magic.cast_spell(bot, spellId) end
end

function ai_magic.can_use_foe_requiem(bot)
    local spellId = pick_debuff_song_tier(bot, BRD_FOE_REQUIEM_TIERS)
    if spellId == nil then return false end
    return main_mob_needs_song(bot, spellId, xi.effect.REQUIEM, xi.immunity.REQUIEM)
end

function ai_magic.cast_foe_requiem(bot)
    local spellId = pick_debuff_song_tier(bot, BRD_FOE_REQUIEM_TIERS)
    if spellId then ai_magic.cast_spell(bot, spellId) end
end

-----------------------------------
-- 103b. Proactive add debuffs — RDM downtime filler. Walks notoriety
-- like get_next_sleep_target does, but instead of picking a sleep
-- target picks a debuff spell to apply to any add missing that effect.
--
-- Priority list is a plain spell-ID array like enfeebleSpells /
-- rdmEnfeebleSpells. Effect lookup goes through the central
-- spellToDebuffEffect map (same one get_next_spell uses). Silence has
-- an add-eligibility gate — silencing a melee-only add is pointless.
--
-- Wired MUCH lower in the RDM tick than main-mob enfeebles: bottom of
-- the elseif chain, above casual_nuke_is_up. A paralyzed / silenced
-- add buys survival, but not at the cost of main work.
-----------------------------------
local addDebuffSpells = {
    xi.magic.spell.SILENCE,
    xi.magic.spell.PARALYZE,
}

local addDebuffImmunity = {
    [xi.magic.spell.SILENCE]  = xi.immunity.SILENCE,
    [xi.magic.spell.PARALYZE] = xi.immunity.PARALYZE,
}

-- Spell-specific mob eligibility gate. Extend when a new debuff needs one.
local function add_debuff_gate(spellId, mob)
    if spellId == xi.magic.spell.SILENCE then
        return mob.hasSpellList and mob:hasSpellList()
    end
    return true
end

local function pick_add_debuff(bot)
    local primary = bot:isHeadless() and GetPlayerByID(bot:getParentCharId()) or bot
    if primary == nil or primary.getNotorietyList == nil then return nil end
    local mainMobId = xi.singleplayer.bots.get_alliance_target_id()
    for _, mob in ipairs(primary:getNotorietyList() or {}) do
        if mob:getID() ~= mainMobId then
            for _, spellId in ipairs(addDebuffSpells) do
                local effectId = spellToDebuffEffect[spellId]
                if effectId ~= nil
                   and not mob:hasImmunity(addDebuffImmunity[spellId])
                   and not mob:hasStatusEffect(effectId)
                   and add_debuff_gate(spellId, mob)
                   and ai_magic.spell_is_up(bot, spellId, true)
                   and bot:checkDistance(mob) <= ai_magic.spell_range(spellId)
                then
                    return { spellId = spellId, targetId = mob:getID() }
                end
            end
        end
    end
    return nil
end

function ai_magic.can_enfeeble_add(bot)
    return pick_add_debuff(bot) ~= nil
end

function ai_magic.cast_enfeeble_add(bot)
    local pick = pick_add_debuff(bot)
    if pick then ai_magic.cast_spell_on(bot, pick.spellId, pick.targetId) end
end

-----------------------------------
-- 103d. Skillchain analysis — shared MB config machinery.
--
-- Constants transcribed from src/map/entities/battleentity.h:248.
-- SKILLCHAIN_MAP is engine's FormSkillchain table
-- (src/map/utils/battleutils.cpp:3281). SC_MB_ELEMS maps each SC family
-- to the MB-boosted xi.element list. Used by role_smn (avatar selection,
-- MB rage feasibility) and role_brd (Threnody element pick).
--
-- pair_mb_elements: config-static analysis of an SC pair (WS lookup →
-- SC family → MB elements). No runtime SC effect needed.
-- detect_pending_mb: runtime — reads target's SKILLCHAIN effect at
-- tier=0 (opener landed, closer coming), matches against configured
-- pair openers, returns union of possible MB elements.
-----------------------------------
local SC_TRANSFIXION   = 1   -- Lv1 Light
local SC_COMPRESSION   = 2   -- Lv1 Dark
local SC_LIQUEFACTION  = 3   -- Lv1 Fire
local SC_SCISSION      = 4   -- Lv1 Earth
local SC_REVERBERATION = 5   -- Lv1 Water
local SC_DETONATION    = 6   -- Lv1 Wind
local SC_INDURATION    = 7   -- Lv1 Ice
local SC_IMPACTION     = 8   -- Lv1 Thunder
local SC_GRAVITATION   = 9   -- Lv2 Earth-family
local SC_DISTORTION    = 10  -- Lv2 Water/Ice-family
local SC_FUSION        = 11  -- Lv2 Fire-family
local SC_FRAGMENTATION = 12  -- Lv2 Wind/Thunder-family
local SC_LIGHT         = 13  -- Lv3 Light
local SC_DARKNESS      = 14  -- Lv3 Darkness
local SC_LIGHT_II      = 15  -- Lv4 Light
local SC_DARKNESS_II   = 16  -- Lv4 Darkness

local SC_MB_ELEMS = {
    [SC_TRANSFIXION]   = { xi.element.LIGHT },
    [SC_COMPRESSION]   = { xi.element.DARK },
    [SC_LIQUEFACTION]  = { xi.element.FIRE },
    [SC_SCISSION]      = { xi.element.EARTH },
    [SC_REVERBERATION] = { xi.element.WATER },
    [SC_DETONATION]    = { xi.element.WIND },
    [SC_INDURATION]    = { xi.element.ICE },
    [SC_IMPACTION]     = { xi.element.THUNDER },
    [SC_GRAVITATION]   = { xi.element.EARTH },
    [SC_DISTORTION]    = { xi.element.WATER, xi.element.ICE },
    [SC_FUSION]        = { xi.element.FIRE },
    [SC_FRAGMENTATION] = { xi.element.WIND, xi.element.THUNDER },
    [SC_LIGHT]         = { xi.element.FIRE, xi.element.WIND, xi.element.THUNDER, xi.element.LIGHT },
    [SC_DARKNESS]      = { xi.element.EARTH, xi.element.WATER, xi.element.ICE, xi.element.DARK },
    [SC_LIGHT_II]      = { xi.element.FIRE, xi.element.WIND, xi.element.THUNDER, xi.element.LIGHT },
    [SC_DARKNESS_II]   = { xi.element.EARTH, xi.element.WATER, xi.element.ICE, xi.element.DARK },
}

local SKILLCHAIN_MAP = {
    -- Level 3 Pairs
    [SC_LIGHT    .. ',' .. SC_LIGHT   ] = SC_LIGHT_II,
    [SC_DARKNESS .. ',' .. SC_DARKNESS] = SC_DARKNESS_II,
    -- Level 2 Pairs
    [SC_DISTORTION    .. ',' .. SC_GRAVITATION  ] = SC_DARKNESS,
    [SC_FRAGMENTATION .. ',' .. SC_GRAVITATION  ] = SC_FRAGMENTATION,
    [SC_GRAVITATION   .. ',' .. SC_DISTORTION   ] = SC_DARKNESS,
    [SC_FUSION        .. ',' .. SC_DISTORTION   ] = SC_FUSION,
    [SC_GRAVITATION   .. ',' .. SC_FUSION       ] = SC_GRAVITATION,
    [SC_FRAGMENTATION .. ',' .. SC_FUSION       ] = SC_LIGHT,
    [SC_DISTORTION    .. ',' .. SC_FRAGMENTATION] = SC_DISTORTION,
    [SC_FUSION        .. ',' .. SC_FRAGMENTATION] = SC_LIGHT,
    -- Level 1 Pairs > Level 2 Skillchain
    [SC_SCISSION      .. ',' .. SC_TRANSFIXION  ] = SC_DISTORTION,
    [SC_IMPACTION     .. ',' .. SC_LIQUEFACTION ] = SC_FUSION,
    [SC_COMPRESSION   .. ',' .. SC_DETONATION   ] = SC_GRAVITATION,
    [SC_REVERBERATION .. ',' .. SC_INDURATION   ] = SC_FRAGMENTATION,
    -- Level 1 Pairs
    [SC_COMPRESSION   .. ',' .. SC_TRANSFIXION  ] = SC_COMPRESSION,
    [SC_REVERBERATION .. ',' .. SC_TRANSFIXION  ] = SC_REVERBERATION,
    [SC_TRANSFIXION   .. ',' .. SC_COMPRESSION  ] = SC_TRANSFIXION,
    [SC_DETONATION    .. ',' .. SC_COMPRESSION  ] = SC_DETONATION,
    [SC_SCISSION      .. ',' .. SC_LIQUEFACTION ] = SC_SCISSION,
    [SC_LIQUEFACTION  .. ',' .. SC_SCISSION     ] = SC_LIQUEFACTION,
    [SC_REVERBERATION .. ',' .. SC_SCISSION     ] = SC_REVERBERATION,
    [SC_DETONATION    .. ',' .. SC_SCISSION     ] = SC_DETONATION,
    [SC_INDURATION    .. ',' .. SC_REVERBERATION] = SC_INDURATION,
    [SC_IMPACTION     .. ',' .. SC_REVERBERATION] = SC_IMPACTION,
    [SC_SCISSION      .. ',' .. SC_DETONATION   ] = SC_SCISSION,
    [SC_COMPRESSION   .. ',' .. SC_INDURATION   ] = SC_COMPRESSION,
    [SC_IMPACTION     .. ',' .. SC_INDURATION   ] = SC_IMPACTION,
    [SC_LIQUEFACTION  .. ',' .. SC_IMPACTION    ] = SC_LIQUEFACTION,
    [SC_DETONATION    .. ',' .. SC_IMPACTION    ] = SC_DETONATION,
}

local function compute_sc_element(openerProps, closerProps)
    if openerProps == nil or closerProps == nil then return 0 end
    local closer = { closerProps.primary or 0, closerProps.secondary or 0, closerProps.tertiary or 0 }
    local opener = { openerProps.primary or 0, openerProps.secondary or 0, openerProps.tertiary or 0 }
    for _, c in ipairs(closer) do
        if c ~= 0 then
            for _, o in ipairs(opener) do
                if o ~= 0 then
                    local res = SKILLCHAIN_MAP[c .. ',' .. o]
                    if res ~= nil then return res end
                end
            end
        end
    end
    return 0
end

function ai_magic.pair_mb_elements(pair)
    if pair == nil then return nil end
    local resolve = xi.singleplayer.bots.ability.resolve_ws_id
    if resolve == nil or GetWeaponskillProperties == nil then return nil end
    local openerWsId = resolve(pair.openWS)
    local closerWsId = resolve(pair.closeWS)
    if openerWsId == 0 or closerWsId == 0 then return nil end
    local openerProps = GetWeaponskillProperties(openerWsId)
    local closerProps = GetWeaponskillProperties(closerWsId)
    if openerProps == nil or closerProps == nil then return nil end
    local scElem = compute_sc_element(openerProps, closerProps)
    if scElem == 0 then return nil end
    return SC_MB_ELEMS[scElem]
end

function ai_magic.detect_pending_mb(bot)
    local target = xi.singleplayer.bots.ai_util.assist_target(bot)
    if target == nil or target.getStatusEffect == nil then return nil end
    local sc = target:getStatusEffect(xi.effect.SKILLCHAIN)
    if sc == nil or sc.getTier == nil or sc:getTier() ~= 0 then return nil end

    local power = sc.getPower and sc:getPower() or 0
    local openerProps = {
        primary   = bit.band(power, 0xF),
        secondary = bit.band(bit.rshift(power, 4), 0xF),
        tertiary  = bit.band(bit.rshift(power, 8), 0xF),
    }

    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil or alliance.sc == nil then return nil end

    local resolve = xi.singleplayer.bots.ability.resolve_ws_id
    local elementSet = {}
    for _, pair in ipairs(alliance.sc) do
        local openerWsId = resolve and resolve(pair.openWS) or 0
        if openerWsId ~= 0 and GetWeaponskillProperties ~= nil then
            local candidate = GetWeaponskillProperties(openerWsId)
            if candidate ~= nil
               and candidate.primary   == openerProps.primary
               and candidate.secondary == openerProps.secondary
               and candidate.tertiary  == openerProps.tertiary then
                for _, mbElem in ipairs(ai_magic.pair_mb_elements(pair) or {}) do
                    elementSet[mbElem] = true
                end
            end
        end
    end

    if next(elementSet) == nil then return nil end
    local list = {}
    for elem in pairs(elementSet) do table.insert(list, elem) end
    return list
end

-----------------------------------
-- 103e. Threnody — BRD elemental defense-down debuff on target,
-- picked to weaken the imminent MB. Trigger: pending SC (opener landed,
-- tier=0). 2s cast + song fits within the 3-8s closer window.
--
-- Element pick:
--   1. detect_pending_mb yields candidate MB elements from the matched
--      opener's SC pair(s).
--   2. Filter: BLM at bot:getMainLvl() must be able to cast the strongest
--      single-target nuke for that element (level lookup via
--      GetSpell:getLevel(xi.job.BLM) — no hardcoded levels).
--   3. Tiebreak: static "strongest element" order Earth < Water < Wind
--      < Fire < Ice < Lightning; last valid wins.
--
-- Overwrite policy: skip only when the exact same-element Threnody is
-- already up (compare THRENODY effect's subPower to the element's MDEF
-- mod ID — the effect script sets subPower to the mod ID at cast). A
-- different element's Threnody is safe to overwrite.
--
-- Light/Dark absent — no standard single-target MB nuke for BLM.
-----------------------------------
local BLM_SINGLE_TARGET_MB_NUKE = {
    [xi.element.FIRE]    = xi.magic.spell.FIRE_IV,
    [xi.element.ICE]     = xi.magic.spell.BLIZZARD_IV,
    [xi.element.WIND]    = xi.magic.spell.AERO_IV,
    [xi.element.EARTH]   = xi.magic.spell.STONE_IV,
    [xi.element.THUNDER] = xi.magic.spell.THUNDER_IV,
    [xi.element.WATER]   = xi.magic.spell.WATER_IV,
}

local ELEMENT_TO_THRENODY_SPELL = {
    [xi.element.FIRE]    = xi.magic.spell.FIRE_THRENODY,
    [xi.element.ICE]     = xi.magic.spell.ICE_THRENODY,
    [xi.element.WIND]    = xi.magic.spell.WIND_THRENODY,
    [xi.element.EARTH]   = xi.magic.spell.EARTH_THRENODY,
    [xi.element.THUNDER] = xi.magic.spell.LIGHTNING_THRENODY,
    [xi.element.WATER]   = xi.magic.spell.WATER_THRENODY,
}

-- Weakest → strongest; iterate forward and keep last valid to pick winner.
local ELEMENT_STRENGTH_ORDER = {
    xi.element.EARTH,
    xi.element.WATER,
    xi.element.WIND,
    xi.element.FIRE,
    xi.element.ICE,
    xi.element.THUNDER,
}

-- Mod IDs the Threnody effect writes into subPower for the "same
-- element already up?" check. Naming from xi.mod (LTNG for Lightning).
local ELEMENT_TO_MDEF_MOD = {
    [xi.element.FIRE]    = xi.mod.FIRE_MDEF,
    [xi.element.ICE]     = xi.mod.ICE_MDEF,
    [xi.element.WIND]    = xi.mod.WIND_MDEF,
    [xi.element.EARTH]   = xi.mod.EARTH_MDEF,
    [xi.element.THUNDER] = xi.mod.LTNG_MDEF,
    [xi.element.WATER]   = xi.mod.WATER_MDEF,
}

local function pick_threnody_element(bot)
    local pending = ai_magic.detect_pending_mb(bot)
    if pending == nil then return nil end

    local botLevel = bot:getMainLvl()
    local candidates = {}
    for _, element in ipairs(pending) do
        local nukeId = BLM_SINGLE_TARGET_MB_NUKE[element]
        if nukeId and GetSpell then
            local spell = GetSpell(nukeId)
            if spell and spell:getLevel(xi.job.BLM) <= botLevel then
                candidates[element] = true
            end
        end
    end
    if next(candidates) == nil then return nil end

    local picked = nil
    for _, element in ipairs(ELEMENT_STRENGTH_ORDER) do
        if candidates[element] then picked = element end
    end
    return picked
end

function ai_magic.can_use_threnody(bot)
    local element = pick_threnody_element(bot)
    if element == nil then return false end
    local spellId = ELEMENT_TO_THRENODY_SPELL[element]
    if not ai_magic.spell_is_up(bot, spellId, true) then return false end
    if not ai_magic.current_mob_in_range(bot, spellId) then return false end

    -- Same-element Threnody already up? Skip. Different element = overwrite ok.
    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return false end
    if target.hasStatusEffect and target:hasStatusEffect(xi.effect.THRENODY) then
        local effect = target:getStatusEffect(xi.effect.THRENODY)
        if effect and effect.getSubPower
           and effect:getSubPower() == ELEMENT_TO_MDEF_MOD[element] then
            return false
        end
    end
    return true
end

function ai_magic.cast_threnody(bot)
    local element = pick_threnody_element(bot)
    if element == nil then return end
    ai_magic.cast_spell(bot, ELEMENT_TO_THRENODY_SPELL[element])
end

-----------------------------------
-- 104. get_next_spell  (generic priority-list picker)
-----------------------------------
function ai_magic.get_next_spell(bot, spellTbl, isOffensive, checkStatus)
    for _, spellId in ipairs(spellTbl) do
        local blocked = false
        if checkStatus then
            local effectId = spellToDebuffEffect[spellId]
            -- If the spell isn't in the debuff map we don't know what to gate
            -- on, so let it through rather than always-block or always-allow.
            if effectId ~= nil then
                blocked = ai_magic.target_has_status(bot, effectId)
            end
        end
        if not blocked and ai_magic.spell_is_up(bot, spellId, isOffensive) then
            return spellId
        end
    end
    return nil
end

-----------------------------------
-- BLM nuke families
-----------------------------------
local thunderNukes  = { xi.magic.spell.THUNDER_V,  xi.magic.spell.THUNDER_IV,  xi.magic.spell.THUNDER_III,  xi.magic.spell.THUNDER_II,  xi.magic.spell.THUNDER }
local blizzardNukes = { xi.magic.spell.BLIZZARD_V, xi.magic.spell.BLIZZARD_IV, xi.magic.spell.BLIZZARD_III, xi.magic.spell.BLIZZARD_II, xi.magic.spell.BLIZZARD }
local fireNukes     = { xi.magic.spell.FIRE_V,     xi.magic.spell.FIRE_IV,     xi.magic.spell.FIRE_III,     xi.magic.spell.FIRE_II,     xi.magic.spell.FIRE }
local aeroNukes     = { xi.magic.spell.AERO_V,     xi.magic.spell.AERO_IV,     xi.magic.spell.AERO_III,     xi.magic.spell.AERO_II,     xi.magic.spell.AERO }
local waterNukes    = { xi.magic.spell.WATER_V,    xi.magic.spell.WATER_IV,    xi.magic.spell.WATER_III,    xi.magic.spell.WATER_II,    xi.magic.spell.WATER }
local stoneNukes    = { xi.magic.spell.STONE_V,    xi.magic.spell.STONE_IV,    xi.magic.spell.STONE_III,    xi.magic.spell.STONE_II,    xi.magic.spell.STONE }

local SC_MB_ELEMENTS = {
    [1]  = { 'Fire', 'Thunder', 'Aero' },                -- Light
    [2]  = { 'Blizzard', 'Stone', 'Water' },             -- Darkness
    [3]  = { 'Stone' },                                  -- Gravitation
    [4]  = { 'Thunder', 'Aero' },                        -- Fragmentation
    [5]  = { 'Blizzard', 'Water' },                      -- Distortion
    [6]  = { 'Fire' },                                   -- Fusion
    [8]  = { 'Fire' },                                   -- Liquefaction
    [9]  = { 'Blizzard' },                               -- Induration
    [10] = { 'Water' },                                  -- Reverberation
    [12] = { 'Stone' },                                  -- Scission
    [13] = { 'Aero' },                                   -- Detonation
    [14] = { 'Thunder' },                                -- Impaction
    [15] = { 'Fire', 'Thunder', 'Aero' },                -- Radiance
    [16] = { 'Blizzard', 'Stone', 'Water' },             -- Umbra
}

local familyNukes = {
    Fire = fireNukes, Blizzard = blizzardNukes, Thunder = thunderNukes,
    Aero = aeroNukes, Water = waterNukes, Stone = stoneNukes,
}

-- Expose the SC-element lookup for role_smn (Rage BP MB awareness).
-- Returns the element family list { 'Fire', 'Thunder', ... } for the
-- bot's active SC, or nil if no SC is up.
function ai_magic.sc_mb_elements_for(bot)
    local scType = xi.singleplayer.bots.ability.active_sc_type(bot)
    return SC_MB_ELEMENTS[scType]
end

-----------------------------------
-- 105. get_mb_spell_for_sc
-----------------------------------
function ai_magic.get_mb_spell_for_sc(bot)
    local elements = SC_MB_ELEMENTS[xi.singleplayer.bots.ability.active_sc_type(bot)]
    if not elements or #elements == 0 then return nil end
    -- Cast-time gate: if the strongest tier can't finish before the MB
    -- window closes, fall through to weaker tiers (Fire III too slow → try
    -- Fire II → Fire). familyNukes is ordered strongest-first inside each
    -- family list; outer loop walks tier index, inner walks elements so
    -- ties are broken consistently across nuke families.
    local mbCloseMs = xi.singleplayer.bots.ability.mb_window_close_ms(bot)
    local now       = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    local budgetMs  = (mbCloseMs > 0) and (mbCloseMs - now) or math.huge

    local maxLen = 0
    for _, family in ipairs(elements) do
        local tbl = familyNukes[family]
        if tbl and #tbl > maxLen then maxLen = #tbl end
    end
    for i = 1, maxLen do
        for _, family in ipairs(elements) do
            local tbl     = familyNukes[family]
            local spellId = tbl and tbl[i]
            if spellId and ai_magic.spell_is_up(bot, spellId, true) then
                local castMs = ai_magic.get_cast_time_in_seconds(spellId) * 1000
                if castMs <= budgetMs then return spellId end
            end
        end
    end
    return nil
end

-----------------------------------
-- 106. can_mb
-----------------------------------
function ai_magic.can_mb(bot)
    local mbCloseMs = xi.singleplayer.bots.ability.mb_window_close_ms(bot)
    if mbCloseMs == 0 then return false end
    if not ai_magic.mob_in_cast_range(bot) then return false end
    local now = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    if now > mbCloseMs then return false end
    local spellId = ai_magic.get_mb_spell_for_sc(bot)
    if spellId == nil then return false end
    return now + (ai_magic.get_cast_time_in_seconds(spellId) * 1000) <= mbCloseMs
end

-----------------------------------
-- 107. cast_mb
-----------------------------------
function ai_magic.cast_mb(bot)
    local spellId = ai_magic.get_mb_spell_for_sc(bot)
    if spellId then ai_magic.cast_spell(bot, spellId) end
end

-----------------------------------
-- BLM enfeeble list
-----------------------------------
local blmEnfeebleSpells = { xi.magic.spell.POISON_II, xi.magic.spell.POISON, xi.magic.spell.CHOKE }

-----------------------------------
-- 108. get_next_blm_enfeeble
-----------------------------------
function ai_magic.get_next_blm_enfeeble(bot)
    return ai_magic.get_next_spell(bot, blmEnfeebleSpells, true, true)
end

-----------------------------------
-- 109. can_blm_enfeeble
-----------------------------------
function ai_magic.can_blm_enfeeble(bot) return ai_magic.mob_in_cast_range(bot) and ai_magic.get_next_blm_enfeeble(bot) ~= nil end

-----------------------------------
-- 110. blm_enfeeble
-----------------------------------
function ai_magic.blm_enfeeble(bot)
    local spellId = ai_magic.get_next_blm_enfeeble(bot)
    if spellId then ai_magic.cast_spell(bot, spellId) end
end

-----------------------------------
-- 111. get_next_leech
-----------------------------------
function ai_magic.get_next_leech(bot)
    local lowHP = bot:getHPP() < 100
    local lowMP = bot:getMPP() < 80
    if lowHP then
        if ai_magic.spell_is_up(bot, xi.magic.spell.DRAIN_II, true) then return xi.magic.spell.DRAIN_II end
        if ai_magic.spell_is_up(bot, xi.magic.spell.DRAIN,    true) then return xi.magic.spell.DRAIN    end
    elseif lowMP then
        if ai_magic.spell_is_up(bot, xi.magic.spell.ASPIR_II, true) then return xi.magic.spell.ASPIR_II end
        if ai_magic.spell_is_up(bot, xi.magic.spell.ASPIR,    true) then return xi.magic.spell.ASPIR    end
    end
    return nil
end

-----------------------------------
-- 112. can_leech
-----------------------------------
function ai_magic.can_leech(bot) return ai_magic.mob_in_cast_range(bot) and ai_magic.get_next_leech(bot) ~= nil end

-----------------------------------
-- 113. cast_leech
-----------------------------------
function ai_magic.cast_leech(bot)
    local spellId = ai_magic.get_next_leech(bot)
    if spellId then ai_magic.cast_spell(bot, spellId) end
end

-----------------------------------
-- BLM casual nuke list (V→I interleaved across all six elements)
-----------------------------------
local casualNukes = {
    xi.magic.spell.THUNDER_V, xi.magic.spell.BLIZZARD_V, xi.magic.spell.FIRE_V,
    xi.magic.spell.AERO_V,    xi.magic.spell.WATER_V,    xi.magic.spell.STONE_V,
    xi.magic.spell.THUNDER_IV, xi.magic.spell.BLIZZARD_IV, xi.magic.spell.FIRE_IV,
    xi.magic.spell.AERO_IV,    xi.magic.spell.WATER_IV,    xi.magic.spell.STONE_IV,
    xi.magic.spell.THUNDER_III, xi.magic.spell.BLIZZARD_III, xi.magic.spell.FIRE_III,
    xi.magic.spell.AERO_III,    xi.magic.spell.WATER_III,    xi.magic.spell.STONE_III,
    xi.magic.spell.THUNDER_II, xi.magic.spell.BLIZZARD_II, xi.magic.spell.FIRE_II,
    xi.magic.spell.AERO_II,    xi.magic.spell.WATER_II,    xi.magic.spell.STONE_II,
    xi.magic.spell.THUNDER, xi.magic.spell.BLIZZARD, xi.magic.spell.FIRE,
    xi.magic.spell.AERO,    xi.magic.spell.WATER,    xi.magic.spell.STONE,
}

-- spellId -> nuke family, built by inverting familyNukes so casual nukes can
-- be matched against the alliance's MB-reserved families. Covers all 5 tiers.
local casualNukeFamily = {}
for family, spells in pairs(familyNukes) do
    for _, sid in ipairs(spells) do casualNukeFamily[sid] = family end
end

-- xi.element enum -> nuke family. pair_mb_elements returns element ids; the
-- nuke tables use family-name strings. Light/Dark have no casual nuke family.
local ELEMENT_TO_NUKE_FAMILY = {
    [xi.element.FIRE]    = 'Fire',
    [xi.element.ICE]     = 'Blizzard',
    [xi.element.WIND]    = 'Aero',
    [xi.element.EARTH]   = 'Stone',
    [xi.element.THUNDER] = 'Thunder',
    [xi.element.WATER]   = 'Water',
}

-- Nuke families the alliance reserves for magic-bursting its configured SCs,
-- derived from the config SC pairs. Only consulted in 'exclude' mode; returns
-- {} when there are no SC pairs, so exclude becomes a no-op.
local function alliance_mb_families()
    local out = {}
    for _, pair in ipairs(xi.singleplayer.bots.ability.sc_pairs() or {}) do
        local elems = ai_magic.pair_mb_elements(pair)
        if type(elems) == 'table' then
            for _, e in ipairs(elems) do
                local fam = ELEMENT_TO_NUKE_FAMILY[e]
                if fam then out[fam] = true end
            end
        end
    end
    return out
end

-- Count of casual nukes currently castable (honoring the exclude filter).
-- Sizes the 'All' rotation so it cycles through everything without starving.
local function count_castable_casual(bot, mbFams)
    local n = 0
    for _, spellId in ipairs(casualNukes) do
        if ai_magic.spell_is_up(bot, spellId, true)
           and not (mbFams and mbFams[casualNukeFamily[spellId]]) then
            n = n + 1
        end
    end
    return n
end

-----------------------------------
-- 114. get_next_casual_nuke
-----------------------------------
function ai_magic.get_next_casual_nuke(bot)
    local state = getState(bot)
    -- Exclude mode: skip spells whose element the alliance reserves for MBs.
    local mbFams = (state.casualNukeMbMode == 'exclude') and alliance_mb_families() or nil
    for _, spellId in ipairs(casualNukes) do
        if ai_magic.spell_is_up(bot, spellId, true)
           and not xi.singleplayer.bots.ai_util.table_contains(state.nukeHistory, spellId)
           and not (mbFams and mbFams[casualNukeFamily[spellId]]) then
            return spellId
        end
    end
    return nil
end

-----------------------------------
-- 115. casual_nuke_is_up
-----------------------------------
function ai_magic.casual_nuke_is_up(bot)
    if not ai_magic.mob_in_cast_range(bot) then return false end
    local state = getState(bot)
    local delay = state.casualNukingDelay * 1000 * state.casualNukeDelayMultiple
    if xi.singleplayer.bots.ai_util.get_ms_since_epoch() < (state.lastCasualNukeEnd or 0) + delay then return false end
    state.casualNukeDelayMultiple = 1
    if not ai_magic.sc_is_close(bot) then return ai_magic.get_next_casual_nuke(bot) ~= nil end
    local target = xi.singleplayer.bots.get_current_mob_target()
    local targetHPP = target and target:getHPP() or 100
    if ai_magic.sc_is_close(bot) and (targetHPP == nil or targetHPP > 20) then return false end
    return ai_magic.get_next_casual_nuke(bot) ~= nil
end

-----------------------------------
-- 116. can_rotate_nukes
-----------------------------------
function ai_magic.can_rotate_nukes(bot)
    local mainJob = ai_magic.job_string(bot:getMainJob())
    local subJob  = ai_magic.job_string(bot:getSubJob())
    return mainJob == 'BLM' or mainJob == 'RDM' or subJob == 'BLM' or subJob == 'RDM'
end

-----------------------------------
-- 117. cast_casual_nuke
-----------------------------------
function ai_magic.cast_casual_nuke(bot)
    local spellId = ai_magic.get_next_casual_nuke(bot)
    if spellId == nil then return end
    ai_magic.cast_spell(bot, spellId)
    local state = getState(bot)
    -- Stamp our own "last casual nuke" timestamp so the next-nuke gate fires
    -- ~casualNukingDelay after the LAST NUKE — not after every Dia/Bio/Choke
    -- that also touches lastCastEnd. Original Ashita conflated the two, which
    -- meant casting an enfeeble silenced nukes for 7s. We keep lastCastEnd as
    -- the throttle for other rate-limited paths (hate-melt, etc.) and use a
    -- dedicated field for the casual-nuke cadence.
    state.lastCasualNukeEnd = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    if ai_magic.can_rotate_nukes(bot) then
        -- Rotation of N blocks the last N-1 distinct spells (N=3 default → the
        -- classic 3-spell cycle). 0 = 'All': block all-but-one CASTABLE spell
        -- so it cycles through everything available, sized live so it never
        -- empties the pool into silence.
        local rot  = state.casualNukeRotation or 3
        local keep
        if rot <= 0 then
            local mbFams = (state.casualNukeMbMode == 'exclude') and alliance_mb_families() or nil
            keep = math.max(0, count_castable_casual(bot, mbFams) - 1)
        else
            keep = math.max(0, rot - 1)
        end
        table.insert(state.nukeHistory, spellId)
        while #state.nukeHistory > keep do table.remove(state.nukeHistory, 1) end
    end
end

-- ============================================================
-- Per-bot casual-nuke config setters (0x176 SET_CASUAL_NUKE_*).
-- ============================================================

-- Apply `fn(state, member)` to the owned bot named `botName` (primary itself,
-- or a headless whose parentCharId == primary). Returns true if applied.
local function apply_to_owned_bot(primary, botName, fn)
    if primary == nil or botName == nil or botName == '' then return false end
    local target    = botName:lower()
    local primaryId = primary:getID()
    for _, member in ipairs(primary:getAlliance() or {}) do
        local owned = (member == primary)
            or (member.isHeadless and member:isHeadless()
                and member.getParentCharId and member:getParentCharId() == primaryId)
        if owned and member:getName():lower() == target then
            fn(xi.singleplayer.bots.ensure_bot(member:getID()), member)
            return true
        end
    end
    return false
end

-- Casual-nuke rotation size. value 1..6 = that many spells; 0 = 'All'.
function ai_magic.set_bot_casual_nuke_rotation(primary, botName, value)
    local v = tonumber(value) or 3
    if v < 0 then v = 0 end
    if v > 6 then v = 6 end
    local ok = apply_to_owned_bot(primary, botName, function(s, m)
        s.casualNukeRotation = v
        printf(string.format('ai_magic.set_bot_casual_nuke_rotation: %s -> %s',
            m:getName(), (v == 0) and 'All' or tostring(v)))
    end)
    if not ok then
        printf(string.format('ai_magic.set_bot_casual_nuke_rotation: no owned bot "%s"', tostring(botName)))
    end
end

-- Casual-nuke MB-spell mode. mode byte: 0 = exclude, 1 = include.
function ai_magic.set_bot_casual_nuke_mb_mode(primary, botName, mode)
    local newMode = (tonumber(mode) == 0) and 'exclude' or 'include'
    local ok = apply_to_owned_bot(primary, botName, function(s, m)
        s.casualNukeMbMode = newMode
        printf(string.format('ai_magic.set_bot_casual_nuke_mb_mode: %s -> %s',
            m:getName(), newMode))
    end)
    if not ok then
        printf(string.format('ai_magic.set_bot_casual_nuke_mb_mode: no owned bot "%s"', tostring(botName)))
    end
end

-----------------------------------
-- 118. get_blm_cure_tier
-----------------------------------
function ai_magic.get_blm_cure_tier(bot)
    -- PARTY-scope: BLM emergency-cure is a last resort for the BLM's own
    -- party. Alliance scope would have the BLM panic-cure off-party members
    -- another party's WHM should be handling.
    local lowestHpp, under30 = 100, 0
    for _, member in ipairs(ai_magic.get_party_members(bot)) do
        local hpp = member:getHPP()
        if hpp > 0 then
            if hpp < lowestHpp then lowestHpp = hpp end
            if hpp < 30 then under30 = under30 + 1 end
        end
    end
    if under30 > 3 then return 'Curaga' end
    if lowestHpp < 30 then return 'Cure_P1' end
    return 'None'
end

-----------------------------------
-- 119. rdm_sleep_cooldown
--   Returns TRUE only when the party's RDM has no single-target sleep
--   available — i.e. BOTH Sleep and Sleep II are on recast. In that case
--   role_nuke's cascade lets the BLM step in ("can_sleep_add with rdm").
--   RDM has the more potent enfeebling skill, so if either tier is up we
--   prefer to let the RDM handle it; if the RDM is mid-cast on something
--   else, we still wait for them to finish rather than burning the BLM's
--   slot. No RDM in party → false (the no_rdm branch above covers that).
-----------------------------------
function ai_magic.rdm_sleep_cooldown(_)
    -- Walk alliance.rdmSleepPool — every RDM with sleep capability gets
    -- a chance to cover. Return true (BLM steps in) ONLY if EVERY RDM in
    -- the pool has both Sleep AND Sleep II on recast. Fixes a multi-RDM
    -- bug where the first RDM having Sleep on recast would let BLM steal
    -- the slot even when RDM #2 was free.
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil or alliance.rdmSleepPool == nil then return false end
    if #alliance.rdmSleepPool == 0 then return false end
    for _, id in ipairs(alliance.rdmSleepPool) do
        local rdm = GetPlayerByID(id)
        if rdm ~= nil
           and not rdm:hasRecast(xi.recast.MAGIC, xi.magic.spell.SLEEP)
        then
            return false  -- this RDM can fire Sleep right now
        end
        if rdm ~= nil
           and not rdm:hasRecast(xi.recast.MAGIC, xi.magic.spell.SLEEP_II)
        then
            return false  -- this RDM can fire Sleep II right now
        end
    end
    return true  -- every RDM has both sleeps on recast
end

-----------------------------------
-- 121. can_stun — true when this bot is the picked stunner (MP%-sorted
--                pool of BLM/RDM/DRK with Stun up).
-----------------------------------
function ai_magic.can_stun(bot)
    return xi.singleplayer.bots.pool and xi.singleplayer.bots.pool.am_i_stunner(bot)
end

-----------------------------------
-- 122. stun
-----------------------------------
function ai_magic.stun(bot)
    if ai_magic.can_stun(bot) then ai_magic.cast_spell(bot, xi.magic.spell.STUN) end
end

-----------------------------------
-- 123. get_heal_target_index
-----------------------------------
function ai_magic.get_heal_target_index(bot)
    -- ALLIANCE-scope: with a single shared mob and one main tank, PLD's
    -- cure-enmity stacks on the same mob the PLD already tanks, so alliance
    -- scope is a free backup-heal with no cross-party hate steal. If/when
    -- multi-engagement (per-party mobs) lands, switch this and the two
    -- consumers (get_pld_cure_tier, cast_pld_healing_spell) to party-scope
    -- behind a flag — the cure-enmity then WOULD pull hate from other tanks.
    local myHPP = bot:getHPP()
    local mageIndex, meleeIndex = 0, 0
    local members = ai_magic.get_alliance_members(bot)
    local cureRange = ai_magic.DEFAULT_SPELL_RANGE
    for x, member in ipairs(members) do
        if member ~= bot then
            local hpp = member:getHPP()
            local job = ai_magic.job_string(member:getMainJob())
            local name = member:getName()
            local inRange = bot:checkDistance(member) <= cureRange
            if inRange and name and name ~= '' and hpp > 0 and hpp < 80 and xi.singleplayer.bots.ai_util.table_contains(ai_magic.mageJobs, job) then
                mageIndex = x
            elseif inRange and name and name ~= '' and hpp > 0 and hpp < 60 then
                meleeIndex = x
            end
        end
    end
    if myHPP < 40 then return 0 end
    if mageIndex > 0 then return mageIndex end
    if meleeIndex > 0 then return meleeIndex end
    if myHPP < 80 then return 0 end
    return -1
end

-----------------------------------
-- 124. get_pld_cure_tier
-----------------------------------
function ai_magic.get_pld_cure_tier(bot)
    -- ALLIANCE-scope: see get_heal_target_index — single shared mob means
    -- PLD cure-enmity stacks on own tank target; backup-heal alliance is free.
    local myHPP = bot:getHPP()
    local meleeHPP, mageHPP = 100, 100
    for _, member in ipairs(ai_magic.get_alliance_members(bot)) do
        if member ~= bot then
            local hpp = member:getHPP()
            local job = ai_magic.job_string(member:getMainJob())
            if xi.singleplayer.bots.ai_util.table_contains(ai_magic.mageJobs, job) then mageHPP = hpp else meleeHPP = hpp end
        end
    end
    if myHPP < 40   then return 'Cure_P1' end
    if mageHPP < 80 then return 'Cure_P2' end
    if meleeHPP < 60 then return 'Cure_P3' end
    if myHPP < 80   then return 'Cure_P4' end
    return 'None'
end

local pldCureSpells = cureSpells

-----------------------------------
-- 125. can_cast_pld_cure
-----------------------------------
function ai_magic.can_cast_pld_cure(bot)
    local idx = ai_magic.get_heal_target_index(bot)
    if idx < 0 then return false end
    local topIdx
    for i, spellId in ipairs(pldCureSpells) do
        if bot:hasSpell(spellId) then topIdx = i; break end
    end
    if topIdx == nil then return false end
    for i = topIdx, math.min(topIdx + 1, #pldCureSpells) do
        if ai_magic.spell_is_up(bot, pldCureSpells[i], false) then return true end
    end
    return false
end

-----------------------------------
-- 126. cast_pld_healing_spell
-----------------------------------
function ai_magic.cast_pld_healing_spell(bot)
    local idx = ai_magic.get_heal_target_index(bot)
    if idx < 0 then return end
    -- Must match get_heal_target_index's iteration scope (ALLIANCE) so the
    -- returned index resolves to the right member.
    local members = ai_magic.get_alliance_members(bot)
    local target = (idx == 0) and bot or members[idx]
    if target == nil then return end
    local efficient = ai_magic.get_most_efficient_cure_spell(target)
    if ai_magic.spell_is_up(bot, efficient, false) then ai_magic.cast_party_spell(bot, efficient, target); return end
    for _, spellId in ipairs(cureSpells) do
        if ai_magic.spell_is_up(bot, spellId, false) then ai_magic.cast_party_spell(bot, spellId, target); return end
    end
end

-----------------------------------
-- Multi-PLD Flash rotation gate — main-mob branch only. Symmetric with
-- provoke_rotation_open in ai_ability: 45/N-second cadence across N PLDs
-- in scope, lowest-charId tiebreak on same-tick contention. Flash-on-add
-- bypasses this (peel urgency). Single-PLD scope is always open (interval
-- equals individual 45s recast).
-----------------------------------
local function flash_rotation_open(bot)
    local A = xi.singleplayer.bots.alliance
    if A == nil then return true end
    local plds = xi.singleplayer.bots.ai_util.plds_in_scope(bot)
    if #plds <= 1 then return true end
    local slot = A.multiEngageMode and xi.singleplayer.bots.get_party_slot(bot) or 1
    local interval = 45000 / #plds
    A.lastFlashAtMs = A.lastFlashAtMs or { 0, 0, 0 }
    local last = A.lastFlashAtMs[slot] or 0
    local now  = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    if now < last + interval then return false end
    local myId = bot:getID()
    for _, p in ipairs(plds) do
        if p:getID() < myId and ai_magic.spell_is_up(p, xi.magic.spell.FLASH, true) then
            return false
        end
    end
    return true
end

-----------------------------------
-- 127. flash_is_up — main-mob Flash gate. Rotation-throttled for multi-PLD
-- scopes; flash_add_is_up handles add peels and bypasses rotation.
-----------------------------------
function ai_magic.flash_is_up(bot)
    if not ai_magic.spell_is_up(bot, xi.magic.spell.FLASH, true) then return false end
    if not ai_magic.current_mob_in_range(bot, xi.magic.spell.FLASH) then return false end
    return flash_rotation_open(bot)
end

-----------------------------------
-- 128. flash — cast on main target. Stamps the rotation timestamp for
-- this bot's scope so the next PLD in the rotation waits 45/N seconds.
-----------------------------------
function ai_magic.flash(bot)
    local A = xi.singleplayer.bots.alliance
    if A ~= nil then
        local slot = A.multiEngageMode and xi.singleplayer.bots.get_party_slot(bot) or 1
        A.lastFlashAtMs = A.lastFlashAtMs or { 0, 0, 0 }
        A.lastFlashAtMs[slot] = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    end
    ai_magic.cast_melee_spell(bot, xi.magic.spell.FLASH)
end

-----------------------------------
-- 128b. flash_add_is_up - mirror of flash_is_up but targets a peelable add
--                        instead of the current alliance target. Gated by
--                        the bot's addControlMode ('flash' or 'both'); in
--                        'provoke' mode this is always false so the role
--                        tick falls through to flash_is_up on the main.
-----------------------------------
function ai_magic.flash_add_is_up(bot)
    if xi.singleplayer.bots.threat == nil
       or xi.singleplayer.bots.threat.peelable_for == nil then
        return false
    end
    local threat = xi.singleplayer.bots.threat.peelable_for(bot)
    if threat == nil then return false end
    local s    = xi.singleplayer.bots.alliance and xi.singleplayer.bots.alliance.bot[bot:getID()]
    local mode = (s and s.addControlMode) or 'provoke'
    if mode ~= 'flash' and mode ~= 'both' then return false end
    -- Off-recast + spell-known + still-engaged baseline. Range check uses
    -- the add's position via cast_spell_on's own GetEntityByID resolve, so
    -- if the bot ends up out of range the cast fails gracefully one frame
    -- later rather than gating the AI here.
    return ai_magic.spell_is_up(bot, xi.magic.spell.FLASH, true)
end

-----------------------------------
-- 128c. flash_add - cast Flash on the bot's peelable add (NOT current target).
--                  Companion to flash_add_is_up. Uses cast_spell_on to direct
--                  the spell at the threat mob's entity ID.
-----------------------------------
function ai_magic.flash_add(bot)
    local threat = xi.singleplayer.bots.threat.peelable_for(bot)
    if threat == nil then return false end
    return ai_magic.cast_spell_on(bot, xi.magic.spell.FLASH, threat.mob:getID())
end

-----------------------------------
-- 129. get_sleeping_whm  (returns member entity)
-----------------------------------
function ai_magic.get_sleeping_whm(bot)
    -- ALLIANCE-scope: single-target Cure has alliance-wide range, so a
    -- sleeping WHM anywhere in the alliance is a wake target. (The original
    -- Ashita addon's partyStatus was party-only, but that was a packet-source
    -- limitation, not a spell-mechanic one — the right scope here is alliance.)
    for _, member in ipairs(ai_magic.get_alliance_members(bot)) do
        if ai_magic.job_string(member:getMainJob()) == 'WHM' then
            for _, id in ipairs(sleepStatusIds) do
                if ai_magic.is_effect_active(member, id) then return member end
            end
        end
    end
    return nil
end

-----------------------------------
-- 130. sleeping_whm
-----------------------------------
function ai_magic.sleeping_whm(bot)
    return ai_magic.get_sleeping_whm(bot) ~= nil and ai_magic.spell_is_up(bot, xi.magic.spell.CURE, false)
end

-----------------------------------
-- 131. wake_up_whm
-----------------------------------
function ai_magic.wake_up_whm(bot)
    if ai_magic.sleeping_whm(bot) then
        ai_magic.cast_party_spell(bot, xi.magic.spell.CURE, ai_magic.get_sleeping_whm(bot))
    end
end

-----------------------------------
-- 132. handle_walking
--     Returns true if a movement action was issued this tick.
-----------------------------------
function ai_magic.handle_walking(bot)
    local state = getState(bot)
    local assistName = ai_magic.get_assist(bot)
    if assistName == nil or assistName == '' then return false end
    local assist = ai_magic.get_member_by_name(bot, assistName)
    if assist == nil then return false end
    local dx = assist:getXPos() - bot:getXPos()
    local dz = assist:getZPos() - bot:getZPos()
    local d = math.sqrt(dx * dx + dz * dz)
    if not state.followOn and d > 12 then
        state.followOn = true
        -- Movement is owned by ai_move.runMovementTick. The previous
        -- xi.singleplayer.bots.ai_move.stepToward call here was a pre-cast catchup that
        -- closed the gap one tick earlier than the canonical path.
        -- Removed during the autoai split to keep movement single-sourced.
        return true
    elseif state.followOn and d <= 8 then
        state.followOn = false
        return true
    end
    return false
end

-----------------------------------
-- 136. check_for_target_death
--     Server-side: hook from mob:onMobDeath (registered by bot_ai).
-----------------------------------
function ai_magic.check_for_target_death(bot, mobId)
    local state = getState(bot)
    if xi.singleplayer.bots.get_alliance_target_id() == mobId then
        xi.singleplayer.bots.set_alliance_target(0)
        -- Clear both "burn it down" flags: nukeUntilDead (consumed in
        -- role_nuke/role_rdm) and wsUntilDead (consumed in role_melee).
        -- Both are set together by bots_spawn.finish_alliance and naturally
        -- expire together when the target dies.
        state.nukeUntilDead = false
        state.wsUntilDead   = false
    end
    state.spellLog[mobId] = nil
end

-----------------------------------
-- 142. check_for_casting
--     Server-side: dispatched from MAGIC_USE (phase='finish') and
--     MAGIC_INTERRUPTED (phase='interrupt') in bots_listeners.register.
--     The 'start' phase was dropped — castingSpell is now read directly
--     via bot:isBotCasting() and the MAGIC_START hook called this with
--     'start' to no effect. Only 'finish' / 'interrupt' do real work
--     (refresh lastCastEnd throttle; on finish, log the cast for the
--     once-per-mob spell guard).
-----------------------------------
function ai_magic.check_for_casting(bot, phase, spellId)
    local state = getState(bot)
    state.lastCastEnd = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    if phase == 'finish' then
        local mobId = xi.singleplayer.bots.get_alliance_target_id()
        if mobId ~= 0 then ai_magic.note_cast(bot, mobId, spellId) end
    end
end

-----------------------------------
-- 143. check_for_stun
--     Server-side: hook from stun spell-land action. Closes the
--     alliance-level stun window so the next tick won't try to cast
--     again. Fairness rotates via MP%-sorted pool pick.
-----------------------------------
function ai_magic.check_for_stun(_, _)
    local alliance = xi.singleplayer.bots.alliance
    if alliance ~= nil then alliance.stunWindowUntilMs = 0 end
end

-----------------------------------
-- 146. check_for_getting_attacked
-----------------------------------
function ai_magic.check_for_getting_attacked(bot)
    local state = getState(bot)
    state.casualNukeDelayMultiple = 3
    local job = ai_magic.job_string(bot:getMainJob())
    local delay = (job == 'BLM') and 10000 or 5000
    state.stopCastingUntil = xi.singleplayer.bots.ai_util.get_ms_since_epoch() + delay
end

-----------------------------------
-- 147. reset
-----------------------------------
function ai_magic.reset(bot)
    local state = getState(bot)
    state.lastCastEnd = 0
    state.casualNukeDelayMultiple = 1
    state.stopCastingUntil = 0
    state.nextPosUpdate = 0
    state.spellLog = {}
    state.nukeUntilDead = false
    state.wsUntilDead   = false  -- match nukeUntilDead's reset for ai_magic.reset
    xi.singleplayer.bots.set_alliance_target(0)
end

-----------------------------------
-- 151. process_pre_cast_checks
-----------------------------------
function ai_magic.process_pre_cast_checks(bot)
    local state = getState(bot)
    -- combat_active returns the alliance target mob when the alliance is
    -- actively fighting (allianceTarget non-zero + mob alive), else nil.
    -- Used to gate the rest-stop-for-SC branch below: stand up early if
    -- alliance is mid-fight AND SC is imminent AND we have enough MP.
    local primaryEntity = bot:isHeadless() and GetPlayerByID(bot:getParentCharId()) or bot
    local activeTarget  = ai_magic.combat_active(primaryEntity)

    -- Hard skips
    if ai_magic.is_casting(bot)
       or (xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.has_neutralizing_effect(bot))
       or bot:getHP() <= 0 then
        return true
    end

    -- Role AI policy item branches. Priority HP → Status → MP per spec.
    -- Replaced the prior legacy paths (potent-poison antidote, silence /
    -- paralysis remedy, NM-gated ether, lowMP-poisoned remedy) — all
    -- subsumed by try_status_item + try_mp_item against Role AI policy.
    if xi.singleplayer.bots.item.try_hp_item     and xi.singleplayer.bots.item.try_hp_item(bot)     then return true end
    if xi.singleplayer.bots.item.try_status_item and xi.singleplayer.bots.item.try_status_item(bot) then return true end
    if xi.singleplayer.bots.item.try_mp_item     and xi.singleplayer.bots.item.try_mp_item(bot)     then return true end

    if ai_magic.handle_walking(bot) then return true end
    if ai_magic.is_moving(bot) then return true end

    -- MP-low rest cascade — fallback when no policy ether fired. Just sit
    -- and regen. startBotResting bails silently if engaged, so the
    -- isEngaged check avoids start_rest spam in combat.
    local engaged = bot.isEngaged and bot:isEngaged() or false
    local lowMP = (not engaged)
              and xi.singleplayer.bots.ai_util.current_mp_percent(bot) < 20
              and xi.singleplayer.bots.ai_util.can_rest(bot)
              and not xi.singleplayer.bots.ai_util.is_resting(bot)

    if lowMP then
        -- SMN with pet out: perpetuation defeats resting. Release the pet
        -- this tick; next tick lowMP fires the branch below and rest begins
        -- normally. Guarded on the smn module being loaded so ai_magic
        -- keeps working before role_smn has been loaded.
        local ai_util = xi.singleplayer.bots.ai_util
        local smn = xi.singleplayer.bots.smn
        if ai_util.is_smn and ai_util.is_smn(bot)
           and smn and smn.has_pet and smn.has_pet(bot)
           and smn.release_pet then
            ai_util.log(bot, 'AutoMagic', 'release-pet-pre-rest')
            smn.release_pet(bot)
            return true
        end
        xi.singleplayer.bots.ai_util.log(bot, 'AutoMagic', 'can_rest')
        xi.singleplayer.bots.ai_util.start_rest(bot)
        return true
    elseif xi.singleplayer.bots.ai_util.is_resting(bot) then
        -- Stand-up conditions:
        --   * MP topped off (>85%): default "we're done resting" signal.
        --   * SC close + MP > 20 + role that fires into SC windows: Nuker,
        --     RDM, SMN. WHM/BRD/Melee/Tank don't participate in MB and
        --     shouldn't burn rest to chase one. (Previously gated on
        --     is_job(WHM) which was a coarser exclusion.)
        --   * Role.Healer + party member HP <= 25%: urgent cure — a
        --     resting healer must abandon rest and cure to avoid party
        --     death during the "camp between fights" window.
        local Role = xi.singleplayer.bots.Role
        local role = state.role
        local scCasterRole = role == Role.Nuker or role == Role.Rdm or role == Role.Smn
        local urgentCure = false
        -- Healer stand-up-for-cure requires enough MP to actually cast. Without
        -- this gate a WHM at low HP+MP flickers: sits (lowMP), stands (self
        -- at <=25% HP triggers urgentCure), can't cast (MP too low), camp-
        -- passive re-adds HEALING, repeat every tick. 20% mirrors the lowMP
        -- threshold above — below it we WANT to be resting for MP recovery,
        -- and HEALING tick regens HP too so the self case self-corrects.
        if role == Role.Healer
           and xi.singleplayer.bots.ai_util.current_mp_percent(bot) >= 20 then
            local lowest = ai_magic.get_player_with_lowest_hpp(
                bot, ai_magic.spell_range(xi.magic.spell.CURE), true)
            urgentCure = lowest ~= nil and lowest:getHPP() <= 25
        end
        if xi.singleplayer.bots.ai_util.current_mp_percent(bot) > 95
           or (activeTarget and scCasterRole
               and xi.singleplayer.bots.ai_util.current_mp_percent(bot) > 20 and ai_magic.sc_is_close(bot))
           or urgentCure then
            xi.singleplayer.bots.ai_util.log(bot, 'AutoMagic', 'stop_rest')
            xi.singleplayer.bots.ai_util.stop_rest(bot)
        end
        return true
    end

    -- Hate-melt window: mage went too far and pulled hate; the casting freeze
    -- is the recovery. Placed at the bottom so antidote, remedy, ether/rest
    -- branches above all still fire — those don't reproduce hate the way a
    -- nuke would, and we WANT MP recovery during the wait.
    if xi.singleplayer.bots.ai_util.get_ms_since_epoch() < (state.stopCastingUntil or 0) then return true end

    return false
end

-----------------------------------
-- build_whm_ctx
--   Computes the shared /WHM cure-and-status context that every /WHM
--   sub role (role_heal, role_smn, and any future /WHM-sub role file)
--   needs at the top of its tick. Returns a table that whm_cascade
--   consumes directly.
--
--   logTag: 'AutoHeal' for role_heal, 'AutoSMN' for role_smn, etc.
--   Preserves per-caller identity in the log stream so grepping by
--   role still works after the extraction.
-----------------------------------
function ai_magic.build_whm_ctx(bot, logTag)
    -- combat_active returns the alliance target mob when the alliance is
    -- actively fighting, else nil. Was previously assist:isEngaged() — a
    -- fragile signal that returned false when the tank died mid-fight,
    -- causing WHM to think the fight was over and cast Raise on the dead
    -- tank. `primary` param preserved for API compat but no longer used
    -- by combat_active.
    local primary      = bot:isHeadless() and GetPlayerByID(bot:getParentCharId()) or bot
    local activeTarget = ai_magic.combat_active(primary)

    local state     = xi.singleplayer.bots.ensure_bot(bot:getID())
    local healScope = state.healScope or 'party'

    return {
        activeTarget         = activeTarget,
        healScope            = healScope,
        cureTier             = ai_magic.get_cure_tier(bot),
        allianceCureTier     = ai_magic.get_alliance_cure_tier(bot),
        allianceBlmCureTier  = ai_magic.get_alliance_blm_cure_tier(bot),
        log                  = function(msg) xi.singleplayer.bots.ai_util.log(bot, logTag, msg) end,
    }
end

-----------------------------------
-- whm_cascade
--   The /WHM sub cure / status / bar / haste / enfeeble decision tree
--   extracted from role_heal so /WHM-sub roles (role_smn) can call it
--   after their own priorities. Order preserved from the original
--   role_heal.tick cascade. Every branch reads from ctx (activeTarget,
--   healScope, cureTier, allianceCureTier, allianceBlmCureTier, log)
--   plus the bot entity.
-----------------------------------
function ai_magic.whm_cascade(bot, ctx)
    local log                 = ctx.log
    local activeTarget        = ctx.activeTarget
    local healScope           = ctx.healScope
    local cureTier            = ctx.cureTier
    local allianceCureTier    = ctx.allianceCureTier
    local allianceBlmCureTier = ctx.allianceBlmCureTier

    if cureTier == 'Curaga' and ai_magic.can_cast_curaga(bot) then
        log('Curaga');
        ai_magic.cast_curaga(bot);
    elseif cureTier == 'Cure_P1' and ai_magic.can_cast_cure(bot) then
        log('Cure_P1');
        ai_magic.cast_cure(bot);
    elseif healScope == 'allianceMain' and allianceCureTier == 'Cure_P1' and ai_magic.can_cast_cure(bot) then
        log('alliance_main_Cure_P1');
        ai_magic.cast_alliance_cure(bot);
    elseif ai_magic.can_cure_high_priority_status(bot) then
        log('can_cure_high_priority_status');
        ai_magic.cure_high_priority_status(bot);
    elseif healScope == 'allianceMain' and ai_magic.can_cure_alliance_high_priority_status(bot) then
        log('alliance_main_high_status');
        ai_magic.cure_alliance_high_priority_status(bot);
    elseif ai_magic.can_clear_mage_rest_blocker(bot) then
        log('clear_mage_rest_blocker');
        ai_magic.clear_mage_rest_blocker(bot);
    elseif not activeTarget and ai_magic.can_raise(bot) then
        log('can_raise');
        ai_magic.cast_raise(bot);
    elseif cureTier == 'Cure_P2' and ai_magic.can_cast_cure(bot) then
        log('Cure_P2');
        ai_magic.cast_cure(bot);
    elseif healScope == 'allianceMain' and allianceCureTier == 'Cure_P2' and ai_magic.can_cast_cure(bot) then
        log('alliance_main_Cure_P2');
        ai_magic.cast_alliance_cure(bot);
    elseif healScope == 'allianceAssist' and allianceBlmCureTier == 'Cure_P1' and ai_magic.can_cast_cure(bot) then
        log('alliance_assist_blm_Cure_P1');
        ai_magic.cast_alliance_cure(bot);
    elseif ai_magic.sleeping_members(bot) then
        log('sleeping_members');
        ai_magic.wake_up_members(bot);
    elseif activeTarget and ai_magic.can_bar_spell(bot) then
        log('can_bar_spell');
        ai_magic.cast_bar_spell(bot);
    elseif ai_magic.can_cure_medium_priority_status(bot) then
        log('can_cure_medium_priority_status');
        ai_magic.cure_medium_priority_status(bot);
    elseif healScope == 'allianceMain' and ai_magic.can_cure_alliance_medium_priority_status(bot) then
        log('alliance_main_medium_status');
        ai_magic.cure_alliance_medium_priority_status(bot);
    elseif cureTier == 'Regen' and ai_magic.can_cast_regen(bot) then
        log('Regen');
        ai_magic.cast_regen(bot);
    elseif xi.singleplayer.bots.ability.always_ability_is_up(bot) then
        log('always_ability_is_up');
        xi.singleplayer.bots.ability.use_next_always_ability(bot);
    elseif ai_magic.can_protectra_or_shellra(bot) then
        log('can_protectra_or_shellra');
        ai_magic.cast_protectra_or_shellra(bot);
    elseif activeTarget and ai_magic.can_haste(bot) then
        log('can_haste');
        ai_magic.cast_haste(bot);
    elseif ai_magic.sleeping_alliance(bot) then
        log('sleeping_alliance');
        ai_magic.wake_up_alliance(bot);
    elseif activeTarget and ai_magic.no_rdm(bot) and ai_magic.no_nin(bot) and ai_magic.can_whm_enfeeble(bot) then
        log('can_whm_enfeeble');
        ai_magic.whm_enfeeble(bot);
    elseif ai_magic.can_cure_low_priority_status(bot) then
        log('can_cure_low_priority_status');
        ai_magic.cure_low_priority_status(bot);
    elseif healScope == 'allianceMain' and ai_magic.can_cure_alliance_low_priority_status(bot) then
        log('alliance_main_low_status');
        ai_magic.cure_alliance_low_priority_status(bot);
    elseif not activeTarget and ai_magic.can_buff_self(bot) then
        log('can_buff_self');
        ai_magic.buff_self(bot);
    elseif ai_magic.can_use_food(bot) then
        log('can_use_food');
        ai_magic.use_food(bot);
    elseif activeTarget and ai_magic.can_mb(bot) then
        log('can_mb');
        ai_magic.cast_mb(bot);
    elseif activeTarget and ai_magic.casual_whm_nuke_is_up(bot) then
        log('casual_whm_nuke_is_up');
        local nextSpell = ai_magic.get_next_casual_whm_nuke(bot);
        if nextSpell ~= nil then ai_magic.cast_spell(bot, nextSpell) end;
    else
        return false
    end
    return true
end

-- 152. equip_on_outgoing_action GONE. The original Ashita addon's
-- actionType→gear dispatcher; replaced by ai_equip_swap.register_listeners
-- which hooks PAI events directly (MAGIC_STATE_ENTER → premagic, etc.) AND
-- by ai_magic.cast_spell / ai_ability.use_ws pre-swapping before the call.

-----------------------------------
-- 154. equip_gearlock
-----------------------------------
function ai_magic.equip_gearlock(bot)
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_gearlock then
        xi.singleplayer.bots.ai_equip_swap.equip_gearlock(bot)
    end
end

-----------------------------------
-- Internal: spellLog recorder used by cast_* paths
-----------------------------------
function ai_magic.note_cast(bot, mobId, spellId)
    if mobId == nil or mobId == 0 or spellId == nil then return end
    local state = getState(bot)
    state.spellLog[mobId] = state.spellLog[mobId] or {}
    state.spellLog[mobId][spellId] = true
    state.lastCastEnd = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
end

-----------------------------------
-- Stun + bash interrupt-window setter. Wired from the engine's new
-- luautils::OnMobSkillStart hook (lua_hooks.cpp), which fires in the
-- CMobSkillState constructor with the move's REAL m_castTime. So the
-- interrupt window matches the actual mob TP windup — short on instant
-- moves, long on Bahamut-class 5s windups — instead of a constant guess.
--
-- Window-flag model (#229): set alliance.stunWindowUntilMs +
-- alliance.bashWindowUntilMs once at the trigger; role ticks consume the
-- windows via can_stun() (magic side) and bash_is_up/bash (ability side).
-- If everyone is mid-action at the instant of the trigger, the window is
-- still open next tick and someone (or themselves, post-cast) covers the
-- interrupt.
--
-- Stun mode (alliance.stunMode, set via 0x176 SET_STUN_MODE - replaces the
-- legacy BOT_STUN_PERSIST_UNTIL_FIRED settings flag):
--   'always' (default) - the STUN window doesn't elapse; stays open until a
--                        stunner successfully fires (cleared by check_for_stun)
--                        or the alliance target dies / disengages (cleared by
--                        bots.set_alliance_target(0)). Gives the alliance a
--                        "control breather" post-WS at the cost of one extra
--                        stun cast per move.
--   'window'           - the STUN window equals the mob's actual WS castTime
--                        (with a 500ms minimum for instant moves). Strict
--                        interrupt window; if everyone is busy at the trigger
--                        instant, the interrupt is missed.
-- Bash window is always strict - the gameplay rationale (a melee tank/DRK
-- bashing a mob during the AA cycle vs a caster stunning) doesn't generalize
-- the same way.
-----------------------------------
-- Alliance-wide stun-mode setter. Called from luautils::OnBotSetStunMode
-- in response to 0x176 SET_STUN_MODE. Validates against the allowed values
-- and falls back to 'always' on anything unexpected so a malformed wire
-- byte can't write an undefined string into the alliance state.
function ai_magic.set_alliance_stun_mode(primary, mode)
    if primary == nil then return end
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil then return end
    if mode ~= 'always' and mode ~= 'window' then mode = 'always' end
    alliance.stunMode = mode
    printf(string.format('ai_magic.set_alliance_stun_mode: %s', mode))
end

-----------------------------------
-- NIN ninjutsu block (Utsusemi shadow management + elemental wheel +
-- Kurayami/Hojo/Jubaku/Dokumori debuffs). Shared across role_tank
-- (main tank) and role_melee (off-tank). Sub-job assumption is
-- NIN/WAR — no self-cures.
--
--   1. Utsusemi: never overwrite live shadows (Ichi would clobber Ni
--      and waste the better spell). Refresh threshold is aggressive
--      for tanks (<=1 shadow when engaged), defensive for melee (0
--      shadows). Prefer Ni over Ichi when both are off recast.
--   2. Elemental wheel: cycle Katon → Hyoton → Huton → Doton → Raiton
--      → Suiton (Fire → Ice → Wind → Earth → Lightning → Water) at
--      the Ichi tier for sustained DoT-stack DPS + hate. A per-bot 2s
--      gap between offensive ninjutsu casts lets autoattacks land in
--      the seams.
--   3. Ninjutsu debuffs: Kurayami/Hojo/Jubaku/Dokumori, only when no
--      RDM is present in the alliance (RDM owns enfeebles otherwise).
--      Missing or expired debuff preempts the wheel.
-----------------------------------

-- Utsusemi: { Ni, Ichi, San } preference order. Ni first because it
-- gives more shadows AND is preferred even on equal-count tiers due to
-- longer duration. San is post-75 but harmless in spell_is_up checks.
local UTSUSEMI_SPELLS = {
    xi.magic.spell.UTSUSEMI_NI,    -- 340
    xi.magic.spell.UTSUSEMI_ICHI,  -- 339
    xi.magic.spell.UTSUSEMI_SAN,   -- 338
}

-- COPY_IMAGE family of status effects — any of these means shadows are
-- up and Utsusemi must NOT be recast.
local UTSUSEMI_STATUSES = { 66, 444, 445, 446 }

-- Elemental wheel order (FFXI resistance wheel). Ichi tier picked for
-- the wheel because shorter recasts let the cycle sustain; Ni tier is
-- for nuking, not steady DPS.
local NINJITSU_WHEEL_SPELLS = {
    xi.magic.spell.KATON_ICHI,   -- 320 Fire
    xi.magic.spell.HYOTON_ICHI,  -- 323 Ice
    xi.magic.spell.HUTON_ICHI,   -- 326 Wind
    xi.magic.spell.DOTON_ICHI,   -- 329 Earth
    xi.magic.spell.RAITON_ICHI,  -- 332 Thunder
    xi.magic.spell.SUITON_ICHI,  -- 335 Water
}

-- Ninjutsu debuffs. Each entry maps a target status effect to its
-- preferred spell tiers (Ni > Ichi). Cast only if no RDM in alliance.
local NINJITSU_DEBUFF_TIERS = {
    { effect = xi.effect.BLINDNESS, tiers = { xi.magic.spell.KURAYAMI_NI, xi.magic.spell.KURAYAMI_ICHI } },
    { effect = xi.effect.SLOW,      tiers = { xi.magic.spell.HOJO_NI,     xi.magic.spell.HOJO_ICHI     } },
    { effect = xi.effect.PARALYSIS, tiers = { xi.magic.spell.JUBAKU_NI,   xi.magic.spell.JUBAKU_ICHI   } },
    { effect = xi.effect.POISON,    tiers = { xi.magic.spell.DOKUMORI_NI, xi.magic.spell.DOKUMORI_ICHI } },
}

-- 2s pacing between offensive ninjutsu casts (wheel + debuffs) so
-- autoattacks land between spells. Utsusemi bypasses the gap since
-- shadow refresh is defensive priority.
local OFFENSIVE_NINJITSU_GAP_MS = 2000

ai_magic.UTSUSEMI_SPELLS          = UTSUSEMI_SPELLS
ai_magic.NINJITSU_WHEEL_SPELLS    = NINJITSU_WHEEL_SPELLS
ai_magic.NINJITSU_DEBUFF_TIERS    = NINJITSU_DEBUFF_TIERS
ai_magic.OFFENSIVE_NINJITSU_GAP_MS = OFFENSIVE_NINJITSU_GAP_MS

-- shadow_count — number of Utsusemi shadows up (0 if none). Power of
-- EFFECT_COPY_IMAGE is the live shadow counter; the COPY_IMAGE_2/3/4
-- effect IDs were a pre-merge legacy split now folded into the single
-- power-tracking model. All four IDs checked for forward compat with
-- engines that still use the split form.
function ai_magic.shadow_count(bot)
    for _, statusId in ipairs(UTSUSEMI_STATUSES) do
        local eff = bot:getStatusEffect(statusId)
        if eff ~= nil then
            local power = eff.getPower and eff:getPower() or 0
            if power > 0 then return power end
            return 1
        end
    end
    return 0
end

function ai_magic.has_shadows(bot)
    return ai_magic.shadow_count(bot) > 0
end

-- get_next_utsusemi_spell — spellId to cast, or nil. Never returns a
-- spell while shadows are up (Ichi would clobber Ni).
function ai_magic.get_next_utsusemi_spell(bot)
    if ai_magic.has_shadows(bot) then return nil end
    for _, spellId in ipairs(UTSUSEMI_SPELLS) do
        if ai_magic.spell_is_up(bot, spellId, false) then
            return spellId
        end
    end
    return nil
end

-- can_cast_utsusemi — Shihei tool check included (engine enforces
-- consumption but we skip the cast when there's no tool to burn).
function ai_magic.can_cast_utsusemi(bot)
    return ai_magic.get_next_utsusemi_spell(bot) ~= nil
       and xi.singleplayer.bots.item.have_shihei(bot)
end

function ai_magic.cast_utsusemi(bot)
    local spellId = ai_magic.get_next_utsusemi_spell(bot)
    if spellId == nil then return false end
    return ai_magic.cast_party_spell(bot, spellId, bot)
end

-- should_refresh_utsusemi — isTank=true uses the aggressive threshold
-- (<=1 shadow when engaged) so the cast queues up before shadows reach
-- 0 mid-combat. Off-tanks and idle bots wait for 0 to avoid wasting
-- a Ni's worth of shadows.
function ai_magic.should_refresh_utsusemi(bot, isTank)
    local shadows = ai_magic.shadow_count(bot)
    if shadows == 0 then return true end
    if isTank and shadows <= 1 and bot:isEngaged() then return true end
    return false
end

function ai_magic.can_refresh_utsusemi(bot, isTank)
    return ai_magic.should_refresh_utsusemi(bot, isTank)
       and ai_magic.can_cast_utsusemi(bot)
end

-- offensive_ninjitsu_off_cooldown — 2s wheel/debuff pacing gap.
function ai_magic.offensive_ninjitsu_off_cooldown(bot)
    local state = xi.singleplayer.bots.get_bot_state(bot)
    local now   = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    return now - (state.lastOffensiveNinjutsuMs or 0) >= OFFENSIVE_NINJITSU_GAP_MS
end

local function note_offensive_ninjitsu_cast(bot)
    local state = xi.singleplayer.bots.get_bot_state(bot)
    state.lastOffensiveNinjutsuMs = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
end

-----------------------------------
-- Multi-NIN subset resolution. When N NINs share a scope (party or alliance
-- depending on multiEngageMode), the wheel (6 spells) and debuff list
-- (4 spells) are contiguously split by NIN slot index so bots don't
-- collide on the same spell. Slot ordering is charId ascending — same as
-- the tank/PLD rotation tiebreaks, keeps mental model consistent.
--
-- Split shape:
--   6 wheel × 2 NINs → NIN1 {K,H,Hu}, NIN2 {D,R,S}
--   6 wheel × 3 NINs → NIN1 {K,H}, NIN2 {Hu,D}, NIN3 {R,S}
--   4 debuff × 2 NINs → NIN1 {Kurayami,Hojo}, NIN2 {Jubaku,Dokumori}
--   4 debuff × 3 NINs → NIN1 {Kurayami,Hojo}, NIN2 {Jubaku}, NIN3 {Dokumori}
--   Leftover items go to the first (n mod N) slots.
--
-- Single-NIN scope: full list, no filtering (unchanged behavior).
-----------------------------------
local function nin_wheel_subset_for(bot)
    local nins = xi.singleplayer.bots.ai_util.nins_in_scope(bot)
    if #nins <= 1 then return NINJITSU_WHEEL_SPELLS end
    local slot = xi.singleplayer.bots.ai_util.slot_index_in(bot, nins) or 1
    return xi.singleplayer.bots.ai_util.contiguous_slice(NINJITSU_WHEEL_SPELLS, slot, #nins)
end

local function nin_debuff_entries_for(bot)
    local nins = xi.singleplayer.bots.ai_util.nins_in_scope(bot)
    if #nins <= 1 then return NINJITSU_DEBUFF_TIERS end
    local slot = xi.singleplayer.bots.ai_util.slot_index_in(bot, nins) or 1
    return xi.singleplayer.bots.ai_util.contiguous_slice(NINJITSU_DEBUFF_TIERS, slot, #nins)
end

-- next_missing_ninjitsu_debuff_spell — walks this bot's allocated slice of
-- NINJITSU_DEBUFF_TIERS. Priority within the slice preserved from the
-- master list.
function ai_magic.next_missing_ninjitsu_debuff_spell(bot, target)
    if target == nil then return nil end
    for _, entry in ipairs(nin_debuff_entries_for(bot)) do
        if not target:hasStatusEffect(entry.effect) then
            for _, spellId in ipairs(entry.tiers) do
                if ai_magic.spell_is_up(bot, spellId, true, target) then
                    return spellId
                end
            end
        end
    end
    return nil
end

-- next_ninjitsu_wheel_spell — scans this bot's allocated wheel subset
-- from ninWheelIdx forward (wrapping within the subset). Returned index
-- is into the subset, not the master wheel — state.ninWheelIdx stays
-- subset-local for stable per-bot cycling.
function ai_magic.next_ninjitsu_wheel_spell(bot)
    local subset = nin_wheel_subset_for(bot)
    if #subset == 0 then return nil, 1 end
    local state = xi.singleplayer.bots.get_bot_state(bot)
    local startIdx = state.ninWheelIdx or 1
    if startIdx < 1 or startIdx > #subset then startIdx = 1 end
    for offset = 0, #subset - 1 do
        local idx = ((startIdx - 1 + offset) % #subset) + 1
        local spellId = subset[idx]
        if ai_magic.spell_is_up(bot, spellId, true) then
            return spellId, idx
        end
    end
    return nil, startIdx
end

-- can_cast_ninjitsu_debuff / cast_next_ninjitsu_debuff — pure predicate
-- + action. Gates: 2s pacing gap + no RDM in alliance + commanded
-- target exists + target missing at least one of the four debuffs.
function ai_magic.can_cast_ninjitsu_debuff(bot)
    if not ai_magic.offensive_ninjitsu_off_cooldown(bot) then return false end
    if not ai_magic.no_rdm(bot) then return false end
    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return false end
    return ai_magic.next_missing_ninjitsu_debuff_spell(bot, target) ~= nil
end

function ai_magic.cast_next_ninjitsu_debuff(bot)
    local target = xi.singleplayer.bots.get_current_mob_target()
    if target == nil then return false end
    local spellId = ai_magic.next_missing_ninjitsu_debuff_spell(bot, target)
    if spellId == nil then return false end
    local ok = ai_magic.cast_spell(bot, spellId)
    if ok then note_offensive_ninjitsu_cast(bot) end
    return ok
end

-- can_cast_ninjitsu_wheel / cast_next_ninjitsu_wheel — pure predicate
-- + action. Fires next wheel slot and advances ninWheelIdx.
function ai_magic.can_cast_ninjitsu_wheel(bot)
    if not ai_magic.offensive_ninjitsu_off_cooldown(bot) then return false end
    return (ai_magic.next_ninjitsu_wheel_spell(bot)) ~= nil
end

function ai_magic.cast_next_ninjitsu_wheel(bot)
    local spellId, idx = ai_magic.next_ninjitsu_wheel_spell(bot)
    if spellId == nil then return false end
    local ok = ai_magic.cast_spell(bot, spellId)
    if ok then
        local state = xi.singleplayer.bots.get_bot_state(bot)
        state.ninWheelIdx = (idx % #NINJITSU_WHEEL_SPELLS) + 1
        note_offensive_ninjitsu_cast(bot)
    end
    return ok
end

xi.singleplayer.bots.onMobSkillStart = xi.singleplayer.bots.onMobSkillStart or function(_, _) end
m:addOverride('xi.singleplayer.bots.onMobSkillStart', function(actor, castTimeMs)
    if super then super(actor, castTimeMs) end
    if actor == nil then return end
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil then return end
    local now      = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    -- Some mob moves have m_castTime = 0 (instant). Treat as a small minimum
    -- so the window is at least a couple ticks wide for late-availability
    -- stunners. 500ms is a few AI ticks; covers the "just-now-free" window.
    local windup   = (castTimeMs or 0) > 0 and castTimeMs or 500
    local until_ms = now + windup

    local stunMode = alliance.stunMode or 'always'
    if stunMode == 'always' then
        alliance.stunWindowUntilMs = math.huge
    else
        alliance.stunWindowUntilMs = until_ms
    end
    alliance.bashWindowUntilMs = until_ms
end)

return m
