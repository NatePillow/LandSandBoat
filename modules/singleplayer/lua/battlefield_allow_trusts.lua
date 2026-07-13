-----------------------------------
-- Allow trusts in all battlefields
-----------------------------------
require('modules/module_utils')
require('scripts/globals/battlefield')
-----------------------------------
local m = Module:new('battlefield_allow_trusts')

m:addOverride('xi.server.onServerStart', function()
    print('battlefield_allow_trusts start')
    super()

    for _, battlefield in pairs(xi.battlefield.contents) do
        battlefield.allowTrusts = true
    end

end)

return m
