-----------------------------------
-- Puller AI.
--
-- One designated bot (alliance.pullerCharId) scouts for VT/IT mobs within
-- alliance.pullerRange of alliance.campAnchor and brings them home. Active
-- only when walkingFormation == 'camp' and pullerCharId != 0.
--
-- State machine:
--   Idle         — at camp, waiting. No notoriety on alliance.
--   Scouting     — picked a target, walking toward it.
--   Pulling      — within pull-tool range, dispatching Dia or ranged attack.
--   Returning    — heading back to camp anchor.
--   Handoff      — arrived at anchor with a pulled mob; sets allianceTarget.
--
-- Abort rule: any mob on primary:getNotorietyList() flips state → Returning
-- immediately, regardless of where we are. No distinction between "our pulled
-- mob" and "random aggro" — just go. The engine's move-interrupts-cast (if
-- any) handles in-flight cast/RA naturally; even without that, parallel motion
-- starts immediately and the cast just plays out alongside the run.
--
-- Pull tools (in priority order):
--   1. Dia (spell id 23) — 16y range, ~3 MP. Available on a wide range of
--      jobs and subs (WHM/RDM/PLD/RUN/SCH/GEO main or /WHM /RDM sub etc).
--   2. Ranged attack — requires a ranged weapon. ~20-25y depending on weapon.
-- If neither is available, the puller logs once per scan attempt and stays Idle.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_puller')

xi              = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.ai_puller = xi.singleplayer.bots.ai_puller or {}
local ai_puller = xi.singleplayer.bots.ai_puller

local PULL_TOOL_DIA_RANGE   = 15.0   -- Dia's effective range minus a safety yalm
local PULL_TOOL_RANGED_RANGE = 18.0  -- typical ranged minus safety
local AT_ANCHOR_DIST        = 1.5    -- "arrived at camp"
local PULL_TARGET_LOSS_HP   = 0      -- mob dead → drop target
local DIA_SPELL_ID          = xi and xi.magic and xi.magic.spell and xi.magic.spell.DIA or 23

local STATE_IDLE      = 'idle'
local STATE_SCOUTING  = 'scouting'
local STATE_PULLING   = 'pulling'
local STATE_RETURNING = 'returning'
local STATE_HANDOFF   = 'handoff'

-----------------------------------
-- Setters (called from C++ packet hooks)
-----------------------------------
-- Puller Start/Stop toggle. Wired to SET_PULLER_PAUSED (0x26). Alliance-
-- wide. When paused=true, the tick's IDLE→SCOUTING transition is blocked;
-- any pull already in flight continues to completion.
function ai_puller.set_paused(primary, paused)
    if primary == nil then return end
    local A = xi.singleplayer.bots.alliance
    if A == nil then return end
    A.pullerPaused = paused and true or false
    printf(string.format('ai_puller.set_paused: %s', tostring(A.pullerPaused)))
end

function ai_puller.set_puller(primary, botName)
    if primary == nil then return end
    local A = xi.singleplayer.bots.alliance
    if A == nil then return end
    if botName == nil or botName == '' then
        A.pullerCharId = 0
        A.pullerPaused = true
        printf('ai_puller.set_puller: cleared')
        return
    end
    local target = botName:lower()
    local primaryId = primary:getID()
    -- A bot is owned if it's the primary OR a headless owned by primary.
    -- Without the primary clause, the user couldn't set themselves as the
    -- puller — silent "no owned headless" log.
    for _, member in ipairs(primary:getAlliance() or {}) do
        local owned = (member == primary)
            or (member.isHeadless and member:isHeadless()
                and member.getParentCharId and member:getParentCharId() == primaryId)
        if owned and member:getName():lower() == target then
            A.pullerCharId = member:getID()
            -- Fresh assignment starts paused — user hits Start explicitly.
            A.pullerPaused = true
            -- Reset the newly-assigned puller's state.puller scratch so a
            -- stale HANDOFF (or any other non-IDLE state) from a prior
            -- assignment doesn't survive re-enabling. Without this reset a
            -- leftover targetId + allianceTarget pair kept the puller
            -- pinned in HANDOFF forever, doing nothing.
            local s = xi.singleplayer.bots.ensure_bot(member:getID())
            if s.puller ~= nil then
                s.puller.state, s.puller.targetId = STATE_IDLE, 0
                s.puller.lastLogMs, s.puller.lastScanTriageMs = 0, 0
            end
            printf(string.format('ai_puller.set_puller: %s (paused)', member:getName()))
            return
        end
    end
    printf(string.format('ai_puller.set_puller: no owned bot "%s"', tostring(botName)))
end

function ai_puller.set_puller_range(primary, rangeYalms)
    if primary == nil then return end
    local A = xi.singleplayer.bots.alliance
    if A == nil then return end
    local r = tonumber(rangeYalms) or 50
    if r < 5   then r = 5   end
    if r > 255 then r = 255 end
    A.pullerRange = r
    printf(string.format('ai_puller.set_puller_range: %dy', r))
end

-- Difficulty range. EXPCHAIN values: 0=TW, 1=EP, 2=DC, 3=EM, 4=T, 5=VT, 6=IT.
-- Each value clamped to [0,6]; min/max swapped if reversed.
function ai_puller.set_puller_con_range(primary, minCon, maxCon)
    if primary == nil then return end
    local A = xi.singleplayer.bots.alliance
    if A == nil then return end
    local mn = tonumber(minCon) or 5
    local mx = tonumber(maxCon) or 6
    if mn < 0 then mn = 0 end
    if mn > 6 then mn = 6 end
    if mx < 0 then mx = 0 end
    if mx > 6 then mx = 6 end
    if mn > mx then mn, mx = mx, mn end
    A.pullerMinCon = mn
    A.pullerMaxCon = mx
    printf(string.format('ai_puller.set_puller_con_range: min=%d max=%d', mn, mx))
end

-- Minimum heal-role (Healer, or Rdm backup) MP% before the puller resumes
-- pulling the next mob. See heal_role_blocks_pull. Clamped to [0, 100].
function ai_puller.set_puller_resume_mpp(primary, mpp)
    if primary == nil then return end
    local A = xi.singleplayer.bots.alliance
    if A == nil then return end
    local v = tonumber(mpp) or 60
    if v < 0   then v = 0   end
    if v > 100 then v = 100 end
    A.pullerResumeMpp = v
    printf(string.format('ai_puller.set_puller_resume_mpp: %d%%', v))
end

-- Name filter. names is a sol::table from C++; iterate ipairs to extract.
-- Empty table clears the filter.
function ai_puller.set_name_filter(primary, names)
    if primary == nil then return end
    local A = xi.singleplayer.bots.alliance
    if A == nil then return end
    local list = {}
    if type(names) == 'table' then
        for _, n in ipairs(names) do
            if type(n) == 'string' and n ~= '' then
                list[#list + 1] = n
            end
        end
    end
    A.pullerNameFilter = list
    printf(string.format('ai_puller.set_name_filter: %d name(s)', #list))
end

-- Scan within 255y of alliance.campAnchor (or primary's position if no anchor),
-- group spawned-and-alive mobs by display name, sort top 20 by count descending,
-- push S2C 0x1A4 PULLER_NEARBY_NAMES.
function ai_puller.request_nearby_names(primary)
    if primary == nil then return end
    local A = xi.singleplayer.bots.alliance
    if A == nil then return end

    -- Pick reference point: prefer camp anchor; fall back to primary position so
    -- the user can discover names before they've set a camp.
    local ax, az
    if A.campAnchor ~= nil then
        ax, az = A.campAnchor.x, A.campAnchor.z
    else
        ax, az = primary:getXPos(), primary:getZPos()
    end

    -- Originally tried bot:getEntitiesInRange (the AoE targetfind pipeline).
    -- Dead end for a PC-side query: targetfind takes the PLAYER_PLAYER
    -- branch when both caller and target are TYPE_PC (targetfind.cpp:145),
    -- which only returns party members — never mobs. To find mobs from a
    -- PC perspective we'd need a non-PC target reference, which is the
    -- chicken-and-egg of discovery.
    --
    -- Instead: walk the whole zone's mob list via zone:getMobs() and
    -- filter by distance ourselves. Cheap (one zone-list walk per Refresh
    -- click, not per-tick), and bypasses every targetfind allegiance/
    -- battleID gate.
    local zone = primary.getZone and primary:getZone()
    if zone == nil or zone.getMobs == nil then return end
    local candidates = zone:getMobs() or {}

    -- zone:getMobs() guarantees the entries are mobs (CLuaMobEntity), so the
    -- objtype check we previously had was both redundant and broken — sol
    -- doesn't expose bound methods as readable fields, so `ent.objtype`
    -- evaluated as nil → the and-chain short-circuited and EVERY mob was
    -- rejected with "not a mob".
    --
    -- zone:getMobs() also returns ALL mob definitions including despawned
    -- ones; isDead() catches those. Among the survivors we filter by
    -- distance from anchor and non-empty name.
    local counts = {}  -- [name] = count
    local rej_dead, rej_distance, rej_name, kept = 0, 0, 0, 0
    for _, ent in pairs(candidates) do
        if ent:isDead() then
            rej_dead = rej_dead + 1
        else
            local d  = math.sqrt((ent:getXPos() - ax) ^ 2 + (ent:getZPos() - az) ^ 2)
            if d > 255 then
                rej_distance = rej_distance + 1
            else
                local name = ent:getName() or ''
                if name == '' then
                    rej_name = rej_name + 1
                else
                    counts[name] = (counts[name] or 0) + 1
                    kept = kept + 1
                end
            end
        end
    end
    printf('[ai_puller] filter breakdown: kept=%d, rej_dead=%d, rej_distance=%d, rej_name=%d',
        kept, rej_dead, rej_distance, rej_name)

    -- Flatten + sort by count desc, alphabetical tiebreak. Take top 20.
    local list = {}
    for name, c in pairs(counts) do
        list[#list + 1] = { name = name, count = c }
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    while #list > 20 do list[#list] = nil end

    printf('[ai_puller] request_nearby_names: %d zone mob(s), %d unique name(s) within 255y, top %d pushed for %s',
        #candidates, #list, math.min(#list, 20), primary:getName())

    -- Push via the engine-bound packet pusher. The Lua binding for sending a
    -- typed S2C packet from Lua is fork-specific; we use a helper that takes
    -- the name/count list. Naming follows existing 0x1A0/0x1A3 ack pattern.
    if primary.pushPullerNearbyNames ~= nil then
        primary:pushPullerNearbyNames(list)
    else
        printf('[ai_puller] request_nearby_names: pushPullerNearbyNames binding missing')
    end
end

-----------------------------------
-- Helpers
-----------------------------------
local function get_primary(bot)
    -- Puller is a headless; primary is its parent.
    local pid = bot.getParentCharId and bot:getParentCharId() or 0
    if pid == 0 then return nil end
    return GetPlayerByID(pid)
end

local function planar_dist(ax, az, bx, bz)
    local dx = bx - ax
    local dz = bz - az
    return math.sqrt(dx * dx + dz * dz)
end

-- Any aggro at all → return to camp. Cheap check off primary's notoriety.
local function alliance_under_threat(primary)
    if primary == nil or primary.getNotorietyList == nil then return false end
    local list = primary:getNotorietyList() or {}
    return #list > 0
end

-- Pick a pull tool the bot can actually use right now. Returns:
--   'dia'    — spell known + recast clear + enough MP
--   'ranged' — has a ranged weapon, not already ranging
--   nil      — neither, can't pull
local function pick_pull_tool(bot)
    -- Dia
    if bot:hasSpell(DIA_SPELL_ID)
       and (not bot.canUseSpell or bot:canUseSpell(DIA_SPELL_ID))
       and not bot:hasRecast(xi.recast.MAGIC, DIA_SPELL_ID)
    then
        local spell = GetSpell and GetSpell(DIA_SPELL_ID) or nil
        local mp    = bot:getMP() or 0
        local cost  = (spell and spell.getMPCost and spell:getMPCost()) or 0
        if mp >= cost then return 'dia' end
    end
    -- Ranged weapon present? getRangedDmg > 0 is a decent proxy (any equipped
    -- ranged + ammo combination). Skip if already firing. The engine binding
    -- is getRangedDmg (no 'a' before 'ge'); typo'ing this to getRangedDamage
    -- silently false-routes — Lua reports the method as nil and short-circuits.
    if bot.getRangedDmg and (bot:getRangedDmg() or 0) > 0
       and not (bot.isBotRangedAttacking and bot:isBotRangedAttacking())
    then
        return 'ranged'
    end
    return nil
end

local function tool_range(tool)
    if tool == 'dia'    then return PULL_TOOL_DIA_RANGE    end
    if tool == 'ranged' then return PULL_TOOL_RANGED_RANGE end
    return 0
end

-----------------------------------
-- Target scan
-----------------------------------
-- Walk the zone's mob list and pick the closest qualifying mob within scanRange
-- of the camp anchor. The "from a PC, find mobs" engine query is unreachable —
-- bot:getEntitiesInRange takes the PLAYER_PLAYER branch in targetfind (both
-- caller and target are TYPE_PC) and only returns party members. So we walk
-- zone:getMobs() and filter ourselves; same pattern as request_nearby_names.
--
-- Selection rule: anchor distance gates inclusion (mob must be within scanRange
-- of camp), but the WINNER is the candidate closest to the bot's current
-- position — minimizes how far the puller has to travel to engage.
local function scan_for_target(bot, primary, anchor, scanRange)
    if anchor == nil then return nil end
    local zone = bot.getZone and bot:getZone()
    if zone == nil or zone.getMobs == nil then return nil end
    local candidates = zone:getMobs() or {}

    -- Build a set of mobs already on primary's notoriety to skip them fast.
    local notorietyByID = {}
    if primary and primary.getNotorietyList then
        for _, m in ipairs(primary:getNotorietyList() or {}) do
            notorietyByID[m:getID()] = true
        end
    end

    local A = xi.singleplayer.bots.alliance
    local minCon = (A and A.pullerMinCon) or 5
    local maxCon = (A and A.pullerMaxCon) or 6

    -- Name filter: build a case-insensitive set for fast lookup, empty = no filter.
    local nameFilter = nil
    if A and type(A.pullerNameFilter) == 'table' and #A.pullerNameFilter > 0 then
        nameFilter = {}
        for _, n in ipairs(A.pullerNameFilter) do
            nameFilter[n:lower()] = true
        end
    end

    local bx, _, bz = bot:getXPos(), bot:getYPos(), bot:getZPos()

    -- TRIAGE (#puller-not-moving): tally rejection reasons for the closest
    -- candidates in-range, print top few once per 5s so we can see WHY
    -- scan_for_target is returning nil. Filter values are already in the
    -- IDLE log message; this shows the per-candidate side.
    local triage = { rej_missing = 0, rej_dead = 0, rej_engaged = 0,
                     rej_notoriety = 0, rej_range = 0, rej_con = {}, rej_name = {} }

    -- Guard each entity access with pcall so any weird half-init mob doesn't
    -- crash the whole tick. `isEngaged()` already captures "claimed and
    -- fighting" — the mob's engine-side ClaimID has no Lua binding
    -- (getClaimID was speculatively called but doesn't exist), so we drop it.
    -- Worst case: puller tries to pull a mob someone-else-claimed-but-not-yet-
    -- engaged, engine rejects the pull, next tick puller moves on.
    local best, bestBotDist = nil, math.huge
    for _, ent in pairs(candidates) do
        local ok_dead, dead     = pcall(function() return ent:isDead() end)
        local ok_eng,  engaged  = pcall(function() return ent:isEngaged() end)
        local ok_id,   id       = pcall(function() return ent:getID() end)
        if not (ok_dead and ok_eng and ok_id) then
            triage.rej_missing = triage.rej_missing + 1
        elseif dead then
            triage.rej_dead = triage.rej_dead + 1
        elseif engaged then
            triage.rej_engaged = triage.rej_engaged + 1
        elseif notorietyByID[id] then
            triage.rej_notoriety = triage.rej_notoriety + 1
        else
            local _, ex = pcall(function() return ent:getXPos() end)
            local _, ez = pcall(function() return ent:getZPos() end)
            ex = ex or 0
            ez = ez or 0
            local dAnchor = planar_dist(anchor.x, anchor.z, ex, ez)
            if dAnchor > scanRange then
                triage.rej_range = triage.rej_range + 1
            else
                -- Con check vs the puller. `checkDifficulty` returns
                -- EMobDifficulty as uint8: 0=TooWeak, 1=IncrediblyEasyPrey,
                -- 2=EasyPrey, 3=DecentChallenge, 4=EvenMatch, 5=Tough,
                -- 6=VeryTough, 7=IncrediblyTough. Called on the PC entity
                -- with the mob as arg. Guard with pcall in case some entity
                -- lacks the binding (statues etc.).
                local ok_con, conN = pcall(function() return bot:checkDifficulty(ent) end)
                if not ok_con then conN = nil end
                local conOk = type(conN) == 'number' and conN >= minCon and conN <= maxCon

                -- Name filter
                local _, rawName = pcall(function() return ent:getName() end)
                rawName = rawName or ''
                local nameOk = true
                if nameFilter ~= nil then
                    nameOk = nameFilter[rawName:lower()] == true
                end

                if not conOk then
                    triage.rej_con[rawName] = (triage.rej_con[rawName] or 0) + 1
                elseif not nameOk then
                    triage.rej_name[rawName] = (triage.rej_name[rawName] or 0) + 1
                else
                    local dBot = planar_dist(bx, bz, ex, ez)
                    if dBot < bestBotDist then
                        best, bestBotDist = ent, dBot
                    end
                end
            end
        end
    end

    -- Rate-limited triage dump when we found nothing. Uses the bot's puller
    -- pstate lastLogMs slot so it interleaves with the tick's IDLE log line.
    if best == nil then
        local ps = xi.singleplayer.bots.ensure_bot(bot:getID()).puller
        local now = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
        if ps and (now - (ps.lastScanTriageMs or 0)) > 5000 then
            ps.lastScanTriageMs = now
            local nameKeys = {}
            if nameFilter ~= nil then
                for k in pairs(nameFilter) do table.insert(nameKeys, k) end
            end
            printf(string.format(
                '[ai_puller/scan] %s: missing=%d dead=%d engaged=%d notoriety=%d oor=%d nameFilter={%s}',
                bot:getName(), triage.rej_missing, triage.rej_dead, triage.rej_engaged,
                triage.rej_notoriety, triage.rej_range,
                table.concat(nameKeys, ',')))
            local function dump(tbl, tag)
                local pairs_list = {}
                for name, c in pairs(tbl) do table.insert(pairs_list, name .. '=' .. c) end
                if #pairs_list > 0 then
                    printf(string.format('[ai_puller/scan] %s: rej_%s: %s',
                        bot:getName(), tag, table.concat(pairs_list, ', ')))
                end
            end
            dump(triage.rej_con,  'con')
            dump(triage.rej_name, 'name')
        end
    end

    return best
end

-----------------------------------
-- Per-bot puller state. Stored on the bot's scratch entry under .puller.
-----------------------------------
local function pstate(bot)
    local s = xi.singleplayer.bots.ensure_bot(bot:getID())
    s.puller = s.puller or {
        state         = STATE_IDLE,
        targetId      = 0,
        lastLogMs     = 0,
    }
    return s.puller
end

local function log_once(p, msg, bot)
    local now = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
    if (now - (p.lastLogMs or 0)) > 5000 then
        p.lastLogMs = now
        printf(string.format('[ai_puller] %s: %s', bot:getName(), msg))
    end
end

-- Heal-role pull gate. A headless puller shouldn't drag in the next mob while
-- the party's healing can't sustain a fight: hold IDLE→SCOUTING while any
-- heal-role member is dead or low on MP. Roles, not jobs — Healer (WHM) is the
-- authoritative heal role; the Rdm role is a backup healer, consulted ONLY when
-- the party has no Healer role at all. Scans the puller's party, which includes
-- the primary, so the gate still applies when the primary is the heal role.
-- Threshold is the configurable alliance.pullerResumeMpp.
local PULLER_RESUME_MPP_DEFAULT = 60

-- Returns (false) when healing is ready to pull, or (true, member, reason)
-- naming the heal-role member that's blocking and why ('dead' | '<n>% MP').
local function heal_role_blocks_pull(bot)
    local R = xi.singleplayer.bots.Role or {}
    local A = xi.singleplayer.bots.alliance
    local minMpp = (A and A.pullerResumeMpp) or PULLER_RESUME_MPP_DEFAULT

    -- Bucket the party's heal roles. Healer is authoritative; Rdm is the
    -- fallback used only when no Healer role is present in the party.
    local healers, backups = {}, {}
    for _, member in ipairs(bot:getParty() or {}) do
        local state = A and A.bot and A.bot[member:getID()]
        local role  = state and state.role
        if role == R.Healer then
            table.insert(healers, member)
        elseif role == R.Rdm then
            table.insert(backups, member)
        end
    end
    local group = (#healers > 0) and healers or backups

    for _, member in ipairs(group) do
        local hpp = (member.getHPP and member:getHPP()) or 100
        if hpp <= 0 then
            return true, member, 'dead'
        end
        local mpp = (member.getMPP and member:getMPP()) or 100
        if mpp < minMpp then
            return true, member, string.format('%d%% MP', mpp)
        end
    end
    return false
end

-----------------------------------
-- Main tick. Called from bots.runCombatTick for the puller bot only.
-----------------------------------
function ai_puller.tick(bot)
    local A = xi.singleplayer.bots.alliance
    if A == nil then return end

    -- Active only in camp formation with a non-zero anchor.
    if A.walkingFormation ~= 'camp' or A.campAnchor == nil then return end

    -- Engaged handoff: once the alliance's fight starts and the puller is
    -- swinging, defer to the normal role tick + formation dispatch. Keep
    -- p.state as-is (usually HANDOFF) so the fight-end unwind still works.
    -- Next tick, when disengaged, tick returns to running state machine.
    if bot.isEngaged and bot:isEngaged() then return end

    local p       = pstate(bot)
    local primary = get_primary(bot)
    if primary == nil then return end

    local underThreat = alliance_under_threat(primary)
    local anchor      = A.campAnchor
    local bx, _, bz   = bot:getXPos(), bot:getYPos(), bot:getZPos()
    local anchorDist  = planar_dist(bx, bz, anchor.x, anchor.z)

    -- ABORT — any alliance threat sends us straight to Returning. The pulled
    -- mob (if we pulled one) is already on primary notoriety, so it'll trigger
    -- this branch and we naturally walk back with it on our tail.
    if underThreat and p.state ~= STATE_RETURNING and p.state ~= STATE_HANDOFF then
        p.state = STATE_RETURNING
        -- Don't interrupt explicitly — the parallel pathTo below + the engine's
        -- "moving cancels cast" handling cover the common cases. If a cast
        -- finishes while we're running, no harm.
    end

    if p.state == STATE_IDLE then
        if underThreat then
            log_once(p, 'IDLE: underThreat (notoriety non-empty), waiting', bot)
            return
        end
        -- Pause gate: only blocks IDLE→SCOUTING. A pull already in flight
        -- (higher state) continues until natural completion, matching the
        -- "Stop shouldn't cancel an active pull" spec.
        if A.pullerPaused then
            log_once(p, 'IDLE: paused (Start button not pressed)', bot)
            return
        end
        -- Heal-role gate: hold if the party's healing (Healer role, or Rdm
        -- backup) is dead or low on MP so we don't pull into a fight it can't
        -- sustain. Only gates the next pull; an in-flight pull is unaffected.
        local healBlocked, healBot, healReason = heal_role_blocks_pull(bot)
        if healBlocked then
            log_once(p, string.format('IDLE: heal role not ready (%s: %s)', healBot:getName(), healReason), bot)
            return
        end
        -- Pick a tool first; no point scouting if we can't pull.
        local tool = pick_pull_tool(bot)
        if tool == nil then
            log_once(p, 'IDLE: pick_pull_tool=nil (no Dia + no ranged weapon)', bot)
            return
        end
        local target = scan_for_target(bot, primary, anchor, A.pullerRange or 50)
        if target == nil then
            log_once(p, string.format('IDLE: scan_for_target=nil (tool=%s pullerRange=%d con=%d..%d nameFilter=%d)',
                tool, A.pullerRange or 50, A.pullerMinCon or 5, A.pullerMaxCon or 6,
                (type(A.pullerNameFilter) == 'table') and #A.pullerNameFilter or 0), bot)
            return
        end
        log_once(p, string.format('IDLE→SCOUTING: target=%s id=%d tool=%s', target:getName(), target:getID(), tool), bot)
        p.state    = STATE_SCOUTING
        p.targetId = target:getID()
        return

    elseif p.state == STATE_SCOUTING then
        local target = GetEntityByID(p.targetId)
        -- getClaimID has no Lua binding (see scan_for_target); use
        -- isEngaged as the "someone else grabbed it" signal.
        if target == nil or target:isDead() or target:isEngaged() then
            log_once(p, string.format('SCOUTING→IDLE: target lost (nil=%s dead=%s eng=%s)',
                tostring(target == nil),
                target and tostring(target:isDead()) or 'na',
                target and tostring(target:isEngaged()) or 'na'), bot)
            p.state, p.targetId = STATE_IDLE, 0
            return
        end
        local tool = pick_pull_tool(bot)
        if tool == nil then
            log_once(p, 'SCOUTING→IDLE: pick_pull_tool=nil', bot)
            p.state, p.targetId = STATE_IDLE, 0
            return
        end
        local tx, _, tz = target:getXPos(), target:getYPos(), target:getZPos()
        local d = planar_dist(bx, bz, tx, tz)
        if d <= tool_range(tool) then
            log_once(p, string.format('SCOUTING→PULLING: d=%.1f tool=%s(range=%d)',
                d, tool, tool_range(tool)), bot)
            p.state = STATE_PULLING
            return
        end
        log_once(p, string.format('SCOUTING: stepToward target d=%.1f tool_range=%d',
            d, tool_range(tool)), bot)
        xi.singleplayer.bots.ai_move.stepToward(bot, tx, target:getYPos(), tz)
        return

    elseif p.state == STATE_PULLING then
        local target = GetEntityByID(p.targetId)
        if target == nil or target:isDead() then
            log_once(p, 'PULLING→RETURNING: target lost/dead', bot)
            p.state, p.targetId = STATE_RETURNING, 0
            return
        end
        local tool = pick_pull_tool(bot)
        if tool == 'dia' then
            log_once(p, string.format('PULLING: casting Dia on %s', target:getName() or '?'), bot)
            if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_premagic then
                xi.singleplayer.bots.ai_equip_swap.equip_premagic(bot, DIA_SPELL_ID)
            end
            bot:castSpell(DIA_SPELL_ID, target)
        elseif tool == 'ranged' then
            log_once(p, string.format('PULLING: rangedAttack on %s', target:getName() or '?'), bot)
            if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_preranged then
                xi.singleplayer.bots.ai_equip_swap.equip_preranged(bot)
            end
            bot:rangedAttack(target)
        else
            -- Lost the tool between picks (recast triggered, ran out of MP, etc.).
            -- Back to scouting; next tick re-picks or returns to idle.
            log_once(p, 'PULLING→SCOUTING: tool lost between picks', bot)
            p.state = STATE_SCOUTING
            return
        end
        -- After pulling, transition to Returning. The mob will land on primary's
        -- notoriety in a tick or two, which is fine — abort rule keeps us in
        -- Returning anyway.
        p.state = STATE_RETURNING
        return

    elseif p.state == STATE_RETURNING then
        if anchorDist <= AT_ANCHOR_DIST then
            log_once(p, string.format('RETURNING→HANDOFF: at anchor (dist=%.1f)', anchorDist), bot)
            p.state = STATE_HANDOFF
            return
        end
        log_once(p, string.format('RETURNING: stepToward anchor (dist=%.1f)', anchorDist), bot)
        xi.singleplayer.bots.ai_move.stepToward(bot, anchor.x, bot:getYPos(), anchor.z)
        return

    elseif p.state == STATE_HANDOFF then
        -- At anchor. If we have a pulled target and alliance hasn't picked one
        -- yet, set allianceTarget so the assist engages.
        if (A.allianceTarget or 0) == 0 and p.targetId ~= 0 then
            local target = GetEntityByID(p.targetId)
            if target ~= nil and not target:isDead() then
                xi.singleplayer.bots.set_alliance_target(p.targetId)
                log_once(p, string.format('HANDOFF: set_alliance_target(%d) name=%s',
                    p.targetId, target:getName() or '?'), bot)
            else
                log_once(p, string.format('HANDOFF: target %d lost/dead pre-handoff', p.targetId), bot)
            end
        else
            log_once(p, string.format('HANDOFF: allianceTarget=%d targetId=%d underThreat=%s',
                A.allianceTarget or 0, p.targetId, tostring(underThreat)), bot)
        end
        -- Wait for alliance to finish (allianceTarget cleared, notoriety empty).
        -- Note: keep targetId until the fight is over so we don't re-pull the
        -- same mob mid-fight if ai_threat happens to clear allianceTarget briefly.
        if not underThreat and (A.allianceTarget or 0) == 0 then
            p.state, p.targetId = STATE_IDLE, 0
        end
        return
    end
end

return m
