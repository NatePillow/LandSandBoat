-----------------------------------
-- Updating NM spawns to happen ASAP
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('immediate_lottery_nm_spawn')

m:addOverride('xi.mob.phOnDespawn', function(ph, phNmId, chance, cooldown, params)
    print('immediate_lottery_nm_spawn start')
    if (params == nil) then
        params = {}
    end
    params.immediate = true
    super(ph, phNmId, chance, cooldown, params)
end)

return m
