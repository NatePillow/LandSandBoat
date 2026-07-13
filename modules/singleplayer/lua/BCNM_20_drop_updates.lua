-----------------------------------
-- Updating drops for BCNMs
-----------------------------------
require('modules/module_utils')
require('scripts/globals/battlefield')
-----------------------------------
local m = Module:new('BCNM_20_drop_updates')

m:addOverride('xi.server.onServerStart', function()
    print('BCNM_20_drop_updates start')
    super()

    xi.battlefield.contents[xi.battlefield.id.WINGS_OF_FURY].loot = {
        {
            { itemId = xi.item.GIL,                 weight = 10000, amount = 1500 },
        },

        {
            quantity = 3,
            { itemId = xi.item.PLATOON_AXE,             weight =  625 },
            { itemId = xi.item.PLATOON_BOW,             weight =  625 },
            { itemId = xi.item.PLATOON_CESTI,           weight =  625 },
            { itemId = xi.item.PLATOON_CUTTER,          weight =  625 },
            { itemId = xi.item.PLATOON_DAGGER,          weight =  625 },
            { itemId = xi.item.PLATOON_DISC,            weight =  625 },
            { itemId = xi.item.PLATOON_EDGE,            weight =  625 },
            { itemId = xi.item.PLATOON_GUN,             weight =  625 },
            { itemId = xi.item.PLATOON_LANCE,           weight =  625 },
            { itemId = xi.item.PLATOON_MACE,            weight =  625 },
            { itemId = xi.item.PLATOON_POLE,            weight =  625 },
            { itemId = xi.item.PLATOON_SPATHA,          weight =  625 },
            { itemId = xi.item.PLATOON_SWORD,           weight =  625 },
            { itemId = xi.item.PLATOON_ZAGHNAL,         weight =  625 },
            { itemId = xi.item.GUNROMARU,               weight =  625 },
            { itemId = xi.item.GANKO,                   weight =  625 },
        },

        {
            { itemId = xi.item.NONE,                weight = 5000 },
            { itemId = xi.item.ASTRAL_RING,         weight = 5000 },
        },

        {
            { itemId = xi.item.THUNDER_SPIRIT_PACT, weight = 2500 },
            { itemId = xi.item.SCROLL_OF_INVISIBLE, weight = 2500 },
            { itemId = xi.item.SCROLL_OF_SNEAK,     weight = 2500 },
            { itemId = xi.item.SCROLL_OF_DEODORIZE, weight = 2500 },
        },

        {
            { itemId = xi.item.MANNEQUIN_HEAD,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_BODY,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_HANDS,        weight = 2000 },
            { itemId = xi.item.MANNEQUIN_LEGS,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_FEET,         weight = 2000 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.CHARMING_TRIO].loot = {
        {
            { itemId = xi.item.GIL,                    weight = 10000, amount = 1500 },
        },

        {
            quantity = 3,
            { itemId = xi.item.PLATOON_AXE,             weight =  625 },
            { itemId = xi.item.PLATOON_BOW,             weight =  625 },
            { itemId = xi.item.PLATOON_CESTI,           weight =  625 },
            { itemId = xi.item.PLATOON_CUTTER,          weight =  625 },
            { itemId = xi.item.PLATOON_DAGGER,          weight =  625 },
            { itemId = xi.item.PLATOON_DISC,            weight =  625 },
            { itemId = xi.item.PLATOON_EDGE,            weight =  625 },
            { itemId = xi.item.PLATOON_GUN,             weight =  625 },
            { itemId = xi.item.PLATOON_LANCE,           weight =  625 },
            { itemId = xi.item.PLATOON_MACE,            weight =  625 },
            { itemId = xi.item.PLATOON_POLE,            weight =  625 },
            { itemId = xi.item.PLATOON_SPATHA,          weight =  625 },
            { itemId = xi.item.PLATOON_SWORD,           weight =  625 },
            { itemId = xi.item.PLATOON_ZAGHNAL,         weight =  625 },
            { itemId = xi.item.GUNROMARU,               weight =  625 },
            { itemId = xi.item.GANKO,                   weight =  625 },
        },

        {
            { itemId = xi.item.NONE,                weight = 5000 },
            { itemId = xi.item.ASTRAL_RING,         weight = 5000 },
        },

        {
            { itemId = xi.item.AIR_SPIRIT_PACT,        weight = 5000 },
            { itemId = xi.item.SCROLL_OF_DRAIN,        weight = 5000 },
        },

        {
            { itemId = xi.item.MANNEQUIN_HEAD,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_BODY,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_HANDS,        weight = 2000 },
            { itemId = xi.item.MANNEQUIN_LEGS,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_FEET,         weight = 2000 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.CRUSTACEAN_CONUNDRUM].loot = {
        {
            { itemId = xi.item.GIL,                     weight = 10000, amount = 1500 },
        },

        {
            quantity = 3,
            { itemId = xi.item.PLATOON_AXE,             weight =  625 },
            { itemId = xi.item.PLATOON_BOW,             weight =  625 },
            { itemId = xi.item.PLATOON_CESTI,           weight =  625 },
            { itemId = xi.item.PLATOON_CUTTER,          weight =  625 },
            { itemId = xi.item.PLATOON_DAGGER,          weight =  625 },
            { itemId = xi.item.PLATOON_DISC,            weight =  625 },
            { itemId = xi.item.PLATOON_EDGE,            weight =  625 },
            { itemId = xi.item.PLATOON_GUN,             weight =  625 },
            { itemId = xi.item.PLATOON_LANCE,           weight =  625 },
            { itemId = xi.item.PLATOON_MACE,            weight =  625 },
            { itemId = xi.item.PLATOON_POLE,            weight =  625 },
            { itemId = xi.item.PLATOON_SPATHA,          weight =  625 },
            { itemId = xi.item.PLATOON_SWORD,           weight =  625 },
            { itemId = xi.item.PLATOON_ZAGHNAL,         weight =  625 },
            { itemId = xi.item.GUNROMARU,               weight =  625 },
            { itemId = xi.item.GANKO,                   weight =  625 },
        },

        {
            { itemId = xi.item.NONE,                weight = 5000 },
            { itemId = xi.item.ASTRAL_RING,         weight = 5000 },
        },

        {
            { itemId = xi.item.MANNEQUIN_HEAD,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_BODY,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_HANDS,        weight = 2000 },
            { itemId = xi.item.MANNEQUIN_LEGS,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_FEET,         weight = 2000 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.SHOOTING_FISH].loot = {
        {
            { itemId = xi.item.GIL,                     weight = 10000, amount = 1500 },
        },

        {
            quantity = 3,
            { itemId = xi.item.PLATOON_AXE,             weight =  625 },
            { itemId = xi.item.PLATOON_BOW,             weight =  625 },
            { itemId = xi.item.PLATOON_CESTI,           weight =  625 },
            { itemId = xi.item.PLATOON_CUTTER,          weight =  625 },
            { itemId = xi.item.PLATOON_DAGGER,          weight =  625 },
            { itemId = xi.item.PLATOON_DISC,            weight =  625 },
            { itemId = xi.item.PLATOON_EDGE,            weight =  625 },
            { itemId = xi.item.PLATOON_GUN,             weight =  625 },
            { itemId = xi.item.PLATOON_LANCE,           weight =  625 },
            { itemId = xi.item.PLATOON_MACE,            weight =  625 },
            { itemId = xi.item.PLATOON_POLE,            weight =  625 },
            { itemId = xi.item.PLATOON_SPATHA,          weight =  625 },
            { itemId = xi.item.PLATOON_SWORD,           weight =  625 },
            { itemId = xi.item.PLATOON_ZAGHNAL,         weight =  625 },
            { itemId = xi.item.GUNROMARU,               weight =  625 },
            { itemId = xi.item.GANKO,                   weight =  625 },
        },

        {
            { itemId = xi.item.NONE,                weight = 5000 },
            { itemId = xi.item.ASTRAL_RING,         weight = 5000 },
        },

        {
            { itemId = xi.item.SCROLL_OF_BLAZE_SPIKES,  weight = 2500 },
            { itemId = xi.item.SCROLL_OF_HORDE_LULLABY, weight = 2500 },
            { itemId = xi.item.THUNDER_SPIRIT_PACT,     weight = 2500 },
            { itemId = xi.item.SCROLL_OF_WARP,          weight = 2500 },
        },

        {
            { itemId = xi.item.MANNEQUIN_HEAD,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_BODY,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_HANDS,        weight = 2000 },
            { itemId = xi.item.MANNEQUIN_LEGS,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_FEET,         weight = 2000 },
        },
    }

end)

return m
