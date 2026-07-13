-----------------------------------
-- Warp other party members to your location
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('emote_get_position')

m:addOverride('xi.player.onPlayerEmote', function(player, emoteId)
    print('emote_get_position start')
    super(player, emoteId)
    if emoteId == xi.emote.KNEEL then
        print("x: " .. player:getXPos() .. "; y: " .. player:getYPos() .. "; z: " .. player:getZPos() .. "; rot: " .. player:getRotPos() .. "; zoneId: " .. player:getZoneID())
    end
end)

return m
