-----------------------------------
-- adoulin (SoA) quest recipes for the account-wide progression cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
--
-- Post-ToAU content — KEEP-EXISTING ONLY. The Geomancer unlock and the
-- Coalition action KIs (Climbing, Demolishing, etc.) are covered here
-- because they gate progression a headless would otherwise be locked out
-- of even under a 75-era-scope playthrough. No new SoA recipes should
-- land here without expanding the cascade scope (see ../README.md § Scope).
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_adoulin')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local quest   = cascade.quest

do
    local aq = xi.questLog.ADOULIN
    local q  = xi.quest.id.adoulin

    cascade.recipes.adoulin = {

        -- ============ Coalition action KIs (5 quests, 5 KIs) ============
        quest(aq, q.HIDE_AND_GO_PEAK,         'scripts/quests/adoulin/Hide_and_Go_Peak',
            function(p) p:addKeyItem(xi.ki.CLIMBING) end),
        quest(aq, q.A_STONES_THROW_AWAY,      'scripts/quests/adoulin/A_Stones_Throw_Away',
            function(p) p:addKeyItem(xi.ki.DEMOLISHING) end),
        quest(aq, q.BREAKING_THE_ICE,         'scripts/quests/adoulin/Breaking_the_Ice',
            function(p) p:addKeyItem(xi.ki.FRAGMENTING) end),
        quest(aq, q.LERENES_LAMENT,           'scripts/quests/adoulin/Lerenes_Lament',
            function(p) p:addKeyItem(xi.ki.PULVERIZING) end),
        quest(aq, q.IM_ON_A_BOAT,             'scripts/quests/adoulin/Im_on_a_Boat',
            function(p) p:addKeyItem(xi.ki.WATERCRAFTING) end),

        -- ============ GEO job unlock ============
        quest(aq, q.DANCES_WITH_LUOPANS,      'scripts/quests/adoulin/Dances_with_Luopans',
            function(p) p:unlockJob(xi.job.GEO) end),

        -- RUN job unlock. CHILDREN_OF_THE_RUNE completes inside the Octavien
        -- NPC (scripts/zones/Eastern_Adoulin/npcs/Octavien.lua), so there's no
        -- standalone quest script — nil source, unlock RUN + grant the job
        -- gesture KI in apply (mirrors the RNG unlock in windurst.lua).
        quest(aq, q.CHILDREN_OF_THE_RUNE,     nil,
            function(p)
                p:unlockJob(xi.job.RUN)
                npcUtil.giveKeyItem(p, xi.ki.JOB_GESTURE_RUNE_FENCER)
            end),
    }
end

return m
