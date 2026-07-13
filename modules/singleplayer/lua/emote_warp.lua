-----------------------------------
-- Warp other party members to your location
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('emote_warp')

m:addOverride('xi.player.onPlayerEmote', function(player, emoteId)
    print('emote_warp start')
    super(player, emoteId)
    if emoteId == xi.emote.WELCOME then
        for _, member in ipairs(player:getAlliance()) do
            if (player:getID() ~= member:getID() and (player:getZoneID() ~= member:getZoneID() or player:checkDistance(member:getXPos(), member:getYPos(), member:getZPos()) > 20)) then
                member:setPos(player:getXPos(), player:getYPos(), player:getZPos(), player:getRotPos(), player:getZoneID())
            end
        end
    end
end)

return m
