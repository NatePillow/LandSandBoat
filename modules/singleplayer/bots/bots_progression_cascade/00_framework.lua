-----------------------------------
-- Cascade framework — namespace + recipe factories, loaded FIRST inside
-- the bots_progression_cascade/ subdir so the per-area recipe files can
-- use `cascade.quest` / `cascade.mission` at load time.
--
-- WHY THIS FILE EXISTS AT ALL:
--   LSB's LoadLuaModules walks modules/ via std::set<path> which sorts
--   path components component-by-component. For siblings
--     bots_progression_cascade.lua        (parent framework)
--     bots_progression_cascade/adoulin.lua (per-area recipe)
--   the FIRST components are `bots_progression_cascade.lua` vs
--   `bots_progression_cascade` (no extension yet — path splits on `/`).
--   Shorter string sorts less, so the SUBDIR wins the tie and all
--   per-area files load BEFORE the parent framework file. Result:
--   `cascade.quest` doesn't exist yet, subdir loads explode with
--   "attempt to index local 'cascade' (a nil value)".
--
--   Fix: hoist the framework init into a subdir file whose name sorts
--   before all its siblings. Digit `0` (ASCII 48) beats every letter
--   (97+), so `00_framework.lua` loads first inside the subdir. Now
--   the load order is:
--     00_framework.lua → adoulin.lua → ... → windurst.lua → parent
--   and the parent runs last, which is what its live-wrap hook needs
--   anyway (it iterates `cascade.recipes` populated by every subdir).
--
-- The parent bots_progression_cascade.lua re-inits the namespace via
-- the same `or {}` idiom and leaves these factories in place as-is —
-- redefining them to the same values is harmless. This file is the
-- authoritative source for subdir-load-time correctness.
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_framework')

xi              = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.bots_progression_cascade = xi.singleplayer.bots.bots_progression_cascade or {}

local cascade = xi.singleplayer.bots.bots_progression_cascade
cascade.recipes = cascade.recipes or {}

-- Normalize quest.reward.item / mission.reward.item into a list of {id, qty}.
-- Mirrors the parent-file helper; kept private here so subdir load time is
-- fully self-contained.
local function reward_items(reward)
    local out = {}
    if reward == nil or reward.item == nil then return out end
    local function push(v)
        if type(v) == 'number' then
            table.insert(out, { v, 1 })
        elseif type(v) == 'table' and type(v[1]) == 'number' then
            table.insert(out, { v[1], v[2] or 1 })
        end
    end
    if type(reward.item) == 'number' then
        push(reward.item)
    elseif type(reward.item) == 'table' then
        if type(reward.item[1]) == 'number' and #reward.item == 2 and type(reward.item[2]) == 'number' then
            push(reward.item)
        else
            for _, v in ipairs(reward.item) do push(v) end
        end
    end
    return out
end

-- Map a mission log id to the matching nation id. Returns nil for non-nation
-- log lines (zilart/cop/toau/jeuno/etc) where reward.rank is meaningless.
local function nation_for_mission_log(area)
    if area == xi.mission.log_id.SANDORIA then return xi.nation.SANDORIA end
    if area == xi.mission.log_id.BASTOK   then return xi.nation.BASTOK   end
    if area == xi.mission.log_id.WINDURST then return xi.nation.WINDURST end
    return nil
end

local function quest(area, qid, source, apply)
    return {
        kind   = 'quest',
        log    = area,
        qid    = qid,
        source = source,
        apply  = function(p)
            -- source: a script-path string (require its .reward), an inline
            -- reward table, or nil (no reward — the reward acts live wholly in
            -- the apply closure). nil/table covers unlocks whose source is a
            -- battlefield / NPC rather than a standalone quest script.
            local reward = {}
            if type(source) == 'string' then
                reward = require(source).reward or {}
            elseif type(source) == 'table' then
                reward = source
            end
            local items = reward_items(reward)
            local need  = #items
            local have  = p.getFreeSlotsCount and p:getFreeSlotsCount() or 255
            if need > 0 and have < need then
                return { status = 'deferred', need = need, have = have }
            end
            local ok = npcUtil.completeQuest(p, area, qid, reward)
            if ok == false then
                return { status = 'error', need = need, have = have }
            end
            if apply then apply(p) end
            return { status = 'applied', need = need, have = have }
        end,
    }
end

local function mission(area, mid, source, apply)
    return {
        kind   = 'mission',
        log    = area,
        mid    = mid,
        source = source,
        apply  = function(p)
            local mn    = require(source)
            local items = reward_items(mn.reward)
            local need  = #items
            local have  = p.getFreeSlotsCount and p:getFreeSlotsCount() or 255
            if need > 0 and have < need then
                return { status = 'deferred', need = need, have = have }
            end

            local reward         = mn.reward or {}
            local recipeNation    = nation_for_mission_log(area)
            local crossNationRank = nil
            if recipeNation ~= nil and recipeNation ~= p:getNation()
               and type(reward.rank) == 'number' then
                crossNationRank = reward.rank
                local stripped = {}
                for k, v in pairs(reward) do
                    if k ~= 'rank' and k ~= 'rankPoints' then stripped[k] = v end
                end
                reward = stripped
            end

            p:addMission(area, mid)

            local ok = npcUtil.completeMission(p, area, mid, reward)
            if ok == false then
                return { status = 'error', need = need, have = have }
            end

            if crossNationRank ~= nil
               and p:getRank(recipeNation) < crossNationRank then
                p:setRankByNation(recipeNation, crossNationRank)
            end

            if apply then apply(p) end
            return { status = 'applied', need = need, have = have }
        end,
    }
end

cascade.quest   = quest
cascade.mission = mission

return m
