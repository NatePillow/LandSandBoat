-----------------------------------
-- Updating drops for BCNMs
-----------------------------------
require('modules/module_utils')
require('scripts/globals/battlefield')
-----------------------------------
local m = Module:new('BCNM_50_drop_updates')

m:addOverride('xi.server.onServerStart', function()
    print('BCNM_50_drop_updates start')
    super()

    xi.battlefield.contents[xi.battlefield.id.FINAL_BOUT].loot = {
        {
            { itemId = xi.item.GIL,                      weight = 10000, amount = 8000 }, -- Gil
        },

        {
            { itemId = xi.item.NUE_FANG,                 weight = 10000 }, -- Nue Fang
        },

        {
            { itemId = xi.item.KAGEBOSHI,                weight = 1665 },
            { itemId = xi.item.ODENTA,                   weight = 1667 },
            { itemId = xi.item.SHOCK_MASK,               weight = 1667 }, -- Shock Mask
            { itemId = xi.item.SUPER_RIBBON,             weight = 1667 }, -- Super Ribbon
            { itemId = xi.item.MERCURIAL_KRIS,           weight = 1667 },
            { itemId = xi.item.GRAMARY_CAPE,             weight = 1667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.SLY_GAUNTLETS,           weight = 1665 }, -- sly_gauntlets
            { itemId = xi.item.SPIKED_FINGER_GAUNTLETS, weight = 1667 }, -- spiked_finger_gauntlets
            { itemId = xi.item.RUSH_GLOVES,             weight = 1667 }, -- rush_gloves
            { itemId = xi.item.RIVAL_RIBBON,            weight = 1667 }, -- rival_ribbon
            { itemId = xi.item.MANA_CIRCLET,            weight = 1667 }, -- mana_circlet
            { itemId = xi.item.IVORY_MITTS,             weight = 1667 }, -- ivory_mitts
        },

        {
            quantity = 2,
            { itemId = xi.item.STORM_GORGET,     weight = 1426 }, -- storm_gorget
            { itemId = xi.item.INTELLECT_TORQUE, weight = 1429 }, -- intellect_torque
            { itemId = xi.item.BENIGN_NECKLACE,  weight = 1429 }, -- benign_necklace
            { itemId = xi.item.HEAVY_MANTLE,     weight = 1429 }, -- heavy_mantle
            { itemId = xi.item.HATEFUL_COLLAR,   weight = 1429 }, -- hateful_collar
            { itemId = xi.item.ESOTERIC_MANTLE,  weight = 1429 }, -- esoteric_mantle
            { itemId = xi.item.TEMPLARS_MANTLE,  weight = 1429 }, -- templars_mantle
        },

        {
            { itemId = xi.item.SCROLL_OF_QUAKE,          weight = 2500 }, -- Scroll of Quake
            { itemId = xi.item.SCROLL_OF_FREEZE,         weight = 2500 }, -- Scroll of Freeze
            { itemId = xi.item.SCROLL_OF_RAISE_II,       weight = 2500 }, -- Scroll of Raise II
            { itemId = xi.item.SCROLL_OF_REGEN_III,      weight = 2500 }, -- Scroll of Regen III
        },

        {
            quantity = 3,
            { itemId = xi.item.CHUNK_OF_DARK_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_EARTH_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_FIRE_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_ICE_ORE,       weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHT_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHTNING_ORE, weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WATER_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WIND_ORE,      weight =   1250 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.AWFUL_AUTOPSY].loot = {
        {
            { itemId = xi.item.GIL,                      weight = 10000, amount = 8000 }, -- Gil
        },

        {
            { itemId = xi.item.NUE_FANG,                 weight = 10000 }, -- Nue Fang
        },

        {
            { itemId = xi.item.KAGEBOSHI,                weight = 1665 },
            { itemId = xi.item.ODENTA,                   weight = 1667 },
            { itemId = xi.item.SHOCK_MASK,               weight = 1667 }, -- Shock Mask
            { itemId = xi.item.SUPER_RIBBON,             weight = 1667 }, -- Super Ribbon
            { itemId = xi.item.MERCURIAL_KRIS,           weight = 1667 },
            { itemId = xi.item.GRAMARY_CAPE,             weight = 1667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.SLY_GAUNTLETS,           weight = 1665 }, -- sly_gauntlets
            { itemId = xi.item.SPIKED_FINGER_GAUNTLETS, weight = 1667 }, -- spiked_finger_gauntlets
            { itemId = xi.item.RUSH_GLOVES,             weight = 1667 }, -- rush_gloves
            { itemId = xi.item.RIVAL_RIBBON,            weight = 1667 }, -- rival_ribbon
            { itemId = xi.item.MANA_CIRCLET,            weight = 1667 }, -- mana_circlet
            { itemId = xi.item.IVORY_MITTS,             weight = 1667 }, -- ivory_mitts
        },

        {
            quantity = 2,
            { itemId = xi.item.STORM_GORGET,     weight = 1426 }, -- storm_gorget
            { itemId = xi.item.INTELLECT_TORQUE, weight = 1429 }, -- intellect_torque
            { itemId = xi.item.BENIGN_NECKLACE,  weight = 1429 }, -- benign_necklace
            { itemId = xi.item.HEAVY_MANTLE,     weight = 1429 }, -- heavy_mantle
            { itemId = xi.item.HATEFUL_COLLAR,   weight = 1429 }, -- hateful_collar
            { itemId = xi.item.ESOTERIC_MANTLE,  weight = 1429 }, -- esoteric_mantle
            { itemId = xi.item.TEMPLARS_MANTLE,  weight = 1429 }, -- templars_mantle
        },

        {
            { itemId = xi.item.SCROLL_OF_QUAKE,          weight = 2500 }, -- Scroll of Quake
            { itemId = xi.item.SCROLL_OF_FREEZE,         weight = 2500 }, -- Scroll of Freeze
            { itemId = xi.item.SCROLL_OF_RAISE_II,       weight = 2500 }, -- Scroll of Raise II
            { itemId = xi.item.SCROLL_OF_REGEN_III,      weight = 2500 }, -- Scroll of Regen III
        },

        {
            quantity = 3,
            { itemId = xi.item.CHUNK_OF_DARK_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_EARTH_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_FIRE_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_ICE_ORE,       weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHT_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHTNING_ORE, weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WATER_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WIND_ORE,      weight =   1250 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.EYE_OF_THE_TIGER].loot = {
        {
            { itemId = xi.item.GIL,                      weight = 10000, amount = 8000 }, -- Gil
        },

        {
            { itemId = xi.item.NUE_FANG,                 weight = 10000 }, -- Nue Fang
        },

        {
            { itemId = xi.item.KAGEBOSHI,                weight = 1665 },
            { itemId = xi.item.ODENTA,                   weight = 1667 },
            { itemId = xi.item.SHOCK_MASK,               weight = 1667 }, -- Shock Mask
            { itemId = xi.item.SUPER_RIBBON,             weight = 1667 }, -- Super Ribbon
            { itemId = xi.item.MERCURIAL_KRIS,           weight = 1667 },
            { itemId = xi.item.GRAMARY_CAPE,             weight = 1667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.SLY_GAUNTLETS,           weight = 1665 }, -- sly_gauntlets
            { itemId = xi.item.SPIKED_FINGER_GAUNTLETS, weight = 1667 }, -- spiked_finger_gauntlets
            { itemId = xi.item.RUSH_GLOVES,             weight = 1667 }, -- rush_gloves
            { itemId = xi.item.RIVAL_RIBBON,            weight = 1667 }, -- rival_ribbon
            { itemId = xi.item.MANA_CIRCLET,            weight = 1667 }, -- mana_circlet
            { itemId = xi.item.IVORY_MITTS,             weight = 1667 }, -- ivory_mitts
        },

        {
            quantity = 2,
            { itemId = xi.item.STORM_GORGET,     weight = 1426 }, -- storm_gorget
            { itemId = xi.item.INTELLECT_TORQUE, weight = 1429 }, -- intellect_torque
            { itemId = xi.item.BENIGN_NECKLACE,  weight = 1429 }, -- benign_necklace
            { itemId = xi.item.HEAVY_MANTLE,     weight = 1429 }, -- heavy_mantle
            { itemId = xi.item.HATEFUL_COLLAR,   weight = 1429 }, -- hateful_collar
            { itemId = xi.item.ESOTERIC_MANTLE,  weight = 1429 }, -- esoteric_mantle
            { itemId = xi.item.TEMPLARS_MANTLE,  weight = 1429 }, -- templars_mantle
        },

        {
            { itemId = xi.item.SCROLL_OF_QUAKE,          weight = 2500 }, -- Scroll of Quake
            { itemId = xi.item.SCROLL_OF_FREEZE,         weight = 2500 }, -- Scroll of Freeze
            { itemId = xi.item.SCROLL_OF_RAISE_II,       weight = 2500 }, -- Scroll of Raise II
            { itemId = xi.item.SCROLL_OF_REGEN_III,      weight = 2500 }, -- Scroll of Regen III
        },

        {
            quantity = 3,
            { itemId = xi.item.CHUNK_OF_DARK_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_EARTH_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_FIRE_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_ICE_ORE,       weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHT_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHTNING_ORE, weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WATER_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WIND_ORE,      weight =   1250 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.RAPID_RAPTORS].loot = {
        {
            { itemId = xi.item.NUE_FANG,                 weight = 10000 }, -- Nue Fang
        },

        {
            { itemId = xi.item.KAGEBOSHI,                weight = 1665 },
            { itemId = xi.item.ODENTA,                   weight = 1667 },
            { itemId = xi.item.SHOCK_MASK,               weight = 1667 }, -- Shock Mask
            { itemId = xi.item.SUPER_RIBBON,             weight = 1667 }, -- Super Ribbon
            { itemId = xi.item.MERCURIAL_KRIS,           weight = 1667 },
            { itemId = xi.item.GRAMARY_CAPE,             weight = 1667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.SLY_GAUNTLETS,           weight = 1665 }, -- sly_gauntlets
            { itemId = xi.item.SPIKED_FINGER_GAUNTLETS, weight = 1667 }, -- spiked_finger_gauntlets
            { itemId = xi.item.RUSH_GLOVES,             weight = 1667 }, -- rush_gloves
            { itemId = xi.item.RIVAL_RIBBON,            weight = 1667 }, -- rival_ribbon
            { itemId = xi.item.MANA_CIRCLET,            weight = 1667 }, -- mana_circlet
            { itemId = xi.item.IVORY_MITTS,             weight = 1667 }, -- ivory_mitts
        },

        {
            quantity = 2,
            { itemId = xi.item.STORM_GORGET,     weight = 1426 }, -- storm_gorget
            { itemId = xi.item.INTELLECT_TORQUE, weight = 1429 }, -- intellect_torque
            { itemId = xi.item.BENIGN_NECKLACE,  weight = 1429 }, -- benign_necklace
            { itemId = xi.item.HEAVY_MANTLE,     weight = 1429 }, -- heavy_mantle
            { itemId = xi.item.HATEFUL_COLLAR,   weight = 1429 }, -- hateful_collar
            { itemId = xi.item.ESOTERIC_MANTLE,  weight = 1429 }, -- esoteric_mantle
            { itemId = xi.item.TEMPLARS_MANTLE,  weight = 1429 }, -- templars_mantle
        },

        {
            { itemId = xi.item.PETRIFIED_LOG,     weight = 10000 }, -- petrified_log
        },

        {
            quantity = 3,
            { itemId = xi.item.CHUNK_OF_DARK_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_EARTH_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_FIRE_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_ICE_ORE,       weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHT_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHTNING_ORE, weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WATER_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WIND_ORE,      weight =   1250 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.HOSTILE_HERBIVORES].loot = {
        {
            { itemId = xi.item.OCEAN_BELT,               weight = 2000 },
            { itemId = xi.item.JUNGLE_BELT,              weight = 2000 },
            { itemId = xi.item.STEPPE_BELT,              weight = 2000 },
            { itemId = xi.item.DESERT_BELT,              weight = 2000 },
            { itemId = xi.item.FOREST_BELT,              weight = 2000 },
        },

        {
            { itemId = xi.item.OCEAN_STONE,              weight = 2000 },
            { itemId = xi.item.JUNGLE_STONE,             weight = 2000 },
            { itemId = xi.item.STEPPE_STONE,             weight = 2000 },
            { itemId = xi.item.DESERT_STONE,             weight = 2000 },
            { itemId = xi.item.FOREST_STONE,             weight = 2000 },
        },

        {
            { itemId = xi.item.GUARDIANS_RING,           weight = 1440 },
            { itemId = xi.item.CONJURERS_RING,           weight = 1442 },
            { itemId = xi.item.FENCERS_RING,             weight = 1419 },
            { itemId = xi.item.MINSTRELS_RING,           weight = 1419 },
            { itemId = xi.item.MEDICINE_RING,            weight = 1419 },
            { itemId = xi.item.TAMERS_RING,              weight = 1442 },
            { itemId = xi.item.TRACKERS_RING,            weight = 1419 },
        },

        {
            { itemId = xi.item.KAMPFER_RING,             weight = 1258 },
            { itemId = xi.item.SHINOBI_RING,             weight = 1257 },
            { itemId = xi.item.SLAYERS_RING,             weight = 1257 },
            { itemId = xi.item.SORCERERS_RING,           weight = 1257 },
            { itemId = xi.item.SOLDIERS_RING,            weight = 1257 },
            { itemId = xi.item.DRAKE_RING,               weight = 1238 },
            { itemId = xi.item.ROGUES_RING,              weight = 1238 },
            { itemId = xi.item.RONIN_RING,               weight = 1238 },
        },

        {
            { itemId = xi.item.OPTICAL_NEEDLE, weight = 2500 },
            { itemId = xi.item.KAKANPU,        weight = 2500 },
            { itemId = xi.item.MANTRA_COIN,    weight = 2500 },
            { itemId = xi.item.NAZAR_BONJUK,   weight = 2500 },
        },

        {
            { itemId = xi.item.LIBATION_ABJURATION, weight = 5000 },
            { itemId = xi.item.OBLATION_ABJURATION, weight = 5000 },
        },

        {
            { itemId = xi.item.SCROLL_OF_QUAKE,          weight = 2000 },
            { itemId = xi.item.SCROLL_OF_FREEZE,         weight = 2000 },
            { itemId = xi.item.SCROLL_OF_RAISE_II,       weight = 2000 },
            { itemId = xi.item.SCROLL_OF_REGEN_III,      weight = 2000 },
            { itemId = xi.item.LIGHT_SPIRIT_PACT,        weight = 2000 },
        },

        {
            quantity = 3,
            { itemId = xi.item.CHUNK_OF_DARK_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_EARTH_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_FIRE_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_ICE_ORE,       weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHT_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHTNING_ORE, weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WATER_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WIND_ORE,      weight =   1250 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.THREE_TWO_ONE].loot = {
        {
            { itemId = xi.item.GIL,                      weight = 10000, amount = 12000 },
        },

        {
            { itemId = xi.item.OCEAN_BELT,               weight = 2000 },
            { itemId = xi.item.JUNGLE_BELT,              weight = 2000 },
            { itemId = xi.item.STEPPE_BELT,              weight = 2000 },
            { itemId = xi.item.DESERT_BELT,              weight = 2000 },
            { itemId = xi.item.FOREST_BELT,              weight = 2000 },
        },

        {
            { itemId = xi.item.OCEAN_STONE,              weight = 2000 },
            { itemId = xi.item.JUNGLE_STONE,             weight = 2000 },
            { itemId = xi.item.STEPPE_STONE,             weight = 2000 },
            { itemId = xi.item.DESERT_STONE,             weight = 2000 },
            { itemId = xi.item.FOREST_STONE,             weight = 2000 },
        },

        {
            { itemId = xi.item.GUARDIANS_RING,           weight = 1440 },
            { itemId = xi.item.CONJURERS_RING,           weight = 1442 },
            { itemId = xi.item.FENCERS_RING,             weight = 1419 },
            { itemId = xi.item.MINSTRELS_RING,           weight = 1419 },
            { itemId = xi.item.MEDICINE_RING,            weight = 1419 },
            { itemId = xi.item.TAMERS_RING,              weight = 1442 },
            { itemId = xi.item.TRACKERS_RING,            weight = 1419 },
        },

        {
            { itemId = xi.item.KAMPFER_RING,             weight = 1258 },
            { itemId = xi.item.SHINOBI_RING,             weight = 1257 },
            { itemId = xi.item.SLAYERS_RING,             weight = 1257 },
            { itemId = xi.item.SORCERERS_RING,           weight = 1257 },
            { itemId = xi.item.SOLDIERS_RING,            weight = 1257 },
            { itemId = xi.item.DRAKE_RING,               weight = 1238 },
            { itemId = xi.item.ROGUES_RING,              weight = 1238 },
            { itemId = xi.item.RONIN_RING,               weight = 1238 },
        },

        {
            { itemId = xi.item.OPTICAL_NEEDLE, weight = 2500 },
            { itemId = xi.item.KAKANPU,        weight = 2500 },
            { itemId = xi.item.MANTRA_COIN,    weight = 2500 },
            { itemId = xi.item.NAZAR_BONJUK,   weight = 2500 },
        },

        {
            { itemId = xi.item.LIBATION_ABJURATION, weight = 5000 },
            { itemId = xi.item.OBLATION_ABJURATION, weight = 5000 },
        },

        {
            { itemId = xi.item.PETRIFIED_LOG,            weight =  1426 },
            { itemId = xi.item.SCROLL_OF_FREEZE,         weight =  1429 },
            { itemId = xi.item.SCROLL_OF_QUAKE,          weight =  1429 },
            { itemId = xi.item.SCROLL_OF_RAISE_II,       weight =  1429 },
            { itemId = xi.item.SCROLL_OF_REGEN_III,      weight =  1429 },
            { itemId = xi.item.FIRE_SPIRIT_PACT,         weight =  1429 },
            { itemId = xi.item.LIGHT_SPIRIT_PACT,        weight =  1429 },
        },

        {
            quantity = 3,
            { itemId = xi.item.CHUNK_OF_DARK_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_EARTH_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_FIRE_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_ICE_ORE,       weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHT_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHTNING_ORE, weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WATER_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WIND_ORE,      weight =   1250 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.IDOL_THOUGHTS].loot = {
        {
            { itemId = xi.item.OCEAN_BELT,               weight = 2000 },
            { itemId = xi.item.JUNGLE_BELT,              weight = 2000 },
            { itemId = xi.item.STEPPE_BELT,              weight = 2000 },
            { itemId = xi.item.DESERT_BELT,              weight = 2000 },
            { itemId = xi.item.FOREST_BELT,              weight = 2000 },
        },

        {
            { itemId = xi.item.OCEAN_STONE,              weight = 2000 },
            { itemId = xi.item.JUNGLE_STONE,             weight = 2000 },
            { itemId = xi.item.STEPPE_STONE,             weight = 2000 },
            { itemId = xi.item.DESERT_STONE,             weight = 2000 },
            { itemId = xi.item.FOREST_STONE,             weight = 2000 },
        },

        {
            { itemId = xi.item.GUARDIANS_RING,           weight = 1440 },
            { itemId = xi.item.CONJURERS_RING,           weight = 1442 },
            { itemId = xi.item.FENCERS_RING,             weight = 1419 },
            { itemId = xi.item.MINSTRELS_RING,           weight = 1419 },
            { itemId = xi.item.MEDICINE_RING,            weight = 1419 },
            { itemId = xi.item.TAMERS_RING,              weight = 1442 },
            { itemId = xi.item.TRACKERS_RING,            weight = 1419 },
        },

        {
            { itemId = xi.item.KAMPFER_RING,             weight = 1258 },
            { itemId = xi.item.SHINOBI_RING,             weight = 1257 },
            { itemId = xi.item.SLAYERS_RING,             weight = 1257 },
            { itemId = xi.item.SORCERERS_RING,           weight = 1257 },
            { itemId = xi.item.SOLDIERS_RING,            weight = 1257 },
            { itemId = xi.item.DRAKE_RING,               weight = 1238 },
            { itemId = xi.item.ROGUES_RING,              weight = 1238 },
            { itemId = xi.item.RONIN_RING,               weight = 1238 },
        },

        {
            { itemId = xi.item.OPTICAL_NEEDLE, weight = 2500 },
            { itemId = xi.item.KAKANPU,        weight = 2500 },
            { itemId = xi.item.MANTRA_COIN,    weight = 2500 },
            { itemId = xi.item.NAZAR_BONJUK,   weight = 2500 },
        },

        {
            { itemId = xi.item.LIBATION_ABJURATION, weight = 5000 },
            { itemId = xi.item.OBLATION_ABJURATION, weight = 5000 },
        },

        {
            { itemId = xi.item.SCROLL_OF_FREEZE, weight = 10000 },
        },

        {
            quantity = 3,
            { itemId = xi.item.CHUNK_OF_DARK_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_EARTH_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_FIRE_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_ICE_ORE,       weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHT_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHTNING_ORE, weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WATER_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WIND_ORE,      weight =   1250 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.TREASURE_AND_TRIBULATIONS].loot = {
        {
            { itemId = xi.item.GUARDIANS_RING,           weight = 1440 },
            { itemId = xi.item.CONJURERS_RING,           weight = 1442 },
            { itemId = xi.item.FENCERS_RING,             weight = 1419 },
            { itemId = xi.item.MINSTRELS_RING,           weight = 1419 },
            { itemId = xi.item.MEDICINE_RING,            weight = 1419 },
            { itemId = xi.item.TAMERS_RING,              weight = 1442 },
            { itemId = xi.item.TRACKERS_RING,            weight = 1419 },
        },

        {
            { itemId = xi.item.KAMPFER_RING,             weight = 1258 },
            { itemId = xi.item.SHINOBI_RING,             weight = 1257 },
            { itemId = xi.item.SLAYERS_RING,             weight = 1257 },
            { itemId = xi.item.SORCERERS_RING,           weight = 1257 },
            { itemId = xi.item.SOLDIERS_RING,            weight = 1257 },
            { itemId = xi.item.DRAKE_RING,               weight = 1238 },
            { itemId = xi.item.ROGUES_RING,              weight = 1238 },
            { itemId = xi.item.RONIN_RING,               weight = 1238 },
        },

        {
            { itemId = xi.item.PETRIFIED_LOG,            weight = 10000 }, -- Petrified Log
        },

        {
            quantity = 6,
            { itemId = xi.item.CHUNK_OF_DARK_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_EARTH_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_FIRE_ORE,      weight =   1250 },
            { itemId = xi.item.CHUNK_OF_ICE_ORE,       weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHT_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_LIGHTNING_ORE, weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WATER_ORE,     weight =   1250 },
            { itemId = xi.item.CHUNK_OF_WIND_ORE,      weight =   1250 },
        },
    }

end)

return m
