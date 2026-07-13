-----------------------------------
-- Updating drops for ENMs
-----------------------------------
require('modules/module_utils')
require('scripts/globals/battlefield')
-----------------------------------
local m = Module:new('ENM_75_drop_updates')

m:addOverride('xi.server.onServerStart', function()
    print('ENM_75_drop_updates start')
    super()

    --xi.battlefield.contents[].loot = {

    --}

end)

return m
