-----------------------------------
-- Updating drops for BCNMs
-----------------------------------
require('modules/module_utils')
require('scripts/globals/battlefield')
-----------------------------------
local m = Module:new('BCNM_40_drop_updates')

m:addOverride('xi.server.onServerStart', function()
    print('BCNM_40_drop_updates start')
    super()

    xi.battlefield.contents[xi.battlefield.id.UNDER_OBSERVATION].loot = {
        {
            { itemId = xi.item.GIL,                   weight = 10000, amount = 5000 },
        },

        {
            { itemId = xi.item.ARCHERS_RING,          weight = 10000 },
        },

        {
            { itemId = xi.item.NONE,                  weight = 9000 },
            { itemId = xi.item.PEACOCK_CHARM,         weight = 1000 },
        },

        {
            { itemId = xi.item.BEHOURD_LANCE,         weight = 2000 },
            { itemId = xi.item.MUTILATOR,             weight = 2000 },
            { itemId = xi.item.RAIFU,                 weight = 2000 },
            { itemId = xi.item.TOURNEY_PATAS,         weight = 2000 },
            { itemId = xi.item.DE_SAINTRES_AXE,       weight = 2000 },
        },

        {
            { itemId = xi.item.BUZZARD_TUCK,          weight = 2000 },
            { itemId = xi.item.GRUDGE_SWORD,          weight = 2000 },
            { itemId = xi.item.CALVELEYS_DAGGER,      weight = 2000 },
            { itemId = xi.item.JONGLEURS_DAGGER,      weight = 2000 },
            { itemId = xi.item.SHIKAR_BOW,            weight = 2000 },
        },

        {
            { itemId = xi.item.KAGEHIDE,              weight = 2000 },
            { itemId = xi.item.OHAGURO,               weight = 2000 },
            { itemId = xi.item.SEALED_MACE,           weight = 2000 },
            { itemId = xi.item.DUSKY_STAFF,           weight = 2000 },
            { itemId = xi.item.HIMMEL_STOCK,          weight = 2000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.ELEGANT_SHIELD,        weight = 1112 },
            { itemId = xi.item.JENNET_SHIELD,         weight = 1111 },
            { itemId = xi.item.AGILE_GORGET,          weight = 1111 },
            { itemId = xi.item.JAGD_GORGET,           weight = 1111 },
            { itemId = xi.item.MANA_RING,             weight = 1111 },
            { itemId = xi.item.TILT_BELT,             weight = 1111 },
            { itemId = xi.item.MANTRA_BELT,           weight = 1111 },
            { itemId = xi.item.MARKSMANS_RING,        weight = 1111 },
            { itemId = xi.item.REARGUARD_MANTLE,      weight = 1111 },
        },

        {
            { itemId = xi.item.SCROLL_OF_ICE_SPIKES,  weight = 3334 },
            { itemId = xi.item.SCROLL_OF_REFRESH,     weight = 3333 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI, weight = 3333 },
        },

        {
            { itemId = xi.item.FIRE_SPIRIT_PACT,      weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ABSORB_STR,  weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ERASE,       weight = 2500 },
            { itemId = xi.item.SCROLL_OF_PHALANX,     weight = 2500 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.UNDYING_PROMISE].loot = {
        {
            { itemId = xi.item.GIL,                   weight = 10000, amount = 5000 },
        },

        {
            { itemId = xi.item.ARCHERS_RING,          weight = 10000 },
        },

        {
            { itemId = xi.item.BEHOURD_LANCE,         weight = 2000 },
            { itemId = xi.item.MUTILATOR,             weight = 2000 },
            { itemId = xi.item.RAIFU,                 weight = 2000 },
            { itemId = xi.item.TOURNEY_PATAS,         weight = 2000 },
            { itemId = xi.item.DE_SAINTRES_AXE,       weight = 2000 },
        },

        {
            { itemId = xi.item.BUZZARD_TUCK,          weight = 2000 },
            { itemId = xi.item.GRUDGE_SWORD,          weight = 2000 },
            { itemId = xi.item.CALVELEYS_DAGGER,      weight = 2000 },
            { itemId = xi.item.JONGLEURS_DAGGER,      weight = 2000 },
            { itemId = xi.item.SHIKAR_BOW,            weight = 2000 },
        },

        {
            { itemId = xi.item.KAGEHIDE,              weight = 2000 },
            { itemId = xi.item.OHAGURO,               weight = 2000 },
            { itemId = xi.item.SEALED_MACE,           weight = 2000 },
            { itemId = xi.item.DUSKY_STAFF,           weight = 2000 },
            { itemId = xi.item.HIMMEL_STOCK,          weight = 2000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.ELEGANT_SHIELD,        weight = 1112 },
            { itemId = xi.item.JENNET_SHIELD,         weight = 1111 },
            { itemId = xi.item.AGILE_GORGET,          weight = 1111 },
            { itemId = xi.item.JAGD_GORGET,           weight = 1111 },
            { itemId = xi.item.MANA_RING,             weight = 1111 },
            { itemId = xi.item.TILT_BELT,             weight = 1111 },
            { itemId = xi.item.MANTRA_BELT,           weight = 1111 },
            { itemId = xi.item.MARKSMANS_RING,        weight = 1111 },
            { itemId = xi.item.REARGUARD_MANTLE,      weight = 1111 },
        },

        {
            { itemId = xi.item.SCROLL_OF_ICE_SPIKES,  weight = 3334 },
            { itemId = xi.item.SCROLL_OF_REFRESH,     weight = 3333 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI, weight = 3333 },
        },

        {
            { itemId = xi.item.FIRE_SPIRIT_PACT,      weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ABSORB_STR,  weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ERASE,       weight = 2500 },
            { itemId = xi.item.SCROLL_OF_PHALANX,     weight = 2500 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.ROYAL_JELLY].loot = {
        {
            { itemId = xi.item.GIL,                   weight = 10000, amount = 5000 },
        },

        {
            { itemId = xi.item.ARCHERS_RING,          weight = 10000 },
        },

        {
            { itemId = xi.item.ARCHERS_RING,          weight = 10000 },
        },

        {
            { itemId = xi.item.NONE,                  weight = 5000 },
            { itemId = xi.item.ARCHERS_RING,          weight = 5000 },
        },

        {
            { itemId = xi.item.NONE,                  weight = 5000 },
            { itemId = xi.item.ARCHERS_RING,          weight = 5000 },
        },

        {
            { itemId = xi.item.NONE,                  weight = 5000 },
            { itemId = xi.item.ARCHERS_RING,          weight = 5000 },
        },

        {
            { itemId = xi.item.NONE,                  weight = 5000 },
            { itemId = xi.item.ARCHERS_RING,          weight = 5000 },
        },

        {
            { itemId = xi.item.NONE,                  weight = 5000 },
            { itemId = xi.item.ARCHERS_RING,          weight = 5000 },
        },

        {
            { itemId = xi.item.SCROLL_OF_ICE_SPIKES,  weight = 3334 },
            { itemId = xi.item.SCROLL_OF_REFRESH,     weight = 3333 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI, weight = 3333 },
        },

        {
            { itemId = xi.item.FIRE_SPIRIT_PACT,      weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ABSORB_STR,  weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ERASE,       weight = 2500 },
            { itemId = xi.item.SCROLL_OF_PHALANX,     weight = 2500 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.ROYAL_SUCCESSION].loot = {
        {
            { itemId = xi.item.GIL,                   weight = 10000, amount = 5000 },
        },

        {
            { itemId = xi.item.ARCHERS_RING,          weight = 10000 },
        },

        {
            { itemId = xi.item.BEHOURD_LANCE,         weight = 2000 },
            { itemId = xi.item.MUTILATOR,             weight = 2000 },
            { itemId = xi.item.RAIFU,                 weight = 2000 },
            { itemId = xi.item.TOURNEY_PATAS,         weight = 2000 },
            { itemId = xi.item.DE_SAINTRES_AXE,       weight = 2000 },
        },

        {
            { itemId = xi.item.BUZZARD_TUCK,          weight = 2000 },
            { itemId = xi.item.GRUDGE_SWORD,          weight = 2000 },
            { itemId = xi.item.CALVELEYS_DAGGER,      weight = 2000 },
            { itemId = xi.item.JONGLEURS_DAGGER,      weight = 2000 },
            { itemId = xi.item.SHIKAR_BOW,            weight = 2000 },
        },

        {
            { itemId = xi.item.KAGEHIDE,              weight = 2000 },
            { itemId = xi.item.OHAGURO,               weight = 2000 },
            { itemId = xi.item.SEALED_MACE,           weight = 2000 },
            { itemId = xi.item.DUSKY_STAFF,           weight = 2000 },
            { itemId = xi.item.HIMMEL_STOCK,          weight = 2000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.ELEGANT_SHIELD,        weight = 1112 },
            { itemId = xi.item.JENNET_SHIELD,         weight = 1111 },
            { itemId = xi.item.AGILE_GORGET,          weight = 1111 },
            { itemId = xi.item.JAGD_GORGET,           weight = 1111 },
            { itemId = xi.item.MANA_RING,             weight = 1111 },
            { itemId = xi.item.TILT_BELT,             weight = 1111 },
            { itemId = xi.item.MANTRA_BELT,           weight = 1111 },
            { itemId = xi.item.MARKSMANS_RING,        weight = 1111 },
            { itemId = xi.item.REARGUARD_MANTLE,      weight = 1111 },
        },

        {
            { itemId = xi.item.SCROLL_OF_ICE_SPIKES,  weight = 3334 },
            { itemId = xi.item.SCROLL_OF_REFRESH,     weight = 3333 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI, weight = 3333 },
        },

        {
            { itemId = xi.item.FIRE_SPIRIT_PACT,      weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ABSORB_STR,  weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ERASE,       weight = 2500 },
            { itemId = xi.item.SCROLL_OF_PHALANX,     weight = 2500 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.FACTORY_REJECTS].loot = {
        {
            { itemId = xi.item.GIL,                   weight = 10000, amount = 6000 },
        },

        {
            { itemId = xi.item.ARCHERS_RING,          weight = 10000 },
        },

        {
            { itemId = xi.item.BEHOURD_LANCE,         weight = 2000 },
            { itemId = xi.item.MUTILATOR,             weight = 2000 },
            { itemId = xi.item.RAIFU,                 weight = 2000 },
            { itemId = xi.item.TOURNEY_PATAS,         weight = 2000 },
            { itemId = xi.item.DE_SAINTRES_AXE,       weight = 2000 },
        },

        {
            { itemId = xi.item.BUZZARD_TUCK,          weight = 2000 },
            { itemId = xi.item.GRUDGE_SWORD,          weight = 2000 },
            { itemId = xi.item.CALVELEYS_DAGGER,      weight = 2000 },
            { itemId = xi.item.JONGLEURS_DAGGER,      weight = 2000 },
            { itemId = xi.item.SHIKAR_BOW,            weight = 2000 },
        },

        {
            { itemId = xi.item.KAGEHIDE,              weight = 2000 },
            { itemId = xi.item.OHAGURO,               weight = 2000 },
            { itemId = xi.item.SEALED_MACE,           weight = 2000 },
            { itemId = xi.item.DUSKY_STAFF,           weight = 2000 },
            { itemId = xi.item.HIMMEL_STOCK,          weight = 2000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.ELEGANT_SHIELD,        weight = 1112 },
            { itemId = xi.item.JENNET_SHIELD,         weight = 1111 },
            { itemId = xi.item.AGILE_GORGET,          weight = 1111 },
            { itemId = xi.item.JAGD_GORGET,           weight = 1111 },
            { itemId = xi.item.MANA_RING,             weight = 1111 },
            { itemId = xi.item.TILT_BELT,             weight = 1111 },
            { itemId = xi.item.MANTRA_BELT,           weight = 1111 },
            { itemId = xi.item.MARKSMANS_RING,        weight = 1111 },
            { itemId = xi.item.REARGUARD_MANTLE,      weight = 1111 },
        },

        {
            { itemId = xi.item.SCROLL_OF_ICE_SPIKES,  weight = 3334 },
            { itemId = xi.item.SCROLL_OF_REFRESH,     weight = 3333 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI, weight = 3333 },
        },

        {
            { itemId = xi.item.FIRE_SPIRIT_PACT,      weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ABSORB_STR,  weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ERASE,       weight = 2500 },
            { itemId = xi.item.SCROLL_OF_PHALANX,     weight = 2500 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.STEAMED_SPROUTS].loot = {
        {
            { itemId = xi.item.GIL,                   weight = 10000, amount = 6000 },
        },

        {
            { itemId = xi.item.SURVIVAL_BELT,         weight = 5000 },
            { itemId = xi.item.ENHANCING_EARRING,     weight = 2500 },
            { itemId = xi.item.GUARDING_GORGET,       weight = 2500 },
        },

        {
            { itemId = xi.item.DRUIDS_ROPE,           weight = 5000 },
            { itemId = xi.item.BLITZ_RING,            weight = 2500 },
            { itemId = xi.item.BALANCE_BUCKLER,       weight = 2500 },
        },

        {
            { itemId = xi.item.SPIRIT_TORQUE,         weight = 5000 },
            { itemId = xi.item.NEMESIS_EARRING,       weight = 2500 },
            { itemId = xi.item.EARTH_MANTLE,          weight = 2500 },
        },

        {
            { itemId = xi.item.ANCIENT_SWORD,         weight = 5000 },
            { itemId = xi.item.STRIKE_SHIELD,         weight = 2500 },
            { itemId = xi.item.AEGIS_RING,            weight = 2500 },
        },

        {
            { itemId = xi.item.SOLON_TORQUE,          weight = 5000 },
            { itemId = xi.item.TUNDRA_MANTLE,         weight = 5000 },
        },

        {
            { itemId = xi.item.PETRIFIED_LOG,          weight = 10000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.SCROLL_OF_ICE_SPIKES,  weight = 1426 },
            { itemId = xi.item.SCROLL_OF_REFRESH,     weight = 1429 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI, weight = 1429 },
            { itemId = xi.item.FIRE_SPIRIT_PACT,      weight = 1429 },
            { itemId = xi.item.SCROLL_OF_ABSORB_STR,  weight = 1429 },
            { itemId = xi.item.SCROLL_OF_ERASE,       weight = 1429 },
            { itemId = xi.item.SCROLL_OF_PHALANX,     weight = 1429 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.TAILS_OF_WOE].loot = {
        {
            { itemId = xi.item.GIL,                   weight = 10000, amount = 6000 },
        },

        {
            { itemId = xi.item.SURVIVAL_BELT,         weight = 5000 },
            { itemId = xi.item.ENHANCING_EARRING,     weight = 2500 },
            { itemId = xi.item.GUARDING_GORGET,       weight = 2500 },
        },

        {
            { itemId = xi.item.DRUIDS_ROPE,           weight = 5000 },
            { itemId = xi.item.BLITZ_RING,            weight = 2500 },
            { itemId = xi.item.BALANCE_BUCKLER,       weight = 2500 },
        },

        {
            { itemId = xi.item.SPIRIT_TORQUE,         weight = 5000 },
            { itemId = xi.item.NEMESIS_EARRING,       weight = 2500 },
            { itemId = xi.item.EARTH_MANTLE,          weight = 2500 },
        },

        {
            { itemId = xi.item.ANCIENT_SWORD,         weight = 5000 },
            { itemId = xi.item.STRIKE_SHIELD,         weight = 2500 },
            { itemId = xi.item.AEGIS_RING,            weight = 2500 },
        },

        {
            { itemId = xi.item.SOLON_TORQUE,          weight = 5000 },
            { itemId = xi.item.TUNDRA_MANTLE,         weight = 5000 },
        },

        {
            { itemId = xi.item.PETRIFIED_LOG,          weight = 10000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.SCROLL_OF_ICE_SPIKES,  weight = 1426 },
            { itemId = xi.item.SCROLL_OF_REFRESH,     weight = 1429 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI, weight = 1429 },
            { itemId = xi.item.FIRE_SPIRIT_PACT,      weight = 1429 },
            { itemId = xi.item.SCROLL_OF_ABSORB_STR,  weight = 1429 },
            { itemId = xi.item.SCROLL_OF_ERASE,       weight = 1429 },
            { itemId = xi.item.SCROLL_OF_PHALANX,     weight = 1429 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.WORMS_TURN].loot = {
        {
            { itemId = xi.item.GIL,                   weight = 10000, amount = 6000 },
        },

        {
            { itemId = xi.item.SURVIVAL_BELT,         weight = 5000 },
            { itemId = xi.item.ENHANCING_EARRING,     weight = 2500 },
            { itemId = xi.item.GUARDING_GORGET,       weight = 2500 },
        },

        {
            { itemId = xi.item.DRUIDS_ROPE,           weight = 5000 },
            { itemId = xi.item.BLITZ_RING,            weight = 2500 },
            { itemId = xi.item.BALANCE_BUCKLER,       weight = 2500 },
        },

        {
            { itemId = xi.item.SPIRIT_TORQUE,         weight = 5000 },
            { itemId = xi.item.NEMESIS_EARRING,       weight = 2500 },
            { itemId = xi.item.EARTH_MANTLE,          weight = 2500 },
        },

        {
            { itemId = xi.item.ANCIENT_SWORD,         weight = 5000 },
            { itemId = xi.item.STRIKE_SHIELD,         weight = 2500 },
            { itemId = xi.item.AEGIS_RING,            weight = 2500 },
        },

        {
            { itemId = xi.item.SOLON_TORQUE,          weight = 5000 },
            { itemId = xi.item.TUNDRA_MANTLE,         weight = 5000 },
        },

        {
            { itemId = xi.item.PETRIFIED_LOG,          weight = 10000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.SCROLL_OF_ICE_SPIKES,  weight = 1426 },
            { itemId = xi.item.SCROLL_OF_REFRESH,     weight = 1429 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI, weight = 1429 },
            { itemId = xi.item.FIRE_SPIRIT_PACT,      weight = 1429 },
            { itemId = xi.item.SCROLL_OF_ABSORB_STR,  weight = 1429 },
            { itemId = xi.item.SCROLL_OF_ERASE,       weight = 1429 },
            { itemId = xi.item.SCROLL_OF_PHALANX,     weight = 1429 },
        },
    }

end)

return m
