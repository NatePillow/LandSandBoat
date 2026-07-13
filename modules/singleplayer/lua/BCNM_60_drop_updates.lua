-----------------------------------
-- Updating drops for BCNMs
-----------------------------------
require('modules/module_utils')
require('scripts/globals/battlefield')
-----------------------------------
local m = Module:new('BCNM_60_drop_updates')

m:addOverride('xi.server.onServerStart', function()
    print('BCNM_60_drop_updates start')
    super()

    xi.battlefield.contents[xi.battlefield.id.CELERY].loot = {
        {
            { itemId = xi.item.LIBATION_ABJURATION,     weight = 5000 },
            { itemId = xi.item.OBLATION_ABJURATION,     weight = 5000 },
        },

        {
            { itemId = xi.item.TRAILERS_KUKRI,          weight =  6667 },
            { itemId = xi.item.SAPIENT_CAPE,            weight =  3333 },
        },

        {
            { itemId = xi.item.PHILOMATH_STOLE,         weight =  3334 },
            { itemId = xi.item.ELUSIVE_EARRING,         weight =  3333 },
            { itemId = xi.item.TRAINERS_WRISTBANDS,     weight =  3333 },
        },

        {
            { itemId = xi.item.NURSEMAIDS_HARP,         weight =  3334 },
            { itemId = xi.item.WALKURE_MASK,            weight =  3333 },
            { itemId = xi.item.GLEEMANS_BELT,           weight =  3333 },
        },

        {
            { itemId = xi.item.KNIGHTLY_MANTLE,         weight =  3334 },
            { itemId = xi.item.PENITENTS_ROPE,          weight =  3333 },
            { itemId = xi.item.AJARI_BEAD_NECKLACE,     weight =  3333 },
        },

        {
            { itemId = xi.item.TELEPORT_RING_DEM,   weight =  1665 },
            { itemId = xi.item.TELEPORT_RING_MEA,   weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_HOLLA, weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_YHOAT, weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_ALTEP, weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_VAHZL, weight =  1667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.PIECE_OF_OXBLOOD,    weight = 10000 },
        },

        {
            { itemId = xi.item.NONE,                weight =  9999 },
            { itemId = xi.item.KRAKEN_CLUB,         weight =     1 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.SHOTS_IN_THE_DARK].loot = {
        {
            { itemId = xi.item.GIL,                 weight = 10000, amount = 15000 },
        },

        {
            { itemId = xi.item.LIBATION_ABJURATION,     weight = 5000 },
            { itemId = xi.item.OBLATION_ABJURATION,     weight = 5000 },
        },

        {
            { itemId = xi.item.TRAILERS_KUKRI,          weight =  6667 },
            { itemId = xi.item.SAPIENT_CAPE,            weight =  3333 },
        },

        {
            { itemId = xi.item.PHILOMATH_STOLE,         weight =  3334 },
            { itemId = xi.item.ELUSIVE_EARRING,         weight =  3333 },
            { itemId = xi.item.TRAINERS_WRISTBANDS,     weight =  3333 },
        },

        {
            { itemId = xi.item.NURSEMAIDS_HARP,         weight =  3334 },
            { itemId = xi.item.WALKURE_MASK,            weight =  3333 },
            { itemId = xi.item.GLEEMANS_BELT,           weight =  3333 },
        },

        {
            { itemId = xi.item.KNIGHTLY_MANTLE,         weight =  3334 },
            { itemId = xi.item.PENITENTS_ROPE,          weight =  3333 },
            { itemId = xi.item.AJARI_BEAD_NECKLACE,     weight =  3333 },
        },

        {
            { itemId = xi.item.TELEPORT_RING_DEM,   weight =  1665 },
            { itemId = xi.item.TELEPORT_RING_MEA,   weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_HOLLA, weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_YHOAT, weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_ALTEP, weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_VAHZL, weight =  1667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.PIECE_OF_OXBLOOD,    weight = 10000 },
        },

        {
            { itemId = xi.item.NONE,                weight =  9999 },
            { itemId = xi.item.KRAKEN_CLUB,         weight =     1 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.UP_IN_ARMS].loot = {
        {
            { itemId = xi.item.GIL,                 weight = 10000, amount = 15000 },
        },

        {
            { itemId = xi.item.LIBATION_ABJURATION,     weight = 5000 },
            { itemId = xi.item.OBLATION_ABJURATION,     weight = 5000 },
        },

        {
            { itemId = xi.item.TRAILERS_KUKRI,          weight =  6667 },
            { itemId = xi.item.SAPIENT_CAPE,            weight =  3333 },
        },

        {
            { itemId = xi.item.PHILOMATH_STOLE,         weight =  3334 },
            { itemId = xi.item.ELUSIVE_EARRING,         weight =  3333 },
            { itemId = xi.item.TRAINERS_WRISTBANDS,     weight =  3333 },
        },

        {
            { itemId = xi.item.NURSEMAIDS_HARP,         weight =  3334 },
            { itemId = xi.item.WALKURE_MASK,            weight =  3333 },
            { itemId = xi.item.GLEEMANS_BELT,           weight =  3333 },
        },

        {
            { itemId = xi.item.KNIGHTLY_MANTLE,         weight =  3334 },
            { itemId = xi.item.PENITENTS_ROPE,          weight =  3333 },
            { itemId = xi.item.AJARI_BEAD_NECKLACE,     weight =  3333 },
        },

        {
            { itemId = xi.item.TELEPORT_RING_DEM,   weight =  1665 },
            { itemId = xi.item.TELEPORT_RING_MEA,   weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_HOLLA, weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_YHOAT, weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_ALTEP, weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_VAHZL, weight =  1667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.PIECE_OF_OXBLOOD,    weight = 10000 },
        },

        {
            { itemId = xi.item.NONE,                weight =  9999 },
            { itemId = xi.item.KRAKEN_CLUB,         weight =     1 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.WILD_WILD_WHISKERS].loot = {
        {
            { itemId = xi.item.GIL,                      weight = 10000, amount = 15000 },
        },

        {
            { itemId = xi.item.LIBATION_ABJURATION,     weight = 5000 },
            { itemId = xi.item.OBLATION_ABJURATION,     weight = 5000 },
        },

        {
            { itemId = xi.item.TRAILERS_KUKRI,          weight =  6667 },
            { itemId = xi.item.SAPIENT_CAPE,            weight =  3333 },
        },

        {
            { itemId = xi.item.PHILOMATH_STOLE,         weight =  3334 },
            { itemId = xi.item.ELUSIVE_EARRING,         weight =  3333 },
            { itemId = xi.item.TRAINERS_WRISTBANDS,     weight =  3333 },
        },

        {
            { itemId = xi.item.NURSEMAIDS_HARP,         weight =  3334 },
            { itemId = xi.item.WALKURE_MASK,            weight =  3333 },
            { itemId = xi.item.GLEEMANS_BELT,           weight =  3333 },
        },

        {
            { itemId = xi.item.KNIGHTLY_MANTLE,         weight =  3334 },
            { itemId = xi.item.PENITENTS_ROPE,          weight =  3333 },
            { itemId = xi.item.AJARI_BEAD_NECKLACE,     weight =  3333 },
        },

        {
            { itemId = xi.item.TELEPORT_RING_DEM,   weight =  1665 },
            { itemId = xi.item.TELEPORT_RING_MEA,   weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_HOLLA, weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_YHOAT, weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_ALTEP, weight =  1667 },
            { itemId = xi.item.TELEPORT_RING_VAHZL, weight =  1667 },
        },

        {
            quantity = 2,
            { itemId = xi.item.PIECE_OF_OXBLOOD,    weight = 10000 },
        },

        {
            { itemId = xi.item.NONE,                weight =  9999 },
            { itemId = xi.item.KRAKEN_CLUB,         weight =     1 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.AMPHIBIAN_ASSAULT].loot = {
        {
            { itemId = xi.item.GIL,                    weight = 10000, amount = 18000 },
        },

        {
            { itemId = xi.item.DARK_TORQUE,            weight =  3334 },
            { itemId = xi.item.DIVINE_TORQUE,          weight =  3333 },
            { itemId = xi.item.ELEMENTAL_TORQUE,       weight =  3333 },
        },

        {
            { itemId = xi.item.ENFEEBLING_TORQUE,      weight =  3334 },
            { itemId = xi.item.ENHANCING_TORQUE,       weight =  3333 },
            { itemId = xi.item.HEALING_TORQUE,         weight =  3333 },
        },

        {
            { itemId = xi.item.NINJUTSU_TORQUE,        weight =  2500 },
            { itemId = xi.item.STRING_TORQUE,          weight =  2500 },
            { itemId = xi.item.SUMMONING_TORQUE,       weight =  2500 },
            { itemId = xi.item.WIND_TORQUE,            weight =  2500 },
        },

        {
            { itemId = xi.item.EVASION_TORQUE,         weight =  2500 },
            { itemId = xi.item.GUARDING_TORQUE,        weight =  2500 },
            { itemId = xi.item.PARRYING_TORQUE,        weight =  2500 },
            { itemId = xi.item.SHIELD_TORQUE,          weight =  2500 },
        },

        {
            quantity = 3,
            { itemId = xi.item.DARK_TORQUE,            weight =  1300 },
            { itemId = xi.item.ELEMENTAL_TORQUE,       weight =  1300 },
            { itemId = xi.item.ENFEEBLING_TORQUE,      weight =  1300 },
            { itemId = xi.item.ENHANCING_TORQUE,       weight =  1300 },
            { itemId = xi.item.HEALING_TORQUE,         weight =  1300 },
            { itemId = xi.item.DIVINE_TORQUE,          weight =  700 },
            { itemId = xi.item.EVASION_TORQUE,         weight =  700 },
            { itemId = xi.item.GUARDING_TORQUE,        weight =  700 },
            { itemId = xi.item.PARRYING_TORQUE,        weight =  700 },
            { itemId = xi.item.SHIELD_TORQUE,          weight =  700 },
        },

        {
            { itemId = xi.item.FIRE_SPIRIT_PACT,       weight =  2000 },
            { itemId = xi.item.SCROLL_OF_ABSORB_STR,   weight =  2000 },
            { itemId = xi.item.SCROLL_OF_ERASE,        weight =  2000 },
            { itemId = xi.item.SCROLL_OF_PHALANX,      weight =  2000 },
            { itemId = xi.item.SCROLL_OF_RAISE_II,     weight =  2000 },
        },

        {
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

    xi.battlefield.contents[xi.battlefield.id.BROTHERS_D_AURPHE].loot = {
        {
            { itemId = xi.item.GIL,                       weight = 10000, amount = 18000 },
        },

        {
            { itemId = xi.item.CROSS_COUNTERS,            weight =  2500 },
            { itemId = xi.item.EURYTOS_BOW,               weight =  2500 },
            { itemId = xi.item.MERCURIAL_SWORD,           weight =  2500 },
            { itemId = xi.item.MERCURIAL_SPEAR,           weight =  2500 },
        },

        {
            quantity = 2,
            { itemId = xi.item.CREEK_M_CLOMPS,            weight =  1250 },
            { itemId = xi.item.CREEK_F_CLOMPS,            weight =  1250 },
            { itemId = xi.item.MARINE_M_BOOTS,            weight =  1250 },
            { itemId = xi.item.MARINE_F_BOOTS,            weight =  1250 },
            { itemId = xi.item.WOOD_M_LEDELSENS,          weight =  1250 },
            { itemId = xi.item.WOOD_F_LEDELSENS,          weight =  1250 },
            { itemId = xi.item.DUNE_SANDALS,              weight =  1250 },
            { itemId = xi.item.RIVER_GAITERS,             weight =  1250 },
        },

        {
            quantity = 2,
            { itemId = xi.item.MARINE_M_GLOVES,           weight =  1250 },
            { itemId = xi.item.MARINE_F_GLOVES,           weight =  1250 },
            { itemId = xi.item.WOOD_GAUNTLETS,            weight =  1250 },
            { itemId = xi.item.WOOD_GLOVES,               weight =  1250 },
            { itemId = xi.item.CREEK_M_MITTS,             weight =  1250 },
            { itemId = xi.item.CREEK_F_MITTS,             weight =  1250 },
            { itemId = xi.item.RIVER_GAUNTLETS,           weight =  1250 },
            { itemId = xi.item.DUNE_BRACERS,              weight =  1250 },
        },

        {
            { itemId = xi.item.SCROLL_OF_FLARE,           weight =  3333 },
            { itemId = xi.item.SCROLL_OF_VALOR_MINUET_IV, weight =  3333 },
            { itemId = xi.item.SCROLL_OF_RERAISE_II,      weight =  3334 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.DEMOLITION_SQUAD].loot = {
        {
            { itemId = xi.item.GIL,                       weight = 10000, amount = 18000 },
        },

        {
            { itemId = xi.item.CROSS_COUNTERS,            weight =  2500 },
            { itemId = xi.item.EURYTOS_BOW,               weight =  2500 },
            { itemId = xi.item.MERCURIAL_SWORD,           weight =  2500 },
            { itemId = xi.item.MERCURIAL_SPEAR,           weight =  2500 },
        },

        {
            quantity = 2,
            { itemId = xi.item.CREEK_M_CLOMPS,            weight =  1250 },
            { itemId = xi.item.CREEK_F_CLOMPS,            weight =  1250 },
            { itemId = xi.item.MARINE_M_BOOTS,            weight =  1250 },
            { itemId = xi.item.MARINE_F_BOOTS,            weight =  1250 },
            { itemId = xi.item.WOOD_M_LEDELSENS,          weight =  1250 },
            { itemId = xi.item.WOOD_F_LEDELSENS,          weight =  1250 },
            { itemId = xi.item.DUNE_SANDALS,              weight =  1250 },
            { itemId = xi.item.RIVER_GAITERS,             weight =  1250 },
        },

        {
            quantity = 2,
            { itemId = xi.item.MARINE_M_GLOVES,           weight =  1250 },
            { itemId = xi.item.MARINE_F_GLOVES,           weight =  1250 },
            { itemId = xi.item.WOOD_GAUNTLETS,            weight =  1250 },
            { itemId = xi.item.WOOD_GLOVES,               weight =  1250 },
            { itemId = xi.item.CREEK_M_MITTS,             weight =  1250 },
            { itemId = xi.item.CREEK_F_MITTS,             weight =  1250 },
            { itemId = xi.item.RIVER_GAUNTLETS,           weight =  1250 },
            { itemId = xi.item.DUNE_BRACERS,              weight =  1250 },
        },

        {
            { itemId = xi.item.SCROLL_OF_FLARE,           weight =  3333 },
            { itemId = xi.item.SCROLL_OF_VALOR_MINUET_IV, weight =  3333 },
            { itemId = xi.item.SCROLL_OF_RERAISE_II,      weight =  3334 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.DISMEMBERMENT_BRIGADE].loot = {
        {
            { itemId = xi.item.GIL,                       weight = 10000, amount = 18000 },
        },

        {
            { itemId = xi.item.ASSAULT_EARRING,        weight =  10000 },
        },

        {
            { itemId = xi.item.ASTRAL_SHIELD,          weight =  2000 },
            { itemId = xi.item.ENHANCING_MANTLE,       weight =  2000 },
            { itemId = xi.item.PEACE_RING,             weight =  2000 },
            { itemId = xi.item.SPECTACLES,             weight =  2000 },
            { itemId = xi.item.MASTER_BELT,            weight =  2000 },
        },

        {
            { itemId = xi.item.ARCHALAUSS_POLE,         weight =   2500 },
            { itemId = xi.item.DOMINION_MACE,           weight =   2500 },
            { itemId = xi.item.FEY_WAND,                weight =   2500 },
            { itemId = xi.item.HAMELIN_FLUTE,           weight =   2500 },
        },

        {
            { itemId = xi.item.ARAMISS_RAPIER,          weight =   2500 },
            { itemId = xi.item.CHICKEN_KNIFE,           weight =   2500 },
            { itemId = xi.item.DRAGVANDIL,              weight =   2500 },
            { itemId = xi.item.KABRAKANS_AXE,           weight =   2500 },
        },

        {
            { itemId = xi.item.FORSETIS_AXE,            weight =   2500 },
            { itemId = xi.item.VASSAGOS_SCYTHE,         weight =   2500 },
            { itemId = xi.item.SCHWARZ_LANCE,           weight =   2500 },
            { itemId = xi.item.SPARTAN_CESTI,           weight =   2500 },
        },

        {
            { itemId = xi.item.OMOKAGE,                 weight =   2000 },
            { itemId = xi.item.SAIREN,                  weight =   2000 },
            { itemId = xi.item.ARMBRUST,                weight =   2000 },
            { itemId = xi.item.LIGHT_BOOMERANG,         weight =   2000 },
            { itemId = xi.item.SARNGA,                  weight =   2000 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.DIVINE_PUNISHERS].loot = {
        {
            { itemId = xi.item.GIL,                       weight = 10000, amount = 18000 },
        },

        {
            { itemId = xi.item.ASSAULT_EARRING,        weight =  10000 },
        },

        {
            { itemId = xi.item.ASTRAL_SHIELD,          weight =  2000 },
            { itemId = xi.item.ENHANCING_MANTLE,       weight =  2000 },
            { itemId = xi.item.PEACE_RING,             weight =  2000 },
            { itemId = xi.item.SPECTACLES,             weight =  2000 },
            { itemId = xi.item.MASTER_BELT,            weight =  2000 },
        },

        {
            { itemId = xi.item.ARCHALAUSS_POLE,         weight =   2500 },
            { itemId = xi.item.DOMINION_MACE,           weight =   2500 },
            { itemId = xi.item.FEY_WAND,                weight =   2500 },
            { itemId = xi.item.HAMELIN_FLUTE,           weight =   2500 },
        },

        {
            { itemId = xi.item.ARAMISS_RAPIER,          weight =   2500 },
            { itemId = xi.item.CHICKEN_KNIFE,           weight =   2500 },
            { itemId = xi.item.DRAGVANDIL,              weight =   2500 },
            { itemId = xi.item.KABRAKANS_AXE,           weight =   2500 },
        },

        {
            { itemId = xi.item.FORSETIS_AXE,            weight =   2500 },
            { itemId = xi.item.VASSAGOS_SCYTHE,         weight =   2500 },
            { itemId = xi.item.SCHWARZ_LANCE,           weight =   2500 },
            { itemId = xi.item.SPARTAN_CESTI,           weight =   2500 },
        },

        {
            { itemId = xi.item.OMOKAGE,                 weight =   2000 },
            { itemId = xi.item.SAIREN,                  weight =   2000 },
            { itemId = xi.item.ARMBRUST,                weight =   2000 },
            { itemId = xi.item.LIGHT_BOOMERANG,         weight =   2000 },
            { itemId = xi.item.SARNGA,                  weight =   2000 },
        },

        {
            { itemId = xi.item.NONE,                      weight =  9000 },
            { itemId = xi.item.FUMA_KYAHAN,               weight =  500 },
            { itemId = xi.item.OCHIUDOS_KOTE,             weight =  500 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.GRIMSHELL_SHOCKTROOPERS].loot = {
        {
            { itemId = xi.item.GIL,                       weight = 10000, amount = 18000 },
        },

        {
            { itemId = xi.item.ASSAULT_EARRING,        weight =  10000 },
        },

        {
            { itemId = xi.item.ASTRAL_SHIELD,          weight =  2000 },
            { itemId = xi.item.ENHANCING_MANTLE,       weight =  2000 },
            { itemId = xi.item.PEACE_RING,             weight =  2000 },
            { itemId = xi.item.SPECTACLES,             weight =  2000 },
            { itemId = xi.item.MASTER_BELT,            weight =  2000 },
        },

        {
            { itemId = xi.item.ARCHALAUSS_POLE,         weight =   2500 },
            { itemId = xi.item.DOMINION_MACE,           weight =   2500 },
            { itemId = xi.item.FEY_WAND,                weight =   2500 },
            { itemId = xi.item.HAMELIN_FLUTE,           weight =   2500 },
        },

        {
            { itemId = xi.item.ARAMISS_RAPIER,          weight =   2500 },
            { itemId = xi.item.CHICKEN_KNIFE,           weight =   2500 },
            { itemId = xi.item.DRAGVANDIL,              weight =   2500 },
            { itemId = xi.item.KABRAKANS_AXE,           weight =   2500 },
        },

        {
            { itemId = xi.item.FORSETIS_AXE,            weight =   2500 },
            { itemId = xi.item.VASSAGOS_SCYTHE,         weight =   2500 },
            { itemId = xi.item.SCHWARZ_LANCE,           weight =   2500 },
            { itemId = xi.item.SPARTAN_CESTI,           weight =   2500 },
        },

        {
            { itemId = xi.item.OMOKAGE,                 weight =   2000 },
            { itemId = xi.item.SAIREN,                  weight =   2000 },
            { itemId = xi.item.ARMBRUST,                weight =   2000 },
            { itemId = xi.item.LIGHT_BOOMERANG,         weight =   2000 },
            { itemId = xi.item.SARNGA,                  weight =   2000 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.JUNGLE_BOOGYMEN].loot = {
        {
            { itemId = xi.item.GIL,                    weight = 10000, amount = 18000 },
        },

        {
            { itemId = xi.item.DARK_TORQUE,            weight =  3334 },
            { itemId = xi.item.DIVINE_TORQUE,          weight =  3333 },
            { itemId = xi.item.ELEMENTAL_TORQUE,       weight =  3333 },
        },

        {
            { itemId = xi.item.ENFEEBLING_TORQUE,      weight =  3334 },
            { itemId = xi.item.ENHANCING_TORQUE,       weight =  3333 },
            { itemId = xi.item.HEALING_TORQUE,         weight =  3333 },
        },

        {
            { itemId = xi.item.NINJUTSU_TORQUE,        weight =  2500 },
            { itemId = xi.item.STRING_TORQUE,          weight =  2500 },
            { itemId = xi.item.SUMMONING_TORQUE,       weight =  2500 },
            { itemId = xi.item.WIND_TORQUE,            weight =  2500 },
        },

        {
            { itemId = xi.item.EVASION_TORQUE,         weight =  2500 },
            { itemId = xi.item.GUARDING_TORQUE,        weight =  2500 },
            { itemId = xi.item.PARRYING_TORQUE,        weight =  2500 },
            { itemId = xi.item.SHIELD_TORQUE,          weight =  2500 },
        },

        {
            quantity = 3,
            { itemId = xi.item.DARK_TORQUE,            weight =  1300 },
            { itemId = xi.item.ELEMENTAL_TORQUE,       weight =  1300 },
            { itemId = xi.item.ENFEEBLING_TORQUE,      weight =  1300 },
            { itemId = xi.item.ENHANCING_TORQUE,       weight =  1300 },
            { itemId = xi.item.HEALING_TORQUE,         weight =  1300 },
            { itemId = xi.item.DIVINE_TORQUE,          weight =  700 },
            { itemId = xi.item.EVASION_TORQUE,         weight =  700 },
            { itemId = xi.item.GUARDING_TORQUE,        weight =  700 },
            { itemId = xi.item.PARRYING_TORQUE,        weight =  700 },
            { itemId = xi.item.SHIELD_TORQUE,          weight =  700 },
        },

        {
            { itemId = xi.item.FIRE_SPIRIT_PACT,       weight =  2000 },
            { itemId = xi.item.SCROLL_OF_ABSORB_STR,   weight =  2000 },
            { itemId = xi.item.SCROLL_OF_ERASE,        weight =  2000 },
            { itemId = xi.item.SCROLL_OF_PHALANX,      weight =  2000 },
            { itemId = xi.item.SCROLL_OF_RAISE_II,     weight =  2000 },
        },

        {
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

    xi.battlefield.contents[xi.battlefield.id.KINDRED_SPIRITS].loot = {
        {
            { itemId = xi.item.GIL,                     weight = 10000, amount = 18000 },
        },

        {
            { itemId = xi.item.ASSAULT_EARRING,        weight =  10000 },
        },

        {
            { itemId = xi.item.ASTRAL_SHIELD,          weight =  2000 },
            { itemId = xi.item.ENHANCING_MANTLE,       weight =  2000 },
            { itemId = xi.item.PEACE_RING,             weight =  2000 },
            { itemId = xi.item.SPECTACLES,             weight =  2000 },
            { itemId = xi.item.MASTER_BELT,            weight =  2000 },
        },

        {
            { itemId = xi.item.ARCHALAUSS_POLE,         weight =   2500 },
            { itemId = xi.item.DOMINION_MACE,           weight =   2500 },
            { itemId = xi.item.FEY_WAND,                weight =   2500 },
            { itemId = xi.item.HAMELIN_FLUTE,           weight =   2500 },
        },

        {
            { itemId = xi.item.ARAMISS_RAPIER,          weight =   2500 },
            { itemId = xi.item.CHICKEN_KNIFE,           weight =   2500 },
            { itemId = xi.item.DRAGVANDIL,              weight =   2500 },
            { itemId = xi.item.KABRAKANS_AXE,           weight =   2500 },
        },

        {
            { itemId = xi.item.FORSETIS_AXE,            weight =   2500 },
            { itemId = xi.item.VASSAGOS_SCYTHE,         weight =   2500 },
            { itemId = xi.item.SCHWARZ_LANCE,           weight =   2500 },
            { itemId = xi.item.SPARTAN_CESTI,           weight =   2500 },
        },

        {
            { itemId = xi.item.OMOKAGE,                 weight =   2000 },
            { itemId = xi.item.SAIREN,                  weight =   2000 },
            { itemId = xi.item.ARMBRUST,                weight =   2000 },
            { itemId = xi.item.LIGHT_BOOMERANG,         weight =   2000 },
            { itemId = xi.item.SARNGA,                  weight =   2000 },
        },

        {
            { itemId = xi.item.SCROLL_OF_RERAISE_II,    weight =  2500 },
            { itemId = xi.item.SCROLL_OF_FIRE_III,      weight =  2500 },
            { itemId = xi.item.SCROLL_OF_CARNAGE_ELEGY, weight =  2500 },
            { itemId = xi.item.ICE_SPIRIT_PACT,         weight =  2500 },
        },
    }

    xi.battlefield.contents[xi.battlefield.id.LEGION_XI_COMITATENSIS].loot = {
        {
            { itemId = xi.item.GIL,                    weight = 10000, amount = 18000 },
        },

        {
            { itemId = xi.item.DARK_TORQUE,            weight =  3334 },
            { itemId = xi.item.DIVINE_TORQUE,          weight =  3333 },
            { itemId = xi.item.ELEMENTAL_TORQUE,       weight =  3333 },
        },

        {
            { itemId = xi.item.ENFEEBLING_TORQUE,      weight =  3334 },
            { itemId = xi.item.ENHANCING_TORQUE,       weight =  3333 },
            { itemId = xi.item.HEALING_TORQUE,         weight =  3333 },
        },

        {
            { itemId = xi.item.NINJUTSU_TORQUE,        weight =  2500 },
            { itemId = xi.item.STRING_TORQUE,          weight =  2500 },
            { itemId = xi.item.SUMMONING_TORQUE,       weight =  2500 },
            { itemId = xi.item.WIND_TORQUE,            weight =  2500 },
        },

        {
            { itemId = xi.item.EVASION_TORQUE,         weight =  2500 },
            { itemId = xi.item.GUARDING_TORQUE,        weight =  2500 },
            { itemId = xi.item.PARRYING_TORQUE,        weight =  2500 },
            { itemId = xi.item.SHIELD_TORQUE,          weight =  2500 },
        },

        {
            quantity = 3,
            { itemId = xi.item.DARK_TORQUE,            weight =  1300 },
            { itemId = xi.item.ELEMENTAL_TORQUE,       weight =  1300 },
            { itemId = xi.item.ENFEEBLING_TORQUE,      weight =  1300 },
            { itemId = xi.item.ENHANCING_TORQUE,       weight =  1300 },
            { itemId = xi.item.HEALING_TORQUE,         weight =  1300 },
            { itemId = xi.item.DIVINE_TORQUE,          weight =  700 },
            { itemId = xi.item.EVASION_TORQUE,         weight =  700 },
            { itemId = xi.item.GUARDING_TORQUE,        weight =  700 },
            { itemId = xi.item.PARRYING_TORQUE,        weight =  700 },
            { itemId = xi.item.SHIELD_TORQUE,          weight =  700 },
        },

        {
            { itemId = xi.item.FIRE_SPIRIT_PACT,       weight =  2000 },
            { itemId = xi.item.SCROLL_OF_ABSORB_STR,   weight =  2000 },
            { itemId = xi.item.SCROLL_OF_ERASE,        weight =  2000 },
            { itemId = xi.item.SCROLL_OF_PHALANX,      weight =  2000 },
            { itemId = xi.item.SCROLL_OF_RAISE_II,     weight =  2000 },
        },

        {
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
