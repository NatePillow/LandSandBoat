-----------------------------------
-- Updating drops for ENMs
-----------------------------------
require('modules/module_utils')
require('scripts/globals/battlefield')
-----------------------------------
local m = Module:new('ENM_40_drop_updates')

m:addOverride('xi.server.onServerStart', function()
    print('ENM_40_drop_updates start')
    super()

    xi.battlefield.contents[xi.battlefield.id.FIRE_IN_THE_SKY].loot = {
        {
            { itemId = xi.item.CLOUD_EVOKER,      weight = 1000 }, -- Cloud Evoker
        },

        {
            quantity = 2,
            { itemId = 15433,                     weight = 166 }, -- reverend_sash
            { itemId = 15434,                     weight = 166 }, -- vanguard_belt
            { itemId = 17215,                     weight = 166 }, -- thugs_zamburak
            { itemId = 16708,                     weight = 166 }, -- horror_voulge
            { itemId = xi.item.GEIST_EARRING,     weight = 166 },
            { itemId = xi.item.QUICK_BELT,        weight = 166 },
        },

        {
            { itemId = xi.item.CROSSBOWMANS_RING, weight = 333 },
            { itemId = xi.item.WOODSMAN_RING,     weight = 333 },
            { itemId = xi.item.ETHER_RING,        weight = 333 },
        },
    }

    --xi.battlefield.contents[xi.battlefield.id.BAD_SEED].loot = {
        -- unimplemented
    --}

    xi.battlefield.contents[xi.battlefield.id.TEST_YOUR_MITE].loot = {
        {
            { itemId = xi.item.CLOUD_EVOKER,      weight = 1000 }, -- Cloud Evoker
        },

        {
            quantity = 2,
            { itemId = 15433,                     weight = 166 }, -- reverend_sash
            { itemId = 15434,                     weight = 166 }, -- vanguard_belt
            { itemId = 17215,                     weight = 166 }, -- thugs_zamburak
            { itemId = 16708,                     weight = 166 }, -- horror_voulge
            { itemId = xi.item.GEIST_EARRING,     weight = 166 },
            { itemId = xi.item.QUICK_BELT,        weight = 166 },
        },

        {
            { itemId = xi.item.CROSSBOWMANS_RING, weight = 333 },
            { itemId = xi.item.WOODSMAN_RING,     weight = 333 },
            { itemId = xi.item.ETHER_RING,        weight = 333 },
        },
    }

end)

return m
