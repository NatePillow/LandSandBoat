-----------------------------------
-- Updating drops for ENMs
-----------------------------------
require('modules/module_utils')
require('scripts/globals/battlefield')
-----------------------------------
local m = Module:new('ENM_30_drop_updates')

m:addOverride('xi.server.onServerStart', function()
    print('ENM_30_drop_updates start')
    super()

    xi.battlefield.contents[xi.battlefield.id.YOU_ARE_WHAT_YOU_EAT].loot = {
        {
            quantity = 7,
            { itemId = xi.item.CLUSTER_OF_BURNING_MEMORIES,    weight = 125 },
            { itemId = xi.item.CLUSTER_OF_BITTER_MEMORIES,     weight = 125 },
            { itemId = xi.item.CLUSTER_OF_FLEETING_MEMORIES,   weight = 125 },
            { itemId = xi.item.CLUSTER_OF_PROFANE_MEMORIES,    weight = 125 },
            { itemId = xi.item.CLUSTER_OF_STARTLING_MEMORIES,  weight = 125 },
            { itemId = xi.item.CLUSTER_OF_SOMBER_MEMORIES,     weight = 125 },
            { itemId = xi.item.CLUSTER_OF_RADIANT_MEMORIES,    weight = 125 },
            { itemId = xi.item.CLUSTER_OF_MALEVOLENT_MEMORIES, weight = 125 },
        },

        {
            { itemId = xi.item.VIOLENT_VISION,                 weight = 200 },
            { itemId = xi.item.PAINFUL_VISION,                 weight = 200 },
            { itemId = xi.item.TIMOROUS_VISION,                weight = 200 },
            { itemId = xi.item.BRILLIANT_VISION,               weight = 200 },
            { itemId = xi.item.VENERABLE_VISION,               weight = 200 },
        },

        {
            { itemId = xi.item.VERNAL_VISION,                  weight = 200 },
            { itemId = xi.item.PUNCTILIOUS_VISION,             weight = 200 },
            { itemId = xi.item.AUDACIOUS_VISION,               weight = 200 },
            { itemId = xi.item.VIVID_VISION,                   weight = 200 },
            { itemId = xi.item.ENDEARING_VISION,               weight = 200 },
        },

        {
            { itemId = xi.item.SOLEMN_VISION,                  weight = 200 },
            { itemId = xi.item.VALIANT_VISION,                 weight = 200 },
            { itemId = xi.item.PRETENTIOUS_VISION,             weight = 200 },
            { itemId = xi.item.MALICIOUS_VISION,               weight = 200 },
            { itemId = xi.item.PRISTINE_VISION,                weight = 200 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.SIMULANT].loot = {
        {
            quantity = 7,
            { itemId = xi.item.CLUSTER_OF_BURNING_MEMORIES,    weight = 125 },
            { itemId = xi.item.CLUSTER_OF_BITTER_MEMORIES,     weight = 125 },
            { itemId = xi.item.CLUSTER_OF_FLEETING_MEMORIES,   weight = 125 },
            { itemId = xi.item.CLUSTER_OF_PROFANE_MEMORIES,    weight = 125 },
            { itemId = xi.item.CLUSTER_OF_STARTLING_MEMORIES,  weight = 125 },
            { itemId = xi.item.CLUSTER_OF_SOMBER_MEMORIES,     weight = 125 },
            { itemId = xi.item.CLUSTER_OF_RADIANT_MEMORIES,    weight = 125 },
            { itemId = xi.item.CLUSTER_OF_MALEVOLENT_MEMORIES, weight = 125 },
        },

        {
            { itemId = xi.item.VIOLENT_VISION,                 weight = 200 },
            { itemId = xi.item.PAINFUL_VISION,                 weight = 200 },
            { itemId = xi.item.TIMOROUS_VISION,                weight = 200 },
            { itemId = xi.item.BRILLIANT_VISION,               weight = 200 },
            { itemId = xi.item.VENERABLE_VISION,               weight = 200 },
        },

        {
            { itemId = xi.item.VERNAL_VISION,                  weight = 200 },
            { itemId = xi.item.PUNCTILIOUS_VISION,             weight = 200 },
            { itemId = xi.item.AUDACIOUS_VISION,               weight = 200 },
            { itemId = xi.item.VIVID_VISION,                   weight = 200 },
            { itemId = xi.item.ENDEARING_VISION,               weight = 200 },
        },

        {
            { itemId = xi.item.SOLEMN_VISION,                  weight = 200 },
            { itemId = xi.item.VALIANT_VISION,                 weight = 200 },
            { itemId = xi.item.PRETENTIOUS_VISION,             weight = 200 },
            { itemId = xi.item.MALICIOUS_VISION,               weight = 200 },
            { itemId = xi.item.PRISTINE_VISION,                weight = 200 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.PLAYING_HOST].loot = {
        {
            quantity = 7,
            { itemId = xi.item.CLUSTER_OF_BURNING_MEMORIES,    weight = 125 },
            { itemId = xi.item.CLUSTER_OF_BITTER_MEMORIES,     weight = 125 },
            { itemId = xi.item.CLUSTER_OF_FLEETING_MEMORIES,   weight = 125 },
            { itemId = xi.item.CLUSTER_OF_PROFANE_MEMORIES,    weight = 125 },
            { itemId = xi.item.CLUSTER_OF_STARTLING_MEMORIES,  weight = 125 },
            { itemId = xi.item.CLUSTER_OF_SOMBER_MEMORIES,     weight = 125 },
            { itemId = xi.item.CLUSTER_OF_RADIANT_MEMORIES,    weight = 125 },
            { itemId = xi.item.CLUSTER_OF_MALEVOLENT_MEMORIES, weight = 125 },
        },

        {
            { itemId = xi.item.VIOLENT_VISION,                 weight = 200 },
            { itemId = xi.item.PAINFUL_VISION,                 weight = 200 },
            { itemId = xi.item.TIMOROUS_VISION,                weight = 200 },
            { itemId = xi.item.BRILLIANT_VISION,               weight = 200 },
            { itemId = xi.item.VENERABLE_VISION,               weight = 200 },
        },

        {
            { itemId = xi.item.VERNAL_VISION,                  weight = 200 },
            { itemId = xi.item.PUNCTILIOUS_VISION,             weight = 200 },
            { itemId = xi.item.AUDACIOUS_VISION,               weight = 200 },
            { itemId = xi.item.VIVID_VISION,                   weight = 200 },
            { itemId = xi.item.ENDEARING_VISION,               weight = 200 },
        },

        {
            { itemId = xi.item.SOLEMN_VISION,                  weight = 200 },
            { itemId = xi.item.VALIANT_VISION,                 weight = 200 },
            { itemId = xi.item.PRETENTIOUS_VISION,             weight = 200 },
            { itemId = xi.item.MALICIOUS_VISION,               weight = 200 },
            { itemId = xi.item.PRISTINE_VISION,                weight = 200 },
        },
    }

end)

return m
