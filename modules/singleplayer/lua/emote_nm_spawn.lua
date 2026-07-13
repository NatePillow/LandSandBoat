-----------------------------------
-- Spawn all NMs in zone after emote
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('emote_nm_spawn')

m:addOverride('xi.player.onPlayerEmote', function(player, emoteId)
    print('emote_nm_spawn start')
    super(player, emoteId)
    if emoteId == xi.emote.PSYCH then
        local zoneID = player:getZoneID()
        local zone = zones[zoneID]
        for mobName, mobID in pairs(zone.mob) do
            if mobName == 'VOIDWALKER' then
                goto continue_loop
            end

            if type(mobID) == "table" then
                for _, id in ipairs(mobID) do
                    local mob = GetMobByID(id)
                    if mob ~= nil and mob:isNM() and not mob:isSpawned() then
                        print('emote_nm_spawn spawning (table): ' .. mob:getName())
                        xi.mob.updateNMSpawnPoint(mob)
                        mob:setRespawnTime(1)
                        DisallowRespawn(id, false)
                    else
                        print('emote_nm_spawn NOT spawning (table): ' .. mob:getName())
                    end
                end
            else
                local mob = GetMobByID(mobID)
                if mob ~= nil and mob:isNM() and not mob:isSpawned() then
                    print('emote_nm_spawn spawning: ' .. mob:getName())
                    xi.mob.updateNMSpawnPoint(mob)
                    mob:setRespawnTime(1)
                    DisallowRespawn(mobID, false)
                else
                    print('emote_nm_spawn NOT spawning: ' .. mob:getName())
                end
            end

            ::continue_loop::
        end
    end
end)

return m
