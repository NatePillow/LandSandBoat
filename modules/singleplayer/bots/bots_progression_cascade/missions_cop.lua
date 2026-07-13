-----------------------------------
-- Chains of Promathia mission recipes for the cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
--
-- CoP is heavily inline-KI-driven — each chapter has structural KIs granted
-- outside the .reward block that gate later chapters. The apply closures
-- here transcribe those grants so a headless-only sync catches up correctly.
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_missions_cop')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local mission = cascade.mission

do
    local cm = xi.mission.log_id.COP
    local mi = xi.mission.id.cop

    cascade.recipes.cop = {

        -- ===== Chapter 1 =====
        mission(cm, mi.THE_RITES_OF_LIFE,         'scripts/missions/cop/1_1_The_Rites_of_Life',
            function(p) npcUtil.giveKeyItem(p, xi.ki.MYSTERIOUS_AMULET) end),
        mission(cm, mi.BELOW_THE_ARKS,            'scripts/missions/cop/1_2_Below_the_Arks',
            function(p)
                -- Mothercrystals gates on having all 3 Lights — grant all so
                -- the chain advances.
                npcUtil.giveKeyItem(p, xi.ki.LIGHT_OF_HOLLA)
                npcUtil.giveKeyItem(p, xi.ki.LIGHT_OF_DEM)
                npcUtil.giveKeyItem(p, xi.ki.LIGHT_OF_MEA)
            end),
        mission(cm, mi.THE_MOTHERCRYSTALS,        'scripts/missions/cop/1_3_The_Mothercrystals'),

        -- ===== Chapter 2 =====
        mission(cm, mi.AN_INVITATION_WEST,        'scripts/missions/cop/2_1_An_Invitation_West'),
        mission(cm, mi.THE_LOST_CITY,             'scripts/missions/cop/2_2_The_Lost_City'),
        mission(cm, mi.DISTANT_BELIEFS,           'scripts/missions/cop/2_3_Distant_Beliefs'),
        -- 2-4 grants MYSTERIOUS_AMULET inline.
        mission(cm, mi.AN_ETERNAL_MELODY,         'scripts/missions/cop/2_4_An_Eternal_Melody',
            function(p) npcUtil.giveKeyItem(p, xi.ki.MYSTERIOUS_AMULET) end),
        mission(cm, mi.ANCIENT_VOWS,              'scripts/missions/cop/2_5_Ancient_Vows'),

        -- ===== Chapter 3 =====
        mission(cm, mi.THE_CALL_OF_THE_WYRMKING,  'scripts/missions/cop/3_1_The_Call_of_the_Wyrmking'),
        mission(cm, mi.A_VESSEL_WITHOUT_A_CAPTAIN,'scripts/missions/cop/3_2_A_Vessel_Without_a_Captain'),
        mission(cm, mi.THE_ROAD_FORKS,            'scripts/missions/cop/3_3_The_Road_Forks'),
        mission(cm, mi.TENDING_AGED_WOUNDS,       'scripts/missions/cop/3_4_Tending_Aged_Wounds'),
        -- 3-5 grants 500*GIL_RATE gil (Prishe's gift) + PSOXJA_PASS inline.
        mission(cm, mi.DARKNESS_NAMED,            'scripts/missions/cop/3_5_Darkness_Named',
            function(p)
                p:addGil(500 * xi.settings.main.GIL_RATE)
                npcUtil.giveKeyItem(p, xi.ki.PSOXJA_PASS)
            end),

        -- ===== Chapter 4 =====
        mission(cm, mi.SHELTERING_DOUBT,          'scripts/missions/cop/4_1_Sheltering_Doubt'),
        mission(cm, mi.THE_SAVAGE,                'scripts/missions/cop/4_2_The_Savage'),
        mission(cm, mi.THE_SECRETS_OF_WORSHIP,    'scripts/missions/cop/4_3_The_Secrets_of_Worship',
            function(p) npcUtil.giveKeyItem(p, xi.ki.RELIQUIARIUM_KEY) end),
        mission(cm, mi.SLANDEROUS_UTTERINGS,      'scripts/missions/cop/4_4_Slanderous_Utterings'),

        -- ===== Chapter 5 =====
        -- 5-1 grants MYSTERIOUS_AMULET_DRAINED + LIGHT_OF_VAHZL inline.
        mission(cm, mi.THE_ENDURING_TUMULT_OF_WAR,'scripts/missions/cop/5_1_The_Enduring_Tumult_of_War',
            function(p)
                npcUtil.giveKeyItem(p, xi.ki.MYSTERIOUS_AMULET_DRAINED)
                npcUtil.giveKeyItem(p, xi.ki.LIGHT_OF_VAHZL)
            end),
        mission(cm, mi.DESIRES_OF_EMPTINESS,      'scripts/missions/cop/5_2_Desires_of_Emptiness'),
        mission(cm, mi.THREE_PATHS,               'scripts/missions/cop/5_3_Three_Paths',
            function(p)
                -- Three branching companion paths — singleplayer: give all three titles.
                p:addTitle(xi.title.COMPANION_OF_LOUVERANCE)
                p:addTitle(xi.title.TENZENS_ALLY)
                p:addTitle(xi.title.ULMIAS_SOULMATE)
            end),

        -- ===== Chapter 6 =====
        mission(cm, mi.FOR_WHOM_THE_VERSE_IS_SUNG,'scripts/missions/cop/6_1_For_Whom_the_Verse_is_Sung'),
        mission(cm, mi.A_PLACE_TO_RETURN,         'scripts/missions/cop/6_2_A_Place_to_Return'),
        mission(cm, mi.MORE_QUESTIONS_THAN_ANSWERS,'scripts/missions/cop/6_3_More_Questions_than_Answers'),
        mission(cm, mi.ONE_TO_BE_FEARED,          'scripts/missions/cop/6_4_One_to_be_Feared'),

        -- ===== Chapter 7 =====
        mission(cm, mi.CHAINS_AND_BONDS,          'scripts/missions/cop/7_1_Chains_and_Bonds',
            function(p) npcUtil.giveItem(p, xi.item.DUCAL_GUARDS_RING) end),
        mission(cm, mi.FLAMES_IN_THE_DARKNESS,    'scripts/missions/cop/7_2_Flames_in_the_Darkness'),
        mission(cm, mi.FIRE_IN_THE_EYES_OF_MEN,   'scripts/missions/cop/7_3_Fire_in_the_Eyes_of_Men'),
        mission(cm, mi.CALM_BEFORE_THE_STORM,     'scripts/missions/cop/7_4_Calm_Before_the_Storm',
            function(p)
                npcUtil.giveKeyItem(p, xi.ki.VESSEL_OF_LIGHT)
                npcUtil.giveKeyItem(p, xi.ki.LETTERS_FROM_ULMIA_AND_PRISHE)
            end),
        mission(cm, mi.THE_WARRIORS_PATH,         'scripts/missions/cop/7_5_The_Warriors_Path',
            function(p) npcUtil.giveKeyItem(p, xi.ki.LIGHT_OF_ALTAIEU) end),

        -- ===== Chapter 8 =====
        mission(cm, mi.GARDEN_OF_ANTIQUITY,       'scripts/missions/cop/8_1_Garden_of_Antiquity'),
        mission(cm, mi.A_FATE_DECIDED,            'scripts/missions/cop/8_2_A_Fate_Decided'),
        mission(cm, mi.WHEN_ANGELS_FALL,          'scripts/missions/cop/8_3_When_Angels_Fall',
            function(p)
                npcUtil.giveKeyItem(p, xi.ki.BRAND_OF_DAWN)
                npcUtil.giveKeyItem(p, xi.ki.BRAND_OF_TWILIGHT)
                npcUtil.giveKeyItem(p, xi.ki.MYSTERIOUS_AMULET_PRISHE)
            end),
        mission(cm, mi.DAWN,                      'scripts/missions/cop/8_4_Dawn',
            function(p)
                -- Singleplayer rule: give all 3 ring options instead of forcing dialog choice.
                p:addItem(xi.item.RAJAS_RING)
                p:addItem(xi.item.SATTVA_RING)
                p:addItem(xi.item.TAMAS_RING)
            end),
    }
end

return m
