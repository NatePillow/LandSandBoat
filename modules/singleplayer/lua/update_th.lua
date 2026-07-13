-----------------------------------
-- Updating drop rates
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('update_th')

m:addOverride('xi.combat.treasureHunter.getDropRate', function(thLevel, dropRate)
    print('update_th start')
    local thTier = utils.defaultIfNil(thLevel, 0)
    local increase = thTier * 100
    local newDropRate = utils.clamp(dropRate + increase, 0, 10000)
    return newDropRate
end)

return m
