-----------------------------------
-- Alliance candidate pools (#216, expanded #229).
--
-- Compiled at spawn from alliance.roleMap + job/ability/spell capability.
-- Re-sorted per decision by HP%/MP%; tiebreak is pool-array index (stable).
-- Pools live on xi.singleplayer.bots.alliance as flat charId arrays:
-- { provokePool, stunPool, bashPool, rdmSleepPool, blmSleepPool }.
--
-- Sort keys + floors (locked design — see bots.lua schema comment):
--   * provokePool    : HP% desc, floor 30%
--   * stunPool       : MP% desc, "enough MP to cast" only (no extra floor)
--   * bashPool       : HP% desc, no MP/recast floor (bash is MP-free)
--   * rdmSleepPool   : MP% desc, "enough MP to cast" only
--   * blmSleepPool   : MP% desc, "enough MP to cast" only
--
-- Sleep precedence: try rdmSleepPool first, fall back to blmSleepPool.
-- brdPool (#217), Sleepga + Repose (#218), and mob-specific spell variant
-- selection (#219) are deferred — none here.
--
-- Trigger model — see role consumers for fire path:
--   * provokePool / sleep pools: SUSTAINED-condition trigger (mob is hitting
--     a vulnerable target / awake hostile add exists). Picked every tick by
--     the role decision tree; natural retry next tick if pick is busy.
--   * stunPool / bashPool: INSTANTANEOUS trigger (mob SkillStart event).
--     ai_magic.flag_interrupt_windows sets alliance.stunWindowUntilMs +
--     bashWindowUntilMs on the trigger; role ticks consume the window
--     until something fires or the window elapses — so a busy stunner /
--     basher at the instant of SkillStart doesn't whiff the interrupt.
--
-- Bash differs from stun in two ways worth noting at the top:
--   * No MP cost — bashPool has no MP floor at pick time
--   * Two different abilities populate one pool: PLDs with Shield Bash
--     (Tank role) + DRKs with Weapon Bash (Melee role). Which ability to
--     fire is derived at pick time from bot:getMainJob(), so the pool
--     itself just stores charIds. pick_basher returns { id, ability }.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_pool')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.pool = xi.singleplayer.bots.pool or {}
local ai_pool = xi.singleplayer.bots.pool

-- Role classifiers. Pool membership is role-gated, NOT job-gated — only the
-- right kind of bot is even considered. Within the role gate we then verify
-- the actual ability/spell exists on the bot (hasJobAbility / hasSpell) at
-- compile time, so a bot that's too low-level to have the action is never
-- in the pool.
--
-- LIMITATION (documented, accepted): compile_pools runs at spawn. A bot
-- that levels up mid-alliance into the threshold for a new ability/spell
-- won't enter the pool until the next spawn. Mid-alliance level-ups are
-- rare so this is documented and accepted rather than fixed with a re-
-- compile hook on level events.
local function role_can_provoke(role)
    -- Provoke pool is melee-only. Tanks fire Provoke ASAP via role_tank's
    -- `provoke_is_up` (have_ability + target check, no pool ranking) — they
    -- own the alliance target by definition and don't compete with melees
    -- for the Voke slot. Pool ranking decides "which melee peels when the
    -- mob slips to a fragile victim and tank's Voke is unavailable."
    local R = xi.singleplayer.bots.Role
    return role == R.Melee
end

local function role_is_mage_or_support(role)
    local R = xi.singleplayer.bots.Role
    return role == R.Healer or role == R.Nuker or role == R.Rdm or role == R.Skillup
        or role == R.Brd or role == R.Smn
end

-- Stun is naturally BLM/DRK; RDM only when subbed /DRK at L75+, so the
-- spell-existence check below catches that case via hasSpell. The role
-- gate accepts mage/support roles plus the Melee-DRK exception.
local function role_can_stun(role, job)
    if role_is_mage_or_support(role) then return true end
    if role == xi.singleplayer.bots.Role.Melee and job == 'DRK' then return true end
    return false
end

-- Bash interrupt eligibility for the COMPILE-time pool gate: must be a
-- PLD (Tank role) with Shield Bash OR a DRK (Melee role) with Weapon Bash
-- (hasJobAbility is the strict current-job/level check — see lua_bindings
-- charutils::hasAbility + BuildingCharAbilityTable). The specific ability
-- to fire is derived at pick time from bot:getMainJob() instead of being
-- stored on the entry — keeps the pool as a flat charId array (symmetric
-- with other pools), survives job changes, and handles the high-level
-- PLD/DRK edge case by always preferring main-job's bash.
local function role_can_bash(role, job, bot)
    local R = xi.singleplayer.bots.Role
    if role == R.Tank  and job == 'PLD' and bot:hasJobAbility(xi.jobAbility.SHIELD_BASH) then return true end
    if role == R.Melee and job == 'DRK' and bot:hasJobAbility(xi.jobAbility.WEAPON_BASH) then return true end
    return false
end

-- Live derivation at pick time. Prefers main-job's ability. Returns nil
-- if neither is available (shouldn't happen for pool members; defensive).
--
-- Real FFXI mechanics caveat we DON'T check: Shield Bash needs a shield
-- equipped and Weapon Bash needs a 2H weapon equipped. We gate on job
-- (PLD → Shield Bash, DRK → Weapon Bash) and trust the equip pairing:
-- PLDs nearly always carry shields, DRKs nearly always wield 2H weapons.
-- A PLD who strips their shield mid-fight or a DRK who swaps to 1H+1H
-- would still be picked by the pool and use_ability would fail at the
-- engine layer. The window gets closed optimistically inside ai_ability.bash;
-- in that edge case the interrupt is missed and the move lands. Cost
-- of the false-pick is one wasted recast attempt. Accepting the cost
-- as a deliberate simplification vs threading slot-state through the
-- pool (which would add cost on every pick for a near-zero failure mode).
local function bash_ability_for_runtime(bot)
    local jobs = xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.jobs or {}
    local mainJob = jobs[bot:getMainJob()] or ''
    if mainJob == 'PLD' and bot:hasJobAbility(xi.jobAbility.SHIELD_BASH) then return 'Shield Bash' end
    if mainJob == 'DRK' and bot:hasJobAbility(xi.jobAbility.WEAPON_BASH) then return 'Weapon Bash' end
    -- Subjob fallback in the rare PLD-L60+/DRK or DRK-L70+/PLD case.
    if bot:hasJobAbility(xi.jobAbility.SHIELD_BASH) then return 'Shield Bash' end
    if bot:hasJobAbility(xi.jobAbility.WEAPON_BASH) then return 'Weapon Bash' end
    return nil
end

local function job_string(jobByte)
    local jobs = xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.jobs or {}
    return jobs[jobByte] or ''
end

local function primary_entity()
    local alliance = xi.singleplayer.bots.alliance
    return alliance and GetPlayerByID(alliance.mainCharId or 0) or nil
end

-- Split into two checks so each pool site can be explicit about which axis
-- it cares about. compile_pools cares about NEITHER (capability is location-
-- independent); pick_* care about BOTH (the picked bot has to actually act).
local function alive(bot)
    if bot == nil then return false end
    if bot.isDead and bot:isDead() then return false end
    return true
end

local function same_zone(bot, primary)
    if bot == nil or primary == nil then return false end
    if bot.getZone == nil or primary.getZone == nil then return false end
    return bot:getZone() == primary:getZone()
end

-- Walk a pool in array order, build a ranked list of eligible candidates.
-- Stable on ties: pool-array index decides tiebreak (earliest wins).
local function rank_pool(pool, eligible_fn, sort_key_fn)
    local out = {}
    for idx, id in ipairs(pool) do
        local bot = GetPlayerByID(id)
        if eligible_fn(bot) then
            table.insert(out, { id = id, key = sort_key_fn(bot), idx = idx })
        end
    end
    table.sort(out, function(a, b)
        if a.key == b.key then return a.idx < b.idx end
        return a.key > b.key  -- always descending for our pools
    end)
    return out
end

-----------------------------------
-- compile_pools: build the pools from spawnedBots. Called at the end of
-- bots_spawn populate. The primary is intentionally excluded from every pool
-- (bots own all fire decisions); its sleep tier is recorded separately for
-- lower-tier suppression only. See the primarySleepTier block below.
-----------------------------------
-- Zone-agnostic: pool MEMBERSHIP is about capability, which doesn't change
-- with location. A bot in a different zone still has Provoke / Stun / Sleep
-- — they just can't act on the current target right now. The zone gate
-- lives in pick_* below, so the pool list stays stable across natural
-- zoning and the picker just looks past stale entries until the cross-zone
-- bot warps back (see #214's warp framing — bots are expected to be co-
-- located in steady state).
function ai_pool.compile_pools(primary, spawnedBots)
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil then return end
    alliance.provokePool  = {}
    alliance.stunPool     = {}
    alliance.bashPool     = {}  -- flat charIds; ability picked live at pick time
    alliance.rdmSleepPool = {}
    alliance.brdSleepPool = {}
    alliance.blmSleepPool = {}

    -- hasSpell is "ever learned it" (spells stay in m_SpellList forever) but
    -- canUseSpell is the authoritative current-job/level/state gate (same
    -- check ai_magic.spell_is_up uses at runtime). Pair them at compile time
    -- so the pool only contains bots whose current main+sub can actually
    -- cast — no compile-time false positives like a current-WHM-L1 who
    -- once learned Stun on BLM-L40.
    local function castable(bot, spellId)
        if not bot:hasSpell(spellId) then return false end
        if bot.canUseSpell and not bot:canUseSpell(spellId) then return false end
        return true
    end
    local function has_sleep_spell(bot)
        return castable(bot, xi.magic.spell.SLEEP_II) or castable(bot, xi.magic.spell.SLEEP)
    end
    -- BRD sleep is Foe Lullaby family (single target). Horde Lullaby
    -- handles the AoE branch via sleepgaSpells (engine treats both as
    -- targeted-AoE sleep). A BRD with Foe Lullaby OR Foe Lullaby II is
    -- pool-eligible — neither is gated on a sub-job.
    local function has_lullaby(bot)
        return castable(bot, xi.magic.spell.FOE_LULLABY_II)
            or castable(bot, xi.magic.spell.FOE_LULLABY)
    end

    local function consider(bot)
        if bot == nil then return end
        local role = alliance.roleMap and alliance.roleMap[bot:getID()]
                  or xi.singleplayer.bots.Role.Idle
        local job  = job_string(bot:getMainJob())

        if role_can_provoke(role) and bot:hasJobAbility(xi.jobAbility.PROVOKE) then
            table.insert(alliance.provokePool, bot:getID())
        end

        if role_can_stun(role, job) and castable(bot, xi.magic.spell.STUN) then
            table.insert(alliance.stunPool, bot:getID())
        end

        if role_can_bash(role, job, bot) then
            table.insert(alliance.bashPool, bot:getID())
        end

        if role_is_mage_or_support(role) and job == 'RDM' and has_sleep_spell(bot) then
            table.insert(alliance.rdmSleepPool, bot:getID())
        end

        -- BRD lands between RDM and BLM in sleep precedence (#217). Brd role
        -- is the natural gate but the lullaby check ensures we don't pool a
        -- BRD too low-level to know any Foe Lullaby tier.
        if role == xi.singleplayer.bots.Role.Brd and has_lullaby(bot) then
            table.insert(alliance.brdSleepPool, bot:getID())
        end

        if role_is_mage_or_support(role) and job == 'BLM' and has_sleep_spell(bot) then
            table.insert(alliance.blmSleepPool, bot:getID())
        end
    end

    -- The primary is intentionally NOT added to any pool: bots own every fire
    -- decision so a human can never block a pick. (A human ranked #1 but not
    -- reacting used to silently drop the interrupt/peel/sleep.) We only record
    -- the primary's sleep TIER here — capability, same spawn-time lifecycle as
    -- pool membership — so a viable primary RDM/BRD can suppress STRICTLY-LOWER
    -- sleep tiers. That viability is re-checked live in pick_sleeper, so a dead
    -- or OOM primary stops suppressing and the lower headless cover.
    alliance.primarySleepTier = nil
    if primary ~= nil then
        local pRole = alliance.roleMap and alliance.roleMap[primary:getID()]
                   or xi.singleplayer.bots.Role.Idle
        local pJob  = job_string(primary:getMainJob())
        if role_is_mage_or_support(pRole) and pJob == 'RDM' and has_sleep_spell(primary) then
            alliance.primarySleepTier = 'rdm'
        elseif pRole == xi.singleplayer.bots.Role.Brd and has_lullaby(primary) then
            alliance.primarySleepTier = 'brd'
        end
    end

    for _, b in pairs(spawnedBots or {}) do consider(b) end

    printf('ai_pool.compile_pools: provoke=%d stun=%d bash=%d rdmSleep=%d brdSleep=%d blmSleep=%d primarySleepTier=%s',
        #alliance.provokePool, #alliance.stunPool, #alliance.bashPool,
        #alliance.rdmSleepPool, #alliance.brdSleepPool, #alliance.blmSleepPool,
        tostring(alliance.primarySleepTier))
end

-----------------------------------
-- Provoke pick.
--   Floor   : HP% >= 30 (below that, tank is too fragile for another mob)
--   Range   : checkDistance <= 20y to targetEntity
--   Recast  : Provoke off recast (ai_ability.ability_off_recast)
--   Sort    : HP% desc
-----------------------------------
local PROVOKE_HP_FLOOR = 30
local PROVOKE_RANGE    = 20

function ai_pool.pick_provoker(targetEntity)
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil or alliance.provokePool == nil then return nil end
    if targetEntity == nil or (targetEntity.isDead and targetEntity:isDead()) then return nil end
    local primary = primary_entity()
    if primary == nil then return nil end

    local ability_off_recast = xi.singleplayer.bots.ability
        and xi.singleplayer.bots.ability.ability_off_recast
    local eligible = function(bot)
        if not alive(bot) or not same_zone(bot, primary) then return false end
        if bot:getHPP() < PROVOKE_HP_FLOOR then return false end
        if bot:checkDistance(targetEntity) > PROVOKE_RANGE then return false end
        if ability_off_recast and not ability_off_recast(bot, 'Provoke') then return false end
        if xi.singleplayer.bots.ai_util.is_busy_actioning(bot) then return false end
        return true
    end
    local ranked = rank_pool(alliance.provokePool, eligible, function(b) return b:getHPP() end)
    return ranked[1] and ranked[1].id or nil
end

function ai_pool.am_i_provoker(bot, targetEntity)
    if bot == nil then return false end
    return ai_pool.pick_provoker(targetEntity) == bot:getID()
end

-----------------------------------
-- Stun pick.
--   Filter  : spell_is_up(STUN) — handles has spell + recast + MP + silence
--             + offensive-line cooldowns. + alive + in zone + in range.
--   Sort    : MP% desc
-----------------------------------
local function spell_is_up_offensive(bot, spellId)
    return xi.singleplayer.bots.magic
       and xi.singleplayer.bots.magic.spell_is_up
       and xi.singleplayer.bots.magic.spell_is_up(bot, spellId, true)
end

local function current_mob_in_range(bot, spellId)
    return xi.singleplayer.bots.magic
       and xi.singleplayer.bots.magic.current_mob_in_range
       and xi.singleplayer.bots.magic.current_mob_in_range(bot, spellId)
end

local function mpp(bot)
    local maxMp = bot.getMaxMP and bot:getMaxMP() or 0
    if maxMp <= 0 then return 0 end
    return (bot.getMP and bot:getMP() or 0) * 100 / maxMp
end

function ai_pool.pick_stunner()
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil or alliance.stunPool == nil then return nil end
    local primary = primary_entity()
    if primary == nil then return nil end

    local eligible = function(bot)
        if not alive(bot) or not same_zone(bot, primary) then return false end
        if not current_mob_in_range(bot, xi.magic.spell.STUN) then return false end
        if not spell_is_up_offensive(bot, xi.magic.spell.STUN) then return false end
        if xi.singleplayer.bots.ai_util.is_busy_actioning(bot) then return false end
        return true
    end
    local ranked = rank_pool(alliance.stunPool, eligible, mpp)
    return ranked[1] and ranked[1].id or nil
end

function ai_pool.am_i_stunner(bot)
    if bot == nil then return false end
    return ai_pool.pick_stunner() == bot:getID()
end

-----------------------------------
-- Bash pick. Bash is melee-range, no MP cost. Same trigger as Stun (mob
-- WS windup) but different fire path because the abilities differ per job.
--   Filter  : alive + in zone + within melee range of the target +
--             ability off recast + not busy actioning
--   Sort    : HP% desc (healthiest bot bashes; getting hit drops them down
--             the order next pick, natural rotation)
-- Returns { id, ability } so the firing role knows which ability name to
-- pass to use_ability. Returns nil if no bashers are eligible.
-----------------------------------
function ai_pool.pick_basher(targetEntity)
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil or alliance.bashPool == nil then return nil end
    if targetEntity == nil or (targetEntity.isDead and targetEntity:isDead()) then return nil end
    local primary = primary_entity()
    if primary == nil then return nil end

    local ability_off_recast = xi.singleplayer.bots.ability
        and xi.singleplayer.bots.ability.ability_off_recast

    local best, bestKey, bestIdx, bestAbility
    for idx, id in ipairs(alliance.bashPool) do
        local bot = GetPlayerByID(id)
        if bot ~= nil and alive(bot) and same_zone(bot, primary)
           and bot:checkDistance(targetEntity) <= bot:getMeleeRange(targetEntity)
           and not xi.singleplayer.bots.ai_util.is_busy_actioning(bot) then
            local ability = bash_ability_for_runtime(bot)
            if ability ~= nil
               and (ability_off_recast == nil or ability_off_recast(bot, ability)) then
                local hpp = bot:getHPP()
                if best == nil or hpp > bestKey or (hpp == bestKey and idx < bestIdx) then
                    best, bestKey, bestIdx, bestAbility = id, hpp, idx, ability
                end
            end
        end
    end
    if best == nil then return nil end
    return { id = best, ability = bestAbility }
end

function ai_pool.am_i_basher(bot, targetEntity)
    if bot == nil then return false end
    local picked = ai_pool.pick_basher(targetEntity)
    return picked ~= nil and picked.id == bot:getID() and picked.ability or false
end

-----------------------------------
-- Sleep pick (RDM → BRD → BLM precedence, per #217).
--   Filter  : pool-appropriate sleep spell is up
--               rdm/blm: SLEEP_II → SLEEP cascade
--               brd:     FOE_LULLABY_II → FOE_LULLABY cascade
--             + alive + in zone + add-target in this bot's sleep range
--             + not is_busy_actioning.
--   Sort    : MP% desc within each pool tier.
--   Tier    : try rdmSleepPool first; if empty after filter, try
--             brdSleepPool; if STILL empty, fall through to blmSleepPool.
--             Lower-tier pools are last-resort so BRD's renewable songs +
--             RDM's enfeebles get priority over the BLM's mage MP economy.
-----------------------------------
-- Any sleep spell from the RDM/BLM family up. Used by their pool gates.
local function any_sleep_spell_up(bot)
    if not spell_is_up_offensive(bot, xi.magic.spell.SLEEP_II) then
        if not spell_is_up_offensive(bot, xi.magic.spell.SLEEP) then return false end
    end
    return true
end
-- Any Foe Lullaby up. BRD's sleep cascade; the AoE branch (Horde Lullaby)
-- is handled separately by ai_magic.get_next_sleepga_spell when there are
-- enough awake adds.
local function any_lullaby_up(bot)
    if not spell_is_up_offensive(bot, xi.magic.spell.FOE_LULLABY_II) then
        if not spell_is_up_offensive(bot, xi.magic.spell.FOE_LULLABY) then return false end
    end
    return true
end

local function has_sleep_target_in_range(bot)
    if xi.singleplayer.bots.magic == nil
       or xi.singleplayer.bots.magic.get_next_sleep_target == nil then return false end
    return xi.singleplayer.bots.magic.get_next_sleep_target(bot) ~= nil
end

-- Pool-specific eligibility: rdm/blm pools use Sleep cascade, brd pool
-- uses Lullaby cascade. spellUpCheck is the function-pointer that does
-- the cascade per pool.
local function pick_from_sleep_pool(pool, primary, spellUpCheck)
    local eligible = function(bot)
        if not alive(bot) or not same_zone(bot, primary) then return false end
        if not spellUpCheck(bot) then return false end
        if not has_sleep_target_in_range(bot) then return false end
        if xi.singleplayer.bots.ai_util.is_busy_actioning(bot) then return false end
        return true
    end
    local ranked = rank_pool(pool, eligible, mpp)
    return ranked[1] and ranked[1].id or nil
end

-- Is the primary CURRENTLY a viable sleeper for its recorded tier? The primary
-- is never a fire candidate (it's in no pool), but a viable primary RDM/BRD
-- suppresses strictly-lower sleep tiers so headless BRD/BLM don't step on the
-- human's role. Same eligibility bar the pools use — alive + the tier's sleep
-- spell up (spell_is_up live-checks MP / recast / silence). Zone is implicit
-- (an entity is always in its own zone). Dead / OOM primary → not viable →
-- no suppression → lower headless cover.
local function primary_viable_sleeper(primary, tier)
    if primary == nil or tier == nil then return false end
    if not alive(primary) then return false end
    if tier == 'rdm' then return any_sleep_spell_up(primary) end
    if tier == 'brd' then return any_lullaby_up(primary) end
    return false
end

function ai_pool.pick_sleeper()
    local alliance = xi.singleplayer.bots.alliance
    if alliance == nil then return nil end
    local primary = primary_entity()
    if primary == nil then return nil end

    -- Primary's sleep tier ('rdm'|'brd'|nil), captured at compile time. Used
    -- only to suppress strictly-lower tiers while the primary is viable.
    local tier = alliance.primarySleepTier

    local rdm = pick_from_sleep_pool(alliance.rdmSleepPool or {}, primary, any_sleep_spell_up)
    if rdm ~= nil then return rdm end
    -- A viable primary RDM owns the top tier → don't drop to BRD/BLM.
    if tier == 'rdm' and primary_viable_sleeper(primary, tier) then return nil end

    local brd = pick_from_sleep_pool(alliance.brdSleepPool or {}, primary, any_lullaby_up)
    if brd ~= nil then return brd end
    -- A viable primary RDM or BRD owns a higher tier → don't drop to BLM.
    if (tier == 'rdm' or tier == 'brd') and primary_viable_sleeper(primary, tier) then return nil end

    return pick_from_sleep_pool(alliance.blmSleepPool or {}, primary, any_sleep_spell_up)
end

function ai_pool.am_i_sleeper(bot)
    if bot == nil then return false end
    return ai_pool.pick_sleeper() == bot:getID()
end

return m
