-----------------------------------
-- Windurst quest recipes for the account-wide progression cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_windurst')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local quest   = cascade.quest

do
    local wq = xi.questLog.WINDURST
    local q  = xi.quest.id.windurst

    cascade.recipes.windurst = {

        -- ============ Job unlocks ============
        -- SMN job unlock + Carbuncle spell.
        quest(wq, q.I_CAN_HEAR_A_RAINBOW,           'scripts/quests/windurst/SMN_I_Can_Hear_a_Rainbow',
            function(p)
                p:unlockJob(xi.job.SMN)
                p:addSpell(xi.magic.spell.CARBUNCLE)
            end),

        -- RNG job unlock + gesture KI.
        quest(wq, q.THE_FANGED_ONE,                 'scripts/quests/windurst/The_Fanged_One',
            function(p)
                p:unlockJob(xi.job.RNG)
                npcUtil.giveKeyItem(p, xi.ki.JOB_GESTURE_RANGER)
            end),

        -- ============ Job AF ============
        -- THF AF1-3
        quest(wq, q.THE_TENSHODO_SHOWDOWN,          'scripts/quests/windurst/THF_AF1_The_Tenshodo_Showdown'),
        quest(wq, q.AS_THICK_AS_THIEVES,            'scripts/quests/windurst/THF_AF2_As_Thick_as_Thieves'),
        quest(wq, q.HITTING_THE_MARQUISATE,         'scripts/quests/windurst/THF_AF3_Hitting_the_Marquisate'),

        -- SMN AF1
        quest(wq, q.THE_PUPPET_MASTER,              'scripts/quests/windurst/SMN_AF1_The_Puppet_Master'),

        -- ============ Avatar Diabolos ============
        -- Player picks 1 of 6 options: 4 items, 15k gil, or Diabolos spell.
        -- Singleplayer over-grant: deliver all.
        quest(wq, q.WAKING_DREAMS,                  'scripts/quests/windurst/Waking_Dreams',
            function(p)
                p:addSpell(xi.magic.spell.DIABOLOS)
                npcUtil.giveItem(p, xi.item.DIABOLOSS_POLE)
                npcUtil.giveItem(p, xi.item.DIABOLOSS_EARRING)
                npcUtil.giveItem(p, xi.item.DIABOLOSS_RING)
                npcUtil.giveItem(p, xi.item.DIABOLOSS_TORQUE)
                p:addGil(15000)
            end),

        -- ============ Weaponskill unlocks (Annals of Truth series) ============
        quest(wq, q.FROM_SAPLINGS_GROW,             'scripts/quests/windurst/From_Saplings_Grow',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.EMPYREAL_ARROW) end),
        quest(wq, q.BLOOD_AND_GLORY,                'scripts/quests/windurst/Blood_and_Glory',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.RETRIBUTION) end),
        quest(wq, q.ORASTERY_WOES,                  'scripts/quests/windurst/Orastery_Woes',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.BLACK_HALO) end),

        -- ============ Inline gil / fame grants ============
        -- Making Amends: 1500 gil inline.
        quest(wq, q.MAKING_AMENDS,                  'scripts/quests/windurst/Making_Amends',
            function(p) p:addGil(1500) end),

        -- Food for Thought: three inline gil payments across three parallel
        -- trade turn-ins (120 + 440 + 440 = 1000 total).
        quest(wq, q.FOOD_FOR_THOUGHT,               'scripts/quests/windurst/Food_for_Thought',
            function(p) p:addGil(1000) end),

        -- Blue Ribbon Blues: 3600 gil.
        quest(wq, q.BLUE_RIBBON_BLUES,              'scripts/quests/windurst/Blue_Ribbon_Blues',
            function(p) p:addGil(3600) end),

        -- Water Way to Go: 900 gil.
        quest(wq, q.WATER_WAY_TO_GO,                'scripts/quests/windurst/Water_Way_to_Go',
            function(p) p:addGil(900) end),

        -- Mihgo's Amigo: 200 gil.
        quest(wq, q.MIHGOS_AMIGO,                   'scripts/quests/windurst/Mihgos_Amigo',
            function(p) p:addGil(200) end),

        -- Teacher's Pet: 250 gil + 67 WINDURST fame (first-completion only).
        quest(wq, q.TEACHERS_PET,                   'scripts/quests/windurst/Teachers_Pet',
            function(p)
                p:addGil(250)
                p:addFame(xi.fameArea.WINDURST, 67)
            end),

        -- Rock Racketeer: 2100 gil.
        quest(wq, q.ROCK_RACKETEER,                 'scripts/quests/windurst/Rock_Racketeer',
            function(p) p:addGil(2100) end),

        -- SOB6 Wild Card: 8000 gil (one of three completion branches; same
        -- amount either way).
        quest(wq, q.WILD_CARD,                      'scripts/quests/windurst/SOB6_Wild_Card',
            function(p) p:addGil(8000) end),

        -- Say It With Flowers: three branch rewards (cactus first-time gives
        -- IRON_SWORD + 30 fame; flower gives 10 fame + 100 gil; cactus repeat
        -- gives 30 fame + 400 gil). Singleplayer over-grant: give the sword,
        -- max fame, max gil.
        quest(wq, q.SAY_IT_WITH_FLOWERS,            'scripts/quests/windurst/Say_It_With_Flowers',
            function(p)
                npcUtil.giveItem(p, xi.item.IRON_SWORD)
                p:addFame(xi.fameArea.WINDURST, 30)
                p:addGil(400)
            end),

        -- ============ Inline titles ============
        -- Curses Foiled A Golem: TOTAL_LOSER title on completion (intentional
        -- per code comment).
        quest(wq, q.CURSES_FOILED_A_GOLEM,          'scripts/quests/windurst/Curses_Foiled_A_Golem',
            function(p) p:addTitle(xi.title.TOTAL_LOSER) end),

        -- ============ Moonlit Path → Fenrir (NPC-driven, no Quest:new) ============
        -- Reward NPC Leepe-Hoppe in Windurst Waters. 8-option pick:
        -- 4 items + 15k gil + FENRIR spell + FENRIR_WHISTLE KI (mount).
        -- Singleplayer over-grant: give everything.
        {
            kind = 'quest', log = wq, qid = q.THE_MOONLIT_PATH,
            apply = function(p)
                npcUtil.completeQuest(p, wq, q.THE_MOONLIT_PATH, {})
                p:addFame(xi.fameArea.WINDURST, 30)
                p:addTitle(xi.title.HEIR_OF_THE_NEW_MOON)
                npcUtil.giveItem(p, xi.item.FENRIRS_STONE)
                npcUtil.giveItem(p, xi.item.FENRIRS_CAPE)
                npcUtil.giveItem(p, xi.item.FENRIRS_TORQUE)
                npcUtil.giveItem(p, xi.item.FENRIRS_EARRING)
                p:addGil(15000)
                p:addSpell(xi.magic.spell.FENRIR)
                npcUtil.giveKeyItem(p, xi.ki.FENRIR_WHISTLE)
                return { status = 'applied' }
            end,
        },
    }
end

return m
