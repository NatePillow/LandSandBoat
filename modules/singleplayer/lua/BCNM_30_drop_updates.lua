-----------------------------------
-- Updating drops for BCNMs
-----------------------------------
require('modules/module_utils')
require('scripts/globals/battlefield')
-----------------------------------
local m = Module:new('BCNM_30_drop_updates')

m:addOverride('xi.server.onServerStart', function()
    print('BCNM_30_drop_updates start')
    super()

    xi.battlefield.contents[xi.battlefield.id.BIRDS_OF_A_FEATHER].loot = {
        {
            { itemId = xi.item.GIL,                    weight = 10000, amount = 3000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.AVATAR_BELT,            weight =  662 },
            { itemId = xi.item.AXE_BELT,               weight =  667 },
            { itemId = xi.item.CESTUS_BELT,            weight =  667 },
            { itemId = xi.item.DAGGER_BELT,            weight =  667 },
            { itemId = xi.item.GUN_BELT,               weight =  667 },
            { itemId = xi.item.KATANA_OBI,             weight =  667 },
            { itemId = xi.item.LANCE_BELT,             weight =  667 },
            { itemId = xi.item.MACE_BELT,              weight =  667 },
            { itemId = xi.item.PICK_BELT,              weight =  667 },
            { itemId = xi.item.RAPIER_BELT,            weight =  667 },
            { itemId = xi.item.SARASHI,                weight =  667 },
            { itemId = xi.item.SCYTHE_BELT,            weight =  667 },
            { itemId = xi.item.SHIELD_BELT,            weight =  667 },
            { itemId = xi.item.SONG_BELT,              weight =  667 },
            { itemId = xi.item.STAFF_BELT,             weight =  667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.ASHIGARU_EARRING,       weight =  662 },
            { itemId = xi.item.BEATERS_EARRING,        weight =  667 },
            { itemId = xi.item.ESQUIRES_EARRING,       weight =  667 },
            { itemId = xi.item.GENIN_EARRING,          weight =  667 },
            { itemId = xi.item.HEALERS_EARRING,        weight =  667 },
            { itemId = xi.item.KILLER_EARRING,         weight =  667 },
            { itemId = xi.item.MAGICIANS_EARRING,      weight =  667 },
            { itemId = xi.item.MERCENARYS_EARRING,     weight =  667 },
            { itemId = xi.item.PILFERERS_EARRING,      weight =  667 },
            { itemId = xi.item.SINGERS_EARRING,        weight =  667 },
            { itemId = xi.item.TRIMMERS_EARRING,       weight =  667 },
            { itemId = xi.item.WARLOCKS_EARRING,       weight =  667 },
            { itemId = xi.item.WIZARDS_EARRING,        weight =  667 },
            { itemId = xi.item.WRESTLERS_EARRING,      weight =  667 },
            { itemId = xi.item.WYVERN_EARRING,         weight =  667 },
        },

        {
            { itemId = xi.item.SCROLL_OF_MAGIC_FINALE, weight = 2500 },
            { itemId = xi.item.SCROLL_OF_DISPEL,       weight = 2500 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI,  weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ERASE,        weight = 2500 },
        },

        {
            { itemId = xi.item.MANNEQUIN_HEAD,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_BODY,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_HANDS,        weight = 2000 },
            { itemId = xi.item.MANNEQUIN_LEGS,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_FEET,         weight = 2000 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.CARAPACE_COMBATANTS].loot = {
        {
            { itemId = xi.item.GIL,                    weight = 10000, amount = 3000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.AVATAR_BELT,            weight =  662 },
            { itemId = xi.item.AXE_BELT,               weight =  667 },
            { itemId = xi.item.CESTUS_BELT,            weight =  667 },
            { itemId = xi.item.DAGGER_BELT,            weight =  667 },
            { itemId = xi.item.GUN_BELT,               weight =  667 },
            { itemId = xi.item.KATANA_OBI,             weight =  667 },
            { itemId = xi.item.LANCE_BELT,             weight =  667 },
            { itemId = xi.item.MACE_BELT,              weight =  667 },
            { itemId = xi.item.PICK_BELT,              weight =  667 },
            { itemId = xi.item.RAPIER_BELT,            weight =  667 },
            { itemId = xi.item.SARASHI,                weight =  667 },
            { itemId = xi.item.SCYTHE_BELT,            weight =  667 },
            { itemId = xi.item.SHIELD_BELT,            weight =  667 },
            { itemId = xi.item.SONG_BELT,              weight =  667 },
            { itemId = xi.item.STAFF_BELT,             weight =  667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.ASHIGARU_EARRING,       weight =  662 },
            { itemId = xi.item.BEATERS_EARRING,        weight =  667 },
            { itemId = xi.item.ESQUIRES_EARRING,       weight =  667 },
            { itemId = xi.item.GENIN_EARRING,          weight =  667 },
            { itemId = xi.item.HEALERS_EARRING,        weight =  667 },
            { itemId = xi.item.KILLER_EARRING,         weight =  667 },
            { itemId = xi.item.MAGICIANS_EARRING,      weight =  667 },
            { itemId = xi.item.MERCENARYS_EARRING,     weight =  667 },
            { itemId = xi.item.PILFERERS_EARRING,      weight =  667 },
            { itemId = xi.item.SINGERS_EARRING,        weight =  667 },
            { itemId = xi.item.TRIMMERS_EARRING,       weight =  667 },
            { itemId = xi.item.WARLOCKS_EARRING,       weight =  667 },
            { itemId = xi.item.WIZARDS_EARRING,        weight =  667 },
            { itemId = xi.item.WRESTLERS_EARRING,      weight =  667 },
            { itemId = xi.item.WYVERN_EARRING,         weight =  667 },
        },

        {
            { itemId = xi.item.SCROLL_OF_ABSORB_AGI,   weight =  1426 },
            { itemId = xi.item.SCROLL_OF_ABSORB_INT,   weight =  1429 },
            { itemId = xi.item.SCROLL_OF_FIRE_II,      weight =  1429 },
            { itemId = xi.item.SCROLL_OF_ERASE,        weight =  1429 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI,  weight =  1429 },
            { itemId = xi.item.SCROLL_OF_DISPEL,       weight =  1429 },
            { itemId = xi.item.SCROLL_OF_MAGIC_FINALE, weight =  1429 },
        },

        {
            { itemId = xi.item.MANNEQUIN_HEAD,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_BODY,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_HANDS,        weight = 2000 },
            { itemId = xi.item.MANNEQUIN_LEGS,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_FEET,         weight = 2000 },
        },

    }

    xi.battlefield.contents[xi.battlefield.id.CREEPING_DOOM].loot = {
        {
            { itemId = xi.item.GIL,                    weight = 10000, amount = 3000 },
        },

        {
            quantity = 4,
            { itemId = xi.item.ASHIGARU_EARRING,       weight =  662 },
            { itemId = xi.item.BEATERS_EARRING,        weight =  667 },
            { itemId = xi.item.ESQUIRES_EARRING,       weight =  667 },
            { itemId = xi.item.GENIN_EARRING,          weight =  667 },
            { itemId = xi.item.HEALERS_EARRING,        weight =  667 },
            { itemId = xi.item.KILLER_EARRING,         weight =  667 },
            { itemId = xi.item.MAGICIANS_EARRING,      weight =  667 },
            { itemId = xi.item.MERCENARYS_EARRING,     weight =  667 },
            { itemId = xi.item.PILFERERS_EARRING,      weight =  667 },
            { itemId = xi.item.SINGERS_EARRING,        weight =  667 },
            { itemId = xi.item.TRIMMERS_EARRING,       weight =  667 },
            { itemId = xi.item.WARLOCKS_EARRING,       weight =  667 },
            { itemId = xi.item.WIZARDS_EARRING,        weight =  667 },
            { itemId = xi.item.WRESTLERS_EARRING,      weight =  667 },
            { itemId = xi.item.WYVERN_EARRING,         weight =  667 },
        },

        {
            { itemId = xi.item.SCROLL_OF_MAGIC_FINALE,  weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ERASE,         weight = 2500 },
            { itemId = xi.item.SCROLL_OF_DISPEL,        weight = 2500 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI,   weight = 2500 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.DIE_BY_THE_SWORD].loot = {
        {
            { itemId = xi.item.GIL,                    weight = 10000, amount = 3000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.AVATAR_BELT,            weight =  662 },
            { itemId = xi.item.AXE_BELT,               weight =  667 },
            { itemId = xi.item.CESTUS_BELT,            weight =  667 },
            { itemId = xi.item.DAGGER_BELT,            weight =  667 },
            { itemId = xi.item.GUN_BELT,               weight =  667 },
            { itemId = xi.item.KATANA_OBI,             weight =  667 },
            { itemId = xi.item.LANCE_BELT,             weight =  667 },
            { itemId = xi.item.MACE_BELT,              weight =  667 },
            { itemId = xi.item.PICK_BELT,              weight =  667 },
            { itemId = xi.item.RAPIER_BELT,            weight =  667 },
            { itemId = xi.item.SARASHI,                weight =  667 },
            { itemId = xi.item.SCYTHE_BELT,            weight =  667 },
            { itemId = xi.item.SHIELD_BELT,            weight =  667 },
            { itemId = xi.item.SONG_BELT,              weight =  667 },
            { itemId = xi.item.STAFF_BELT,             weight =  667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.ASHIGARU_EARRING,       weight =  662 },
            { itemId = xi.item.BEATERS_EARRING,        weight =  667 },
            { itemId = xi.item.ESQUIRES_EARRING,       weight =  667 },
            { itemId = xi.item.GENIN_EARRING,          weight =  667 },
            { itemId = xi.item.HEALERS_EARRING,        weight =  667 },
            { itemId = xi.item.KILLER_EARRING,         weight =  667 },
            { itemId = xi.item.MAGICIANS_EARRING,      weight =  667 },
            { itemId = xi.item.MERCENARYS_EARRING,     weight =  667 },
            { itemId = xi.item.PILFERERS_EARRING,      weight =  667 },
            { itemId = xi.item.SINGERS_EARRING,        weight =  667 },
            { itemId = xi.item.TRIMMERS_EARRING,       weight =  667 },
            { itemId = xi.item.WARLOCKS_EARRING,       weight =  667 },
            { itemId = xi.item.WIZARDS_EARRING,        weight =  667 },
            { itemId = xi.item.WRESTLERS_EARRING,      weight =  667 },
            { itemId = xi.item.WYVERN_EARRING,         weight =  667 },
        },

        {
            { itemId = xi.item.SCROLL_OF_MAGIC_FINALE, weight = 2000 },
            { itemId = xi.item.SCROLL_OF_REGEN,        weight = 2000 },
            { itemId = xi.item.SCROLL_OF_ERASE,        weight = 2000 },
            { itemId = xi.item.SCROLL_OF_DISPEL,       weight = 2000 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI,  weight = 2000 },
        },

        {
            { itemId = xi.item.MANNEQUIN_HEAD,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_BODY,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_HANDS,        weight = 2000 },
            { itemId = xi.item.MANNEQUIN_LEGS,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_FEET,         weight = 2000 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.PETRIFYING_PAIR].loot = {
        {
            { itemId = xi.item.GIL,                    weight = 10000, amount = 3000 },
        },

        {
            { itemId = xi.item.NONE,                      weight = 9000 },
            { itemId = xi.item.LEAPING_BOOTS,             weight = 1000 },
        },

        {
            quantity = 4,
            { itemId = xi.item.AVATAR_BELT,            weight =  662 },
            { itemId = xi.item.AXE_BELT,               weight =  667 },
            { itemId = xi.item.CESTUS_BELT,            weight =  667 },
            { itemId = xi.item.DAGGER_BELT,            weight =  667 },
            { itemId = xi.item.GUN_BELT,               weight =  667 },
            { itemId = xi.item.KATANA_OBI,             weight =  667 },
            { itemId = xi.item.LANCE_BELT,             weight =  667 },
            { itemId = xi.item.MACE_BELT,              weight =  667 },
            { itemId = xi.item.PICK_BELT,              weight =  667 },
            { itemId = xi.item.RAPIER_BELT,            weight =  667 },
            { itemId = xi.item.SARASHI,                weight =  667 },
            { itemId = xi.item.SCYTHE_BELT,            weight =  667 },
            { itemId = xi.item.SHIELD_BELT,            weight =  667 },
            { itemId = xi.item.SONG_BELT,              weight =  667 },
            { itemId = xi.item.STAFF_BELT,             weight =  667 },
        },

        {
            { itemId = xi.item.SCROLL_OF_ABSORB_AGI,      weight =  1426 },
            { itemId = xi.item.SCROLL_OF_ABSORB_INT,      weight =  1429 },
            { itemId = xi.item.SCROLL_OF_ABSORB_VIT,      weight =  1429 },
            { itemId = xi.item.SCROLL_OF_MAGIC_FINALE,    weight =  1429 },
            { itemId = xi.item.SCROLL_OF_DISPEL,          weight =  1429 },
            { itemId = xi.item.SCROLL_OF_ERASE,           weight =  1429 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI,     weight =  1429 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.DROPPING_LIKE_FLIES].loot = {
        {
            { itemId = xi.item.GIL,                     weight = 10000, amount = 4000 },
        },

        {
            { itemId = xi.item.NONE,                    weight = 9000 },
            { itemId = xi.item.EMPEROR_HAIRPIN,         weight = 1000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.ASHIGARU_TARGE,         weight = 662 },
            { itemId = xi.item.VARLETS_TARGE,          weight = 667 },
            { itemId = xi.item.WRESTLERS_ASPIS,        weight = 667 },
            { itemId = xi.item.SINGERS_SHIELD,         weight = 667 },
            { itemId = xi.item.WARLOCKS_SHIELD,        weight = 667 },
            { itemId = xi.item.MAGICIANS_SHIELD,       weight = 667 },
            { itemId = xi.item.MERCENARYS_TARGE,       weight = 667 },
            { itemId = xi.item.BEATERS_ASPIS,          weight = 667 },
            { itemId = xi.item.PILFERERS_ASPIS,        weight = 667 },
            { itemId = xi.item.HEALERS_SHIELD,         weight = 667 },
            { itemId = xi.item.GENIN_ASPIS,            weight = 667 },
            { itemId = xi.item.KILLER_TARGE,           weight = 667 },
            { itemId = xi.item.WIZARDS_SHIELD,         weight = 667 },
            { itemId = xi.item.TRIMMERS_ASPIS,         weight = 667 },
            { itemId = xi.item.WYVERN_TARGE,           weight = 667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.MERCENARY_MANTLE,       weight = 662 },
            { itemId = xi.item.SINGERS_MANTLE,         weight = 667 },
            { itemId = xi.item.WIZARDS_MANTLE,         weight = 667 },
            { itemId = xi.item.ASHIGARU_MANTLE,        weight = 667 },
            { itemId = xi.item.WYVERN_MANTLE,          weight = 667 },
            { itemId = xi.item.KILLER_MANTLE,          weight = 667 },
            { itemId = xi.item.TRIMMERS_MANTLE,        weight = 667 },
            { itemId = xi.item.GENIN_MANTLE,           weight = 667 },
            { itemId = xi.item.WARLOCKS_MANTLE,        weight = 667 },
            { itemId = xi.item.WRESTLERS_MANTLE,       weight = 667 },
            { itemId = xi.item.MAGICIANS_MANTLE,       weight = 667 },
            { itemId = xi.item.PILFERERS_MANTLE,       weight = 667 },
            { itemId = xi.item.BEATERS_MANTLE,         weight = 667 },
            { itemId = xi.item.ESQUIRES_MANTLE,        weight = 667 },
            { itemId = xi.item.HEALERS_MANTLE,         weight = 667 },
        },

        {
            { itemId = xi.item.PETRIFIED_LOG,          weight = 10000 },
        },

        {
            { itemId = xi.item.SCROLL_OF_MAGIC_FINALE,  weight = 2500 },
            { itemId = xi.item.SCROLL_OF_DISPEL,        weight = 2500 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI,   weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ERASE,         weight = 2500 },
        },

        {
            { itemId = xi.item.MANNEQUIN_HEAD,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_BODY,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_HANDS,        weight = 2000 },
            { itemId = xi.item.MANNEQUIN_LEGS,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_FEET,         weight = 2000 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.GROVE_GUARDIANS].loot = {
        {
            { itemId = xi.item.GIL,                    weight = 10000, amount = 4000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.ASHIGARU_TARGE,         weight = 662 },
            { itemId = xi.item.VARLETS_TARGE,          weight = 667 },
            { itemId = xi.item.WRESTLERS_ASPIS,        weight = 667 },
            { itemId = xi.item.SINGERS_SHIELD,         weight = 667 },
            { itemId = xi.item.WARLOCKS_SHIELD,        weight = 667 },
            { itemId = xi.item.MAGICIANS_SHIELD,       weight = 667 },
            { itemId = xi.item.MERCENARYS_TARGE,       weight = 667 },
            { itemId = xi.item.BEATERS_ASPIS,          weight = 667 },
            { itemId = xi.item.PILFERERS_ASPIS,        weight = 667 },
            { itemId = xi.item.HEALERS_SHIELD,         weight = 667 },
            { itemId = xi.item.GENIN_ASPIS,            weight = 667 },
            { itemId = xi.item.KILLER_TARGE,           weight = 667 },
            { itemId = xi.item.WIZARDS_SHIELD,         weight = 667 },
            { itemId = xi.item.TRIMMERS_ASPIS,         weight = 667 },
            { itemId = xi.item.WYVERN_TARGE,           weight = 667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.MERCENARY_MANTLE,       weight = 662 },
            { itemId = xi.item.SINGERS_MANTLE,         weight = 667 },
            { itemId = xi.item.WIZARDS_MANTLE,         weight = 667 },
            { itemId = xi.item.ASHIGARU_MANTLE,        weight = 667 },
            { itemId = xi.item.WYVERN_MANTLE,          weight = 667 },
            { itemId = xi.item.KILLER_MANTLE,          weight = 667 },
            { itemId = xi.item.TRIMMERS_MANTLE,        weight = 667 },
            { itemId = xi.item.GENIN_MANTLE,           weight = 667 },
            { itemId = xi.item.WARLOCKS_MANTLE,        weight = 667 },
            { itemId = xi.item.WRESTLERS_MANTLE,       weight = 667 },
            { itemId = xi.item.MAGICIANS_MANTLE,       weight = 667 },
            { itemId = xi.item.PILFERERS_MANTLE,       weight = 667 },
            { itemId = xi.item.BEATERS_MANTLE,         weight = 667 },
            { itemId = xi.item.ESQUIRES_MANTLE,        weight = 667 },
            { itemId = xi.item.HEALERS_MANTLE,         weight = 667 },
        },

        {
            { itemId = xi.item.PETRIFIED_LOG,          weight = 10000 },
        },

        {
            { itemId = xi.item.SCROLL_OF_MAGIC_FINALE, weight = 2500 },
            { itemId = xi.item.SCROLL_OF_DISPEL,       weight = 2500 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI,  weight = 2500 },
            { itemId = xi.item.SCROLL_OF_ERASE,        weight = 2500 },
        },

        {
            { itemId = xi.item.MANNEQUIN_HEAD,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_BODY,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_HANDS,        weight = 2000 },
            { itemId = xi.item.MANNEQUIN_LEGS,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_FEET,         weight = 2000 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.HAREM_SCAREM].loot = {
        {
            { itemId = xi.item.GIL,                    weight = 10000, amount = 4000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.ASHIGARU_TARGE,         weight = 662 },
            { itemId = xi.item.VARLETS_TARGE,          weight = 667 },
            { itemId = xi.item.WRESTLERS_ASPIS,        weight = 667 },
            { itemId = xi.item.SINGERS_SHIELD,         weight = 667 },
            { itemId = xi.item.WARLOCKS_SHIELD,        weight = 667 },
            { itemId = xi.item.MAGICIANS_SHIELD,       weight = 667 },
            { itemId = xi.item.MERCENARYS_TARGE,       weight = 667 },
            { itemId = xi.item.BEATERS_ASPIS,          weight = 667 },
            { itemId = xi.item.PILFERERS_ASPIS,        weight = 667 },
            { itemId = xi.item.HEALERS_SHIELD,         weight = 667 },
            { itemId = xi.item.GENIN_ASPIS,            weight = 667 },
            { itemId = xi.item.KILLER_TARGE,           weight = 667 },
            { itemId = xi.item.WIZARDS_SHIELD,         weight = 667 },
            { itemId = xi.item.TRIMMERS_ASPIS,         weight = 667 },
            { itemId = xi.item.WYVERN_TARGE,           weight = 667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.MERCENARY_MANTLE,       weight = 662 },
            { itemId = xi.item.SINGERS_MANTLE,         weight = 667 },
            { itemId = xi.item.WIZARDS_MANTLE,         weight = 667 },
            { itemId = xi.item.ASHIGARU_MANTLE,        weight = 667 },
            { itemId = xi.item.WYVERN_MANTLE,          weight = 667 },
            { itemId = xi.item.KILLER_MANTLE,          weight = 667 },
            { itemId = xi.item.TRIMMERS_MANTLE,        weight = 667 },
            { itemId = xi.item.GENIN_MANTLE,           weight = 667 },
            { itemId = xi.item.WARLOCKS_MANTLE,        weight = 667 },
            { itemId = xi.item.WRESTLERS_MANTLE,       weight = 667 },
            { itemId = xi.item.MAGICIANS_MANTLE,       weight = 667 },
            { itemId = xi.item.PILFERERS_MANTLE,       weight = 667 },
            { itemId = xi.item.BEATERS_MANTLE,         weight = 667 },
            { itemId = xi.item.ESQUIRES_MANTLE,        weight = 667 },
            { itemId = xi.item.HEALERS_MANTLE,         weight = 667 },
        },

        {
            { itemId = xi.item.PETRIFIED_LOG,          weight = 10000 },
        },

        {
            { itemId = xi.item.SCROLL_OF_ERASE,        weight = 2000 },
            { itemId = xi.item.SCROLL_OF_DISPEL,       weight = 2000 },
            { itemId = xi.item.SCROLL_OF_MAGIC_FINALE, weight = 2000 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI,  weight = 2000 },
            { itemId = xi.item.SCROLL_OF_REGEN,        weight = 2000 },
        },

        {
            { itemId = xi.item.MANNEQUIN_HEAD,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_BODY,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_HANDS,        weight = 2000 },
            { itemId = xi.item.MANNEQUIN_LEGS,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_FEET,         weight = 2000 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.LET_SLEEPING_DOGS_DIE].loot = {
        {
            { itemId = xi.item.GIL,                    weight = 10000, amount = 4000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.ASHIGARU_TARGE,         weight = 662 },
            { itemId = xi.item.VARLETS_TARGE,          weight = 667 },
            { itemId = xi.item.WRESTLERS_ASPIS,        weight = 667 },
            { itemId = xi.item.SINGERS_SHIELD,         weight = 667 },
            { itemId = xi.item.WARLOCKS_SHIELD,        weight = 667 },
            { itemId = xi.item.MAGICIANS_SHIELD,       weight = 667 },
            { itemId = xi.item.MERCENARYS_TARGE,       weight = 667 },
            { itemId = xi.item.BEATERS_ASPIS,          weight = 667 },
            { itemId = xi.item.PILFERERS_ASPIS,        weight = 667 },
            { itemId = xi.item.HEALERS_SHIELD,         weight = 667 },
            { itemId = xi.item.GENIN_ASPIS,            weight = 667 },
            { itemId = xi.item.KILLER_TARGE,           weight = 667 },
            { itemId = xi.item.WIZARDS_SHIELD,         weight = 667 },
            { itemId = xi.item.TRIMMERS_ASPIS,         weight = 667 },
            { itemId = xi.item.WYVERN_TARGE,           weight = 667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.MERCENARY_MANTLE,       weight = 662 },
            { itemId = xi.item.SINGERS_MANTLE,         weight = 667 },
            { itemId = xi.item.WIZARDS_MANTLE,         weight = 667 },
            { itemId = xi.item.ASHIGARU_MANTLE,        weight = 667 },
            { itemId = xi.item.WYVERN_MANTLE,          weight = 667 },
            { itemId = xi.item.KILLER_MANTLE,          weight = 667 },
            { itemId = xi.item.TRIMMERS_MANTLE,        weight = 667 },
            { itemId = xi.item.GENIN_MANTLE,           weight = 667 },
            { itemId = xi.item.WARLOCKS_MANTLE,        weight = 667 },
            { itemId = xi.item.WRESTLERS_MANTLE,       weight = 667 },
            { itemId = xi.item.MAGICIANS_MANTLE,       weight = 667 },
            { itemId = xi.item.PILFERERS_MANTLE,       weight = 667 },
            { itemId = xi.item.BEATERS_MANTLE,         weight = 667 },
            { itemId = xi.item.ESQUIRES_MANTLE,        weight = 667 },
            { itemId = xi.item.HEALERS_MANTLE,         weight = 667 },
        },

        {
            { itemId = xi.item.PETRIFIED_LOG,          weight = 10000 },
        },

        {
            { itemId = xi.item.SCROLL_OF_ABSORB_AGI,   weight =  1426 },
            { itemId = xi.item.SCROLL_OF_ABSORB_INT,   weight =  1429 },
            { itemId = xi.item.SCROLL_OF_ABSORB_VIT,   weight =  1429 },
            { itemId = xi.item.SCROLL_OF_MAGIC_FINALE, weight =  1429 },
            { itemId = xi.item.SCROLL_OF_ERASE,        weight =  1429 },
            { itemId = xi.item.SCROLL_OF_UTSUSEMI_NI,  weight =  1429 },
            { itemId = xi.item.SCROLL_OF_DISPEL,       weight =  1429 },
        },

        {
            { itemId = xi.item.MANNEQUIN_HEAD,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_BODY,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_HANDS,        weight = 2000 },
            { itemId = xi.item.MANNEQUIN_LEGS,         weight = 2000 },
            { itemId = xi.item.MANNEQUIN_FEET,         weight = 2000 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.TOADAL_RECALL].loot = {
        {
            { itemId = xi.item.GIL,                    weight = 10000, amount = 4000 },
        },

        {
            quantity = 2,
            { itemId = xi.item.ASHIGARU_TARGE,         weight = 662 },
            { itemId = xi.item.VARLETS_TARGE,          weight = 667 },
            { itemId = xi.item.WRESTLERS_ASPIS,        weight = 667 },
            { itemId = xi.item.SINGERS_SHIELD,         weight = 667 },
            { itemId = xi.item.WARLOCKS_SHIELD,        weight = 667 },
            { itemId = xi.item.MAGICIANS_SHIELD,       weight = 667 },
            { itemId = xi.item.MERCENARYS_TARGE,       weight = 667 },
            { itemId = xi.item.BEATERS_ASPIS,          weight = 667 },
            { itemId = xi.item.PILFERERS_ASPIS,        weight = 667 },
            { itemId = xi.item.HEALERS_SHIELD,         weight = 667 },
            { itemId = xi.item.GENIN_ASPIS,            weight = 667 },
            { itemId = xi.item.KILLER_TARGE,           weight = 667 },
            { itemId = xi.item.WIZARDS_SHIELD,         weight = 667 },
            { itemId = xi.item.TRIMMERS_ASPIS,         weight = 667 },
            { itemId = xi.item.WYVERN_TARGE,           weight = 667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.MERCENARY_MANTLE,       weight = 662 },
            { itemId = xi.item.SINGERS_MANTLE,         weight = 667 },
            { itemId = xi.item.WIZARDS_MANTLE,         weight = 667 },
            { itemId = xi.item.ASHIGARU_MANTLE,        weight = 667 },
            { itemId = xi.item.WYVERN_MANTLE,          weight = 667 },
            { itemId = xi.item.KILLER_MANTLE,          weight = 667 },
            { itemId = xi.item.TRIMMERS_MANTLE,        weight = 667 },
            { itemId = xi.item.GENIN_MANTLE,           weight = 667 },
            { itemId = xi.item.WARLOCKS_MANTLE,        weight = 667 },
            { itemId = xi.item.WRESTLERS_MANTLE,       weight = 667 },
            { itemId = xi.item.MAGICIANS_MANTLE,       weight = 667 },
            { itemId = xi.item.PILFERERS_MANTLE,       weight = 667 },
            { itemId = xi.item.BEATERS_MANTLE,         weight = 667 },
            { itemId = xi.item.ESQUIRES_MANTLE,        weight = 667 },
            { itemId = xi.item.HEALERS_MANTLE,         weight = 667 },
        },

        {
            { itemId = xi.item.PETRIFIED_LOG,          weight = 10000 },
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
