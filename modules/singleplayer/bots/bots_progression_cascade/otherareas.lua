-----------------------------------
-- otherAreas quest recipes for the account-wide progression cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
--
-- "otherAreas" is LSB's catch-all for cross-nation sidequests that aren't
-- tied to a specific starting nation: MogSafe expansions, Divine-Might-adjacent
-- content, ANNM titles.
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_otherareas')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local quest   = cascade.quest

do
    local oq = xi.questLog.OTHER_AREAS
    local q  = xi.quest.id.otherAreas

    cascade.recipes.otherareas = {

        -- ============ MogSafe expansions (+10 each per quest) ============
        -- These three sidequests each grant +10 MOGSAFE and +10 MOGSAFE2 inline.
        quest(oq, q.GIVE_A_MOOGLE_A_BREAK,   'scripts/quests/otherAreas/Give_a_Moogle_a_Break',
            function(p)
                p:changeContainerSize(xi.inv.MOGSAFE,  10)
                p:changeContainerSize(xi.inv.MOGSAFE2, 10)
            end),
        quest(oq, q.THE_MOOGLE_PICNIC,      'scripts/quests/otherAreas/The_Moogles_Picnic',
            function(p)
                p:changeContainerSize(xi.inv.MOGSAFE,  10)
                p:changeContainerSize(xi.inv.MOGSAFE2, 10)
            end),
        quest(oq, q.MOOGLES_IN_THE_WILD,     'scripts/quests/otherAreas/Moogles_in_the_Wild',
            function(p)
                p:changeContainerSize(xi.inv.MOGSAFE,  10)
                p:changeContainerSize(xi.inv.MOGSAFE2, 10)
            end),

        -- ============ Way of the Cook — on-time branch (1500 gil max) ============
        quest(oq, q.WAY_OF_THE_COOK,         'scripts/quests/otherAreas/RQ2_Way_of_the_Cook',
            function(p) p:addGil(1500) end),

        -- ============ An Explorer's Footsteps — fixed part of dynamic reward ============
        -- .reward is empty. Gil amount is variable (800-10000) by final trade zone;
        -- the Crawlers' Nest map KI is the deterministic drop.
        quest(oq, q.AN_EXPLORERS_FOOTSTEPS,  'scripts/quests/otherAreas/An_Explorers_Footsteps',
            function(p) npcUtil.giveKeyItem(p, xi.ki.MAP_OF_THE_CRAWLERS_NEST) end),

        -- ============ Waking the Beast — both titles (over-grant) ============
        -- Player picks Option (DISTURBER_OF_SLUMBER vs INTERRUPTER_OF_DREAMS).
        -- Singleplayer over-grant: give both.
        quest(oq, q.WAKING_THE_BEAST,        'scripts/quests/otherAreas/Waking_the_Beast',
            function(p)
                p:addTitle(xi.title.DISTURBER_OF_SLUMBER)
                p:addTitle(xi.title.INTERRUPTER_OF_DREAMS)
            end),

        -- ============ Its Raining Mannequins — race-defined mannequin ============
        -- Per-target race variant (not a "choice" — each character gets the
        -- mannequin matching their own race). Uses p:getRace() on the TARGET,
        -- so a Galka headless gets Galka mannequin regardless of primary's race.
        -- Race enum: HUME_M=1, HUME_F=2, ELVAAN_M=3, ELVAAN_F=4, TARU_M=5,
        -- TARU_F=6, MITHRA=7, GALKA=8. Mannequin base = HUME_M_MANNEQUIN.
        quest(oq, q.ITS_RAINING_MANNEQUINS,  'scripts/quests/otherAreas/Its_Raining_Mannequins',
            function(p) npcUtil.giveItem(p, xi.item.HUME_M_MANNEQUIN + p:getRace() - 1) end),

        -- ============ Trial by Lightning → Ramuh (NPC-driven, no Quest:new) ============
        -- Reward NPC Ripapa in Mhaura. Full 6-option over-grant.
        {
            kind = 'quest', log = oq, qid = q.TRIAL_BY_LIGHTNING,
            apply = function(p)
                npcUtil.completeQuest(p, oq, q.TRIAL_BY_LIGHTNING, {})
                p:addFame(xi.fameArea.WINDURST, 30)
                p:addTitle(xi.title.HEIR_OF_THE_GREAT_LIGHTNING)
                npcUtil.giveItem(p, xi.item.RAMUHS_STAFF)
                npcUtil.giveItem(p, xi.item.LIGHTNING_BELT)
                npcUtil.giveItem(p, xi.item.LIGHTNING_RING)
                npcUtil.giveItem(p, xi.item.ELDER_BRANCH)
                p:addGil(10000)
                p:addSpell(xi.magic.spell.RAMUH)
                return { status = 'applied' }
            end,
        },
    }
end

return m
