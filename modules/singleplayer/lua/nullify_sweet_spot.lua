-----------------------------------
-- Nullifying sweet spot mechanic
-----------------------------------
require('modules/module_utils')
require('scripts/globals/battlefield')
-----------------------------------
local m = Module:new('nullify_sweet_spot')

m:addOverride('xi.server.onServerStart', function()
    print('nullify_sweet_spot start')
    super()

    xi.combat.ranged.sweetSpotDefaults = {
        ['throwing'] = { 0.0, 9.5 },
        ['cannon'  ] = { 0.0, 9.5 },
        ['gun'     ] = { 0.0, 9.5 },
        ['shortbow'] = { 0.0, 9.5 },
        ['crossbow'] = { 0.0, 9.5 },
        ['longbow' ] = { 0.0, 9.5 },
    }

    xi.combat.ranged.sweetSpots = {
        [xi.item.YOICHINOYUMI_75               ] = { 0.0, 9.5 },
        [xi.item.YOICHINOYUMI_80               ] = { 0.0, 9.5 },
        [xi.item.YOICHINOYUMI_85               ] = { 0.0, 9.5 },
        [xi.item.YOICHINOYUMI_90               ] = { 0.0, 9.5 },
        [xi.item.YOICHINOYUMI_95               ] = { 0.0, 9.5 },
        [xi.item.YOICHINOYUMI_99               ] = { 0.0, 9.5 },
        [xi.item.YOICHINOYUMI_99_II            ] = { 0.0, 9.5 },
        [xi.item.YOICHINOYUMI_119              ] = { 0.0, 9.5 },
        [xi.item.YOICHINOYUMI_119_II           ] = { 0.0, 9.5 },
        [xi.item.YOICHINOYUMI_119_III          ] = { 0.0, 9.5 },
        [xi.item.YOICHINOYUMI_119_III_NO_QUIVER] = { 0.0, 9.5 },
    }

end)

return m
