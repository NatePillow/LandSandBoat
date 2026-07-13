-----------------------------------
-- Bastok quest recipes for the account-wide progression cascade.
--
-- See ../README.md for the mechanism, philosophy, and how to add or update
-- recipes. Each recipe delivers the FULL set of grants a quest normally
-- hands out — .reward block via registry walk plus any inline grants
-- transcribed from the source quest here.
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_bastok')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local quest   = cascade.quest

do
    local bq = xi.questLog.BASTOK
    local q  = xi.quest.id.bastok

    cascade.recipes.bastok = {

        -- ============ Sightseeing / civic ============
        quest(bq, q.WELCOME_TO_BASTOK,         'scripts/quests/bastok/Welcome_to_Bastok'),
        quest(bq, q.LURE_OF_THE_WILDCAT,       'scripts/quests/bastok/Lure_of_the_Wildcat_Bastok'),

        -- ============ Job AF quests ============
        -- WAR AF1-3
        quest(bq, q.THE_DOORMAN,               'scripts/quests/bastok/WAR_AF1_The_Doorman'),
        quest(bq, q.THE_TALEKEEPERS_TRUTH,     'scripts/quests/bastok/WAR_AF2_The_Talekeepers_Truth'),
        quest(bq, q.THE_TALEKEEPERS_GIFT,      'scripts/quests/bastok/WAR_AF3_The_Talekeepers_Gift'),

        -- MNK AF1-3
        quest(bq, q.GHOSTS_OF_THE_PAST,        'scripts/quests/bastok/MNK_AF1_Ghosts_of_the_Past'),
        quest(bq, q.THE_FIRST_MEETING,         'scripts/quests/bastok/MNK_AF2_The_First_Meeting'),
        quest(bq, q.TRUE_STRENGTH,             'scripts/quests/bastok/MNK_AF3_True_Strength'),

        -- DRK AF1-3
        quest(bq, q.DARK_LEGACY,               'scripts/quests/bastok/DRK_AF1_Dark_Legacy'),
        quest(bq, q.DARK_PUPPET,               'scripts/quests/bastok/DRK_AF2_Dark_Puppet'),
        quest(bq, q.BLADE_OF_EVIL,             'scripts/quests/bastok/DRK_AF3_Blade_of_Evil'),

        -- ============ Avatar Titan (elemental fight) ============
        -- Both Trial-Size and Trial teach the spell; addSpell is idempotent so
        -- replaying both is safe.
        quest(bq, q.TRIAL_SIZE_TRIAL_BY_EARTH, 'scripts/quests/bastok/Trial_Size_Trial_by_Earth',
            function(p) p:addSpell(xi.magic.spell.TITAN) end),
        -- Trial by Earth has a player-choice reward outside .reward. Singleplayer
        -- rule: over-grant every option. Also grants HEIR_OF_THE_GREAT_EARTH
        -- title in the BCNM-win handler.
        quest(bq, q.TRIAL_BY_EARTH,            'scripts/quests/bastok/Trial_by_Earth',
            function(p)
                p:addSpell(xi.magic.spell.TITAN)
                npcUtil.giveItem(p, xi.item.TITANS_CUDGEL)
                npcUtil.giveItem(p, xi.item.EARTH_BELT)
                npcUtil.giveItem(p, xi.item.EARTH_RING)
                npcUtil.giveItem(p, xi.item.DOSE_OF_DESERT_LIGHT)
                p:addGil(10000)
                p:addTitle(xi.title.HEIR_OF_THE_GREAT_EARTH)
            end),

        -- ============ Job unlocks (inline, outside .reward) ============
        quest(bq, q.BLADE_OF_DARKNESS,         'scripts/quests/bastok/Blade_of_Darkness',
            function(p) p:unlockJob(xi.job.DRK) end),
        quest(bq, q.AYAME_AND_KAEDE,           'scripts/quests/bastok/Ayame_and_Kaede',
            function(p) p:unlockJob(xi.job.NIN) end),

        -- ============ Trust Bastok — 4 trust spells + title ============
        quest(bq, q.TRUST_BASTOK,              'scripts/quests/bastok/Trust_Bastok',
            function(p)
                p:addSpell(xi.magic.spell.AYAME,       { silentLog = true })
                p:addSpell(xi.magic.spell.IRON_EATER,  { silentLog = true })
                p:addSpell(xi.magic.spell.NAJI,        { silentLog = true })
                p:addSpell(xi.magic.spell.VOLKER,      { silentLog = true })
                p:addTitle(xi.title.THE_TRUSTWORTHY)
            end),

        -- ============ PUP limit-break (cap 75 + Instant Warp) ============
        quest(bq, q.ACHIEVING_TRUE_POWER,      'scripts/quests/bastok/PUP_LB_Achieving_True_Power',
            function(p)
                p:setLevelCap(75)
                npcUtil.giveItem(p, xi.item.SCROLL_OF_INSTANT_WARP)
            end),

        -- ============ Weaponskill unlocks (Annals of Truth series) ============
        -- All 4 have .reward.fame only; the WS unlock is entirely inline.
        quest(bq, q.INHERITANCE,                        'scripts/quests/bastok/Inheritance',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.GROUND_STRIKE) end),
        quest(bq, q.SHOOT_FIRST_ASK_QUESTIONS_LATER,    'scripts/quests/bastok/Shoot_First_Ask_Questions_Later',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.DETONATOR) end),
        quest(bq, q.THE_WEIGHT_OF_YOUR_LIMITS,          'scripts/quests/bastok/The_Weight_of_Your_Limits',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.STEEL_CYCLONE) end),
        quest(bq, q.THE_WALLS_OF_YOUR_MIND,             'scripts/quests/bastok/The_Walls_of_Your_Mind',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.ASURAN_FISTS) end),

        -- ============ Legacy fame boost quests ============
        -- These older sidequests have small .reward.fame (5-8) plus a large
        -- first-completion inline addFame in the terminal event handler.
        -- Transcribed amounts are the INLINE portion — registry walk delivers
        -- .reward.fame separately.
        quest(bq, q.FALLEN_COMRADES,           'scripts/quests/bastok/Fallen_Comrades',
            function(p) p:addFame(xi.fameArea.BASTOK, 112) end),
        quest(bq, q.VENGEFUL_WRATH,            'scripts/quests/bastok/Vengeful_Wrath',
            function(p) p:addFame(xi.fameArea.BASTOK, 112) end),
        quest(bq, q.BITE_THE_DUST,             'scripts/quests/bastok/Bite_the_Dust',
            function(p) p:addFame(xi.fameArea.BASTOK, 112) end),
        quest(bq, q.BUCKETS_OF_GOLD,           'scripts/quests/bastok/Buckets_of_Gold',
            function(p) p:addFame(xi.fameArea.BASTOK, 67) end),
        quest(bq, q.MINESWEEPER,               'scripts/quests/bastok/Minesweeper',
            function(p) p:addFame(xi.fameArea.BASTOK, 67) end),
        quest(bq, q.SMOKE_ON_THE_MOUNTAIN,     'scripts/quests/bastok/Smoke_on_the_Mountain',
            function(p) p:addFame(xi.fameArea.BASTOK, 25) end),
        quest(bq, q.THE_DARKSMITH,             'scripts/quests/bastok/The_Darksmith',
            function(p) p:addFame(xi.fameArea.BASTOK, 25) end),

        -- ============ Gil grants (inline, outside .reward.gil) ============
        -- Return to the Depths: 2000 gil mid-quest KI turn-in + 10000 gil in BCNM-win handler.
        quest(bq, q.RETURN_TO_THE_DEPTHS,      'scripts/quests/bastok/Return_to_the_Depths',
            function(p)
                p:addGil(2000)
                p:addGil(10000)
            end),
        -- Gourmet: variable gil (200/350/100) + fame (30/90/0) per trade item.
        -- Singleplayer rule: pick the maximum branch (rare fish path).
        quest(bq, q.GOURMET,                   'scripts/quests/bastok/Gourmet',
            function(p)
                p:addGil(350)
                p:addFame(xi.fameArea.BASTOK, 90)
            end),
        -- Out of the Depths: 4 mid-quest KI turn-ins for cumulative 1000 gil.
        quest(bq, q.OUT_OF_THE_DEPTHS,         'scripts/quests/bastok/Out_of_the_Depths',
            function(p) p:addGil(1000) end),
        -- Mom the Adventurer: variable gil (100/200) via helper — max branch.
        quest(bq, q.MOM_THE_ADVENTURER,        'scripts/quests/bastok/Mom_the_Adventurer',
            function(p) p:addGil(200) end),

        -- ============ Item grants (inline, outside .reward.item) ============
        -- Beadeaux Smog: CHAKRAM is the actual item reward, .reward has nothing.
        quest(bq, q.BEADEAUX_SMOG,             'scripts/quests/bastok/Beadeaux_Smog',
            function(p) npcUtil.giveItem(p, xi.item.CHAKRAM) end),

        -- A Foreman's Best Friend: Map of Gusgen Mines on first completion.
        quest(bq, q.A_FOREMANS_BEST_FRIEND,    'scripts/quests/bastok/A_Foremans_Best_Friend',
            function(p) npcUtil.giveKeyItem(p, xi.ki.MAP_OF_THE_GUSGEN_MINES) end),

        -- Brygid the Stylist Returns: 13-option gear picker. Singleplayer over-grant:
        -- deliver a canonical piece (Duende Cotehardie — option 1).
        quest(bq, q.BRYGID_THE_STYLIST_RETURNS, 'scripts/quests/bastok/Brygid_the_Stylist_Returns',
            function(p) npcUtil.giveItem(p, xi.item.DUENDE_COTEHARDIE) end),
    }
end

return m
