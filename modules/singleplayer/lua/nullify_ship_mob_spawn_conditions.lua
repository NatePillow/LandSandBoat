-----------------------------------
-- Remove weather/time-of-day spawn and despawn restrictions from zone-level NM handlers
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('nullify_ship_mob_spawn_conditions')

m:addOverride('xi.server.onServerStart', function()
    super()

    -- Pashhow Marshlands: Toxic Tamlyn spawns on any weather change, no weather/cooldown requirement
    local pashhow   = require('scripts/zones/Pashhow_Marshlands/Zone')
    local pashhowID = zones[xi.zone.PASHHOW_MARSHLANDS]
    pashhow.onZoneWeatherChange = function(weather)
        local toxicTamlyn = GetMobByID(pashhowID.mob.TOXIC_TAMLYN)
        if not toxicTamlyn then
            return
        end

        if not toxicTamlyn:isSpawned() then
            SpawnMob(pashhowID.mob.TOXIC_TAMLYN)
        end
    end

    -- Ship bound for Selbina: Enagakure spawns any hour for any player with Seance Staff
    local shipSelbina   = require('scripts/zones/Ship_bound_for_Selbina/Zone')
    local shipSelbID    = zones[xi.zone.SHIP_BOUND_FOR_SELBINA]
    shipSelbina.onGameHour = function(zone)
        local enagakure = GetMobByID(shipSelbID.mob.ENAGAKURE)

        if enagakure and not enagakure:isSpawned() then
            for _, player in pairs(zone:getPlayers()) do
                if
                    player:hasKeyItem(xi.ki.SEANCE_STAFF) and
                    player:getCharVar('Enagakure_Killed') == 0
                then
                    SpawnMob(shipSelbID.mob.ENAGAKURE)
                    break
                end
            end
        end
    end

    -- Ship bound for Selbina (Pirates): same Enagakure treatment
    local shipPirates  = require('scripts/zones/Ship_bound_for_Selbina_Pirates/Zone')
    local shipPirID    = zones[xi.zone.SHIP_BOUND_FOR_SELBINA_PIRATES]
    shipPirates.onGameHour = function(zone)
        local enagakure = GetMobByID(shipPirID.mob.ENAGAKURE)

        if enagakure and not enagakure:isSpawned() then
            for _, player in pairs(zone:getPlayers()) do
                if
                    player:hasKeyItem(xi.ki.SEANCE_STAFF) and
                    player:getCharVar('Enagakure_Killed') == 0
                then
                    SpawnMob(shipPirID.mob.ENAGAKURE)
                    break
                end
            end
        end
    end
end)

return m
