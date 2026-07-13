-----------------------------------
-- Updating drops for BCNMs
-----------------------------------
require('modules/module_utils')
require('scripts/globals/battlefield')
-----------------------------------
local m = Module:new('BCNM_uncapped_lachesis_drop_updates')

m:addOverride('xi.server.onServerStart', function()
    print('BCNM_uncapped_lachesis_drop_updates start')
    super()

    --xi.battlefield.contents[].loot = {

    --}

end)

return m
