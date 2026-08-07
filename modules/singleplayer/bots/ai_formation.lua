-----------------------------------
-- ai_formation: per-role positioning logic shared across bot AI.
--
-- Replaces the ad-hoc stop-point math that used to live in autoai.lua's
-- runMovementTick. Captures two distinct positioning contexts:
--
--   BATTLE   (alliance is engaged on a mob)
--     - tank   : hold position (engage logic owns movement)
--     - melee  : arc behind mob from tank's perspective
--     - mages  : cluster at one perpendicular point off the tank-mob axis
--     - no-tank fallback: front role picks first melee in priority order
--       PLD > RUN > NIN > WAR > SAM > MNK > any other
--
--   WALKING  (alliance is idle / following primary)
--     - Camp   : assist stays anchored within 10y of a camp point; doesn't
--                proactively pull mobs (add-detection still engages); other
--                bots trail assist naturally so they end up at camp too.
--     - Column : single file behind primary, ordered assist → melees → mages.
--                Slot 1 sits 1.0y back, every further slot adds 0.5y.
--                Declump skipped — line stays tight.
--     - Rows   : two rank-and-file rows behind primary, bucketed by job.
--                Front row (DD/tank-shaped): WAR/MNK/THF/PLD/DRK/BST/DRG/
--                NIN/SAM/RNG/PUP/DNC/RUN/COR/BLU.
--                Back row (mages + support): WHM/BLM/RDM/BRD/SMN/SCH/GEO.
--                Up to 3 per row; overflow spills to a sub-row 1.0y behind.
--                Rows centered on the behind-axis, 1.0y between adjacent
--                slots. Declump skipped (would smear the formation).
--
-- Declumping uses a stable per-bot direction (declump_unit, derived from
-- charId so positions don't wiggle tick-to-tick) at varying magnitude
-- depending on context:
--   * Walking `camp`: UNIVERSAL — every bot (melee + mage) gets a full
--                     DECLUMP_RADIUS (1.5y) offset around its camp stop
--                     point so they don't stack while idle.
--   * Battle `spread` and `tight`: MAGES ONLY — each mage gets a 1.0y
--                     scatter around its cluster center so the back-line
--                     doesn't stack. Melees use precise slot math and
--                     skip scatter to keep the formation shape clean.
--   * Walking `column` and `role`: no scatter — those formations compute
--                     precise stop points and stacking is impossible by
--                     construction.
--
-- ----------------------------------------------------------------------
-- Mage distance vs Provoke (17.8y) — keep in mind when adding formations.
-- ----------------------------------------------------------------------
-- When a hated mage takes a swing, it's almost always because an add
-- pathfound to them and stopped at swing distance ≈ mage position. At
-- THAT moment the tank's Provoke gate is tank-to-add distance ≤ 17.8y.
--
-- Worked example, 'spread' (mage at 12y perpendicular, tank at melee on
-- front axis ≈ 3y from mob):
--                                            tank↔add distance   Voke slack
--   * Clean spread, no scatter                12.37y              5.4y
--   * Worst-case +1y mage scatter outward     13.34y              4.5y
--   * Add stops 3y short of mage              15.30y              2.5y
--   * Mob drifted +2y in-fight (tank held)    13.00y              4.8y
--   * Worst-of-all: scatter + drift + early   15.81y              2.0y
--
-- 'tight' (mage at 5y behind mob) is always well inside Voke range.
--
-- The geometric ceiling for "Voke always works without the tank moving":
--   max_mage_distance ≤ sqrt(17.8² − meleeRadius²) − scatter − drift_budget
-- With meleeRadius ≈ 3y, scatter 1y, a 2y drift budget:
--   max_mage_distance ≤ sqrt(316.84 − 9) − 1 − 2 ≈ 14.5y
--
-- So 'spread' at 12y is fine. Any NEW formation that pushes mages past
-- ~14y from mob risks Voke whiffing on adds — either tighten the mage
-- distance, add a "tank chases on hated-mage" branch in battle_target,
-- or implement the mage-retreats-to-tank fallback that was considered
-- and skipped (didn't change anything for 'spread'/'tight'). The mage-
-- retreat pattern also helps post-Voke convergence + tank Cure/Flash
-- radius regardless of Voke range, so it's a worthwhile follow-up for
-- non-Voke reasons even at safe mage distances.
-----------------------------------
require('modules/module_utils')

local m = Module:new('ai_formation')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.ai_formation = xi.singleplayer.bots.ai_formation or {}
local ai_formation = xi.singleplayer.bots.ai_formation

-----------------------------------
-- Default formation names. The UI dropdown source.
-- Battle has 2 non-'off' options; walking has 4. User changes via Setup tab.
-----------------------------------
-- "off" is a sentinel meaning "no formation override — use the caller's
-- ad-hoc movement logic in ai_move.lua". target_for() returns nil for it
-- so the caller's existing fallback path runs unchanged. Lets users opt
-- out of formations entirely while keeping the infrastructure dormant.
--
-- Battle (melee radius is hitbox-aware: bot:getMeleeRange(mob) - 1.0,
-- floored at 2y, so positioning matches the engine's "in range" gate):
--   spread — tank front, melees arc behind mob at meleeRadius with 30°
--            spacing between slots; mages cluster ~12y perpendicular off
--            the tank-mob axis with per-mage scatter.
--   tight  — tank front, melees fan to BOTH sides at meleeRadius starting
--            at ±90° (perpendicular) and tilting back 15° per outer slot;
--            mages clustered ~5y directly behind mob with per-mage scatter.
--   AoE    — for fights where staying out of the mob's AoE radius matters
--            more than DPS uptime. Tank + melees identical to 'tight' (tank
--            front, melees fanned on sides). MAGES sample 36 candidate
--            points on a ring around the mob and pick the one most aligned
--            with the direction of primary from the mob — biases retreat
--            "back the way the party came." All mages share the same
--            candidate list and converge on the same anchor point; existing
--            DECLUMP_RADIUS keeps them from literally overlapping.
--
--            Radius-shrink auto-correct: the sampler tries AOE_MAGE_RADIUS
--            first, then shrinks 17→15→13→11→9→7→5 until it finds a ring
--            where at least one candidate keeps every core party member
--            (anyone within AOE_CORE_PARTY_RADIUS of the mob) inside
--            AOE_MAX_CAST_RANGE. This handles the "positioning noise +
--            worst-case melee scatter puts mage 1-2y over Cure IV range"
--            edge case: the mage backs off as far as possible while still
--            being able to reach the mob-cluster. Pullers (out pulling)
--            and traveling members are naturally excluded from the reach
--            constraint by the CORE_PARTY_RADIUS filter — those roles
--            manage their own health.
--
--   Casual — a loose surround, no fixed slots. Tank walks to the NEAREST spot
--            on the melee ring; melees disperse around the ring (a distinct
--            quadrant each) so they surround rather than clump; mages each walk
--            to the CLOSEST point on a ~8y ring (CASUAL_MAGE_RADIUS). Everyone
--            follows the mob (recomputed per tick). No tank-hate discipline —
--            for relaxed fights where "bodies around the mob" is enough.
--
-- Walking:
--   assist — fall through to caller's pre-formation follow logic (legacy).
--   camp   — pin at the camp anchor (set when entering camp); declump
--            radius 1.5y per bot. CAMP_LEASH_YALMS caps how far assist
--            may chase mobs during combat (mob comes to them).
--   column — single-file behind the front bot, 0.5y spacing, no declump.
--   rows   — structured rank-and-file by role, 0.5y intra-row spacing.
ai_formation.BATTLE_FORMATIONS  = { 'off', 'spread', 'tight', 'AoE', 'Casual' }
ai_formation.WALKING_FORMATIONS = { 'off', 'legacy', 'camp', 'column', 'rows' }

-- Casual formation: mages walk to the closest point on this mob-centered ring
-- (~8y — a comfortable cast distance, well inside Cure/nuke range), and the
-- tank + melees surround at melee range. No fixed slots — everyone picks the
-- nearest reachable spot on their ring and follows the mob.
ai_formation.CASUAL_MAGE_RADIUS = 8.0

-- AoE mage-anchor MAX radius. Starting radius the sampler tries first —
-- max distance from mob while still (usually) inside cast range. Party-scope
-- healing caps at 20y (Cure IV); reserving 3y for melee scatter yields 17y.
-- The sampler shrinks from here through AOE_RADIUS_STEPS when the reach
-- constraint fails at 17y.
ai_formation.AOE_MAGE_RADIUS = 17.0

-- Radius-shrink ladder: values the sampler walks when 17y fails to yield
-- any candidate that reaches every core party member. Descending order.
-- Last value (5y) is close enough to reach anyone within 15y of mob — the
-- degenerate case where the party is so spread out that no wider ring works.
ai_formation.AOE_RADIUS_STEPS = { 17.0, 15.0, 13.0, 11.0, 9.0, 7.0, 5.0 }

-- Max cast-range constraint used per party-member reach check. 19y = Cure
-- IV's 20y engine range minus 1y buffer for tick-boundary movement drift.
ai_formation.AOE_MAX_CAST_RANGE = 19.0

-- Core-party-radius filter. Members within this distance of the mob are
-- included in the reach constraint. Members farther out (puller pulling,
-- primary who wandered off) are skipped — they manage their own position.
ai_formation.AOE_CORE_PARTY_RADIUS = 10.0

-- Number of angular candidates sampled per radius. 36 (10° steps) gives
-- good coverage without measurable cost.
ai_formation.AOE_SAMPLE_COUNT = 36

-- Geometry-aware anchor scoring (#open-mage-spot). After the cheap
-- alignment/reach pass, the sampler navmesh-raycasts the best-aligned few
-- candidates to each core member and biases toward the one with clear sight
-- lines (i.e. not tucked behind a wall/pillar). Raycasts are the expensive
-- part, so we (a) only probe the top-K aligned candidates and (b) cache the
-- resulting list, recomputing only on a throttle or when the mob drifts.
--
-- Weight is a TIE-BREAKER on top of alignment, not a driver: alignment is a
-- dot product in [-1,1]; LoS score is [0,1]. At 0.4 a well-aligned but blocked
-- spot can still lose to a slightly-less-aligned open one, but openness can't
-- drag the mage to a wild angle. Raise to prefer openness harder; 0 disables.
ai_formation.AOE_LOS_WEIGHT        = 0.4
ai_formation.AOE_LOS_TOPK          = 8      -- only raycast the K best-aligned candidates
ai_formation.AOE_ANCHOR_TTL_MS     = 2500   -- reuse the cached candidate list this long
ai_formation.AOE_ANCHOR_REDO_DRIFT = 3.0    -- ...unless the mob moves more than this (yalms)

-- Camp leash: how far assist may stray from the camp anchor even during
-- combat. Mobs outside this radius are not chased; assist holds at the
-- edge of the leash and lets the mob come to them. Classic FFXI camping.
ai_formation.CAMP_LEASH_YALMS = 10

-- Camp melee/mage split: distance between the melee-group and mage-group
-- centers (each sits half this from the camp anchor, on opposite sides). Loose
-- grouping so the BRD can refresh melee vs mage songs during idle with less
-- cross-bleed; 8y keeps the party tight — clean song isolation at this spacing
-- is #278's scored-positioning job, not this split's.
ai_formation.CAMP_SPLIT_YALMS = 8

-- Universal declump radius. Each bot's stable offset is a vector at this
-- radius pointing in a per-bot direction derived from char ID.
ai_formation.DECLUMP_RADIUS = 1.5

-- Melee priority for the no-tank fallback. First match in alliance becomes
-- the "front" bot. Job names match xi.singleplayer.bots.ai_formation.JOB_NAMES below.
ai_formation.MELEE_FALLBACK_PRIORITY = { 'PLD', 'RUN', 'NIN', 'WAR', 'SAM', 'MNK' }

-- Mage priority for the no-tank-no-melee fallback. Consulted by front_bot
-- only when neither a Tank role nor a Melee role exists in the alliance.
-- Ordered "most tank-shaped mage" → "least": RDM has D-armor + self-cure,
-- BRD has Songs + sword skill, SCH has Stoneskin Accession, etc. The chosen
-- mage holds position like a tank would so formation has an axis to compute
-- against. Doesn't change role behavior — they still cast as a mage; they
-- just become the geometric anchor.
ai_formation.MAGE_TANK_FALLBACK_PRIORITY = { 'RDM', 'BRD', 'SCH', 'WHM', 'GEO', 'SMN', 'BLM' }

-- Job ID → 3-letter name. Mirror of xi.jobs.* string conversion. Used so
-- the melee fallback can compare bot:getMainJob() to the priority list.
ai_formation.JOB_NAMES = {
    [1]='WAR', [2]='MNK', [3]='WHM', [4]='BLM', [5]='RDM', [6]='THF',
    [7]='PLD', [8]='DRK', [9]='BST', [10]='BRD', [11]='RNG', [12]='SAM',
    [13]='NIN', [14]='DRG', [15]='SMN', [16]='BLU', [17]='COR', [18]='PUP',
    [19]='DNC', [20]='SCH', [21]='GEO', [22]='RUN',
}

-----------------------------------
-- Per-bot stable declump offset.
--
-- Given a bot, return (dx, dz) — a fixed unit-radius vector unique-ish to
-- that bot. Multiply by ai_formation.DECLUMP_RADIUS at the call site to
-- get the actual world-space offset.
--
-- Derivation: char ID × a prime, mod 360, converted to radians. Gives ~360
-- discrete angles. Two bots with adjacent IDs get visibly different
-- angles, which is what we want for a spread.
-----------------------------------
function ai_formation.declump_unit(bot)
    if bot == nil or bot.getID == nil then return 0, 0 end
    local id = bot:getID()
    local angle_deg = (id * 137) % 360
    local rad = math.rad(angle_deg)
    return math.cos(rad), math.sin(rad)
end

function ai_formation.declump_offset(bot)
    local ux, uz = ai_formation.declump_unit(bot)
    return ux * ai_formation.DECLUMP_RADIUS, uz * ai_formation.DECLUMP_RADIUS
end

-----------------------------------
-- Role helpers
-----------------------------------
local function is_mage_role(role)
    local R = xi.singleplayer.bots.Role or {}
    return role == R.Healer or role == R.Nuker or role == R.Rdm
end

local function is_melee_role(role)
    local R = xi.singleplayer.bots.Role or {}
    return role == R.Tank or role == R.Melee
end

ai_formation.is_mage_role  = is_mage_role
ai_formation.is_melee_role = is_melee_role

-----------------------------------
-- Job-based bucketing for the walking `role` formation.
--
-- FRONT (DD/tank-shaped): WAR, MNK, THF, PLD, DRK, BST, DRG, NIN, SAM, RNG,
--                         PUP, DNC, RUN, COR, BLU
-- BACK  (mages/support):  WHM, BLM, RDM, BRD, SMN, SCH, GEO
--
-- Decided by mainJob, not xi.singleplayer.bots.Role: the AI role (Healer/Nuker/etc.) is a
-- behavior selector that doesn't always map cleanly to "where do you stand
-- in a walking line" — e.g. a BST is Melee/Idle by role but should walk with
-- the melees because its pet does. Same logic for COR/RNG (ranged DD).
-----------------------------------
local FRONT_WALKER_JOBS = {
    WAR = true, MNK = true, THF = true, PLD = true, DRK = true,
    BST = true, DRG = true, NIN = true, SAM = true, RNG = true,
    PUP = true, DNC = true, RUN = true, COR = true, BLU = true,
}

-- Returns (frontBucket, backBucket): two sorted arrays of CCharEntity,
-- partitioned by job. Both exclude `main` (the primary anchor). Sort is by
-- char ID for stable cross-tick positioning.
function ai_formation.role_buckets(alliance, main)
    local front = {}
    local back  = {}
    for _, member in ipairs(alliance or {}) do
        if member ~= main then
            local jobId   = member.getMainJob and member:getMainJob() or 0
            local jobName = ai_formation.JOB_NAMES[jobId]
            if jobName and FRONT_WALKER_JOBS[jobName] then
                table.insert(front, member)
            else
                table.insert(back, member)
            end
        end
    end
    table.sort(front, function(a, b) return a:getID() < b:getID() end)
    table.sort(back,  function(a, b) return a:getID() < b:getID() end)
    return front, back
end

-----------------------------------
-- Front-role picker. Walk the alliance and pick the bot that should be
-- treated as "front" (tank slot in battle formation).
--
-- Returns (CCharEntity | nil, isRealTank: bool).
-- isRealTank=false signals the caller this is a melee filling in — they
-- may want to apply tank-style positioning (hold) without expecting tank
-- behaviors like provoke etc.
-----------------------------------
function ai_formation.front_bot(alliance)
    local R = xi.singleplayer.bots.Role or {}
    local realTank
    local meleesByJob = {}
    local mageesByJob = {}
    local anyMelee
    local anyMage
    for _, member in ipairs(alliance or {}) do
        local state = xi.singleplayer.bots.alliance and xi.singleplayer.bots.alliance.bot[member:getID()]
        local role  = state and state.role or nil
        local jobId = member.getMainJob and member:getMainJob() or 0
        local jobName = ai_formation.JOB_NAMES[jobId]
        if role == R.Tank then
            realTank = realTank or member
        elseif role == R.Melee then
            anyMelee = anyMelee or member
            if jobName and meleesByJob[jobName] == nil then
                meleesByJob[jobName] = member
            end
        elseif role == R.Healer or role == R.Nuker or role == R.Rdm then
            anyMage = anyMage or member
            if jobName and mageesByJob[jobName] == nil then
                mageesByJob[jobName] = member
            end
        end
    end
    if realTank ~= nil then return realTank, true end
    for _, jobName in ipairs(ai_formation.MELEE_FALLBACK_PRIORITY) do
        if meleesByJob[jobName] then return meleesByJob[jobName], false end
    end
    if anyMelee then return anyMelee, false end
    -- No tank AND no melee → walk the mage job priority for a geometric anchor.
    -- The chosen mage just holds position so battle_axis has a tank-mob line
    -- to compute against; they continue casting normally otherwise.
    for _, jobName in ipairs(ai_formation.MAGE_TANK_FALLBACK_PRIORITY) do
        if mageesByJob[jobName] then return mageesByJob[jobName], false end
    end
    if anyMage then return anyMage, false end
    return nil, false
end

-----------------------------------
-- Slot index within a role bucket. Used by arc / line / column shapes to
-- give each bot a stable per-role ordinal. Deterministic: sorted by char ID.
-----------------------------------
function ai_formation.slot_in_role(bot, alliance, role)
    local R = xi.singleplayer.bots.Role or {}
    local sameRole = {}
    for _, member in ipairs(alliance or {}) do
        local state = xi.singleplayer.bots.alliance and xi.singleplayer.bots.alliance.bot[member:getID()]
        local mrole = state and state.role or nil
        local matches = (mrole == role)
        -- Demoted-tank case: battle_target reroles non-front tanks as melees
        -- for positioning (since a 2-tank party puts the second tank at melee
        -- range, not in the tank slot). slot_in_role would otherwise filter
        -- them out and they'd all stack at slot 0. Include Tank-role bots
        -- in the Melee bucket so they get distinct slot indices.
        if not matches and role == R.Melee and mrole == R.Tank then
            matches = true
        end
        if matches then
            table.insert(sameRole, member)
        end
    end
    table.sort(sameRole, function(a, b) return a:getID() < b:getID() end)
    for i, member in ipairs(sameRole) do
        if member == bot then return i - 1 end -- 0-based
    end
    return 0
end

-----------------------------------
-- Battle axis: (mob - frontBot) normalized.
-- Returns ax, az (unit axis) and perp_x, perp_z (right-perpendicular).
-- Returns nil when geometry can't be computed (front or mob missing,
-- coincident positions).
-----------------------------------
function ai_formation.battle_axis(frontBot, mob)
    if frontBot == nil or mob == nil then return nil end
    local fx, fz = frontBot:getXPos(), frontBot:getZPos()
    local mx, mz = mob:getXPos(), mob:getZPos()
    local dx, dz = mx - fx, mz - fz
    local len = math.sqrt(dx * dx + dz * dz)
    if len < 0.01 then return nil end
    local ax, az = dx / len, dz / len
    -- Right-perpendicular: rotate axis 90° clockwise (right side of axis
    -- when looking from front toward mob).
    local px, pz = -az, ax
    return ax, az, px, pz
end

-----------------------------------
-- Quadrant system (#234 follow-up).
--
-- The ring around an engaged mob splits into four 90° wedges, each a 2D
-- region the bot's role prefers. Angle convention matches battle_axis:
--   * θ = 0°   → behind mob (away from tank)
--   * θ = 90°  → mob's right side (tank POV)
--   * θ = 180° → in front of mob (tank's slot)
--   * θ = 270° → mob's left side
--
-- Quadrant centers + 90° wedge ranges:
--   FRONT  (Tank): 180°, range 135°–225°. AoE / breath cones land here.
--   SIDE_A (Melee canonical, right of mob): 90°, range 45°–135°.
--   SIDE_B (Melee canonical, left of mob):  270°, range 225°–315°.
--   BACK   (Mage canonical, behind mob):    0° (=360°), range 315°–45° (wraps).
--
-- Quadrant boundaries are at 45°, 135°, 225°, 315°. No-overlap by design.
--
-- Per-role population rules:
--   * Tank / Melee: 90° annular sector at melee range. 16 slots distributed
--                   across 2 radial rings × 8 angular columns.
--   * Mage: 2y-radius disk cluster centered at the quadrant's center angle
--           at a per-formation distance from the mob. 16 slots distributed
--           via concentric hex rings inside the disk.
-----------------------------------
local Q_FRONT  = 'front'
local Q_SIDE_A = 'sideA'
local Q_SIDE_B = 'sideB'
local Q_BACK   = 'back'
ai_formation.Q_FRONT  = Q_FRONT
ai_formation.Q_SIDE_A = Q_SIDE_A
ai_formation.Q_SIDE_B = Q_SIDE_B
ai_formation.Q_BACK   = Q_BACK

local QUADRANT_CENTER_DEG = {
    [Q_FRONT]   = 180,
    [Q_SIDE_A]  = 90,
    [Q_SIDE_B]  = 270,
    [Q_BACK]    = 0,
}

-- Melee/tank slot priority within a 90° quadrant. Each entry is an angular
-- offset (degrees) from the quadrant center plus a radial offset (yalms)
-- from the canonical meleeRadius. First 7 slots are the outer ring fanning
-- out from center to edge — visually pleasing for 1-7 melees per quadrant.
-- Slot 8 sits at a near-edge column. Slots 9-16 mirror the same angular
-- columns at the inner ring (1y closer to mob).
local MELEE_SLOT = {
    -- {angle_offset_deg, radial_offset_yalms}
    { 0,       0 },     -- 1: center, outer ring (canonical)
    { -11.25,  0 },     -- 2: outer, one column left of center
    {  11.25,  0 },     -- 3: outer, one column right of center
    { -22.5,   0 },     -- 4: outer, two columns left
    {  22.5,   0 },     -- 5: outer, two columns right
    { -33.75,  0 },     -- 6: outer, three columns left
    {  33.75,  0 },     -- 7: outer, three columns right
    { -42,     0 },     -- 8: outer, edge inset (3.75° margin to quadrant boundary)
    { 0,      -1.0 },   -- 9-16: same angular columns at the inner ring
    { -11.25, -1.0 },
    {  11.25, -1.0 },
    { -22.5,  -1.0 },
    {  22.5,  -1.0 },
    { -33.75, -1.0 },
    {  33.75, -1.0 },
    { -42,    -1.0 },
}

-- Mage disk-cluster slot offsets. Polar coordinates (r, θ_deg) relative to
-- the disk center, applied in mob-axis space (not world axis — see the
-- application in mage_slot_in_disk). Slot 1 sits at the disk center, slots
-- 2-7 ring it at 1.0y, slots 8-13 at 1.8y (offset 30° for an interleaved
-- look), slots 14-16 at 2.0y.
local MAGE_DISK_SLOT = {
    { 0,   0   }, -- 1: center
    { 1.0, 0   }, -- 2-7: inner hex ring
    { 1.0, 60  },
    { 1.0, 120 },
    { 1.0, 180 },
    { 1.0, 240 },
    { 1.0, 300 },
    { 1.8, 30  }, -- 8-13: outer hex ring (30° offset for interleave)
    { 1.8, 90  },
    { 1.8, 150 },
    { 1.8, 210 },
    { 1.8, 270 },
    { 1.8, 330 },
    { 2.0, 0   }, -- 14-16: outer triangle
    { 2.0, 120 },
    { 2.0, 240 },
}

local function quadrant_center_rad(quadrant)
    return math.rad(QUADRANT_CENTER_DEG[quadrant] or 0)
end

-----------------------------------
-- Compute the (x, z) world position for a melee/tank slot in a quadrant.
-- slotIdx is 1-based (1..16). ax/az/perp_x/perp_z come from battle_axis;
-- meleeRadius is bot:getMeleeRange(mob) - 1.0 (the existing convention).
-----------------------------------
function ai_formation.melee_slot_in_quadrant(quadrant, slotIdx, mob, ax, az, perp_x, perp_z, meleeRadius)
    if slotIdx < 1 then slotIdx = 1 end
    if slotIdx > 16 then slotIdx = 16 end
    local entry = MELEE_SLOT[slotIdx]
    local angle_rad = quadrant_center_rad(quadrant) + math.rad(entry[1])
    local radius    = math.max(2.0, meleeRadius + entry[2])
    local cosa, sina = math.cos(angle_rad), math.sin(angle_rad)
    local rx = cosa * ax + sina * perp_x
    local rz = cosa * az + sina * perp_z
    return mob:getXPos() + rx * radius, mob:getZPos() + rz * radius
end

-----------------------------------
-- Compute the (x, z) world position for a mage slot inside a disk cluster
-- centered in `quadrant` at distance `dist` from the mob along that
-- quadrant's center angle. The disk's internal slot offsets are applied in
-- world-aligned coordinates (the cluster is small, orientation doesn't
-- matter for distinguishing slots).
-----------------------------------
function ai_formation.mage_slot_in_disk(quadrant, slotIdx, mob, ax, az, perp_x, perp_z, dist)
    if slotIdx < 1 then slotIdx = 1 end
    if slotIdx > 16 then slotIdx = 16 end
    local center_rad = quadrant_center_rad(quadrant)
    local ccos, csin = math.cos(center_rad), math.sin(center_rad)
    local cx = mob:getXPos() + (ccos * ax + csin * perp_x) * dist
    local cz = mob:getZPos() + (ccos * az + csin * perp_z) * dist
    local entry = MAGE_DISK_SLOT[slotIdx]
    local r       = entry[1]
    local theta_r = math.rad(entry[2])
    return cx + math.cos(theta_r) * r, cz + math.sin(theta_r) * r
end

-----------------------------------
-- THF back-of-tank candidates. Places THF 1y past the assigned tank on the
-- mob-tank line so Trick Attack's ally-between-caster-and-target line is
-- reliable regardless of the alliance's battle formation. All THFs sharing
-- one tank get the same target position and let engine collision spread
-- them; no per-THF sub-slot fan out.
--
-- Returns nil when the scope has no tanks — caller falls through to generic
-- Melee positioning.
--
-- Assignment: THFs charId-sorted, tanks charId-sorted, THF at 0-based index
-- i → tank at (i mod #tanks). 3 tanks + 2 THFs: T1 has THF1, T2 has THF2,
-- T3 alone. 1 tank + 3 THFs: all three stack behind T1.
--
-- Position tuning: 1y past tank puts THF at ~4y from a typical medium mob
-- (tank at 3y + 1y offset), right at the melee edge. Small-hitbox mobs may
-- push THF out of their own melee range; tune BACK_BIAS smaller if seen.
--
-- Fallback candidates: primary target (1y behind tank), a further slot at
-- 2y behind tank, and the tank's exact position (guaranteed walkable since
-- the tank is standing there). If none of the three are reachable, returns
-- an empty list and ai_move falls through to generic Melee positioning
-- via the surrounding branch cascade.
-----------------------------------
local THF_BACK_BIAS_PRIMARY  = 1.0
local THF_BACK_BIAS_FALLBACK = 2.0
-- Safety margin under THF's melee_range so we're not standing at exactly
-- the swing edge (any small tick jitter would push us out).
local THF_MELEE_SAFETY       = 0.5
-- Extra inset applied to the tank's engaged stop-point when a THF is
-- assigned to that tank. Larger inset = tank walks closer to mob. Value =
-- THF_BACK_BIAS_PRIMARY + a small margin so THF at their 1y-behind slot
-- lands at the tank's previous default distance from mob (guaranteed in
-- range). Consumed by ai_move's melee-role stop-distance calc.
ai_formation.TANK_THF_FORWARD_NUDGE = THF_BACK_BIAS_PRIMARY + THF_MELEE_SAFETY

-- Does this tank have any THF assigned to it under the pairing rule
-- (THF at 0-based index i → tanks[(i mod #tanks)+1])? Used by ai_move to
-- nudge the tank forward so their assigned THF can stay in melee range
-- at ~1y behind.
function ai_formation.tank_has_assigned_thf(tank)
    if tank == nil then return false end
    local ai_util = xi.singleplayer.bots.ai_util
    if ai_util == nil or ai_util.tanks_in_scope == nil or ai_util.thfs_in_scope == nil then
        return false
    end
    local tanks = ai_util.tanks_in_scope(tank)
    if #tanks == 0 then return false end
    local thfs = ai_util.thfs_in_scope(tank)
    if #thfs == 0 then return false end
    local myTankIdx = ai_util.slot_index_in(tank, tanks)
    if myTankIdx == nil then return false end
    for i = 1, #thfs do
        if ((i - 1) % #tanks) + 1 == myTankIdx then return true end
    end
    return false
end

function ai_formation.thf_candidates(bot, mob)
    if bot == nil or mob == nil then return nil end
    local ai_util = xi.singleplayer.bots.ai_util
    if ai_util == nil or ai_util.tanks_in_scope == nil or ai_util.thfs_in_scope == nil then
        return nil
    end
    local tanks = ai_util.tanks_in_scope(bot)
    if #tanks == 0 then return nil end
    local thfs = ai_util.thfs_in_scope(bot)
    local myIdx = ai_util.slot_index_in(bot, thfs) or 1  -- 1-based
    local assignedTank = tanks[((myIdx - 1) % #tanks) + 1]
    if assignedTank == nil then return nil end

    local tx, tz = assignedTank:getXPos(), assignedTank:getZPos()
    local mx, mz = mob:getXPos(), mob:getZPos()
    local dx, dz = tx - mx, tz - mz
    local tank_dist = math.sqrt(dx * dx + dz * dz)
    -- Tank and mob coincident (both at same spot) — no line to compute.
    -- Fall through to generic melee so THF at least moves toward the mob.
    if tank_dist < 0.01 then return nil end
    local nx, nz = dx / tank_dist, dz / tank_dist
    local my = bot:getYPos()

    -- Range-safe bias picker: never place THF beyond THF's own melee_range
    -- (- safety) from mob. If the tank engaged from too far, THF at the
    -- ideal 1y-behind slot would swing air. Clamp effective bias so THF's
    -- final distance from mob stays inside melee_range. Never negative —
    -- putting THF in front of tank would break Trick Attack's ally-between
    -- geometry.
    local thf_melee = (bot.getMeleeRange and bot:getMeleeRange(mob)) or 4.0
    local max_dist  = thf_melee - THF_MELEE_SAFETY
    local function clamp_bias(bias)
        local reach = tank_dist + bias
        if reach > max_dist then
            local shrunk = max_dist - tank_dist
            if shrunk < 0 then shrunk = 0 end
            return shrunk
        end
        return bias
    end
    local biasPrimary  = clamp_bias(THF_BACK_BIAS_PRIMARY)
    local biasFallback = clamp_bias(THF_BACK_BIAS_FALLBACK)

    return {
        { x = tx + nx * biasPrimary,  y = my, z = tz + nz * biasPrimary,
          label = 'thf:behind-' .. assignedTank:getName() .. ':' .. tostring(biasPrimary) },
        { x = tx + nx * biasFallback, y = my, z = tz + nz * biasFallback,
          label = 'thf:behind-' .. assignedTank:getName() .. ':' .. tostring(biasFallback) },
        { x = tx, y = my, z = tz,
          label = 'thf:on-' .. assignedTank:getName() },
    }
end

-----------------------------------
-- Build the ordered candidate list for a bot's per-tick movement.
--
-- Returns an array of { x, y, z, label } entries in fallback order. ai_move
-- iterates them and calls pathTo (without WALLHACK) on each; first success
-- wins, the rest are skipped. On full exhaustion, ai_move warps to primary
-- (the only Tier 2 — strike counters / intermediate tiers don't pull weight
-- given pathTo is sub-ms).
--
-- Fallback rules by role (see #234 followup design discussion):
--   * Mage: slide radial distance in Back (canonical → ±1, ±2, ..., clamped
--           to [2, 16y]; ~15 distances with the disk-center slot at each).
--           Then rotate quadrants in safety order: Back → SideA → SideB →
--           Front. Front is dead-last because it eats cones.
--   * Melee: walk all 16 slots in canonical side (Side A or Side B depending
--            on melee index), then Other Side, then Back, then Front. 64 max.
--   * Tank: Front → SideA → SideB → Back. 64 max.
--
-- Returns {} when the formation system is bypassed (battleFormation = 'off',
-- no frontBot resolvable, or coincident axis).
-----------------------------------
-----------------------------------
-- Nearest-point-on-ring candidates for the 'Casual' formation. Ordered so the
-- point on a mob-centered ring of `radius` CLOSEST to the bot's current
-- position comes first, then fans out around the ring (+/-10deg, +/-20deg, ...)
-- as fallbacks if the nearest spot is unwalkable. Per-bot (keyed on the bot's
-- own position) so bots naturally separate, and it recomputes each tick so the
-- ring follows the mob. Used by Casual's (secondary) tanks on the melee ring
-- and mages on the ~8y ring.
-----------------------------------
local function ring_from_self(bot, mob, radius, my_y)
    local bx, bz = bot:getXPos(), bot:getZPos()
    local mx, mz = mob:getXPos(), mob:getZPos()
    local dx, dz = bx - mx, bz - mz
    local len    = math.sqrt(dx * dx + dz * dz)
    local ux, uz
    if len < 0.01 then
        ux, uz = 1.0, 0.0   -- degenerate: bot on top of mob, pick any bearing
    else
        ux, uz = dx / len, dz / len
    end
    local out   = {}
    local STEP  = math.rad(10)
    -- 0, +1, -1, +2, -2, ... up to +/-180deg: nearest spot first, then the rest
    -- of the ring as fallbacks.
    local order = { 0 }
    for k = 1, 18 do
        table.insert(order, k)
        table.insert(order, -k)
    end
    for _, k in ipairs(order) do
        local a      = k * STEP
        local ca, sa = math.cos(a), math.sin(a)
        local rx, rz = ux * ca - uz * sa, ux * sa + uz * ca
        table.insert(out, { x = mx + radius * rx, y = my_y, z = mz + radius * rz, label = 'casual:' .. k })
    end
    return out
end

function ai_formation.candidates_for(bot, role, mob, engaged)
    if not engaged then return {} end
    if mob == nil or bot == nil then return {} end

    local R = xi.singleplayer.bots.Role or {}
    local A = xi.singleplayer.bots.alliance
    local formationName = (A and A.battleFormation) or 'legacy'
    -- Both 'off' (don't move) and 'legacy' (chase via pre-formation logic)
    -- bypass the slot ring entirely. target_for handles the actual semantic
    -- difference between the two.
    if formationName == 'off' or formationName == 'legacy' then return {} end

    local alliance = bot:getAlliance() or {}
    local frontBot, isRealTank = ai_formation.front_bot(alliance)
    if frontBot == nil then return {} end
    local ax, az, perp_x, perp_z = ai_formation.battle_axis(frontBot, mob)
    if ax == nil then return {} end

    -- Front bot itself holds — no formation movement candidates.
    if bot == frontBot then return {} end

    local result = {}
    local my     = bot:getYPos()

    -- Park melees at the INNER edge of the melee band (getMeleeRange - 2.0 =
    -- hitboxes touching). ai_move's stepToward_any treats a bot as "arrived"
    -- within SLOT_CLOSE_ENOUGH (2.0y) of its slot, and the in-range band is
    -- only 2y wide [getMeleeRange-2, getMeleeRange]. If the slot sat mid-band
    -- (the old -1.0), a far-side park lands at getMeleeRange+1 — 1y OUT of
    -- range (intermittent, worse on small-range mobs like bats). Placing the
    -- slot at the inner edge makes the worst-case far park = getMeleeRange
    -- (in range); the near side overlaps the mob and the engine shoves out.
    local meleeRadius = (bot.getMeleeRange and bot:getMeleeRange(mob) or 3.0) - 2.0
    if meleeRadius < 0.5 then meleeRadius = 0.5 end

    local function add_one(quadrant, s)
        local x, z = ai_formation.melee_slot_in_quadrant(quadrant, s, mob, ax, az, perp_x, perp_z, meleeRadius)
        table.insert(result, { x = x, y = my, z = z, label = quadrant .. ':' .. s })
    end

    -- Builds a quadrant's candidate sub-ring starting at `mySlot` (the bot's
    -- personalized canonical position in that quadrant), then falls through
    -- the natural priority list skipping mySlot. mySlot=1 is the same as the
    -- old "walk 1..16 in order" behavior; mySlot=N tries my slot first then
    -- 1,2,...,N-1,N+1,...,16.
    --
    -- Without this personalization, every melee in Side A starts with the
    -- canonical 90° outer-ring slot — they all converge on the same world
    -- coords, then the engine shoves them around each other producing the
    -- wiggle the user observed. Each bot needs a distinct first candidate.
    local function add_melee_quadrant(quadrant, mySlot)
        mySlot = mySlot or 1
        if mySlot < 1 then mySlot = 1 end
        if mySlot > 16 then mySlot = 16 end
        add_one(quadrant, mySlot)
        for s = 1, 16 do
            if s ~= mySlot then add_one(quadrant, s) end
        end
    end

    -- Build the [2..16] radial slide sequence centered on canonicalDistance:
    -- canonical, c-1, c+1, c-2, c+2, ..., clamped, deduplicated.
    local function radial_slide(canonicalDistance)
        local seq, seen = {}, {}
        local function push(d)
            local di = math.floor(d + 0.5)
            if di < 2 then di = 2 end
            if di > 16 then di = 16 end
            if not seen[di] then table.insert(seq, di); seen[di] = true end
        end
        push(canonicalDistance)
        for step = 1, 16 do
            push(canonicalDistance - step)
            push(canonicalDistance + step)
        end
        return seq
    end

    local function add_mage_quadrant(quadrant, canonicalDistance, mySlotIdx)
        local distances = radial_slide(canonicalDistance)
        for _, dist in ipairs(distances) do
            local x, z = ai_formation.mage_slot_in_disk(quadrant, mySlotIdx, mob, ax, az, perp_x, perp_z, dist)
            table.insert(result, { x = x, y = my, z = z, label = quadrant .. ':d' .. dist .. ':s' .. mySlotIdx })
        end
    end

    if role == R.Tank then
        if formationName == 'Casual' then
            -- Casual: no front-holding hate discipline. The tank just walks to
            -- the nearest spot on the melee ring and follows the mob. (The
            -- engaged front bot already returned {} above and holds where it
            -- engaged, which is itself a melee-ring spot.)
            return ring_from_self(bot, mob, meleeRadius, my)
        end
        -- All tanks live in Front, sharing hate. Distinct slot per tank so
        -- the mob barely turns when hate ping-pongs between them — adjacent
        -- Front slots are 11.25° apart, well inside the mob's facing dead
        -- zone. Putting secondary tanks on Sides A/B (the old behavior)
        -- forced the mob to swing 90° on every hate flip, breaking back
        -- attacks and looking awful.
        --
        -- frontBot has slot_in_role index 0 → tankSlot 1 (canonical 180°),
        -- but they return {} via the bot == frontBot check above, so slot 1
        -- is effectively reserved for the frontBot's natural engagement
        -- position. The second tank gets slot 2 (168.75°), third gets slot 3
        -- (191.25°), etc.
        local tankSlot = ai_formation.slot_in_role(bot, alliance, R.Tank) + 1
        add_melee_quadrant(Q_FRONT,  tankSlot)
        add_melee_quadrant(Q_SIDE_A, 1)
        add_melee_quadrant(Q_SIDE_B, 1)
        add_melee_quadrant(Q_BACK,   1)
        return result
    end

    -- THF-specific positioning: prepend "behind assigned tank" slots to the
    -- generic Melee candidate list. Trick Attack needs the tank-mob line
    -- reliably regardless of the alliance's battle formation, so THFs are
    -- deterministically paired to tanks by charId-sort index modulo #tanks
    -- (extras stack, engine declump nudges them apart; unpaired tanks go
    -- THF-less). If the behind-tank slots are all unwalkable, ai_move's
    -- ring iteration falls through to the appended generic-melee slots so
    -- THF still ends up somewhere useful. thf_candidates returns nil when
    -- the scope has no tanks — then behavior is exactly the generic melee
    -- path with no prefix.
    --
    -- Note on SA: fork lets SA fire from anywhere, so only TA's line-up
    -- drives the positioning rule.
    local thfPrefix
    if role == R.Melee and xi.singleplayer.bots.ai_util.is_thf(bot) then
        thfPrefix = ai_formation.thf_candidates(bot, mob)
    end

    if role == R.Melee then
        local roleSlot = ai_formation.slot_in_role(bot, alliance, R.Melee)
        if not isRealTank then roleSlot = roleSlot + 1 end
        if formationName == 'Casual' then
            -- Casual: disperse melees around the whole ring. Assign each a
            -- distinct primary quadrant by role-slot (cycling Front/SideA/
            -- SideB/Back), a deeper sub-slot for the 5th+ melee, then fall
            -- through the other quadrants; engine declump keeps same-quadrant
            -- melees apart. Net: a loose surround, not a clump on one arc.
            local quads    = { Q_FRONT, Q_SIDE_A, Q_SIDE_B, Q_BACK }
            local primaryQ = quads[(roleSlot % 4) + 1]
            add_melee_quadrant(primaryQ, math.floor(roleSlot / 4) + 1)
            for _, q in ipairs(quads) do
                if q ~= primaryQ then add_melee_quadrant(q, 1) end
            end
        elseif formationName == 'spread' then
            -- Spread: melees stack BEHIND the mob (Q_BACK), one
            -- distinct slot each so they fan across the rear arc; fall through
            -- to the flanks then front if the rear slots are unwalkable.
            -- (tight/AoE flank the sides instead — see the else branch.)
            add_melee_quadrant(Q_BACK,   roleSlot + 1)
            add_melee_quadrant(Q_SIDE_A, 1)
            add_melee_quadrant(Q_SIDE_B, 1)
            add_melee_quadrant(Q_FRONT,  1)
        else
            -- tight / AoE / other: melees flank the perpendicular sides.
            -- Even role-slot → Side A, odd → Side B (alternating assignment).
            -- mySideSlot is the bot's personalized canonical position WITHIN
            -- their side (1-based): role-slot 0 → side slot 1, role-slot 2 →
            -- side slot 2, role-slot 4 → side slot 3, etc. Without this each
            -- bot in the same side started iteration at slot 1 and converged
            -- on the same world coords.
            local canonicalSide = ((roleSlot % 2) == 0) and Q_SIDE_A or Q_SIDE_B
            local otherSide     = (canonicalSide == Q_SIDE_A) and Q_SIDE_B or Q_SIDE_A
            local mySideSlot    = math.floor(roleSlot / 2) + 1
            add_melee_quadrant(canonicalSide, mySideSlot)
            add_melee_quadrant(otherSide,     1)  -- fallback quadrant: start fresh
            add_melee_quadrant(Q_BACK,        1)
            add_melee_quadrant(Q_FRONT,       1)
        end
        -- THF prefix: 3 behind-assigned-tank candidates ordered first, then
        -- the generic-melee ring as fallback if all three are unwalkable.
        if thfPrefix ~= nil then
            local combined = {}
            for _, c in ipairs(thfPrefix) do table.insert(combined, c) end
            for _, c in ipairs(result)    do table.insert(combined, c) end
            return combined
        end
        return result
    end

    if is_mage_role(role) then
        if formationName == 'Casual' then
            -- Casual: each mage walks to the closest point on the ~8y ring and
            -- follows the mob. No fixed spot, no tank dependency, no LoS
            -- sampling -- just the nearest reachable piece of the ring per mage.
            return ring_from_self(bot, mob, ai_formation.CASUAL_MAGE_RADIUS, my)
        end
        -- AoE mode dispatches to the ring-sampler; unrelated to the
        -- quadrant-disk math used by 'spread' and 'tight'.
        --
        -- Degrade to 'spread' when no tank is alive in the alliance (#276).
        -- The ring sampler assumes a tank holds the mob still — when mob is
        -- chasing a mage, "17y from mob's current position" runs away
        -- tick-to-tick faster than the mage can retreat, producing frantic
        -- pursuit. Spread's 12y perpendicular flank gives a stable, far-enough
        -- anchor even when the fight has gone sideways. Melees may still be
        -- alive; this only checks Role.Tank. (Emergency-mode alliance response
        -- to tanks+melees dead is task #275, deferred.)
        local effectiveFormation = formationName
        if effectiveFormation == 'AoE' then
            local anyTankAlive = false
            for _, member in ipairs(alliance) do
                local ms = xi.singleplayer.bots.alliance and xi.singleplayer.bots.alliance.bot[member:getID()]
                if ms and ms.role == R.Tank
                   and member.getHP and member:getHP() > 0
                then
                    anyTankAlive = true
                    break
                end
            end
            if anyTankAlive then
                return ai_formation.mage_aoe_candidates(bot, mob)
            end
            effectiveFormation = 'spread'
        end

        local mageSlot = ai_formation.slot_in_role(bot, alliance, role) + 1
        if mageSlot > 16 then mageSlot = 16 end
        if effectiveFormation == 'spread' then
            -- Spread: mages cluster ~12y off ONE perpendicular flank — a
            -- Voke-safe distance from the front-holding tank (see the Voke
            -- worked example in the header). Pick whichever flank scores better
            -- (more open / clear sight to the party); all mages share the same
            -- side via the alliance cache in better_mage_flank. Fall through to
            -- the other flank, then behind/front, if the pick is unwalkable.
            local bestSide  = ai_formation.better_mage_flank(bot, mob, ax, az, perp_x, perp_z)
            local otherSide = (bestSide == Q_SIDE_A) and Q_SIDE_B or Q_SIDE_A
            add_mage_quadrant(bestSide,  12, mageSlot)
            add_mage_quadrant(otherSide, 12, mageSlot)
            add_mage_quadrant(Q_BACK,    12, mageSlot)
            add_mage_quadrant(Q_FRONT,   12, mageSlot)
        else
            -- tight: mages cluster ~5y directly BEHIND the mob (Q_BACK).
            local canonicalDistance = (effectiveFormation == 'tight') and 5 or 12
            add_mage_quadrant(Q_BACK,   canonicalDistance, mageSlot)
            add_mage_quadrant(Q_SIDE_A, canonicalDistance, mageSlot)
            add_mage_quadrant(Q_SIDE_B, canonicalDistance, mageSlot)
            add_mage_quadrant(Q_FRONT,  canonicalDistance, mageSlot)
        end
        return result
    end

    return result
end

-----------------------------------
-- Shared navmesh-openness primitives. Used by the AoE anchor, the spread
-- flank picker, and the camp split-axis picker — they all answer
-- the same question: "from candidate spot X, how much of the party can I see
-- without a wall in the way?"
-----------------------------------
-- Alliance members within `radius` of (rx,rz), as { x, y, z }. Excludes the
-- bot itself and dead members.
local function collect_core(bot, rx, rz, radius)
    local core = {}
    local r2   = radius * radius
    for _, m in ipairs(bot:getAlliance() or {}) do
        if m ~= nil and m ~= bot and not (m.isDead and m:isDead()) then
            local mxp, mzp = m:getXPos(), m:getZPos()
            local dx, dz = mxp - rx, mzp - rz
            if dx * dx + dz * dz <= r2 then
                core[#core + 1] = { x = mxp, y = m:getYPos(), z = mzp }
            end
        end
    end
    return core
end

-- How many of `targets` ({x,y,z} list) have a clear navmesh line from world
-- position (px,py,pz). Degrades to #targets (treat as fully open) when the
-- raycast binding is absent (pre-rebuild), so callers behave as before.
local function count_clear_sightlines(bot, px, py, pz, targets)
    if bot.raycastClear == nil then return #targets end
    local n = 0
    for _, t in ipairs(targets) do
        if bot:raycastClear(px, py, pz, t.x, t.y, t.z) then n = n + 1 end
    end
    return n
end

-----------------------------------
-- AoE-formation mage candidates. Samples AOE_SAMPLE_COUNT rays around the
-- mob at each radius in AOE_RADIUS_STEPS (17, 15, 13, ...) and returns the
-- first radius's candidates where every core party member (within
-- AOE_CORE_PARTY_RADIUS of the mob) stays inside AOE_MAX_CAST_RANGE.
-- Sorted by "back the way we came" preference.
--
-- Shrink-radius rationale: at max radius (17y), worst-case geometry (mage
-- naturally spread up to 2y from cluster + melee at +3y from mob, opposite
-- sides) puts them 22y apart — 2y over Cure IV's 20y range. Shrinking to
-- 15y closes that gap. The mage backs off as far as possible while still
-- being able to heal the mob-cluster.
--
-- All mages produce the same candidate list (no per-mage personalization),
-- so ai_move's slot-ring iteration converges them on the same reachable
-- candidate. Existing SLOT_CLOSE_ENOUGH (2.0y) spread + DECLUMP keep them
-- from literally stacking.
--
-- Fallback: if no radius yields any valid candidate (extreme spread), the
-- function returns a single candidate at the mob's position — the mage
-- steps in that direction and next tick re-evaluates as members converge.
-----------------------------------
function ai_formation.mage_aoe_candidates(bot, mob)
    if mob == nil or bot == nil then return {} end
    local my       = bot:getYPos()
    local mx, mz   = mob:getXPos(), mob:getZPos()

    -- Cache/throttle: the geometry-scored candidate list is expensive to build
    -- (navmesh raycasts) and doesn't need re-deriving every tick. Reuse it
    -- while it's fresh and the mob hasn't drifted; all mages share the same
    -- anchor, so the first caller each cycle pays and the rest hit the cache.
    local A         = xi.singleplayer.bots.alliance
    local now_ms    = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    local ttl       = ai_formation.AOE_ANCHOR_TTL_MS     or 2500
    local redoDrift = ai_formation.AOE_ANCHOR_REDO_DRIFT  or 3.0
    local cache     = A and A.aoeMageCache
    if cache and cache.mobId == mob:getID()
       and (now_ms - cache.ms) < ttl
       and ((cache.mobX - mx) * (cache.mobX - mx) + (cache.mobZ - mz) * (cache.mobZ - mz)) <= redoDrift * redoDrift then
        return cache.list
    end

    local samples  = ai_formation.AOE_SAMPLE_COUNT      or 36
    local radii    = ai_formation.AOE_RADIUS_STEPS      or { 17, 15, 13, 11, 9, 7, 5 }
    local maxRange = ai_formation.AOE_MAX_CAST_RANGE    or 19.0
    local coreR    = ai_formation.AOE_CORE_PARTY_RADIUS or 10.0
    local maxRange_sq = maxRange * maxRange

    -- Core party positions: members within coreR of the mob (pullers out
    -- pulling / a wandering primary fall outside and are excluded).
    local core = collect_core(bot, mx, mz, coreR)

    -- Preferred direction: from mob toward primary. Party naturally
    -- approached mob from primary's direction, so retreating back that way
    -- is the safest heuristic without arena-specific data. If primary is
    -- essentially AT the mob (engaged in melee), the vector length is
    -- tiny — fall back to zero preference (all directions tied on
    -- alignment; whichever is walkable via pathTo wins).
    local prefer_dx, prefer_dz = 0, 0
    local primary = (A and A.mainCharId and GetPlayerByID) and GetPlayerByID(A.mainCharId) or nil
    if primary ~= nil then
        local pdx = primary:getXPos() - mx
        local pdz = primary:getZPos() - mz
        local plen = math.sqrt(pdx * pdx + pdz * pdz)
        if plen > 1.0 then
            prefer_dx = pdx / plen
            prefer_dz = pdz / plen
        end
    end

    -- Try radii in descending order. First one with at least one candidate
    -- that reaches every core party member wins.
    for _, R in ipairs(radii) do
        local rays = {}
        for i = 0, samples - 1 do
            local theta = (i * 2 * math.pi) / samples
            local dir_x = math.cos(theta)
            local dir_z = math.sin(theta)
            local cx    = mx + R * dir_x
            local cz    = mz + R * dir_z
            local ok = true
            for _, member in ipairs(core) do
                local dx, dz = cx - member.x, cz - member.z
                if dx * dx + dz * dz > maxRange_sq then
                    ok = false
                    break
                end
            end
            if ok then
                local score = prefer_dx * dir_x + prefer_dz * dir_z
                table.insert(rays, { x = cx, y = my, z = cz, score = score,
                                     label = 'AoE:R' .. tostring(R) .. ':' .. tostring(i) })
            end
        end
        if #rays > 0 then
            -- Rank by alignment first (cheap), then navmesh-raycast only the
            -- best-aligned few to bias toward a spot with clear sight lines to
            -- the core party (not tucked behind a wall). LoS is a tie-breaker:
            -- score += weight * (fraction of core members visible).
            table.sort(rays, function(a, b) return a.score > b.score end)
            local losW = ai_formation.AOE_LOS_WEIGHT or 0.4
            if losW > 0 and #core > 0 and bot.raycastClear ~= nil then
                local topK = math.min(#rays, ai_formation.AOE_LOS_TOPK or 8)
                for k = 1, topK do
                    local cand  = rays[k]
                    local clear = count_clear_sightlines(bot, cand.x, cand.y, cand.z, core)
                    cand.score = cand.score + losW * (clear / #core)
                end
                -- Re-rank: probed candidates carry their LoS bonus, un-probed
                -- ones keep alignment-only score (they were worse-aligned).
                table.sort(rays, function(a, b) return a.score > b.score end)
            end
            if A ~= nil then
                A.aoeMageCache = { list = rays, ms = now_ms, mobId = mob:getID(), mobX = mx, mobZ = mz }
            end
            return rays
        end
    end

    -- Extreme fallback: no radius worked (core party members > 2*maxRange
    -- from each other, or empty core). Step toward the mob so next tick's
    -- re-evaluation finds a workable ring as members converge. Not cached, so
    -- the next tick re-tries a full ring as members converge.
    return { { x = mx, y = my, z = mz, score = 0, label = 'AoE:fallback' } }
end

-----------------------------------
-- Shared "which of two anchor spots is more open" scorer. Counts core party
-- members (within 10y of the mob) with a clear navmesh line to each candidate
-- center and returns 'A' or 'B' (A wins ties). Cached per-alliance under
-- cacheKey and throttled like the AoE anchor, so all mages share one pick and
-- it isn't raycast every tick. Degrades to 'A' when the raycast binding is
-- absent (pre-rebuild) or there's no core party to score.
-----------------------------------
local function better_anchor_side(bot, mob, aCx, aCz, bCx, bCz, cacheKey)
    local A      = xi.singleplayer.bots.alliance
    local mx, mz = mob:getXPos(), mob:getZPos()
    local now_ms = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    local ttl    = ai_formation.AOE_ANCHOR_TTL_MS     or 2500
    local drift  = ai_formation.AOE_ANCHOR_REDO_DRIFT  or 3.0
    local cache  = A and A[cacheKey]
    if cache and cache.mobId == mob:getID()
       and (now_ms - cache.ms) < ttl
       and ((cache.mobX - mx) * (cache.mobX - mx) + (cache.mobZ - mz) * (cache.mobZ - mz)) <= drift * drift then
        return cache.side
    end

    local side = 'A'
    if bot.raycastClear ~= nil then
        local my   = bot:getYPos()
        local core = collect_core(bot, mx, mz, 10)   -- members within 10y of the mob
        if #core > 0 then
            local aClear = count_clear_sightlines(bot, aCx, my, aCz, core)
            local bClear = count_clear_sightlines(bot, bCx, my, bCz, core)
            if bClear > aClear then side = 'B' end   -- A wins ties
        end
    end

    if A ~= nil then
        A[cacheKey] = { side = side, ms = now_ms, mobId = mob:getID(), mobX = mx, mobZ = mz }
    end
    return side
end

-----------------------------------
-- Spread mage-flank picker: perpendicular flanks (Q_SIDE_A = +perp, Q_SIDE_B =
-- -perp) at 12y. Returns the more open quadrant.
-----------------------------------
function ai_formation.better_mage_flank(bot, mob, ax, az, perp_x, perp_z)
    local D = 12
    local mx, mz = mob:getXPos(), mob:getZPos()
    local pick = better_anchor_side(bot, mob,
        mx + perp_x * D, mz + perp_z * D,     -- Side A (+perp)
        mx - perp_x * D, mz - perp_z * D,     -- Side B (-perp)
        'spreadFlankCache')
    return (pick == 'B') and Q_SIDE_B or Q_SIDE_A
end

-----------------------------------
-- Camp split-axis picker. The melee and mage groups sit on opposite sides of
-- the camp anchor along some axis; the naive (assist-facing) axis can bury both
-- groups in a wall (e.g. a tunnel). Sample a few axes — only [0,180) matters,
-- since an axis and its negation give the same two centers — and pick the one
-- whose BOTH group centers are most visible FROM the anchor (i.e. not behind a
-- wall). Cached per-alliance + throttled so it isn't raycast every tick and all
-- bots agree on one axis. Degrades to a fixed axis when the raycast binding is
-- absent (count_clear_sightlines reports "all open", so the first sample wins).
-----------------------------------
function ai_formation.best_camp_split_axis(bot, cx, cy, cz, half)
    local A      = xi.singleplayer.bots.alliance
    local now_ms = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    local ttl    = ai_formation.AOE_ANCHOR_TTL_MS     or 2500
    local drift  = ai_formation.AOE_ANCHOR_REDO_DRIFT  or 3.0
    local cache  = A and A.campSplitCache
    if cache and (now_ms - cache.ms) < ttl
       and ((cache.cx - cx) * (cache.cx - cx) + (cache.cz - cz) * (cache.cz - cz)) <= drift * drift then
        return cache.bx, cache.bz
    end

    local N = 6                     -- axes across [0,180): 0,30,60,90,120,150
    local bestBx, bestBz, bestScore = 1, 0, -1
    for i = 0, N - 1 do
        local ang    = (i * math.pi) / N
        local dx, dz = math.cos(ang), math.sin(ang)
        local score  = count_clear_sightlines(bot, cx, cy, cz, {
            { x = cx + dx * half, y = cy, z = cz + dz * half },
            { x = cx - dx * half, y = cy, z = cz - dz * half },
        })
        if score > bestScore then   -- smallest angle wins ties (stable)
            bestBx, bestBz, bestScore = dx, dz, score
        end
    end

    if A ~= nil then
        A.campSplitCache = { bx = bestBx, bz = bestBz, ms = now_ms, cx = cx, cz = cz }
    end
    return bestBx, bestBz
end

-----------------------------------
-- Compute the BATTLE stop point for a bot.
--
-- alliance: list of CCharEntity (bot:getAlliance() or similar)
-- bot:      the CCharEntity we're positioning
-- role:     xi.singleplayer.bots.Role.* for this bot
-- mob:      the engaged mob (CCharEntity / CMobEntity)
--
-- Returns target_x, target_z (world coords AFTER declump applied).
-- Returns nil to signal "use existing default movement" — e.g. tank holds
-- their own engaged-melee position, no formation override needed.
-----------------------------------
function ai_formation.battle_target(formationName, alliance, bot, role, mob)
    -- Single-shot callers (target_for via this path) get the FIRST candidate
    -- from the new quadrant system. ai_move iterates the full candidate list
    -- itself when pathTo returns false. formationName is consumed by
    -- candidates_for via alliance.battleFormation; the explicit parameter is
    -- preserved for signature backward-compatibility but not read here.
    local cands = ai_formation.candidates_for(bot, role, mob, true)
    if #cands == 0 then return nil end
    return cands[1].x, cands[1].z
end

-----------------------------------
-- Compute the WALKING stop point for a bot. Returns target_x, target_z
-- (BEFORE declump) or nil to signal default. Anchors:
--   - main: CCharEntity (the primary)
--   - assist: CCharEntity (the assist; usually = tank)
--   - campAnchor: { x, z } or nil
-----------------------------------
function ai_formation.walking_target(formationName, alliance, bot, role, anchors)
    local R = xi.singleplayer.bots.Role or {}

    -- Forward / behind unit vectors from a uint8 FFXI rotation. Derivation:
    --   worldAngle(A, B) computes rotation = atan2(B.z-A.z, B.x-A.x) * -128/pi.
    --   Inverting that, the forward vector for rotation R is:
    --     fwd_x =  cos(R*pi/128)
    --     fwd_z = -sin(R*pi/128)
    --   "Behind" is just -forward. Earlier code used sin/cos in the wrong
    --   positions, which landed bots ~90° off from intended (visible as bots
    --   stacking to primary's side instead of trailing behind).
    local function behind_unit(entity)
        local angle = (entity:getRotPos() / 128) * math.pi
        return -math.cos(angle), math.sin(angle)
    end

    if formationName == 'camp' then
        -- Camp: assist holds the camp anchor. Everyone else splits by role to
        -- OPPOSITE sides of the anchor — mages behind the assist, melees toward
        -- its front — CAMP_SPLIT_YALMS apart, so the BRD can refresh melee vs
        -- mage songs during idle with less cross-bleed. This only loosely
        -- groups them and tightens the old "everyone trails the assist" blob;
        -- clean song isolation at this spacing is #278's scored-positioning job.
        -- Declump still fans each group within DECLUMP_RADIUS after this return.
        -- (Tank isn't forced to the mage side — it falls on the melee side by
        -- role, or sits at the anchor when it's the assist; #278 handles tank
        -- song grouping if needed.)
        if bot == anchors.assist and anchors.campAnchor then
            return anchors.campAnchor.x, anchors.campAnchor.z
        end
        if anchors.assist ~= nil then
            local cx = anchors.campAnchor and anchors.campAnchor.x or anchors.assist:getXPos()
            local cz = anchors.campAnchor and anchors.campAnchor.z or anchors.assist:getZPos()
            local cy = anchors.assist:getYPos()
            local half   = (ai_formation.CAMP_SPLIT_YALMS or 8) * 0.5
            -- Axis scored for openness so a tunnel doesn't bury both groups in a
            -- wall; mages take the +axis side, melees the -axis side.
            local bx, bz = ai_formation.best_camp_split_axis(bot, cx, cy, cz, half)
            if is_mage_role(role) then
                return cx + bx * half, cz + bz * half
            end
            return cx - bx * half, cz - bz * half
        end
        return nil
    end

    if formationName == 'column' then
        -- Single-file chain behind main, ordered by role tier:
        --   slot 1 = assist  (closest to primary)
        --   then   = melees / front-bucket jobs (Tank/Melee/RNG/COR/BST/PUP/...)
        --   then   = mages  / back-bucket jobs (WHM/BLM/RDM/BRD/SMN/SCH/GEO)
        -- Within each tier, sorted by char ID for stable ordering across ticks.
        -- Distances: slot 1 → 1.0y, slot 2 → 1.5y, slot 3 → 2.0y, …
        --   dist = 0.5 + slot * 0.5
        local main = anchors.main
        if main == nil then return nil end
        local assist = anchors.assist

        -- role_buckets already partitions alliance \ {main} into front (DD-shaped)
        -- and back (mage/support) and sorts each by char ID — reuse it here.
        local frontBucket, backBucket = ai_formation.role_buckets(alliance, main)

        local sorted = {}
        local placed = {} -- guard against double-inserting the assist
        if assist ~= nil and assist ~= main then
            table.insert(sorted, assist)
            placed[assist] = true
        end
        for _, mbr in ipairs(frontBucket) do
            if not placed[mbr] then table.insert(sorted, mbr); placed[mbr] = true end
        end
        for _, mbr in ipairs(backBucket) do
            if not placed[mbr] then table.insert(sorted, mbr); placed[mbr] = true end
        end

        local slot
        for i, member in ipairs(sorted) do
            if member == bot then slot = i; break end
        end
        if slot == nil then return nil end
        local bx, bz = behind_unit(main)
        local dist   = 0.5 + slot * 0.5
        return main:getXPos() + bx * dist, main:getZPos() + bz * dist
    end

    if formationName == 'rows' then
        -- Two rank-and-file rows behind primary, bucketed by job family:
        --   FRONT: Tank, Melee, RNG, COR, BST, PUP, BLU, DNC, THF, NIN, DRG, SAM,
        --          WAR, MNK, DRK, PLD, RUN  (all DD/tank-shaped jobs)
        --   BACK:  WHM, BLM, RDM, SCH, GEO, BRD, SMN  (mages + support)
        -- Each row holds up to 3 bots, centered on the behind-axis with 1.0y
        -- between adjacent slots. Overflow into another sub-row 1.0y back.
        --   Front sub-row N: 1.0 + (N-1)*1.0 behind primary  (1.0, 2.0, 3.0, …)
        --   Back  sub-row M: lastFrontDist + 1.0 + (M-1)*1.0 behind primary
        -- Within a row of size S, perp offset for slot s = (s - (S-1)/2) * 1.0
        local main = anchors.main
        if main == nil then return nil end

        local frontBucket, backBucket = ai_formation.role_buckets(alliance, main)

        local bucket, indexInBucket
        for i, m in ipairs(frontBucket) do
            if m == bot then bucket = 'front'; indexInBucket = i - 1; break end
        end
        if bucket == nil then
            for i, m in ipairs(backBucket) do
                if m == bot then bucket = 'back'; indexInBucket = i - 1; break end
            end
        end
        if bucket == nil then return nil end

        local subRow      = math.floor(indexInBucket / 3)
        local slotInRow   = indexInBucket % 3
        local bucketSize  = (bucket == 'front') and #frontBucket or #backBucket
        local rowSize     = math.min(3, bucketSize - subRow * 3)

        local distBehind
        if bucket == 'front' then
            distBehind = 1.0 + subRow * 1.0
        else
            local numFrontSubRows = math.max(1, math.ceil(#frontBucket / 3))
            local lastFrontDist   = 1.0 + (numFrontSubRows - 1) * 1.0
            -- No front bucket → mages still start 1.0y back from primary, not
            -- 2.0y (which would feel like a phantom front row is there).
            if #frontBucket == 0 then lastFrontDist = 0 end
            distBehind = lastFrontDist + 1.0 + subRow * 1.0
        end

        local bx, bz = behind_unit(main)
        -- Right-perpendicular to the behind-vector (rotate 90° CW).
        local px, pz = -bz, bx
        local perpOffset = (slotInRow - (rowSize - 1) * 0.5) * 1.0

        local cx = main:getXPos() + bx * distBehind
        local cz = main:getZPos() + bz * distBehind
        return cx + px * perpOffset, cz + pz * perpOffset
    end

    return nil
end

-----------------------------------
-- Top-level: compute target for a bot given current state. Returns
-- target_x, target_z (declump APPLIED) or nil for "no formation override".
-----------------------------------
function ai_formation.target_for(bot, role, mob, engaged)
    local A           = xi.singleplayer.bots.alliance
    local battleName  = (A and A.battleFormation)  or 'legacy'
    local walkingName = (A and A.walkingFormation) or 'camp'

    -- BATTLE 'off' = do not move during combat. Return bot's current pos so
    -- the caller's stepToward arrives immediately and emits no step. Mirrors
    -- walking 'off' semantics. Combined with walking 'off' this gives the
    -- same observable behavior as the Stop Movement button without going
    -- through BotMode — just via the formation knobs.
    if engaged and battleName == 'off' then
        return bot:getXPos(), bot:getZPos()
    end

    -- BATTLE 'legacy' = pre-formation behavior. Bypass the formation system
    -- entirely and fall through to whatever the caller's default is — for
    -- melees that's the engage-chase path in ai_move.runMovementTick that
    -- walks to melee range of the mob without picking a side/back slot.
    -- Used to be 'off' until the user pointed out that 'off' should mean
    -- "off, ya know, off."
    if engaged and battleName == 'legacy' then return nil end

    -- WALKING 'off' means "do not move at all" — return the bot's current
    -- position so the caller's stepToward arrives immediately and emits no
    -- step. The legacy "skip formation system, use ad-hoc movement" behavior
    -- moved to the new 'assist' selection below.
    if not engaged and walkingName == 'off' then
        return bot:getXPos(), bot:getZPos()
    end

    -- WALKING 'legacy': fall through to the caller's pre-formation movement
    -- logic (the assist-based ad-hoc follow). Was 'assist' before — renamed
    -- to 'legacy' for parity with battle 'legacy', and because the whole
    -- point of the label is "this is the old behavior, kept for back-compat
    -- and as an escape hatch from the formation system." Declump skipped —
    -- caller owns the position math.
    if not engaged and walkingName == 'legacy' then return nil end

    local alliance = bot:getAlliance() or {}
    local assist   = xi.singleplayer.bots.get_assist_entity()

    local tx, tz
    if engaged then
        tx, tz = ai_formation.battle_target(battleName, alliance, bot, role, mob)
    else
        tx, tz = ai_formation.walking_target(walkingName, alliance, bot, role, {
            main       = (A and A.mainEntity) or nil,
            assist     = assist,
            campAnchor = (A and A.campAnchor) or nil,
        })
    end
    if tx == nil then return nil end
    -- Declump only applies in walking `camp` mode now. `column` is a tight
    -- single-file chain (0.5y spacing) and `role` is a structured rank-and-
    -- file (0.5y intra-row spacing) — a 1.5y declump radius would scatter
    -- either layout into a blob. Battle formations also compute their own
    -- precise stop points, so declump there would just smear them.
    if engaged or walkingName ~= 'camp' then
        return tx, tz
    end
    local dx, dz = ai_formation.declump_offset(bot)
    return tx + dx, tz + dz
end

-----------------------------------
-- Camp anchor management. Called when the user switches walking formation
-- TO camp (sets the anchor from assist's current position) or AWAY from
-- camp (clears the anchor so it's re-seeded next time camp is picked).
-----------------------------------
function ai_formation.set_walking_formation(name)
    local A = xi.singleplayer.bots.alliance
    if A == nil then return end
    A.walkingFormation = name
    if name == 'camp' then
        -- Seed the camp anchor from assist's current position if we can
        -- resolve them, else from the primary's position.
        local assist = xi.singleplayer.bots.get_assist_entity()
        local anchor = assist or A.mainEntity
        if anchor and anchor.getXPos then
            A.campAnchor = { x = anchor:getXPos(), z = anchor:getZPos() }
        end
        -- Camp-settling cue: each alliance member fires the emote configured
        -- for their main job in bots_emote.campEmoteByJob. The table is
        -- empty today — no job emotes when entering camp — but the dispatch
        -- mechanism stays in place. Add entries to bots_emote.campEmoteByJob
        -- (keyed by job name → xi.emote.*) to bring per-job camp poses back.
        local A2 = A.mainEntity or anchor
        local camp_map = (xi.singleplayer.bots.bots_emote or {}).campEmoteByJob or {}
        local job_names = xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.jobs or {}
        if A2 and A2.getAlliance then
            for _, member in ipairs(A2:getAlliance() or {}) do
                if member and not member:isDead() and member.getMainJob then
                    local job   = job_names[member:getMainJob()]
                    local emote = job and camp_map[job]
                    if emote ~= nil then
                        member:sendEmote(nil, emote, xi.emoteMode.ALL, false)
                    end
                end
            end
        end
    else
        A.campAnchor = nil
        -- Puller mode requires camp — leaving camp mode invalidates whatever
        -- state the puller was in. Reset it so re-enabling camp later starts
        -- from a clean IDLE, not a stale mid-cycle state that would deadlock.
        if A.pullerCharId and A.pullerCharId ~= 0 then
            local s = xi.singleplayer.bots.ensure_bot(A.pullerCharId)
            if s and s.puller then
                s.puller.state, s.puller.targetId = 'idle', 0
                s.puller.lastLogMs, s.puller.lastScanTriageMs = 0, 0
            end
        end
    end
end

function ai_formation.set_battle_formation(name)
    local A = xi.singleplayer.bots.alliance
    if A == nil then return end
    A.battleFormation = name
end

-----------------------------------
-- Server entrypoint for the 0x176 SET_FORMATION subcommand. The C++ side
-- routes here with (primary, kind, name); we update the alliance singleton
-- and dispatch to the appropriate setter. Kind 0 = battle, 1 = walking.
-----------------------------------
function ai_formation.on_set_formation(primary, kind, name)
    if primary == nil or name == nil or name == '' then return end
    local A = xi.singleplayer.bots.alliance
    if A == nil then return end
    -- mainEntity is read by formation.target_for; seed it so subsequent
    -- ticks have a primary handle without needing autoai to set it first.
    A.mainEntity = primary
    if kind == 0 then
        ai_formation.set_battle_formation(name)
    else
        ai_formation.set_walking_formation(name)
    end
end

-----------------------------------
-- Camp leash: clamp a target point so it's no more than CAMP_LEASH_YALMS
-- from the camp anchor. Used by the assist's movement code during combat
-- in Camp mode — assist will chase a mob but only as far as the leash
-- allows, letting the mob come to them at the edge of camp.
-----------------------------------
function ai_formation.clamp_to_camp_leash(tx, tz)
    local A = xi.singleplayer.bots.alliance
    if A == nil or A.campAnchor == nil then
        return tx, tz
    end
    local cx, cz = A.campAnchor.x, A.campAnchor.z
    local dx, dz = tx - cx, tz - cz
    local d = math.sqrt(dx * dx + dz * dz)
    if d <= ai_formation.CAMP_LEASH_YALMS then return tx, tz end
    local k = ai_formation.CAMP_LEASH_YALMS / d
    return cx + dx * k, cz + dz * k
end

-----------------------------------
-- Is `entity` outside the camp leash? Used by role_tank / role_melee to
-- refuse to engage mobs that would drag them out of camp. Returns false
-- when not in camp mode or entity is nil, so callers can treat "false"
-- as "safe to engage."
-----------------------------------
function ai_formation.entity_outside_camp_leash(entity)
    local A = xi.singleplayer.bots.alliance
    if A == nil or A.walkingFormation ~= 'camp' or A.campAnchor == nil then
        return false
    end
    if entity == nil or entity.getXPos == nil then return false end
    local cx, cz = A.campAnchor.x, A.campAnchor.z
    local dx = entity:getXPos() - cx
    local dz = entity:getZPos() - cz
    return (dx * dx + dz * dz) > (ai_formation.CAMP_LEASH_YALMS * ai_formation.CAMP_LEASH_YALMS)
end

return m
