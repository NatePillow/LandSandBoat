-----------------------------------
-- ai_move — central home for bot movement primitives and the
-- per-tick movement driver.
--
-- Receives content moved from autoai.lua during the autoai split:
--   * Movement primitives — stepToward, stopPointFrom, faceTarget,
--     followEntity, followBehind, followBeside.
--   * (Pending pass) Stuck-bot recovery + xi.singleplayer.bots.ai_move.runMovementTick.
--
-- Public API is namespaced under xi.singleplayer.bots.ai_move. Callers updated from
-- xi.singleplayer.bots.stepToward etc. to xi.singleplayer.bots.ai_move.stepToward etc. in the same
-- pass that moved the content.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_move')

xi           = xi           or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.ai_move = xi.singleplayer.bots.ai_move or {}

-- Compute planar distance (XZ — FFXI ignores Y for distance).
local function planarDist(ax, az, bx, bz)
    local dx = bx - ax
    local dz = bz - az
    return math.sqrt(dx * dx + dz * dz)
end

-- Per-step arrival distance. Sub-yard threshold lets pathTo run every tick by
-- exactly the lag amount when the followee is moving; 0.05y avoids re-issuing
-- pathTo for sub-cm jitter when the followee is stationary.
local ARRIVAL_DIST = 0.05

-- Step a headless toward (tx, ty, tz) via the engine's CPathFind. pathTo
-- updates the path target each tick (cheap — lazy recompute + re-walk).
-- The AI container's FollowPath() handles velocity smoothing, animation
-- flags, and the proper packet cadence.
--
-- Pathfind deadband, ROLE-AWARE:
--   * Mages (Healer/Nuker/Rdm): 1.5y. The is_moving() gate in
--     process_pre_cast_checks bails on any motion, so mages need
--     enough slack to fully park between formation updates. Their
--     formation stop point (12y perp from mob) doesn't require
--     precision — anywhere near is castable.
--   * Melee/Tank: 0.3y. Their formation target is getMeleeRange − 1.0
--     (1y inside max range). A 1.5y deadband would park them at
--     getMeleeRange + 0.5 — OUT of range. Tight deadband keeps them in
--     range as the mob moves.
--
-- Returns true if a step was issued. Primaries are never stepped — auto-
-- movement is headless-only; the player drives themselves.
xi.singleplayer.bots.ai_move.stepToward = function(entity, tx, ty, tz)
    if entity == nil then return false end
    if entity.getHP and entity:getHP() <= 0 then return false end
    if not (entity.isHeadless and entity:isHeadless()) then return false end
    if entity.pathTo == nil then return false end

    local ex, _, ez = entity:getXPos(), entity:getYPos(), entity:getZPos()
    local d = planarDist(ex, ez, tx, tz)
    if d <= ARRIVAL_DIST then return false end

    local s = entity.getID and xi.singleplayer.bots.ensure_bot(entity:getID()) or nil
    local role     = s and s.role
    local R        = xi.singleplayer.bots.Role or {}
    local deadband = (role == R.Tank or role == R.Melee) and 0.3 or 1.5
    if d > deadband then
        -- Stamp last-moved time — only when we're actually going to pathTo,
        -- not just when stepToward was CALLED. ai_rest reads this and
        -- refuses to re-add HEALING within REST_GRACE_MS of a step (#210
        -- flicker prevention). Stamping before the deadband check was the
        -- root cause of "moved 0ms ago" flicker-guard spam on mages who
        -- were already inside the deadband.
        if s ~= nil then
            s.lastMovedMs = math.floor(os.time() * 1000 + (os.clock() % 1.0) * 1000)
        end

        -- HEALING cancel: pathTo doesn't trip the engine's "client moved →
        -- cancel HEALING" path that real-client input does. Drop the effect
        -- so the visual matches the action; ai_rest re-applies HEALING on
        -- the next idle tick if conditions still allow.
        if entity.hasStatusEffect and entity:hasStatusEffect(xi.effect.HEALING) then
            entity:delStatusEffect(xi.effect.HEALING)
        end

        -- Wall clearance (#189): clamp the per-tick destination so the bot
        -- stops 1.5y before any wall instead of pressing against it.
        -- raycastClampTo returns the requested (tx,ty,tz) unchanged when the
        -- path is clear or when the zone has no navmesh; otherwise it returns
        -- a safe-distance point along the same line. Without this call,
        -- formation stop points behind a mob can land inside terrain and
        -- mages walk straight into walls.
        --
        -- Gated by BOT_RESPECT_GEOMETRY (#234). Default off: bots use navmesh
        -- via pathTo for ROUTE planning but skip the per-tick step clamp, so
        -- they punch through walls when the route fails instead of freezing
        -- against terrain. Flip true to get the realistic-but-fragile behavior.
        if entity.raycastClampTo ~= nil
           and xi.settings.singleplayer
           and xi.settings.singleplayer.BOT_RESPECT_GEOMETRY then
            tx, ty, tz = entity:raycastClampTo(tx, ty, tz)
        end
        entity:pathTo(tx, ty, tz)
    end
    return true
end

-- Slot-ring step (#234 follow-up). Iterates an ordered list of candidate
-- positions, calling pathTo without WALLHACK so the engine returns false on
-- off-mesh / unreachable destinations. First candidate that returns true
-- wins; remaining candidates are skipped. On full exhaustion (Tier 2), the
-- bot is hard-warped to `primary` via setPos — the only escape from a bot
-- that's truly disconnected from the navmesh.
--
-- candidates: array of { x, y, z, label } from ai_formation.candidates_for.
-- primary: the primary char entity (warp target on exhaustion).
--
-- WALLHACK is the engine's "if you can't reach the destination by mesh,
-- append it as a final waypoint and walk the straight line through walls"
-- fallback (pathfind.cpp::FindClosestPath, line 506). It's what was letting
-- bots end up inside terrain pre-fix. Stripping it from the per-tick step
-- means false return value === "this slot is unreachable, try the next."
xi.singleplayer.bots.ai_move.stepToward_any = function(bot, candidates, primary)
    if bot == nil or candidates == nil or #candidates == 0 then return false end
    if not (bot.isHeadless and bot:isHeadless()) then return false end
    if bot.pathTo == nil then return false end
    if bot.getHP and bot:getHP() <= 0 then return false end

    -- Stamp last-moved + cancel HEALING once for the whole batch (shared
    -- prologue with stepToward; doing it per-candidate would be wasteful).
    local s = bot.getID and xi.singleplayer.bots.ensure_bot(bot:getID()) or nil
    if s ~= nil then
        s.lastMovedMs = math.floor(os.time() * 1000 + (os.clock() % 1.0) * 1000)
    end
    if bot.hasStatusEffect and bot:hasStatusEffect(xi.effect.HEALING) then
        bot:delStatusEffect(xi.effect.HEALING)
    end

    -- RUN | SCRIPT but NOT WALLHACK. pathTo returns true on a real route,
    -- false when FindPath couldn't reach the destination via the mesh.
    --
    -- Wiggle-prevention threshold: pathfind.cpp::arePositionsClose returns
    -- true (and FindPath bails out with false) at <1.0y 3D distance. If
    -- our planar (2D) check used the same 1.0y threshold we'd ping-pong
    -- between candidates at the boundary — bot at 1.01y plane-distance
    -- but <1.0y 3D distance: my check says "not close, call pathTo,"
    -- FindPath says "you're here, returning false," we'd treat false as
    -- "unreachable" and walk to the NEXT slot, then wiggle back next tick.
    -- 2.0y gives enough slop to absorb the boundary plus a half-yalm of
    -- 2D-vs-3D rounding.
    local SLOT_CLOSE_ENOUGH = 2.0
    local flags = xi.path.flag.RUN + xi.path.flag.SCRIPT
    local ex, ey, ez = bot:getXPos(), bot:getYPos(), bot:getZPos()
    for _, cand in ipairs(candidates) do
        local d = planarDist(ex, ez, cand.x, cand.z)
        -- "Close enough" only counts with a CLEAR navmesh line to the slot.
        -- Without this, a bot pressed against a wall is within SLOT_CLOSE_ENOUGH
        -- of a slot on the FAR side of that wall, gets accepted as "arrived,"
        -- and never reaches the pathTo reachability check below — so the ring
        -- can't skip the bad slot. That's the melees-thrashing-against-a-wall
        -- case (accept-here one tick, shoved off + pathTo-fails-go-elsewhere the
        -- next). With a wall in the way, fall through to pathTo, which returns
        -- false for the unreachable slot and moves on to the next candidate.
        if d <= SLOT_CLOSE_ENOUGH
           and (bot.raycastClear == nil or bot:raycastClear(ex, ey, ez, cand.x, cand.y, cand.z)) then
            -- Close enough and reachable — bot is effectively at this candidate.
            if s ~= nil then s.ringExhaustedTicks = 0 end
            return true
        end
        if bot:pathTo(cand.x, cand.y, cand.z, flags) then
            if s ~= nil then s.ringExhaustedTicks = 0 end
            return true
        end
    end

    -- Tier 2: ring exhausted. Old behavior warped the bot to primary
    -- immediately. That misfires when the mob is in a slightly awkward
    -- position mid-pull (e.g. all 17 AoE rays hit walls) — mages teleport
    -- to primary every ~400ms tick, producing the "just follows primary"
    -- symptom user observed 2026-07-07.
    --
    -- New behavior: track consecutive exhaustion ticks per bot. Below the
    -- threshold, just hold position — the mob or primary will shift and
    -- next tick's candidates likely resolve. Only warp when the bot is
    -- truly stuck (many consecutive exhausted ticks with zero movement),
    -- which is the genuine "clipped into terrain" case the warp was
    -- designed for.
    if s ~= nil then
        s.ringExhaustedTicks = (s.ringExhaustedTicks or 0) + 1
    end
    local exhaustionCount = s and s.ringExhaustedTicks or 0
    local EXHAUSTION_WARP_THRESHOLD = 25  -- ~10s at 400ms tick
    if exhaustionCount < EXHAUSTION_WARP_THRESHOLD then
        return false
    end
    if primary ~= nil then
        printf('[ai_move] %s slot ring exhausted for %d ticks - warping to primary %s',
            bot:getName(), exhaustionCount, primary:getName())
        bot:setPos(primary:getXPos(), primary:getYPos(), primary:getZPos())
        if s ~= nil then s.ringExhaustedTicks = 0 end
        return true
    end
    return false
end

-- Compute a "stop point" desiredDist yalms from target along the bot→target
-- vector. The result is the position the bot should walk *to* in order to
-- end up at desiredDist from target. Returns nil if the bot is already
-- within desiredDist (no movement needed — bot is in position).
xi.singleplayer.bots.ai_move.stopPointFrom = function(bot, target, desiredDist)
    local bx, bz = bot:getXPos(), bot:getZPos()
    local tx, ty, tz = target:getXPos(), target:getYPos(), target:getZPos()
    local dx, dz = tx - bx, tz - bz
    local d = math.sqrt(dx * dx + dz * dz)
    if d <= desiredDist then return nil end
    local ratio = (d - desiredDist) / d
    return bx + dx * ratio, ty, bz + dz * ratio
end

-- Snap entity's facing toward target without moving. Used by the engaged
-- melee tick so a bot in melee range keeps looking at the mob even when
-- they don't need to take a step. The setPos here is rotation-only (same
-- x/y/z) — it's the engine's idiomatic "set rotation" path. Skips when
-- the requested rotation matches current so we don't spam position-update
-- packets every tick for no visual change.
xi.singleplayer.bots.ai_move.faceTarget = function(entity, target)
    if entity == nil or target == nil then return false end
    local ex, ey, ez = entity:getXPos(), entity:getYPos(), entity:getZPos()
    local tx, tz     = target:getXPos(), target:getZPos()
    if planarDist(ex, ez, tx, tz) < 0.1 then return false end
    local desired = utils.getWorldRotation({ x = ex, y = ey, z = ez },
                                           { x = tx, y = target:getYPos(), z = tz })
    if entity:getRotPos() == desired then return false end
    entity:setPos(ex, ey, ez, desired)
    return true
end

-- Maintain a desired distance relative to another entity. Steps every tick
-- toward a "stop point" desiredDist yalms from target along the bot→target
-- vector. No dead-band: once steady-state, the bot's per-tick step matches
-- the target's per-tick movement (no chunked dashing). Bot lives within
-- ARRIVAL_DIST (1y) of the stop point.
--
-- Backward-compat: existing callers pass (minDist, maxDist). minDist is no
-- longer meaningful (the stop point itself enforces distance). maxDist is
-- treated as desiredDist — the bot will track to that distance from target.
xi.singleplayer.bots.ai_move.followEntity = function(entity, target, minDist, maxDist)
    if entity == nil or target == nil then return false end
    local desiredDist = maxDist or 12
    local sx, sy, sz = xi.singleplayer.bots.ai_move.stopPointFrom(entity, target, desiredDist)
    if sx == nil then return false end
    return xi.singleplayer.bots.ai_move.stepToward(entity, sx, sy, sz)
end

-- Stay `offset` yalms behind the target, where "behind" is based on the
-- target's facing rotation. The computed offset point IS the destination —
-- step toward it directly via stepToward (was previously routed through
-- followEntity with a fake target, which gave incorrect stop-point math
-- under the post-2025 stop-point-based follow semantics).
xi.singleplayer.bots.ai_move.followBehind = function(entity, target, offset)
    if entity == nil or target == nil then return false end
    offset = offset or 2
    local rot = target:getRotPos()
    local angle = (rot / 128) * math.pi + math.pi
    local tx = target:getXPos() + math.sin(angle) * offset
    local tz = target:getZPos() + math.cos(angle) * offset
    return xi.singleplayer.bots.ai_move.stepToward(entity, tx, target:getYPos(), tz)
end

-- Stay `offset` yalms to the side of the target. side > 0 = right of facing,
-- side < 0 = left. The computed offset point IS the destination — step
-- toward it directly via stepToward.
xi.singleplayer.bots.ai_move.followBeside = function(entity, target, offset, side)
    if entity == nil or target == nil then return false end
    offset = offset or 1.5
    side   = side or 1
    local rot = target:getRotPos()
    local angle = (rot / 128) * math.pi + ((side >= 0) and (math.pi / 2) or (-math.pi / 2))
    local tx = target:getXPos() + math.sin(angle) * offset
    local tz = target:getZPos() + math.cos(angle) * offset
    return xi.singleplayer.bots.ai_move.stepToward(entity, tx, target:getYPos(), tz)
end

-- Stuck-bot recovery: rolling-window expected-vs-actual displacement check.
-- A bot that's been issued movement intent every tick over a window of K
-- ticks but only moved a few yalms is wedged on geometry or fighting the
-- navmesh — warp them to the primary so they can rejoin the alliance.
--
-- Window length and floor are tuned so pathTo's compute-then-walk first
-- ticks don't false-trigger: 15 ticks (~6s at 400ms cadence) gives the
-- engine plenty of time to start moving, and 2y of expected displacement
-- is well below the ~30y a walking PC covers in 6s.
--
-- "stepped=true every sample" is the formation-aware gate: walkingFormation
-- 'off' / 'camp' produce stepped=false at steady state (target_for returns
-- current position or anchor → stepToward arrives immediately), so the
-- window never fills with all-stepped samples and detection naturally
-- skips intentional-still scenarios.
local STUCK_WINDOW              = 15
local MIN_EXPECTED_DISPLACEMENT = 2.0

local function detect_stuck(bot, state, stepped, primary)
    if not bot:isHeadless() then return end
    if primary == nil then return end

    state.stuckHistory = state.stuckHistory or {}
    table.insert(state.stuckHistory, {
        stepped = stepped,
        x       = bot:getXPos(),
        z       = bot:getZPos(),
    })
    while #state.stuckHistory > STUCK_WINDOW do
        table.remove(state.stuckHistory, 1)
    end

    if #state.stuckHistory < STUCK_WINDOW then return end

    for _, s in ipairs(state.stuckHistory) do
        if not s.stepped then return end
    end

    local first = state.stuckHistory[1]
    local cx, cz = bot:getXPos(), bot:getZPos()
    local displacement = math.sqrt((cx - first.x) ^ 2 + (cz - first.z) ^ 2)
    if displacement < MIN_EXPECTED_DISPLACEMENT then
        bot:setPos(primary:getXPos(), primary:getYPos(), primary:getZPos())
        state.stuckHistory = {}
        printf('[ai_move] %s stuck: %d ticks stepping, displacement %.2fy < %.1fy - warped to primary',
            bot:getName(), STUCK_WINDOW, displacement, MIN_EXPECTED_DISPLACEMENT)
    end
end

-- True iff the bot is currently locked in an action whose visuals look bad
-- when the entity also moves. Mirrors what CState::CanFollowPath() does for
-- mob/trust movement: while a mob is mid-cast / mid-WS / mid-ability /
-- mid-ranged, the engine pauses its navmesh follow so the action animation
-- plays cleanly. We pause pathTo for the same reason so the bot doesn't
-- stutter-step through the cast bar and the client doesn't see conflicting
-- "actor is moving" and "actor is casting" packets back-to-back.
local function botIsBusyActioning(bot)
    return xi.singleplayer.bots.ai_util.is_busy_actioning(bot)
end

xi.singleplayer.bots.ai_move.runMovementTick = function(bot, state)
    xi.singleplayer.bots.get_primary_for_bot(bot, state)
    local A         = xi.singleplayer.bots.alliance
    local target    = xi.singleplayer.bots.get_current_mob_target()
    local engaged   = xi.singleplayer.bots.ai_util.isAlive(target)
    local stepped   = false
    local assistId  = xi.singleplayer.bots.get_assist_charId()

    -- Puller ownership: when this bot is the active puller in any non-IDLE
    -- state (SCOUTING/PULLING/RETURNING/HANDOFF), ai_puller.tick already
    -- fired its own stepToward this tick. Formation dispatch below would
    -- fight it — walking the puller back to camp anchor on every tick and
    -- producing the "wiggle in place" the user observes. Bail early.
    -- IDLE state falls through so the puller still holds formation when
    -- not actively scouting/pulling/returning.
    -- ENGAGED puller falls through too: the fight is happening, formation
    -- should place them like any other alliance member (combat slot).
    local puller_st = state.puller
    local bot_engaged = bot.isEngaged and bot:isEngaged() or false
    if A and (A.pullerCharId or 0) == bot:getID()
       and puller_st and puller_st.state and puller_st.state ~= 'idle'
       and not bot_engaged then
        return
    end

    -- Camp-leash override: when the alliance target is beyond camp leash
    -- in camp mode, force the bot to hold its walking-formation position
    -- (near anchor) rather than run out to the combat slot. Paired with
    -- role_tank/role_melee refusing to engage — this prevents the "bots
    -- run to mob but don't swing" state where mob is out of leash range.
    -- Puller is the exception: its ai_puller.tick handles movement.
    if engaged and target ~= nil
       and xi.singleplayer.bots.ai_formation
       and xi.singleplayer.bots.ai_formation.entity_outside_camp_leash
       and xi.singleplayer.bots.ai_formation.entity_outside_camp_leash(target) then
        engaged = false
    end

    -- repeat/until-true is a do-block with early-out support: every "this
    -- tick is finished" path breaks out, and detect_stuck runs once at the
    -- bottom with the final `stepped` value regardless of which path we
    -- took. Keeps the stuck-detection sample window honest for early-out
    -- paths (busy actioning, resting) — they count as stepped=false rather
    -- than being skipped entirely.
    repeat
        -- Pause movement during cast / WS / JA / RA, with one exception below.
        -- The gate exists to keep the cast/WS animation clean and avoid
        -- "moving while casting" flicker. For melees, parking out of mob range
        -- means a long-range ability (Chi Blast, Ranged Attack) latches the
        -- gate while we're still too far to do real damage — better to close.
        -- For MAGES, the action's target is usually a party member (Cure,
        -- Haste, Refresh), so distance-to-mob is irrelevant — they must NOT
        -- abandon the cast just because they're far from the mob, or every
        -- support spell cancels mid-cast and never lands (visible bug:
        -- repeated Haste recasts with no Haste icon on the target).
        if botIsBusyActioning(bot) then
            if not xi.singleplayer.bots.ai_util.isMeleeRole(state.role) then break end
            local inMeleeRange = true
            if engaged then
                local dx = target:getXPos() - bot:getXPos()
                local dz = target:getZPos() - bot:getZPos()
                local d  = math.sqrt(dx * dx + dz * dz)
                inMeleeRange = d <= bot:getMeleeRange(target)
            end
            if inMeleeRange then break end
        end

        -- Resting heuristic: skip movement while seated to avoid the sit/stand
        -- flicker that cancels the HEALING tick. BUT only when the bot is still in
        -- "follow comfort zone" — if the primary/assist walked off and the bot is
        -- about to be out of range, the bot needs to stand up and chase.
        if bot:hasStatusEffect(xi.effect.HEALING) then
            local followTarget
            if xi.singleplayer.bots.ai_util.isMageRole(state.role) then
                followTarget = xi.singleplayer.bots.get_assist(state)
            elseif xi.singleplayer.bots.ai_util.isMeleeRole(state.role) and not engaged then
                followTarget = GetPlayerByID(state.parentCharId)
            end
            if followTarget == nil then break end
            local dx = followTarget:getXPos() - bot:getXPos()
            local dz = followTarget:getZPos() - bot:getZPos()
            local d  = math.sqrt(dx * dx + dz * dz)
            -- 12y comfort zone: the assist holds at camp while the primary
            -- moves around within a normal pull radius, only stands when
            -- the primary truly walks off.
            if d <= 12 then break end
        end

        -- Role-set movement override. When a role tick has computed a
        -- specific target for this tick (BRD walking to a party centroid
        -- for a song refresh, future GEO placing a luopan bubble, etc.),
        -- honor it and skip formation dispatch. Consume-on-read: role
        -- must set it every tick it wants the override — a forgotten
        -- clear costs one tick of stale target, not permanent lock.
        if state.roleMovementTarget ~= nil then
            local tgt = state.roleMovementTarget
            state.roleMovementTarget = nil
            stepped = xi.singleplayer.bots.ai_move.stepToward(bot, tgt.x, tgt.y, tgt.z)
            break
        end

        -- Formation-based positioning.
        local mainEntity = GetPlayerByID(state.parentCharId)
        if A then A.mainEntity = mainEntity end

        -- Engaged battle formation → slot-ring iteration. candidates_for
        -- returns up to 64 ordered positions (per-role fallback rules in
        -- ai_formation.lua); stepToward_any walks them with no-WALLHACK
        -- pathTo and warps to primary on full exhaustion. The ring obsoletes
        -- the legacy single-shot path FOR ENGAGED BOTS only — walking flows
        -- still go through target_for below.
        if engaged and xi.singleplayer.bots.ai_formation
           and xi.singleplayer.bots.ai_formation.candidates_for then
            -- Previously had an "if d_to_mob <= getMeleeRange then break"
            -- early-out here to prevent stuck-between-mob-and-wall wiggle.
            -- It was too blunt — fired for any bot within ~4y of mob,
            -- preventing legitimate slot positioning (bot engaged from
            -- mob's front never walks around to their Side A slot). The
            -- per-bot canonical slot + 2y SLOT_CLOSE_ENOUGH threshold in
            -- stepToward_any already prevent re-path churn when the bot
            -- is at their slot, and ring rotation handles the wall case
            -- by finding a reachable alternate quadrant.
            local cands = xi.singleplayer.bots.ai_formation.candidates_for(bot, state.role, target, engaged)
            if #cands > 0 then
                -- Camp leash for the assist: clamp every candidate so the
                -- ring can't pull the assist past the camp boundary even when
                -- chasing the slot ring around the mob.
                if A and A.walkingFormation == 'camp'
                   and assistId ~= 0 and bot:getID() == assistId then
                    for _, c in ipairs(cands) do
                        c.x, c.z = xi.singleplayer.bots.ai_formation.clamp_to_camp_leash(c.x, c.z)
                    end
                end
                stepped = xi.singleplayer.bots.ai_move.stepToward_any(bot, cands, mainEntity)
                -- faceTarget is idempotent (rot-only setPos when changed) so
                -- it's cheap to call every tick the bot is engaged.
                xi.singleplayer.bots.ai_move.faceTarget(bot, target)
                break
            end
        end

        -- Non-engaged (walking) or no engaged formation override: legacy
        -- single-shot target_for path. ai_formation.target_for returns nil
        -- for bots whose role-shape is "hold" (e.g. the front bot in battle).
        local ft_x, ft_z = nil, nil
        if xi.singleplayer.bots.ai_formation and xi.singleplayer.bots.ai_formation.target_for then
            ft_x, ft_z = xi.singleplayer.bots.ai_formation.target_for(bot, state.role, target, engaged)
        end

        if ft_x ~= nil then
            if engaged and A and A.walkingFormation == 'camp'
               and assistId ~= 0 and bot:getID() == assistId then
                ft_x, ft_z = xi.singleplayer.bots.ai_formation.clamp_to_camp_leash(ft_x, ft_z)
            end
            stepped = xi.singleplayer.bots.ai_move.stepToward(bot, ft_x, mainEntity and mainEntity:getYPos() or bot:getYPos(), ft_z)
            if engaged then xi.singleplayer.bots.ai_move.faceTarget(bot, target) end
            break
        end

        if xi.singleplayer.bots.ai_util.isMageRole(state.role) then
            local assist = xi.singleplayer.bots.get_assist(state)
            if assist ~= nil then
                stepped = xi.singleplayer.bots.ai_move.followEntity(bot, assist, 8, 12)
            end
        elseif xi.singleplayer.bots.ai_util.isMeleeRole(state.role) then
            if engaged then
                -- Hitbox-aware melee range from the C++ formula the attack
                -- pipeline uses (attacker.hitbox + 2.0 + target.hitbox).
                -- All melee roles (including Tank) park at 1.5y inside the
                -- engine cap. The previous tank-specific 3.0 inset placed
                -- the tank ~1y from mob center (inside the mob's hitbox)
                -- for THF SATA geometry, but it looked like the tank was
                -- hugging the mob. SATA still works at 1.5 (THF lands ~3.5y
                -- behind tank, well within Sneak Attack's range).
                local inset = 1.5
                -- Tank forward nudge: when a THF is paired with this tank
                -- (charId-sorted modulo assignment from ai_formation), add
                -- the nudge so tank stops closer to mob. THF at their 1y
                -- behind-tank slot then lands at what was the tank's old
                -- default distance from mob — guaranteed inside THF's
                -- melee_range. Non-tanks and tanks without a THF paired
                -- fall through with the default 1.5 inset.
                local R = xi.singleplayer.bots.Role or {}
                if state.role == R.Tank
                   and xi.singleplayer.bots.ai_formation
                   and xi.singleplayer.bots.ai_formation.tank_has_assigned_thf
                   and xi.singleplayer.bots.ai_formation.tank_has_assigned_thf(bot) then
                    inset = inset + (xi.singleplayer.bots.ai_formation.TANK_THF_FORWARD_NUDGE or 0)
                end
                local maxDist = bot:getMeleeRange(target) - inset
                if A and A.walkingFormation == 'camp'
                   and assistId ~= 0 and bot:getID() == assistId then
                    local desired_x, _, desired_z = xi.singleplayer.bots.ai_move.stopPointFrom(bot, target, maxDist)
                    if desired_x then
                        desired_x, desired_z = xi.singleplayer.bots.ai_formation.clamp_to_camp_leash(desired_x, desired_z)
                        stepped = xi.singleplayer.bots.ai_move.stepToward(bot, desired_x, target:getYPos(), desired_z)
                        xi.singleplayer.bots.ai_move.faceTarget(bot, target)
                        break
                    end
                end
                stepped = xi.singleplayer.bots.ai_move.followEntity(bot, target, 0, maxDist)
                xi.singleplayer.bots.ai_move.faceTarget(bot, target)
            else
                -- Idle: cluster around main via followEntity with a small step
                -- threshold (2y). followBehind / followBeside were inconsistent
                -- due to FFXI rotation byte semantics; clustering matches
                -- trust behavior anyway.
                local main = GetPlayerByID(state.parentCharId)
                if main ~= nil then
                    stepped = xi.singleplayer.bots.ai_move.followEntity(bot, main, 0, 2)
                end
            end
        end
    until true

    detect_stuck(bot, state, stepped, primary)
end

-----------------------------------
-- Tank Nudge — server-side dispatcher for the per-bot Tank Forward/Backward
-- buttons. C2S 0x176 TANK_NUDGE → luautils::OnBotTankNudge → here.
-- direction: 0=forward (+1y toward target), 1=backward (-1y away from target).
--
-- Pure one-shot setPos. No state, no pathfinding. Auto-movement runs as usual
-- on the next tick — if the new position is out-of-band for the bot's role,
-- ai_move corrects back; if it's in-band, the nudge sticks. The user explicitly
-- accepted "auto-move may immediately undo it" as part of the design.
--
-- Validation:
--   * bot must belong to primary (parentCharId match)
--   * bot must be engaged (no target = no vector to project)
--   * vector magnitude must be non-zero (avoid div-by-zero if positions match)
-- Silent no-op on validation failure.
-----------------------------------
local TANK_NUDGE_YALMS = 1.0
xi.singleplayer.bots.ai_move.tank_nudge = function(primary, botName, direction)
    if primary == nil or botName == nil or botName == '' then return end
    local target = botName:lower()
    local primaryId = primary:getID()

    -- "Owned" = primary themselves OR a headless they parent. Primary
    -- support exists because a PLD primary tanking deserves the same
    -- position knob as headless tanks. Setting the position on a real PC
    -- triggers a snap on their client - acceptable for a deliberate one-
    -- shot nudge.
    local function is_owned(m)
        if m == primary then return true end
        if m.isHeadless and m:isHeadless()
           and m.getParentCharId and m:getParentCharId() == primaryId then
            return true
        end
        return false
    end

    local bot = nil
    for _, member in ipairs(primary:getAlliance() or {}) do
        if is_owned(member) and member:getName():lower() == target then
            bot = member
            break
        end
    end
    if bot == nil then return end

    local mob = bot.getTarget and bot:getTarget() or nil
    if mob == nil then return end

    local bx, by, bz = bot:getXPos(), bot:getYPos(), bot:getZPos()
    local mx, _,  mz = mob:getXPos(), mob:getYPos(), mob:getZPos()

    local dx, dz = mx - bx, mz - bz
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist < 0.001 then return end  -- bot is already on top of the mob; no direction to project

    local ux, uz = dx / dist, dz / dist  -- unit vector tank → mob
    local sign = (tonumber(direction) == 1) and -1 or 1  -- 1 forward, -1 backward
    local newX = bx + ux * TANK_NUDGE_YALMS * sign
    local newZ = bz + uz * TANK_NUDGE_YALMS * sign

    -- Preserve current rotation; keep Y as-is (engine handles ground snap on
    -- pathfinding ticks, and we want minimal interference).
    local rot = bot.getRotPos and bot:getRotPos() or 0
    bot:setPos(newX, by, newZ, rot)
end

-----------------------------------
-- Tank Walk To Me — snap one bot to the primary's current xyz. Used to
-- recover a stuck tank, pull it out of a bad position, or pass aggro at
-- the primary's feet. C2S 0x176 TANK_WALK_TO_ME → luautils::OnBotTankWalkToMe
-- → here.
--
-- Same one-shot snap pattern as tank_nudge: pure setPos, no pathfinding.
-- Auto-movement runs as usual on the next tick — if the bot is engaged,
-- ai_move will pull it back toward its target; if not, walking formation
-- keeps it near the primary anyway.
--
-- Validation: bot must belong to primary (parentCharId match) and be in
-- the same zone. Silent no-op otherwise.
-----------------------------------
xi.singleplayer.bots.ai_move.tank_walk_to_me = function(primary, botName)
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

    local bot = nil
    for _, member in ipairs(primary:getAlliance() or {}) do
        if is_owned(member) and member:getName():lower() == target then
            bot = member
            break
        end
    end
    if bot == nil then return end
    if bot:getZoneID() ~= primary:getZoneID() then return end

    local rot = bot.getRotPos and bot:getRotPos() or 0
    bot:setPos(primary:getXPos(), primary:getYPos(), primary:getZPos(), rot)
end

return m
