-----------------------------------
-- Updating NM spawns to happen ASAP
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('continuous_nm_spawning')

m:addOverride('xi.player.onGameIn', function(player, firstLogin, zoning)
    print('continuous_nm_spawning start')
    super(player, firstLogin, zoning)
    local zoneID = player:getZoneID()
    local zone = zones[zoneID]
    local oldFunc
    if zone.onZoneTick ~= nil then
        oldFunc = zone.onZoneTick
    end
    -- TODO why doesn't this work? i did see it work in west ronfaure right? is oldFunc breaking it?
    zone.onZoneTick = function(zone)
        print('continuous_nm_spawning inside tick')
        if oldFunc ~= nil then
            oldFunc(zone)
        end
        for _, mobID in pairs(zone.mob) do
            if type(mobID) ~= "table" then
                local mob = GetMobByID(mobID)
                if mob ~= nil and mob:isNM() and not mob:isSpawned() then
                    print('continuous_nm_spawning spawning: ' .. mob:getName())
                    xi.mob.updateNMSpawnPoint(mob)
                    mob:setRespawnTime(1)
                    DisallowRespawn(mobID, false)
                else
                    print('continuous_nm_spawning NOT spawning: ' .. mob:getName())
                end
            end
        end
    end
end)

return m
