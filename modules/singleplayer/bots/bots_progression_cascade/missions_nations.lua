-----------------------------------
-- Nation mission recipes (Bastok, Sandoria, Windurst) for the cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
--
-- All three nations share the same 1-1 → 9-2 mission structure and their
-- 4-1 (Magicite) missions have IDENTICAL inline structural rewards
-- (20000 gil + AIRSHIP_PASS + HAVE_WINGS_WILL_FLY title + 3 Magicite stones).
-- The 2-3-3 and 2-3-4 missions also share KINDRED_REPORT KI grants across
-- all three nations. Consolidating here to keep those patterns visible.
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_missions_nations')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local mission = cascade.mission

-- Shared apply closure for MAGICITE (4-1) — identical structural rewards
-- across all three nations.
local function apply_magicite(p)
    p:addGil(20000)
    npcUtil.giveKeyItem(p, xi.ki.AIRSHIP_PASS)
    p:addTitle(xi.title.HAVE_WINGS_WILL_FLY)
    npcUtil.giveKeyItem(p, xi.ki.MAGICITE_ORASTONE)
    npcUtil.giveKeyItem(p, xi.ki.MAGICITE_OPTISTONE)
    npcUtil.giveKeyItem(p, xi.ki.MAGICITE_AURASTONE)
end

-- Shared apply closure for 2-3-3 / 2-3-4 — grants KINDRED_REPORT KI.
local function apply_kindred_report(p)
    npcUtil.giveKeyItem(p, xi.ki.KINDRED_REPORT)
end

-----------------------------------
-- Bastok missions
-----------------------------------
do
    local bm = xi.mission.log_id.BASTOK
    local mi = xi.mission.id.bastok

    cascade.recipes.bastok_missions = {
        mission(bm, mi.THE_ZERUHN_REPORT,         'scripts/missions/bastok/1_1_The_Zeruhn_Report'),
        mission(bm, mi.GEOLOGICAL_SURVEY,         'scripts/missions/bastok/1_2_A_Geological_Survey'),
        mission(bm, mi.FETICHISM,                 'scripts/missions/bastok/1_3_Fetichism'),

        mission(bm, mi.THE_CRYSTAL_LINE,          'scripts/missions/bastok/2_1_The_Crystal_Line'),
        mission(bm, mi.WADING_BEASTS,             'scripts/missions/bastok/2_2_Wading_Beasts'),
        mission(bm, mi.THE_EMISSARY,              'scripts/missions/bastok/2_3_0_The_Emissary'),
        mission(bm, mi.THE_EMISSARY_SANDORIA,     'scripts/missions/bastok/2_3_1_The_Emissary_Sandoria'),
        mission(bm, mi.THE_EMISSARY_WINDURST,     'scripts/missions/bastok/2_3_2_The_Emissary_Windurst'),
        mission(bm, mi.THE_EMISSARY_SANDORIA2,    'scripts/missions/bastok/2_3_3_The_Emissary_Sandoria2',
            apply_kindred_report),
        mission(bm, mi.THE_EMISSARY_WINDURST2,    'scripts/missions/bastok/2_3_4_The_Emissary_Windurst2',
            apply_kindred_report),

        mission(bm, mi.THE_FOUR_MUSKETEERS,       'scripts/missions/bastok/3_1_The_Four_Musketeers'),
        mission(bm, mi.TO_THE_FORSAKEN_MINES,     'scripts/missions/bastok/3_2_To_the_Forsaken_Mines'),
        mission(bm, mi.JEUNO,                     'scripts/missions/bastok/3_3_Jeuno'),

        mission(bm, mi.MAGICITE,                  'scripts/missions/bastok/4_1_Magicite',
            apply_magicite),

        mission(bm, mi.DARKNESS_RISING,           'scripts/missions/bastok/5_1_Darkness_Rising'),
        mission(bm, mi.XARCABARD_LAND_OF_TRUTHS,  'scripts/missions/bastok/5_2_Xarcabard_Land_of_Truths'),

        mission(bm, mi.RETURN_OF_THE_TALEKEEPER,  'scripts/missions/bastok/6_1_Return_of_the_Talekeeper'),
        mission(bm, mi.THE_PIRATES_COVE,          'scripts/missions/bastok/6_2_The_Pirates_Cove'),

        mission(bm, mi.THE_FINAL_IMAGE,           'scripts/missions/bastok/7_1_The_Final_Image'),
        mission(bm, mi.ON_MY_WAY,                 'scripts/missions/bastok/7_2_On_My_Way'),

        mission(bm, mi.THE_CHAINS_THAT_BIND_US,   'scripts/missions/bastok/8_1_The_Chains_That_Bind_Us'),
        mission(bm, mi.ENTER_THE_TALEKEEPER,      'scripts/missions/bastok/8_2_Enter_the_Talekeeper'),

        mission(bm, mi.THE_SALT_OF_THE_EARTH,     'scripts/missions/bastok/9_1_The_Salt_of_the_Earth'),
        -- 9-2 grants BASTOKAN_FLAG inline in the same handler as mission:complete.
        mission(bm, mi.WHERE_TWO_PATHS_CONVERGE,  'scripts/missions/bastok/9_2_Where_Two_Paths_Converge',
            function(p) npcUtil.giveItem(p, xi.item.BASTOKAN_FLAG) end),
    }
end

-----------------------------------
-- Sandoria missions
-----------------------------------
do
    local sm = xi.mission.log_id.SANDORIA
    local mi = xi.mission.id.sandoria

    cascade.recipes.sandoria_missions = {
        mission(sm, mi.SMASH_THE_ORCISH_SCOUTS,  'scripts/missions/sandoria/1_1_Smash_the_Orcish_Scouts'),
        mission(sm, mi.BAT_HUNT,                 'scripts/missions/sandoria/1_2_Bat_Hunt'),
        -- 1-3 grants setRank(2) + 1000 gil inline (not in .reward).
        mission(sm, mi.SAVE_THE_CHILDREN,        'scripts/missions/sandoria/1_3_Save_the_Children',
            function(p)
                p:setRank(2)
                p:addGil(1000)
            end),

        mission(sm, mi.THE_RESCUE_DRILL,         'scripts/missions/sandoria/2_1_The_Rescue_Drill'),
        mission(sm, mi.THE_DAVOI_REPORT,         'scripts/missions/sandoria/2_2_The_Davoi_Report'),
        mission(sm, mi.JOURNEY_ABROAD,           'scripts/missions/sandoria/2_3_0_Journey_Abroad'),
        mission(sm, mi.JOURNEY_TO_BASTOK,        'scripts/missions/sandoria/2_3_1_Journey_to_Bastok'),
        mission(sm, mi.JOURNEY_TO_WINDURST,      'scripts/missions/sandoria/2_3_2_Journey_to_Windurst'),
        mission(sm, mi.JOURNEY_TO_BASTOK2,       'scripts/missions/sandoria/2_3_3_Journey_to_Bastok2',
            apply_kindred_report),
        mission(sm, mi.JOURNEY_TO_WINDURST2,     'scripts/missions/sandoria/2_3_4_Journey_to_Windurst2',
            apply_kindred_report),

        mission(sm, mi.INFILTRATE_DAVOI,         'scripts/missions/sandoria/3_1_Infiltrate_Davoi'),
        mission(sm, mi.THE_CRYSTAL_SPRING,       'scripts/missions/sandoria/3_2_The_Crystal_Spring'),
        mission(sm, mi.APPOINTMENT_TO_JEUNO,     'scripts/missions/sandoria/3_3_Appointment_to_Jeuno'),

        mission(sm, mi.MAGICITE,                 'scripts/missions/sandoria/4_1_Magicite',
            apply_magicite),

        mission(sm, mi.THE_RUINS_OF_FEI_YIN,     'scripts/missions/sandoria/5_1_The_Ruins_of_FeiYin'),
        mission(sm, mi.THE_SHADOW_LORD,          'scripts/missions/sandoria/5_2_The_Shadow_Lord'),

        mission(sm, mi.LEAUTES_LAST_WISHES,      'scripts/missions/sandoria/6_1_Leautes_Last_Wishes'),
        mission(sm, mi.RANPERRES_FINAL_REST,     'scripts/missions/sandoria/6_2_Ranperres_Final_Rest'),

        mission(sm, mi.PRESTIGE_OF_THE_PAPSQUE,  'scripts/missions/sandoria/7_1_Prestige_of_the_Papsque'),
        mission(sm, mi.THE_SECRET_WEAPON,        'scripts/missions/sandoria/7_2_The_Secret_Weapon'),

        mission(sm, mi.COMING_OF_AGE,            'scripts/missions/sandoria/8_1_Coming_of_Age'),
        mission(sm, mi.LIGHTBRINGER,             'scripts/missions/sandoria/8_2_Lightbringer'),

        mission(sm, mi.BREAKING_BARRIERS,        'scripts/missions/sandoria/9_1_Breaking_Barriers'),
        -- 9-2 grants SAN_DORIAN_FLAG inline.
        mission(sm, mi.THE_HEIR_TO_THE_LIGHT,    'scripts/missions/sandoria/9_2_The_Heir_to_the_Light',
            function(p) npcUtil.giveItem(p, xi.item.SAN_DORIAN_FLAG) end),
    }
end

-----------------------------------
-- Windurst missions
-----------------------------------
do
    local wm = xi.mission.log_id.WINDURST
    local mi = xi.mission.id.windurst

    cascade.recipes.windurst_missions = {
        mission(wm, mi.THE_HORUTOTO_RUINS_EXPERIMENT,'scripts/missions/windurst/1_1_The_Horutoto_Ruins_Experiment'),
        mission(wm, mi.THE_HEART_OF_THE_MATTER,      'scripts/missions/windurst/1_2_The_Heart_of_the_Matter'),
        mission(wm, mi.THE_PRICE_OF_PEACE,           'scripts/missions/windurst/1_3_The_Price_of_Peace'),

        mission(wm, mi.LOST_FOR_WORDS,               'scripts/missions/windurst/2_1_Lost_for_Words'),
        mission(wm, mi.A_TESTING_TIME,               'scripts/missions/windurst/2_2_A_Testing_Time'),
        mission(wm, mi.THE_THREE_KINGDOMS,           'scripts/missions/windurst/2_3_0_The_Three_Kingdoms'),
        mission(wm, mi.THE_THREE_KINGDOMS_SANDORIA,  'scripts/missions/windurst/2_3_1_The_Three_Kingdoms_Sandoria'),
        mission(wm, mi.THE_THREE_KINGDOMS_BASTOK,    'scripts/missions/windurst/2_3_2_The_Three_Kingdoms_Bastok'),
        mission(wm, mi.THE_THREE_KINGDOMS_SANDORIA2, 'scripts/missions/windurst/2_3_3_The_Three_Kingdoms_Sandoria2',
            apply_kindred_report),
        mission(wm, mi.THE_THREE_KINGDOMS_BASTOK2,   'scripts/missions/windurst/2_3_4_The_Three_Kingdoms_Bastok2',
            apply_kindred_report),

        mission(wm, mi.TO_EACH_HIS_OWN_RIGHT,        'scripts/missions/windurst/3_1_To_Each_His_Own_Right'),
        mission(wm, mi.WRITTEN_IN_THE_STARS,         'scripts/missions/windurst/3_2_Written_in_the_Stars'),
        mission(wm, mi.A_NEW_JOURNEY,                'scripts/missions/windurst/3_3_A_New_Journey'),

        mission(wm, mi.MAGICITE,                     'scripts/missions/windurst/4_1_Magicite',
            apply_magicite),

        mission(wm, mi.THE_FINAL_SEAL,               'scripts/missions/windurst/5_1_The_Final_Seal'),
        mission(wm, mi.THE_SHADOW_AWAITS,            'scripts/missions/windurst/5_2_The_Shadow_Awaits'),

        mission(wm, mi.FULL_MOON_FOUNTAIN,           'scripts/missions/windurst/6_1_Full_Moon_Fountain'),
        mission(wm, mi.SAINTLY_INVITATION,           'scripts/missions/windurst/6_2_Saintly_Invitation'),

        mission(wm, mi.THE_SIXTH_MINISTRY,           'scripts/missions/windurst/7_1_The_Sixth_Ministry'),
        mission(wm, mi.AWAKENING_OF_THE_GODS,        'scripts/missions/windurst/7_2_Awakening_of_the_Gods'),

        mission(wm, mi.VAIN,                         'scripts/missions/windurst/8_1_Vain'),
        mission(wm, mi.THE_JESTER_WHOD_BE_KING,      'scripts/missions/windurst/8_2_The_Jester_Whod_be_King'),

        mission(wm, mi.DOLL_OF_THE_DEAD,             'scripts/missions/windurst/9_1_Doll_of_the_Dead'),
        -- Windurst 9-2 delivers WINDURSTIAN_FLAG via .reward.item (registry walk).
        mission(wm, mi.MOON_READING,                 'scripts/missions/windurst/9_2_Moon_Reading'),
    }
end

return m
