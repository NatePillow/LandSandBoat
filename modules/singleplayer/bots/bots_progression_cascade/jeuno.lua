-----------------------------------
-- Jeuno quest recipes for the account-wide progression cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
--
-- Jeuno holds the LB ladder, Borghertz hands, Unlocking-A-Myth, Gobbiebag,
-- DNC AF chain, advanced job unlocks (BRD/BST/DNC), and Aht Urhgan gateway
-- quests. Many use jeuno/helpers.lua under the hood.
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_jeuno')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local quest   = cascade.quest

do
    local jq = xi.questLog.JEUNO
    local q  = xi.quest.id.jeuno

    cascade.recipes.jeuno = {

        -- ============ Limit Break ladder (cap 55→99) ============
        -- Each .reward has fame/title only; inline setLevelCap in the terminal
        -- event handler is the actual cap-raise reward. LB05_1 and LB10 also
        -- deliver BCNM-phase rewards (INSTANT_WARP scroll, MAAT_MASHER title).
        quest(jq, q.IN_DEFIANT_CHALLENGE,       'scripts/quests/jeuno/LB01_In_Defiant_Challenge',
            function(p) p:setLevelCap(55) end),
        quest(jq, q.ATOP_THE_HIGHEST_MOUNTAINS, 'scripts/quests/jeuno/LB02_Atop_the_Highest_Mountains',
            function(p) p:setLevelCap(60) end),
        quest(jq, q.WHENCE_BLOWS_THE_WIND,      'scripts/quests/jeuno/LB03_Whence_Blows_the_wind',
            function(p) p:setLevelCap(65) end),
        quest(jq, q.RIDING_ON_THE_CLOUDS,       'scripts/quests/jeuno/LB04_Riding_on_the_clouds',
            function(p) p:setLevelCap(70) end),
        quest(jq, q.SHATTERING_STARS,           'scripts/quests/jeuno/LB05_1_Shattering_Stars',
            function(p)
                p:setLevelCap(75)
                npcUtil.giveItem(p, xi.item.SCROLL_OF_INSTANT_WARP)
                p:addTitle(xi.title.MAAT_MASHER)
            end),
        quest(jq, q.BEYOND_THE_SUN,             'scripts/quests/jeuno/LB05_2_Beyond_the_Sun'),
        quest(jq, q.NEW_WORLDS_AWAIT,           'scripts/quests/jeuno/LB06_New_Worlds_Await',
            function(p) p:setLevelCap(80) end),
        quest(jq, q.EXPANDING_HORIZONS,         'scripts/quests/jeuno/LB07_Expanding_Horizons',
            function(p) p:setLevelCap(85) end),
        quest(jq, q.BEYOND_THE_STARS,           'scripts/quests/jeuno/LB08_Beyond_the_Stars',
            function(p) p:setLevelCap(90) end),
        quest(jq, q.DORMANT_POWERS_DISLODGED,   'scripts/quests/jeuno/LB09_1_Dormant_Powers_Dislodged',
            function(p) p:setLevelCap(95) end),
        quest(jq, q.PRELUDE_TO_PUISSANCE,       'scripts/quests/jeuno/LB09_2_Prelude_to_Puissance'),
        quest(jq, q.BEYOND_INFINITY,            'scripts/quests/jeuno/LB10_Beyond_Infinity',
            function(p)
                p:setLevelCap(99)
                npcUtil.giveItem(p, xi.item.SCROLL_OF_INSTANT_WARP)
            end),

        -- ============ Borghertz hands (AF gloves; .reward.item covers piece) ============
        quest(jq, q.BORGHERTZS_WARRING_HANDS,    'scripts/quests/jeuno/Borghertzs_Warring_Hands'),
        quest(jq, q.BORGHERTZS_STRIKING_HANDS,   'scripts/quests/jeuno/Borghertzs_Striking_Hands'),
        quest(jq, q.BORGHERTZS_HEALING_HANDS,    'scripts/quests/jeuno/Borghertzs_Healing_Hands'),
        quest(jq, q.BORGHERTZS_SORCEROUS_HANDS,  'scripts/quests/jeuno/Borghertzs_Sorcerous_Hands'),
        quest(jq, q.BORGHERTZS_VERMILLION_HANDS, 'scripts/quests/jeuno/Borghertzs_Vermillion_Hands'),
        quest(jq, q.BORGHERTZS_SNEAKY_HANDS,     'scripts/quests/jeuno/Borghertzs_Sneaky_Hands'),
        quest(jq, q.BORGHERTZS_STALWART_HANDS,   'scripts/quests/jeuno/Borghertzs_Stalwart_Hands'),
        quest(jq, q.BORGHERTZS_SHADOWY_HANDS,    'scripts/quests/jeuno/Borghertzs_Shadowy_Hands'),
        quest(jq, q.BORGHERTZS_WILD_HANDS,       'scripts/quests/jeuno/Borghertzs_Wild_Hands'),
        quest(jq, q.BORGHERTZS_HARMONIOUS_HANDS, 'scripts/quests/jeuno/Borghertzs_Harmonious_Hands'),
        quest(jq, q.BORGHERTZS_CHASING_HANDS,    'scripts/quests/jeuno/Borghertzs_Chasing_Hands'),
        quest(jq, q.BORGHERTZS_LOYAL_HANDS,      'scripts/quests/jeuno/Borghertzs_Loyal_Hands'),
        quest(jq, q.BORGHERTZS_LURKING_HANDS,    'scripts/quests/jeuno/Borghertzs_Lurking_Hands'),
        quest(jq, q.BORGHERTZS_DRAGON_HANDS,     'scripts/quests/jeuno/Borghertzs_Dragon_Hands'),
        quest(jq, q.BORGHERTZS_CALLING_HANDS,    'scripts/quests/jeuno/Borghertzs_Calling_Hands'),

        -- ============ Unlocking-A-Myth (per-job WS unlock via helpers.lua) ============
        -- helpers.lua's UnlockingAMyth:new sets NO .reward block; WS unlock is
        -- entirely inline. Transcribed per-job here.
        quest(jq, q.UNLOCKING_A_MYTH_WARRIOR,      'scripts/quests/jeuno/Unlocking_A_Myth_WAR',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.KINGS_JUSTICE) end),
        quest(jq, q.UNLOCKING_A_MYTH_MONK,         'scripts/quests/jeuno/Unlocking_A_Myth_MNK',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.ASCETICS_FURY) end),
        quest(jq, q.UNLOCKING_A_MYTH_WHITE_MAGE,   'scripts/quests/jeuno/Unlocking_A_Myth_WHM',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.MYSTIC_BOON) end),
        quest(jq, q.UNLOCKING_A_MYTH_BLACK_MAGE,   'scripts/quests/jeuno/Unlocking_A_Myth_BLM',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.VIDOHUNIR) end),
        quest(jq, q.UNLOCKING_A_MYTH_RED_MAGE,     'scripts/quests/jeuno/Unlocking_A_Myth_RDM',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.DEATH_BLOSSOM) end),
        quest(jq, q.UNLOCKING_A_MYTH_THIEF,        'scripts/quests/jeuno/Unlocking_A_Myth_THF',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.MANDALIC_STAB) end),
        quest(jq, q.UNLOCKING_A_MYTH_PALADIN,      'scripts/quests/jeuno/Unlocking_A_Myth_PLD',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.ATONEMENT) end),
        quest(jq, q.UNLOCKING_A_MYTH_DARK_KNIGHT,  'scripts/quests/jeuno/Unlocking_A_Myth_DRK',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.INSURGENCY) end),
        quest(jq, q.UNLOCKING_A_MYTH_BEASTMASTER,  'scripts/quests/jeuno/Unlocking_A_Myth_BST',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.PRIMAL_REND) end),
        quest(jq, q.UNLOCKING_A_MYTH_BARD,         'scripts/quests/jeuno/Unlocking_A_Myth_BRD',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.MORDANT_RIME) end),
        quest(jq, q.UNLOCKING_A_MYTH_RANGER,       'scripts/quests/jeuno/Unlocking_A_Myth_RNG',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.TRUEFLIGHT) end),
        quest(jq, q.UNLOCKING_A_MYTH_SAMURAI,      'scripts/quests/jeuno/Unlocking_A_Myth_SAM',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.TACHI_RANA) end),
        quest(jq, q.UNLOCKING_A_MYTH_NINJA,        'scripts/quests/jeuno/Unlocking_A_Myth_NIN',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.BLADE_KAMU) end),
        quest(jq, q.UNLOCKING_A_MYTH_DRAGOON,      'scripts/quests/jeuno/Unlocking_A_Myth_DRG',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.DRAKESBANE) end),
        quest(jq, q.UNLOCKING_A_MYTH_SUMMONER,     'scripts/quests/jeuno/Unlocking_A_Myth_SMN',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.GARLAND_OF_BLISS) end),
        quest(jq, q.UNLOCKING_A_MYTH_BLUE_MAGE,    'scripts/quests/jeuno/Unlocking_A_Myth_BLU',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.EXPIACION) end),
        quest(jq, q.UNLOCKING_A_MYTH_CORSAIR,      'scripts/quests/jeuno/Unlocking_A_Myth_COR',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.LEADEN_SALUTE) end),
        quest(jq, q.UNLOCKING_A_MYTH_PUPPETMASTER, 'scripts/quests/jeuno/Unlocking_A_Myth_PUP',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.STRINGING_PUMMEL) end),
        quest(jq, q.UNLOCKING_A_MYTH_DANCER,       'scripts/quests/jeuno/Unlocking_A_Myth_DNC',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.PYRRHIC_KLEOS) end),
        quest(jq, q.UNLOCKING_A_MYTH_SCHOLAR,      'scripts/quests/jeuno/Unlocking_A_Myth_SCH',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.OMNISCIENCE) end),

        -- ============ Gobbiebag (+5 inventory + +5 mogsatchel per part) ============
        quest(jq, q.THE_GOBBIEBAG_PART_I,    'scripts/quests/jeuno/The_Gobbiebag_Part_I',
            function(p) p:changeContainerSize(xi.inv.INVENTORY, 5); p:changeContainerSize(xi.inv.MOGSATCHEL, 5) end),
        quest(jq, q.THE_GOBBIEBAG_PART_II,   'scripts/quests/jeuno/The_Gobbiebag_Part_II',
            function(p) p:changeContainerSize(xi.inv.INVENTORY, 5); p:changeContainerSize(xi.inv.MOGSATCHEL, 5) end),
        quest(jq, q.THE_GOBBIEBAG_PART_III,  'scripts/quests/jeuno/The_Gobbiebag_Part_III',
            function(p) p:changeContainerSize(xi.inv.INVENTORY, 5); p:changeContainerSize(xi.inv.MOGSATCHEL, 5) end),
        quest(jq, q.THE_GOBBIEBAG_PART_IV,   'scripts/quests/jeuno/The_Gobbiebag_Part_IV',
            function(p) p:changeContainerSize(xi.inv.INVENTORY, 5); p:changeContainerSize(xi.inv.MOGSATCHEL, 5) end),
        quest(jq, q.THE_GOBBIEBAG_PART_V,    'scripts/quests/jeuno/The_Gobbiebag_Part_V',
            function(p) p:changeContainerSize(xi.inv.INVENTORY, 5); p:changeContainerSize(xi.inv.MOGSATCHEL, 5) end),
        quest(jq, q.THE_GOBBIEBAG_PART_VI,   'scripts/quests/jeuno/The_Gobbiebag_Part_VI',
            function(p) p:changeContainerSize(xi.inv.INVENTORY, 5); p:changeContainerSize(xi.inv.MOGSATCHEL, 5) end),
        quest(jq, q.THE_GOBBIEBAG_PART_VII,  'scripts/quests/jeuno/The_Gobbiebag_Part_VII',
            function(p) p:changeContainerSize(xi.inv.INVENTORY, 5); p:changeContainerSize(xi.inv.MOGSATCHEL, 5) end),
        quest(jq, q.THE_GOBBIEBAG_PART_VIII, 'scripts/quests/jeuno/The_Gobbiebag_Part_VIII',
            function(p) p:changeContainerSize(xi.inv.INVENTORY, 5); p:changeContainerSize(xi.inv.MOGSATCHEL, 5) end),
        quest(jq, q.THE_GOBBIEBAG_PART_IX,   'scripts/quests/jeuno/The_Gobbiebag_Part_IX',
            function(p) p:changeContainerSize(xi.inv.INVENTORY, 5); p:changeContainerSize(xi.inv.MOGSATCHEL, 5) end),
        quest(jq, q.THE_GOBBIEBAG_PART_X,    'scripts/quests/jeuno/The_Gobbiebag_Part_X',
            function(p) p:changeContainerSize(xi.inv.INVENTORY, 5); p:changeContainerSize(xi.inv.MOGSATCHEL, 5) end),

        -- ============ Advanced job unlocks ============
        quest(jq, q.PATH_OF_THE_BARD,        'scripts/quests/jeuno/Path_of_the_Bard',
            function(p) p:unlockJob(xi.job.BRD) end),
        quest(jq, q.PATH_OF_THE_BEASTMASTER, 'scripts/quests/jeuno/Path_of_the_Beastmaster',
            function(p) p:unlockJob(xi.job.BST) end),
        -- Lakeside Minuet also grants the Dancer gesture KI (inline, outside .reward).
        quest(jq, q.LAKESIDE_MINUET,         'scripts/quests/jeuno/Lakeside_Minuet',
            function(p)
                p:unlockJob(xi.job.DNC)
                npcUtil.giveKeyItem(p, xi.ki.JOB_GESTURE_DANCER)
            end),

        -- ============ DNC AF chain ============
        -- AF1 covered by .reward.
        quest(jq, q.THE_UNFINISHED_WALTZ,    'scripts/quests/jeuno/DNC_AF1_The_Unfinished_Waltz'),
        -- AF2 grants gender-specific DANCERS_TIGHTS inline.
        quest(jq, q.THE_ROAD_TO_DIVADOM,     'scripts/quests/jeuno/DNC_AF2_The_Road_to_Divadom',
            function(p)
                npcUtil.giveItem(p, xi.item.DANCERS_TIGHTS_F - p:getGender())
            end),
        -- AF3 grants gender-specific DANCERS_CASAQUE inline.
        quest(jq, q.COMEBACK_QUEEN,          'scripts/quests/jeuno/DNC_AF3_Comeback_Queen',
            function(p)
                npcUtil.giveItem(p, xi.item.DANCERS_CASAQUE_F - p:getGender())
            end),

        quest(jq, q.MARTIAL_MASTERY,         'scripts/quests/jeuno/Martial_Mastery'),

        -- ============ Sub-area / path access ============
        quest(jq, q.LURE_OF_THE_WILDCAT,     'scripts/quests/jeuno/Lure_of_the_Wildcat_Jeuno'),
        quest(jq, q.CREST_OF_DAVOI,          'scripts/quests/jeuno/Crest_of_Davoi'),
        quest(jq, q.MYSTERIES_OF_BEADEAUX_I, 'scripts/quests/jeuno/Mysteries_of_Beadeaux_I'),
        quest(jq, q.MYSTERIES_OF_BEADEAUX_II,'scripts/quests/jeuno/Mysteries_of_Beadeaux_II'),

        -- Community Service: LAMP_LIGHTERS card is a player-choice branch KI.
        -- Singleplayer rule: grant it.
        quest(jq, q.COMMUNITY_SERVICE,       'scripts/quests/jeuno/Community_Service',
            function(p) npcUtil.giveKeyItem(p, xi.ki.LAMP_LIGHTERS_MEMBERSHIP_CARD) end),

        -- The Road to Aht Urhgan: BOARDING_PERMIT KI + Wajaom map (varies by
        -- completion path; deliver both to cover all singleplayer paths).
        quest(jq, q.THE_ROAD_TO_AHT_URHGAN,  'scripts/quests/jeuno/The_Road_to_Aht_Urhgan',
            function(p)
                npcUtil.giveKeyItem(p, xi.ki.BOARDING_PERMIT)
                npcUtil.giveKeyItem(p, xi.ki.MAP_OF_WAJAOM_WOODLANDS)
            end),

        -- ============ Other major grants ============
        quest(jq, q.AXE_THE_COMPETITION,     'scripts/quests/jeuno/Axe_the_Competition',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.DECIMATION) end),

        -- Apocalypse Nigh: player picks 1 of 4 earrings. Singleplayer: give all.
        quest(jq, q.APOCALYPSE_NIGH,         'scripts/quests/jeuno/Apocalypse_Nigh',
            function(p)
                npcUtil.giveItem(p, xi.item.STATIC_EARRING)
                npcUtil.giveItem(p, xi.item.MAGNETIC_EARRING)
                npcUtil.giveItem(p, xi.item.HOLLOW_EARRING)
                npcUtil.giveItem(p, xi.item.ETHEREAL_EARRING)
            end),

        -- ============ The Goblin Tailor — race-defined RSE 4-piece set ============
        -- Per-target race variant (not a "choice" — each character gets the
        -- RSE set matching their own race). Table mirrored from the source's
        -- rseTable; uses p:getRace() on TARGET so each headless gets their
        -- own race's 4 pieces. Singleplayer over-grant vs the source's
        -- one-piece-at-a-time delivery: give all 4 slots.
        quest(jq, q.THE_GOBLIN_TAILOR,       'scripts/quests/jeuno/The_Goblin_Tailor',
            function(p)
                local rseTable = {
                    [xi.race.HUME_M  ] = { xi.item.CUSTOM_TUNIC,     xi.item.CUSTOM_M_GLOVES,  xi.item.CUSTOM_SLACKS,    xi.item.CUSTOM_M_BOOTS    },
                    [xi.race.HUME_F  ] = { xi.item.CUSTOM_VEST,      xi.item.CUSTOM_F_GLOVES,  xi.item.CUSTOM_PANTS,     xi.item.CUSTOM_F_BOOTS    },
                    [xi.race.ELVAAN_M] = { xi.item.MAGNA_JERKIN,     xi.item.MAGNA_GAUNTLETS,  xi.item.MAGNA_M_CHAUSSES, xi.item.MAGNA_M_LEDELSENS },
                    [xi.race.ELVAAN_F] = { xi.item.MAGNA_BODICE,     xi.item.MAGNA_GLOVES,     xi.item.MAGNA_F_CHAUSSES, xi.item.MAGNA_F_LEDELSENS },
                    [xi.race.TARU_M  ] = { xi.item.WONDER_KAFTAN,    xi.item.WONDER_MITTS,     xi.item.WONDER_BRACCAE,   xi.item.WONDER_CLOMPS     },
                    [xi.race.TARU_F  ] = { xi.item.WONDER_KAFTAN,    xi.item.WONDER_MITTS,     xi.item.WONDER_BRACCAE,   xi.item.WONDER_CLOMPS     },
                    [xi.race.MITHRA  ] = { xi.item.SAVAGE_SEPARATES, xi.item.SAVAGE_GAUNTLETS, xi.item.SAVAGE_LOINCLOTH, xi.item.SAVAGE_GAITERS    },
                    [xi.race.GALKA   ] = { xi.item.ELDERS_SURCOAT,   xi.item.ELDERS_BRACERS,   xi.item.ELDERS_BRAGUETTE, xi.item.ELDERS_SANDALS    },
                }
                local pieces = rseTable[p:getRace()]
                if pieces then
                    for _, itemId in ipairs(pieces) do
                        npcUtil.giveItem(p, itemId)
                    end
                end
            end),

        -- ============ Empty Memories — 6-option trade-choice reward ============
        -- .reward has fame=5 only; trade-chosen item + first-completion 25
        -- JEUNO fame are inline. Singleplayer over-grant: give all 6.
        quest(jq, q.EMPTY_MEMORIES,          'scripts/quests/jeuno/Empty_Memories',
            function(p)
                npcUtil.giveItem(p, xi.item.BOTTLE_OF_HYSTEROANIMA)
                npcUtil.giveItem(p, xi.item.BOTTLE_OF_PSYCHOANIMA)
                npcUtil.giveItem(p, xi.item.BOTTLE_OF_TERROANIMA)
                npcUtil.giveItem(p, xi.item.HAMAYUMI)
                npcUtil.giveItem(p, xi.item.STONE_GORGET)
                npcUtil.giveItem(p, xi.item.DIA_WAND)
                p:addFame(xi.fameArea.JEUNO, 25)
            end),
    }
end

return m
