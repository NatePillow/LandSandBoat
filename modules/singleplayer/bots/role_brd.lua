-----------------------------------
-- role_brd (#220) — Bard support role.
--
-- BRD's job is keeping party-scoped songs up on alliance members. Songs
-- are AoE around the singer (target = self), so to land DIFFERENT songs
-- on front-line (Tank+Melee) vs back-line (mages) the BRD physically
-- moves between groups during the song cycle:
--
--   walk to front centroid → cast front slot 1 → cast front slot 2
--   walk to back centroid  → cast back slot 1  → cast back slot 2
--   idle at back (home position) until renewal threshold
--
-- Front first so the cycle ends with BRD naturally at the back (their
-- home — Ballad-aligned for self-MP regen). Refresh BEFORE expiry so
-- buffs never lapse on the party.
--
-- Sub-job assumption: /WHM (75-era default). Gives Cure I-III plus the
-- standard status removes (Poisona / Paralyna / Silena / Stona). Cure +
-- status logic delegates to the same ai_magic helpers role_heal uses.
--
-- Ballad stacking: per src/map/status_effect_container.cpp::ApplyBardEffect,
-- the engine treats songs as separate slots if they differ in TIER OR
-- effect id. Ballad III + Ballad II both stay active on a target since
-- they're different tiers under the same BALLAD effect. That's why the
-- back-roster default is "best Ballad + 2nd-best Ballad", not "best
-- Ballad + March" — matches retail 75-era mage-pt practice.
--
-- Songs are PARTY-scoped, not alliance-scoped. A BRD in pt1 sings to
-- pt1 only. Pt2 needs its own BRD for coverage there.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('role_brd')

xi              = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.brd = xi.singleplayer.bots.brd or {}
local role_brd = xi.singleplayer.bots.brd

-----------------------------------
-- Song family table.
-- Each entry: { effectId, tiers = [highest → lowest spellId], group }
-- 'group' = 'front' / 'back' / 'either' — drives target-centroid choice.
-- Tier order top-down within each family so best_tier() picks the highest
-- one the BRD has learned.
-----------------------------------
local SONG_FAMILIES = {
    front_minuet = {
        effectId = xi.effect.MINUET,
        group    = 'front',
        tiers    = {
            xi.magic.spell.VALOR_MINUET_V,
            xi.magic.spell.VALOR_MINUET_IV,
            xi.magic.spell.VALOR_MINUET_III,
            xi.magic.spell.VALOR_MINUET_II,
            xi.magic.spell.VALOR_MINUET,
        },
    },
    front_madrigal = {
        effectId = xi.effect.MADRIGAL,
        group    = 'front',
        tiers    = {
            xi.magic.spell.BLADE_MADRIGAL,
            xi.magic.spell.SWORD_MADRIGAL,
        },
    },
    back_ballad_a = {
        effectId = xi.effect.BALLAD,
        group    = 'back',
        tiers    = {
            xi.magic.spell.MAGES_BALLAD_III,
            xi.magic.spell.MAGES_BALLAD_II,
            xi.magic.spell.MAGES_BALLAD,
        },
    },
    back_ballad_b = {
        effectId = xi.effect.BALLAD,
        group    = 'back',
        -- Skip the highest tier — that slot is the "a" version. This slot
        -- gets the SECOND-best so both slots coexist on the target (engine's
        -- ApplyBardEffect overwrites only on same-tier matches).
        tiers    = {
            xi.magic.spell.MAGES_BALLAD_II,
            xi.magic.spell.MAGES_BALLAD,
        },
    },
}

-- Active slot order. Two front, two back. Front first so BRD ends at back.
local SLOT_ORDER = { 'front_minuet', 'front_madrigal', 'back_ballad_a', 'back_ballad_b' }

-----------------------------------
-- Tunables.
-----------------------------------
-- Refresh when remaining duration drops below this. 30s gives enough
-- headroom that the cycle can complete without any slot lapsing — 4
-- songs × ~3s cast + walking time fits comfortably in 30s.
local RENEW_THRESHOLD_S = 30

-- "Close enough to sing for this group". Default FFXI song radius without
-- a string instrument is around 10y; string instruments amplify it. We
-- pick 10y as the conservative gate so BRD always walks into safe range
-- before casting. A gearset that auto-swaps to a string instrument for
-- songs gives extra coverage at no logic cost.
local SONG_RANGE_Y = 10.0

-- (The old back-cast split-baby defer + BACK_DISPLACE_Y offset are gone —
-- role_brd.best_cast_point now picks the cast spot that covers the most
-- eligible and fewest ineligible, so bleed avoidance is intrinsic.)

-----------------------------------
-- Helpers.
-----------------------------------
local function planar_dist(ax, az, bx, bz)
    local dx = bx - ax
    local dz = bz - az
    return math.sqrt(dx * dx + dz * dz)
end

-- Pick the highest-tier spell from a family that the BRD can cast right now.
-- Returns nil if none of the family's spells are learned + castable.
local function best_tier(bot, family)
    for _, spellId in ipairs(family.tiers) do
        if bot:hasSpell(spellId)
           and (not bot.canUseSpell or bot:canUseSpell(spellId))
           and not bot:hasRecast(xi.recast.MAGIC, spellId) then
            return spellId
        end
    end
    return nil
end

-- For slot_b in a family with same effect as slot_a: skip whatever tier
-- slot_a is currently using, so we get the SECOND-best for slot_b. Returns
-- the spellId that slot_b should cast, or nil if no second-best is castable.
local function best_tier_excluding(bot, family, excludeSpellId)
    for _, spellId in ipairs(family.tiers) do
        if spellId ~= excludeSpellId
           and bot:hasSpell(spellId)
           and (not bot.canUseSpell or bot:canUseSpell(spellId))
           and not bot:hasRecast(xi.recast.MAGIC, spellId) then
            return spellId
        end
    end
    return nil
end

-- True iff the bot has the given song's effect active with > RENEW_THRESHOLD
-- seconds remaining. We look at the bot's OWN effects rather than a party
-- member's because songs land on everyone in range simultaneously — if BRD
-- doesn't have it, the rest of the group doesn't either.
--
-- For multi-tier slots (Ballad a vs b), we ALSO need to verify the active
-- tier matches what we'd cast. Otherwise a Ballad III cast covers both
-- slot_a (best) and slot_a's tier-check, but slot_b would think Ballad is
-- "up" and never get cast. Solved by checking by tier: getStatusEffect for
-- the effect, then comparing tier to the spellId we'd cast.
local function song_up_for_tier(bot, effectId, spellIdToCast, family)
    if spellIdToCast == nil then return true end  -- nothing to cast → treat as "covered"
    -- Find the tier number for spellIdToCast by walking the family's tier list.
    local castTier = nil
    for idx, sid in ipairs(family.tiers) do
        if sid == spellIdToCast then
            -- The "tier" in the engine is the 1st column of pTable in
            -- enhancing_song.lua. For Ballad: I=1, II=2, III=3. The tiers
            -- array here is best-first, so idx=1 is the highest tier the
            -- BRD has. Map idx → tier number by family size.
            castTier = #family.tiers - idx + 1
            -- Special-case for back_ballad_b which skips the highest:
            -- family.tiers[1] = Ballad II if III is also in tiers list of
            -- _a; but for _b we deliberately offset.
            break
        end
    end
    -- Walk all instances of the effect on the bot; if any match the same
    -- tier we'd cast AND have enough time left, the slot is covered.
    -- Using getStatusEffects (plural) since multiple BALLAD instances can
    -- exist on the same target.
    if bot.getStatusEffects == nil then return false end
    local effects = bot:getStatusEffects() or {}
    local now = os.time()
    for _, eff in ipairs(effects) do
        if eff:getEffectType() == effectId then
            local startTime = (eff.getStartTime and eff:getStartTime()) or 0
            local duration  = (eff.getDuration and eff:getDuration() or 0) / 1000
            local remaining = duration - (now - startTime)
            -- For non-Ballad slots there's only one tier per family so the
            -- tier-match check is trivially true. For Ballad a vs b we
            -- compare against castTier so each slot tracks its own tier.
            local effTier = (eff.getTier and eff:getTier()) or 0
            if (castTier == nil or effTier == castTier or effectId ~= xi.effect.BALLAD)
               and remaining > RENEW_THRESHOLD_S then
                return true
            end
        end
    end
    return false
end

-----------------------------------
-- Pianissimo single-target Ballad cleanup.
--
-- Gap: a PLD (or other MP-hungry front-liner) stands in the melee cluster and
-- catches the front-line AoE songs (Minuet/Madrigal) instead of the back-line
-- Ballad, so it starves for MP. Rather than reshape the formation, use
-- Pianissimo (BRD JA, 5s recast) to make the NEXT song single-target and drop
-- a Ballad straight onto that member wherever it stands. Scales per job via the
-- target finders: PLD always wants 2 Ballads (never melee buffs); DRK wants 1,
-- and only while its MP is low.
--
-- Two-step by nature (JA one tick, single-target song the next). While the
-- PIANISSIMO effect is up, valid_pianissimo_active() gates the normal refresh
-- rotation off so a group song can't eat the effect and silently turn
-- single-target; the pianissimo branches consume it with the pending Ballad
-- instead. Engine single-target-when-PIANISSIMO handling lives in
-- combat/magic_aoe.lua.
-----------------------------------
local BALLAD_FAMILY = SONG_FAMILIES.back_ballad_a

-- Throwaway song to consume a stranded Pianissimo effect (see the sink branch
-- in role_brd.tick). Knight's Minne is the BRD's Lv1 song and is NOT one of the
-- rotation-tracked families (Minuet/Madrigal/Ballad), so a single-target Minne
-- on the BRD burns the effect without disturbing song coverage tracking.
local PIANISSIMO_SINK_SPELL = xi.magic.spell.KNIGHTS_MINNE

-- Count of active Ballad instances (any tier) on a member.
local function member_ballad_count(member)
    if member.getStatusEffects == nil then return 0 end
    local n = 0
    for _, eff in ipairs(member:getStatusEffects() or {}) do
        if eff:getEffectType() == xi.effect.BALLAD then
            n = n + 1
        end
    end
    return n
end

-- Highest-tier Ballad the BRD can cast that `member` doesn't already have at
-- that tier. Reuses song_up_for_tier so tier stacking matches the normal
-- back-line rotation (Ballad III + II coexist as separate slots).
local function best_missing_ballad(bot, member)
    for _, spellId in ipairs(BALLAD_FAMILY.tiers) do
        if bot:hasSpell(spellId)
           and (not bot.canUseSpell or bot:canUseSpell(spellId))
           and not bot:hasRecast(xi.recast.MAGIC, spellId)
           and not song_up_for_tier(member, xi.effect.BALLAD, spellId, BALLAD_FAMILY) then
            return spellId
        end
    end
    return nil
end

-- First in-range party member of `job` that still wants a Ballad.
--   want   - desired active Ballad count (PLD 2, DRK 1).
--   mpCeil - if set, member only qualifies while its MP% is below this.
-- Range-gated on SONG_RANGE_Y so we never commit Pianissimo for a member the
-- single-target song can't reach (which would strand the effect).
local function pianissimo_target(bot, job, want, mpCeil)
    local bx, bz = bot:getXPos(), bot:getZPos()
    for _, m in ipairs(bot.getParty and bot:getParty() or {}) do
        if m ~= nil
           and m:getID() ~= bot:getID()
           and m:getHPP() > 0
           and xi.singleplayer.bots.magic.job_string(m:getMainJob()) == job
           and (mpCeil == nil or m:getMPP() < mpCeil)
           and member_ballad_count(m) < want
           and planar_dist(bx, bz, m:getXPos(), m:getZPos()) <= SONG_RANGE_Y
           and best_missing_ballad(bot, m) ~= nil then
            return m
        end
    end
    return nil
end

function role_brd.pianissimo_pld_target(bot)
    return pianissimo_target(bot, 'PLD', 2, nil)
end

function role_brd.pianissimo_drk_target(bot)
    return pianissimo_target(bot, 'DRK', 1, 25)
end

-- Combined action for both the PLD and DRK cases (mirrors role_melee's
-- use_weapon_skill state machine: called every tick the branch fires,
-- advancing across ticks).
--   no PIANISSIMO effect yet -> fire the JA (self-target).
--   PIANISSIMO active        -> cast the best Ballad `member` lacks; the engine
--                               makes it single-target and consumes the effect.
function role_brd.pianissimo_ballad(bot, member)
    if member == nil then return end
    if not bot:hasStatusEffect(xi.effect.PIANISSIMO) then
        xi.singleplayer.bots.ability.use_pianissimo(bot)
        return
    end
    local spellId = best_missing_ballad(bot, member)
    if spellId ~= nil then
        bot:castSpell(spellId, member)
    end
end

-- True while a committed Pianissimo single-target song is pending: the JA
-- effect is up, waiting for the next song to consume it. Gates the normal
-- refresh rotation (see role_brd.tick) so a group song can't eat the effect.
local function valid_pianissimo_active(bot)
    return bot:hasStatusEffect(xi.effect.PIANISSIMO)
end

-- Classify party members into front / back groups by their role. The
-- alliance.roleMap holds Role enum values per charId.
-- Song groups are split by JOB, not by the assigned combat ROLE: a PLD tank
-- wants Ballad (MP for cures/Flash/enmity JAs) while a NIN tank wants Minuet, so
-- splitting on the Tank role is wrong. Mages + PLD go to the back/Ballad group;
-- every other job (NIN, DRK, RUN, ... included) melees up front. Edit this set
-- to move a job. (The BRD itself is a BRD → back, so its own Ballad applies;
-- best_cast_point excludes the BRD from coverage anyway.)
local BALLAD_JOBS = {
    [xi.job.WHM] = true, [xi.job.BLM] = true, [xi.job.RDM] = true,
    [xi.job.PLD] = true, [xi.job.BRD] = true, [xi.job.SMN] = true,
    [xi.job.SCH] = true, [xi.job.GEO] = true,
}

local function classify_party(bot)
    local front, back = {}, {}
    -- bot:getParty() returns a list of party member entities (incl. self).
    local party = bot.getParty and bot:getParty() or {}
    for _, member in ipairs(party) do
        if member:getHPP() > 0 then   -- don't waste coverage on corpses
            if BALLAD_JOBS[member:getMainJob()] then
                table.insert(back, member)
            else
                table.insert(front, member)
            end
        end
    end
    return front, back
end

-----------------------------------
-- Full cast-point positioner (Levels 1 + 2, unified).
--
-- Place a SONG_RANGE_Y disk to MAXIMIZE eligible members enclosed, then (tie-
-- break) MINIMIZE ineligible enclosed. The coverage counts are piecewise-
-- constant in the cast position — they only change as the disk edge crosses a
-- member, i.e. as the center crosses that member's radius-R circle — so an
-- optimum always sits at an arrangement VERTEX: a member's own position, or a
-- pairwise intersection of two radius-R circles. We enumerate those, score each,
-- keep the best. Exact for these tiny group sizes; no gradient/search.
--
-- Score = eligIn - w*ineligIn:
--   small w (< 1/maxIneligible) = lexicographic (cover most; bleed breaks ties)
--   w = 1                       = 1-for-1 trade
--   larger w                    = avoid bleed harder
-- BRD_INELIGIBLE_W sits in the lexicographic regime by default.
--
-- Range tests use a small dead-band: eligible counts out to R+EDGE (inclusive),
-- ineligible only within R-EDGE (so a candidate grazing an ineligible member's
-- circle sheds it). The BRD is excluded from both sets (it's always at the cast
-- point). Returns cx, cy, cz, eligCovered  (nil if there are no eligible).
-----------------------------------
local BRD_INELIGIBLE_W = 0.05
local CAST_EDGE        = 0.05   -- yalms of edge dead-band
local CAST_ARRIVE_Y    = 2.0    -- close enough to the computed point to cast

-- Radius-R circle-circle intersection points of centers a,b (0, 1, or 2),
-- appended to `out`. Both circles share radius R.
local function circle_intersections(ax, az, bx, bz, R, out)
    local dx, dz = bx - ax, bz - az
    local d = math.sqrt(dx * dx + dz * dz)
    if d < 1e-6 or d > 2 * R then return end     -- coincident, or too far to meet
    local h2 = R * R - (d * 0.5) * (d * 0.5)
    if h2 < 0 then return end
    local h  = math.sqrt(h2)
    local mx, mz = ax + dx * 0.5, az + dz * 0.5  -- midpoint of centers
    local ux, uz = -dz / d, dx / d               -- unit perpendicular
    out[#out + 1] = { x = mx + ux * h, z = mz + uz * h }
    if h > 1e-6 then out[#out + 1] = { x = mx - ux * h, z = mz - uz * h } end
end

function role_brd.best_cast_point(bot, eligible, ineligible)
    if eligible == nil or #eligible == 0 then return nil end
    local R    = SONG_RANGE_Y
    local myId = bot:getID()

    -- Member positions, BRD excluded.
    local elig, inelig = {}, {}
    for _, m in ipairs(eligible) do
        if m:getID() ~= myId then elig[#elig + 1] = { x = m:getXPos(), z = m:getZPos() } end
    end
    for _, m in ipairs(ineligible or {}) do
        if m:getID() ~= myId then inelig[#inelig + 1] = { x = m:getXPos(), z = m:getZPos() } end
    end
    if #elig == 0 then return nil end

    -- Candidate stand-points: each eligible position + all pairwise R-circle
    -- intersections over ALL members (ineligible circles matter too — the
    -- least-bleed covering point grazes an ineligible circle).
    local cands = {}
    for _, p in ipairs(elig) do cands[#cands + 1] = { x = p.x, z = p.z } end
    local all = {}
    for _, p in ipairs(elig)   do all[#all + 1] = p end
    for _, p in ipairs(inelig) do all[#all + 1] = p end
    for i = 1, #all do
        for j = i + 1, #all do
            circle_intersections(all[i].x, all[i].z, all[j].x, all[j].z, R, cands)
        end
    end

    local reIn2  = (R + CAST_EDGE) * (R + CAST_EDGE)   -- eligible in-range (sq)
    local riIn2  = (R - CAST_EDGE) * (R - CAST_EDGE)   -- ineligible bled (sq)
    local best, bestScore, bestElig, bestBleed = nil, -math.huge, 0, 0
    for _, c in ipairs(cands) do
        local ein, iin = 0, 0
        for _, p in ipairs(elig) do
            local dx, dz = p.x - c.x, p.z - c.z
            if dx * dx + dz * dz <= reIn2 then ein = ein + 1 end
        end
        for _, p in ipairs(inelig) do
            local dx, dz = p.x - c.x, p.z - c.z
            if dx * dx + dz * dz < riIn2 then iin = iin + 1 end
        end
        local score = ein - BRD_INELIGIBLE_W * iin
        if score > bestScore then
            best, bestScore, bestElig, bestBleed = c, score, ein, iin
        end
    end
    if best == nil then return nil end
    return best.x, bot:getYPos(), best.z, bestElig, bestBleed
end

-- (eligIn, ineligIn) if the BRD cast from world point (px,pz) right now — same
-- range tests and BRD-exclusion as best_cast_point. Used to decide whether the
-- BRD's CURRENT spot is already as good as the computed optimum (so it casts in
-- place instead of chasing a marginally-better point tick to tick).
function role_brd.coverage_at(bot, px, pz, eligible, ineligible)
    local myId  = bot:getID()
    local reIn2 = (SONG_RANGE_Y + CAST_EDGE) * (SONG_RANGE_Y + CAST_EDGE)
    local riIn2 = (SONG_RANGE_Y - CAST_EDGE) * (SONG_RANGE_Y - CAST_EDGE)
    local ein, iin = 0, 0
    for _, m in ipairs(eligible or {}) do
        if m:getID() ~= myId then
            local dx, dz = m:getXPos() - px, m:getZPos() - pz
            if dx * dx + dz * dz <= reIn2 then ein = ein + 1 end
        end
    end
    for _, m in ipairs(ineligible or {}) do
        if m:getID() ~= myId then
            local dx, dz = m:getXPos() - px, m:getZPos() - pz
            if dx * dx + dz * dz < riIn2 then iin = iin + 1 end
        end
    end
    return ein, iin
end

-----------------------------------
function role_brd.on_load(bot)
end

-----------------------------------
-- Per-bot song-roster override (#252). Slot indices follow SLOT_ORDER:
--   0 = front_minuet
--   1 = front_madrigal
--   2 = back_ballad_a
--   3 = back_ballad_b
-- A non-zero entry pins that slot to the exact spell ID. A zero entry =
-- "auto" sentinel — the slot falls through to best_tier (highest tier
-- the BRD has learned + can currently cast).
-----------------------------------
function role_brd.set_song_roster(primary, botName, slot0, slot1, slot2, slot3)
    if primary == nil or botName == nil or botName == '' then return end
    local A = xi.singleplayer.bots.alliance
    if A == nil or A.bot == nil then return end

    -- Resolve botName → entity → charId. Look in the alliance (primary or
    -- any owned headless). Silently no-op if the name doesn't match.
    local target = nil
    if primary:getName() == botName then
        target = primary
    else
        local headlessList = A.headlessCharIds or {}
        for _, id in ipairs(headlessList) do
            local h = GetPlayerByID(id)
            if h and h:getName() == botName then target = h; break end
        end
    end
    if target == nil then
        printf('role_brd.set_song_roster: no bot "%s" in alliance', botName)
        return
    end

    local state = xi.singleplayer.bots.ensure_bot(target:getID())
    state.songRoster = {
        tonumber(slot0) or 0,
        tonumber(slot1) or 0,
        tonumber(slot2) or 0,
        tonumber(slot3) or 0,
    }
    printf('role_brd.set_song_roster: %s -> [%d, %d, %d, %d]',
        botName, state.songRoster[1], state.songRoster[2],
        state.songRoster[3], state.songRoster[4])
end

-----------------------------------
-- role_brd.try_refresh_song
--
-- Walks SLOT_ORDER; the first slot with a stale song fires an action (walk to
-- the computed cast point, or cast in place) and returns true. Returns false
-- when every slot is already fresh. One song per tick.
--
-- Positioning is delegated to role_brd.best_cast_point: eligible = who should
-- get this song (front melees for Minuet/Madrigal, back mages+PLD for Ballad),
-- ineligible = the other group (a bleed overwrites their song). The positioner
-- picks the spot covering the most eligible / fewest ineligible.
-----------------------------------
function role_brd.try_refresh_song(bot, ctx, front, back, roster)
    local log = ctx.log

    for slotIdx, slotKey in ipairs(SLOT_ORDER) do
        local family = SONG_FAMILIES[slotKey]
        if family ~= nil then
            -- Determine which spell THIS slot would cast.
            local spellId
            local override = roster and roster[slotIdx] or 0
            if override and override > 0
               and bot:hasSpell(override)
               and (not bot.canUseSpell or bot:canUseSpell(override))
               and not bot:hasRecast(xi.recast.MAGIC, override) then
                -- Explicit override pin. Skip family-tier resolution.
                spellId = override
            elseif slotKey == 'back_ballad_b' then
                -- Slot b excludes whatever slot a is using so both tiers
                -- coexist on the target. Resolve slot a first.
                local slotA = (roster and roster[3] and roster[3] > 0)
                              and roster[3]
                              or best_tier(bot, SONG_FAMILIES.back_ballad_a)
                spellId = best_tier_excluding(bot, family, slotA)
            else
                spellId = best_tier(bot, family)
            end

            if spellId ~= nil and not song_up_for_tier(bot, family.effectId, spellId, family) then
                -- Eligible = this song's target group; ineligible = the other.
                local eligible, ineligible
                if family.group == 'front' then
                    eligible, ineligible = front, back
                else
                    eligible, ineligible = back, front
                end
                if #eligible == 0 then
                    goto next_slot   -- nobody to land this song on
                end

                local tx, ty, tz, optCov, optBleed =
                    role_brd.best_cast_point(bot, eligible, ineligible)
                if tx == nil then
                    goto next_slot
                end

                -- Cast in place if the BRD's current spot already matches the
                -- optimum (same coverage, no worse bleed), or if we're right at
                -- the computed point — avoids chasing a marginally-better spot
                -- tick to tick. Otherwise walk to it (consume-on-read override).
                local mx, mz = bot:getXPos(), bot:getZPos()
                local hereCov, hereBleed =
                    role_brd.coverage_at(bot, mx, mz, eligible, ineligible)
                if (hereCov >= optCov and hereBleed <= optBleed)
                   or planar_dist(mx, mz, tx, tz) <= CAST_ARRIVE_Y then
                    log(string.format('song %s (slot %s)', spellId, slotKey))
                    bot:castSpell(spellId, bot)
                    return true
                end

                log(string.format('walk to %s cast point', family.group))
                local state = xi.singleplayer.bots.ensure_bot(bot:getID())
                state.roleMovementTarget = { x = tx, y = ty, z = tz }
                return true
            end
        end
        ::next_slot::
    end
    return false
end

function role_brd.tick(bot)
    if xi.singleplayer.bots.ai_util.is_force_rested(bot) then return end
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.tick then
        xi.singleplayer.bots.ai_equip_swap.tick(bot)
    end
    if xi.singleplayer.bots.magic.process_pre_cast_checks(bot) then return end

    local ctx    = xi.singleplayer.bots.magic.build_whm_ctx(bot, 'AutoBrd')
    local front, back = classify_party(bot)
    local roster = xi.singleplayer.bots.ensure_bot(bot:getID()).songRoster

    local magic = xi.singleplayer.bots.magic

    if magic.can_sleep_add and magic.can_sleep_add(bot) then
        ctx.log('lullaby_add')
        magic.sleep_add(bot)
    elseif not valid_pianissimo_active(bot) and role_brd.try_refresh_song(bot, ctx, front, back, roster) then
        ctx.log('refresh_song')
    elseif role_brd.pianissimo_pld_target(bot) ~= nil and (valid_pianissimo_active(bot) or xi.singleplayer.bots.ability.can_use_pianissimo(bot)) then
        ctx.log('pianissimo_pld')
        role_brd.pianissimo_ballad(bot, role_brd.pianissimo_pld_target(bot))
    elseif role_brd.pianissimo_drk_target(bot) ~= nil and (valid_pianissimo_active(bot) or xi.singleplayer.bots.ability.can_use_pianissimo(bot)) then
        ctx.log('pianissimo_drk')
        role_brd.pianissimo_ballad(bot, role_brd.pianissimo_drk_target(bot))
    elseif valid_pianissimo_active(bot) and magic.spell_is_up(bot, PIANISSIMO_SINK_SPELL, false) then
        ctx.log('pianissimo_sink_self')
        bot:castSpell(PIANISSIMO_SINK_SPELL, bot)
    elseif ctx.activeTarget and magic.can_magic_finale(bot) then
        ctx.log('magic_finale')
        magic.cast_magic_finale(bot)
    elseif ctx.activeTarget and magic.can_use_elegy(bot) then
        ctx.log('elegy')
        magic.cast_elegy(bot)
    elseif ctx.activeTarget and magic.can_use_foe_requiem(bot) then
        ctx.log('foe_requiem')
        magic.cast_foe_requiem(bot)
    elseif ctx.activeTarget and magic.can_use_threnody(bot) then
        ctx.log('threnody')
        magic.cast_threnody(bot)
    else
        magic.whm_cascade(bot, ctx)
    end
end

return m
