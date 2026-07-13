-----------------------------------
-- Outlands quest recipes for the account-wide progression cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
--
-- Outlands quests live in the OUTLANDS quest log — SAM unlock (Forge Your
-- Destiny), Norg-based weaponskill unlocks (Cloak and Dagger etc.), Divine
-- Might, Missing Piece, and 3 elemental Trial-by-X avatar quests
-- (Fire/Wind/Water) whose reward NPCs live in Kazham/Rabao/Norg.
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_outlands')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local quest   = cascade.quest

do
    local oq = xi.questLog.OUTLANDS
    local q  = xi.quest.id.outlands

    cascade.recipes.outlands = {

        -- ============ SAM job unlock (inline in complete handler) ============
        quest(oq, q.FORGE_YOUR_DESTINY,     'scripts/quests/outlands/Forge_Your_Destiny',
            function(p) p:unlockJob(xi.job.SAM) end),

        -- ============ Weaponskill unlocks (Annals of Truth series) ============
        -- All 3 have .reward.fame only; WS unlock is inline.
        quest(oq, q.CLOAK_AND_DAGGER,       'scripts/quests/outlands/Cloak_and_Dagger',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.EVISCERATION) end),
        quest(oq, q.BUGI_SODEN,             'scripts/quests/outlands/Bugi_Soden',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.BLADE_KU) end),
        quest(oq, q.THE_POTENTIAL_WITHIN,   'scripts/quests/outlands/The_Potential_Within',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.TACHI_KASHA) end),

        -- ============ Title-only reward outside .reward ============
        quest(oq, q.THE_MISSING_PIECE,      'scripts/quests/outlands/The_Missing_Piece',
            function(p) p:addTitle(xi.title.ACQUIRER_OF_ANCIENT_ARCANUM) end),

        -- ============ Divine Might — 5-earring player pick ============
        -- .reward has only title; player picks 1 of 5 earrings inline.
        -- Singleplayer over-grant: give all 5.
        quest(oq, q.DIVINE_MIGHT,           'scripts/quests/outlands/Divine_Might',
            function(p)
                npcUtil.giveItem(p, xi.item.SUPPANOMIMI)
                npcUtil.giveItem(p, xi.item.KNIGHTS_EARRING)
                npcUtil.giveItem(p, xi.item.ABYSSAL_EARRING)
                npcUtil.giveItem(p, xi.item.BEASTLY_EARRING)
                npcUtil.giveItem(p, xi.item.BUSHINOMIMI)
            end),
        -- Divine Might Repeat uses the same 5-earring pool.
        quest(oq, q.DIVINE_MIGHT_REPEAT,    'scripts/quests/outlands/Divine_Might_Repeat',
            function(p)
                npcUtil.giveItem(p, xi.item.SUPPANOMIMI)
                npcUtil.giveItem(p, xi.item.KNIGHTS_EARRING)
                npcUtil.giveItem(p, xi.item.ABYSSAL_EARRING)
                npcUtil.giveItem(p, xi.item.BEASTLY_EARRING)
                npcUtil.giveItem(p, xi.item.BUSHINOMIMI)
            end),

        -- ============ Elemental avatar trials (NPC-driven, no Quest:new) ============
        -- These have no source file for require(); reward dispatch lives on
        -- the NPC's onEventFinish handler. Recipes hand-implement the
        -- completion + full 6-option over-grant (4 items + 10k gil + spell
        -- + fame + title).

        -- Trial by Fire → Ifrit; reward NPC Ronta-Onta in Kazham.
        {
            kind = 'quest', log = oq, qid = q.TRIAL_BY_FIRE,
            apply = function(p)
                npcUtil.completeQuest(p, oq, q.TRIAL_BY_FIRE, {})
                p:addFame(xi.fameArea.WINDURST, 30)
                p:addTitle(xi.title.HEIR_OF_THE_GREAT_FIRE)
                npcUtil.giveItem(p, xi.item.IFRITS_BLADE)
                npcUtil.giveItem(p, xi.item.FIRE_BELT)
                npcUtil.giveItem(p, xi.item.FIRE_RING)
                npcUtil.giveItem(p, xi.item.EGILS_TORCH)
                p:addGil(10000)
                p:addSpell(xi.magic.spell.IFRIT)
                return { status = 'applied' }
            end,
        },

        -- Trial by Wind → Garuda; reward NPC Agado-Pugado in Rabao.
        {
            kind = 'quest', log = oq, qid = q.TRIAL_BY_WIND,
            apply = function(p)
                npcUtil.completeQuest(p, oq, q.TRIAL_BY_WIND, {})
                p:addFame(xi.fameArea.SELBINA_RABAO, 30)
                p:addTitle(xi.title.HEIR_OF_THE_GREAT_WIND)
                npcUtil.giveItem(p, xi.item.GARUDAS_DAGGER)
                npcUtil.giveItem(p, xi.item.WIND_BELT)
                npcUtil.giveItem(p, xi.item.WIND_RING)
                npcUtil.giveItem(p, xi.item.BOTTLE_OF_BUBBLY_WATER)
                p:addGil(10000)
                p:addSpell(xi.magic.spell.GARUDA)
                return { status = 'applied' }
            end,
        },

        -- Trial by Water → Leviathan; reward NPC Edal-Tahdal in Norg.
        {
            kind = 'quest', log = oq, qid = q.TRIAL_BY_WATER,
            apply = function(p)
                npcUtil.completeQuest(p, oq, q.TRIAL_BY_WATER, {})
                p:addFame(xi.fameArea.NORG, 30)
                p:addTitle(xi.title.HEIR_OF_THE_GREAT_WATER)
                npcUtil.giveItem(p, xi.item.LEVIATHANS_ROD)
                npcUtil.giveItem(p, xi.item.WATER_BELT)
                npcUtil.giveItem(p, xi.item.WATER_RING)
                npcUtil.giveItem(p, xi.item.EYE_OF_NEPT)
                p:addGil(10000)
                p:addSpell(xi.magic.spell.LEVIATHAN)
                return { status = 'applied' }
            end,
        },
    }
end

return m
