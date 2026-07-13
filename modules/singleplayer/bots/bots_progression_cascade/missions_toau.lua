-----------------------------------
-- Treasures of Aht Urhgan mission recipes for the cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
--
-- Mission 48 (epilogue) is intentionally skipped — it doesn't advance a bit
-- and is post-mission recap content.
--
-- ToAU is the last-in-scope expansion; see ../README.md § Scope.
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_missions_toau')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local mission = cascade.mission

do
    local tm = xi.mission.log_id.TOAU
    local mi = xi.mission.id.toau

    cascade.recipes.toau = {

        -- ===== Intro: Whitegate orientation =====
        mission(tm, mi.LAND_OF_SACRED_SERPENTS,'scripts/missions/toau/01_Land_of_Sacred_Serpents'),
        mission(tm, mi.IMMORTAL_SENTRIES,      'scripts/missions/toau/02_Immortal_Sentries'),
        mission(tm, mi.PRESIDENT_SALAHEEM,     'scripts/missions/toau/03_President_Salaheem'),

        -- ===== Salaheem's Sentinels enlistment =====
        mission(tm, mi.KNIGHT_OF_GOLD,         'scripts/missions/toau/04_Knight_of_Gold'),
        mission(tm, mi.CONFESSIONS_OF_ROYALTY, 'scripts/missions/toau/05_Confessions_of_Royalty'),
        mission(tm, mi.EASTERLY_WINDS,         'scripts/missions/toau/06_Easterly_Winds',
            function(p) npcUtil.giveItem(p, { { xi.item.IMPERIAL_BRONZE_PIECE, 10 } }) end),
        mission(tm, mi.WESTERLY_WINDS,         'scripts/missions/toau/07_Westerly_Winds'),

        -- ===== Astral Compass / Mamool Ja recon =====
        mission(tm, mi.A_MERCENARY_LIFE,       'scripts/missions/toau/08_A_Mercenary_Life'),
        mission(tm, mi.UNDERSEA_SCOUTING,      'scripts/missions/toau/09_Undersea_Scouting'),
        mission(tm, mi.ASTRAL_WAVES,           'scripts/missions/toau/10_Astral_Waves'),
        mission(tm, mi.IMPERIAL_SCHEMES,       'scripts/missions/toau/11_Imperial_Schemes'),

        -- ===== Lamia / Lost Kingdom (Nashmau) =====
        mission(tm, mi.ROYAL_PUPPETEER,        'scripts/missions/toau/12_Royal_Puppeteer'),
        mission(tm, mi.LOST_KINGDOM,           'scripts/missions/toau/13_Lost_Kingdom'),
        mission(tm, mi.THE_DOLPHIN_CREST,      'scripts/missions/toau/14_The_Dolphin_Crest'),
        mission(tm, mi.THE_BLACK_COFFIN,       'scripts/missions/toau/15_The_Black_Coffin'),
        mission(tm, mi.GHOSTS_OF_THE_PAST,     'scripts/missions/toau/16_Ghosts_of_the_Past'),

        -- ===== Aphmau / Ovjang diplomatic mid-arc =====
        mission(tm, mi.GUESTS_OF_THE_EMPIRE,   'scripts/missions/toau/17_Guests_of_the_Empire'),
        mission(tm, mi.PASSING_GLORY,          'scripts/missions/toau/18_Passing_Glory'),
        mission(tm, mi.SWEETS_FOR_THE_SOUL,    'scripts/missions/toau/19_Sweets_for_the_Soul'),
        mission(tm, mi.TEAHOUSE_TUMULT,        'scripts/missions/toau/20_Teahouse_Tumult'),
        mission(tm, mi.FINDERS_KEEPERS,        'scripts/missions/toau/21_Finders_Keepers'),
        mission(tm, mi.SHIELD_OF_DIPLOMACY,    'scripts/missions/toau/22_Shield_of_Diplomacy'),
        mission(tm, mi.SOCIAL_GRACES,          'scripts/missions/toau/23_Social_Graces'),
        mission(tm, mi.FOILED_AMBITION,        'scripts/missions/toau/24_Foiled_Ambition'),
        mission(tm, mi.PLAYING_THE_PART,       'scripts/missions/toau/25_Playing_the_Part'),

        -- ===== Seal of Serpent / Puppet in Peril =====
        mission(tm, mi.SEAL_OF_THE_SERPENT,    'scripts/missions/toau/26_Seal_of_the_Serpent'),
        mission(tm, mi.MISPLACED_NOBILITY,     'scripts/missions/toau/27_Misplaced_Nobility'),
        mission(tm, mi.BASTION_OF_KNOWLEDGE,   'scripts/missions/toau/28_Bastion_of_Knowledge'),
        mission(tm, mi.PUPPET_IN_PERIL,        'scripts/missions/toau/29_Puppet_in_Peril'),

        -- ===== Periqia / Mamool Ja escalation =====
        mission(tm, mi.PREVALENCE_OF_PIRATES,  'scripts/missions/toau/30_Prevalence_of_Pirates'),
        -- 31 Shades of Vengeance unlocks Periqia Assault via KI.
        mission(tm, mi.SHADES_OF_VENGEANCE,    'scripts/missions/toau/31_Shades_of_Vengeance',
            function(p) npcUtil.giveKeyItem(p, xi.ki.PERIQIA_ASSAULT_AREA_ENTRY_PERMIT) end),
        mission(tm, mi.IN_THE_BLOOD,           'scripts/missions/toau/32_In_the_Blood'),
        mission(tm, mi.SENTINELS_HONOR,        'scripts/missions/toau/33_Sentinels_Honor'),
        mission(tm, mi.TESTING_THE_WATERS,     'scripts/missions/toau/34_Testing_the_Waters'),
        mission(tm, mi.LEGACY_OF_THE_LOST,     'scripts/missions/toau/35_Legacy_of_the_Lost'),
        mission(tm, mi.GAZE_OF_THE_SABOTEUR,   'scripts/missions/toau/36_Gaze_of_the_Saboteur'),

        -- ===== Allied Council / Nyzul / Alexander climax =====
        mission(tm, mi.PATH_OF_BLOOD,          'scripts/missions/toau/37_Path_of_Blood'),
        mission(tm, mi.STIRRINGS_OF_WAR,       'scripts/missions/toau/38_Stirrings_of_War'),
        mission(tm, mi.ALLIED_RUMBLINGS,       'scripts/missions/toau/39_Allied_Rumblings'),
        mission(tm, mi.UNRAVELING_REASON,      'scripts/missions/toau/40_Unraveling_Reason'),
        mission(tm, mi.LIGHT_OF_JUDGMENT,      'scripts/missions/toau/41_Light_of_Judgement'),
        -- 42 Path of Darkness unlocks Nyzul Isle via KI.
        mission(tm, mi.PATH_OF_DARKNESS,       'scripts/missions/toau/42_Path_of_Darkness',
            function(p) npcUtil.giveKeyItem(p, xi.ki.NYZUL_ISLE_ROUTE) end),
        mission(tm, mi.FANGS_OF_THE_LION,      'scripts/missions/toau/43_Fangs_of_the_Lion'),
        mission(tm, mi.NASHMEIRAS_PLEA,        'scripts/missions/toau/44_Nashmeiras_Plea'),
        mission(tm, mi.RAGNAROK,               'scripts/missions/toau/45_Ragnarok'),

        -- ===== Imperial Coronation finale =====
        -- 46 Imperial Coronation is a 4-way reward pick. Singleplayer over-grant:
        -- give all 4 (3 rings + the Imperial Standard).
        mission(tm, mi.IMPERIAL_CORONATION,    'scripts/missions/toau/46_Imperial_Coronation',
            function(p)
                npcUtil.giveItem(p, xi.item.BALRAHNS_RING)
                npcUtil.giveItem(p, xi.item.ULTHALAMS_RING)
                npcUtil.giveItem(p, xi.item.JALZAHNS_RING)
                npcUtil.giveItem(p, xi.item.IMPERIAL_STANDARD)
            end),
        mission(tm, mi.THE_EMPRESS_CROWNED,    'scripts/missions/toau/47_The_Empress_Crowned'),
    }
end

return m
