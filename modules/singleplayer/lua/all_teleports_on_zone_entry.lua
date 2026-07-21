-----------------------------------
-- Grant all teleports for a zone the moment a character sets foot in it.
--
-- Fires on every zone-in (via InteractionGlobal.onZoneIn), works out which Home
-- Points, Survival Guides, Waypoints, and regional Outposts physically live in
-- the entered zone, and unlocks any the character does not already have.
--
-- Idempotent: addTeleport ORs the bit, and we check hasTeleport first, so the
-- "what you unlocked" chat line only ever lists genuinely new entries -- no spam
-- on re-entry, and no need to track first-visit state ourselves.
--
-- Wired:   HOMEPOINT, SURVIVAL, WAYPOINT, OUTPOST_{SANDORIA,BASTOK,WINDURST}.
-- Stubbed until the relevant expansion is supported (nothing in-era to unlock):
--   RUNIC_PORTAL    -- TODO: implement when Treasures of Aht Urhgan is supported
--   PAST_MAW        -- TODO: implement when Wings of the Goddess is supported
--   CAMPAIGN_*      -- TODO: implement when Wings of the Goddess is supported
--   ABYSSEA_CONFLUX -- TODO: implement when Abyssea is supported
--   ESCHAN_PORTAL   -- TODO: implement when Seekers of Adoulin is supported
-----------------------------------
require('modules/module_utils')
require('scripts/globals/teleports')
local survivalMap = require('scripts/globals/teleports/survival_guide_map')
-----------------------------------
local m = Module:new('all_teleports_on_zone_entry')

-- Home Points: homepointData is a flat list; the destination zone is dest[5],
-- the storage slot is (index / 32, index % 32).
local function grantHomePoints(player, zoneId)
    local data = xi.homepoint.data
    if not data then
        return 0
    end

    local unlocked = 0
    for index, hp in pairs(data) do
        if hp.dest[5] == zoneId then
            local hpBit = index % 32
            local hpSet = math.floor(index / 32)
            if not player:hasTeleport(xi.teleport.type.HOMEPOINT, hpBit, hpSet) then
                player:addTeleport(xi.teleport.type.HOMEPOINT, hpBit, hpSet)
                unlocked = unlocked + 1
            end
        end
    end

    return unlocked
end

-- Survival Guides: at most one per zone. group/groupIndex are 1-based; the
-- teleport storage is (group - 1, groupIndex - 1).
local function grantSurvivalGuide(player, zoneId)
    local guideIndex = survivalMap.zoneIdToGuideIdMap[zoneId]
    if not guideIndex then
        return 0
    end

    local guide = survivalMap.survivalGuides[guideIndex]
    if not guide then
        return 0
    end

    local surBit = guide.groupIndex - 1
    local surSet = guide.group - 1
    if not player:hasTeleport(xi.teleport.type.SURVIVAL, surBit, surSet) then
        player:addTeleport(xi.teleport.type.SURVIVAL, surBit, surSet)
        return 1
    end

    return 0
end

-- Waypoints: waypointInfo[i] = { offset, group, event, { pos, zone }, unlockPos }.
-- The unlock bit is field [5]; a nil field [5] (e.g. the Lower Jeuno menu node)
-- is not an attunable waypoint and is skipped.
local function grantWaypoints(player, zoneId)
    local info = xi.waypoint.info
    if not info then
        return 0
    end

    local unlocked = 0
    for _, wp in pairs(info) do
        local unlockPos = wp[5]
        local dest      = wp[4]
        if unlockPos ~= nil and dest and dest[5] == zoneId then
            if not player:hasTeleport(xi.teleport.type.WAYPOINT, unlockPos) then
                player:addTeleport(xi.teleport.type.WAYPOINT, unlockPos)
                unlocked = unlocked + 1
            end
        end
    end

    return unlocked
end

-- Outposts: stored per the character's current nation (nation value 0/1/2 maps
-- directly onto OUTPOST_{SANDORIA,BASTOK,WINDURST}); the region bit starts at
-- the 5th bit. Each region's outpost lives in a single zone (outposts[region].zone).
local function grantOutpost(player, zoneId)
    local outposts = xi.conquest.outposts
    if not outposts then
        return 0
    end

    local nation   = player:getNation()
    local unlocked = 0
    for region, op in pairs(outposts) do
        if op.zone == zoneId then
            local outBit = region + 5
            if not player:hasTeleport(nation, outBit) then
                player:addTeleport(nation, outBit)
                unlocked = unlocked + 1
            end
        end
    end

    return unlocked
end

-- ASCII-only: this reaches the FFXI chat log, so no em-dashes/ellipses/bullets.
local function countPhrase(count, singular)
    if count == 1 then
        return string.format('%d %s', count, singular)
    end

    return string.format('%d %ss', count, singular)
end

local function announceUnlocks(player, homePoints, guides, waypoints, outposts)
    local parts = {}
    if homePoints > 0 then
        table.insert(parts, countPhrase(homePoints, 'Home Point'))
    end

    if guides > 0 then
        table.insert(parts, countPhrase(guides, 'Survival Guide'))
    end

    if waypoints > 0 then
        table.insert(parts, countPhrase(waypoints, 'Waypoint'))
    end

    if outposts > 0 then
        table.insert(parts, countPhrase(outposts, 'Outpost'))
    end

    if #parts == 0 then
        return
    end

    player:printToPlayer('Teleports unlocked here: ' .. table.concat(parts, ', ') .. '.', xi.msg.channel.SYSTEM_3)
end

m:addOverride('InteractionGlobal.onZoneIn', function(player, prevZone, fallbackFn)
    local zoneId = player:getZoneID()

    local homePoints = grantHomePoints(player, zoneId)
    local guides     = grantSurvivalGuide(player, zoneId)
    local waypoints  = grantWaypoints(player, zoneId)
    local outposts   = grantOutpost(player, zoneId)

    announceUnlocks(player, homePoints, guides, waypoints, outposts)

    return super(player, prevZone, fallbackFn)
end)

return m
