-----------------------------------
-- Used when a one-off update is needed, typically to align previously made characters with updates to char_create
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('on_login_updates')
--[[
m:addOverride('xi.player.onGameIn', function(player, firstLogin, zoning)
    print('on_login_updates start')
    super(player, firstLogin, zoning)
end)
]]
return m
