-----------------------------------
-- Updating the number of usages for BCNM trigger items
-----------------------------------
require('modules/module_utils')
require('scripts/globals/battlefield')
-----------------------------------
local m = Module:new('battlefield_orb_uses')

m:addOverride('xi.server.onServerStart', function()
    print('battlefield_orb_uses start')
    super()

    xi.battlefield.itemUses =
    {
        [xi.item.WARRIORS_TESTIMONY]      = 99,
        [xi.item.MONKS_TESTIMONY]         = 99,
        [xi.item.WHITE_MAGES_TESTIMONY]   = 99,
        [xi.item.BLACK_MAGES_TESTIMONY]   = 99,
        [xi.item.RED_MAGES_TESTIMONY]     = 99,
        [xi.item.THIEFS_TESTIMONY]        = 99,
        [xi.item.PALADINS_TESTIMONY]      = 99,
        [xi.item.DARK_KNIGHTS_TESTIMONY]  = 99,
        [xi.item.BEASTMASTERS_TESTIMONY]  = 99,
        [xi.item.BARDS_TESTIMONY]         = 99,
        [xi.item.RANGERS_TESTIMONY]       = 99,
        [xi.item.SAMURAIS_TESTIMONY]      = 99,
        [xi.item.NINJAS_TESTIMONY]        = 99,
        [xi.item.DRAGOONS_TESTIMONY]      = 99,
        [xi.item.SUMMONERS_TESTIMONY]     = 99,
        [xi.item.BLUE_MAGES_TESTIMONY]    = 99,
        [xi.item.CORSAIRS_TESTIMONY]      = 99,
        [xi.item.PUPPETMASTERS_TESTIMONY] = 99,
        [xi.item.CLOUDY_ORB]              = 10,
        [xi.item.SKY_ORB]                 = 10,
        [xi.item.STAR_ORB]                = 10,
        [xi.item.COMET_ORB]               = 10,
        [xi.item.MOON_ORB]                = 10,
        [xi.item.ATROPOS_ORB]             = 10,
        [xi.item.CLOTHO_ORB]              = 10,
        [xi.item.LACHESIS_ORB]            = 10,
        [xi.item.THEMIS_ORB]              = 10,
    }

end)

return m
