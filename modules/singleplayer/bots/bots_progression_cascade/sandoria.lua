-----------------------------------
-- Sandoria quest recipes for the account-wide progression cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_sandoria')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local quest   = cascade.quest

do
    local sq = xi.questLog.SANDORIA
    local q  = xi.quest.id.sandoria

    cascade.recipes.sandoria = {

        -- ============ Job unlocks / AF ============
        -- PLD job unlock (inline in complete handler, not in .reward)
        quest(sq, q.A_KNIGHTS_TEST,             'scripts/quests/sandoria/A_Knights_Test',
            function(p) p:unlockJob(xi.job.PLD) end),

        -- DRG job unlock. THE_HOLY_CREST completes inside the Ghelsba Outpost
        -- battlefield (scripts/battlefields/Ghelsba_Outpost/holy_crest.lua), so
        -- there's no standalone quest script to require — inline the title as
        -- the reward and unlock DRG in apply.
        quest(sq, q.THE_HOLY_CREST,             { title = xi.title.HEIR_TO_THE_HOLY_CREST },
            function(p) p:unlockJob(xi.job.DRG) end),

        -- PLD AF1 (AF2/AF3 not yet converted in LSB)
        quest(sq, q.SHARPENING_THE_SWORD,       'scripts/quests/sandoria/Sharpening_the_Sword'),

        -- WHM AF1-2 (AF3 not yet converted)
        quest(sq, q.MESSENGER_FROM_BEYOND,      'scripts/quests/sandoria/Messenger_From_Beyond'),
        quest(sq, q.PRELUDE_OF_BLACK_AND_WHITE, 'scripts/quests/sandoria/Prelude_of_Black_and_White'),

        -- RDM AF1-2 (AF3 not yet converted)
        quest(sq, q.THE_CRIMSON_TRIAL,          'scripts/quests/sandoria/RDM_AF1_The_Crimson_Trial'),
        quest(sq, q.ENVELOPED_IN_DARKNESS,      'scripts/quests/sandoria/RDM_AF2_Enveloped_in_Darkness'),

        -- ============ Weaponskill unlocks (Annals of Truth series) ============
        -- All 3 have .reward.fame only; WS unlock is entirely inline.
        quest(sq, q.OLD_WOUNDS,                 'scripts/quests/sandoria/Old_Wounds',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.SAVAGE_BLADE) end),
        quest(sq, q.SOULS_IN_SHADOW,            'scripts/quests/sandoria/Souls_in_Shadow',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.SPIRAL_HELL) end),
        quest(sq, q.METHODS_CREATE_MADNESS,     'scripts/quests/sandoria/Methods_Create_Madness',
            function(p) p:addLearnedWeaponskill(xi.wsUnlock.IMPULSE_DRIVE) end),

        -- ============ Quests with NO .reward block ============
        -- All reward delivered inline; registry walk wouldn't touch these.
        -- Merchants Bidding: 30 SANDORIA fame + 120 gil per first completion.
        quest(sq, q.THE_MERCHANTS_BIDDING,      'scripts/quests/sandoria/The_Merchants_Bidding',
            function(p)
                p:addFame(xi.fameArea.SANDORIA, 30)
                p:addGil(120)
            end),
        -- Starting a Flame: 100 gil on first complete.
        quest(sq, q.STARTING_A_FLAME,           'scripts/quests/sandoria/Starting_a_Flame',
            function(p) p:addGil(100) end),
        -- A Job for the Consortium: 1000 gil + 30 NORG fame (normal delivery path).
        quest(sq, q.A_JOB_FOR_THE_CONSORTIUM,   'scripts/quests/sandoria/A_Job_for_the_Consortium',
            function(p)
                p:addGil(1000)
                p:addFame(xi.fameArea.NORG, 30)
            end),

        -- ============ Repeatable-pattern quests ============
        -- These deliver item + title outside .reward so the same handler
        -- works for first + repeat plays.
        quest(sq, q.THE_SEAMSTRESS,             'scripts/quests/sandoria/The_Seamstress',
            function(p)
                npcUtil.giveItem(p, xi.item.LEATHER_GLOVES)
                p:addTitle(xi.title.SILENCER_OF_THE_LAMBS)
            end),
        quest(sq, q.LIZARD_SKINS,               'scripts/quests/sandoria/Lizard_Skins',
            function(p)
                npcUtil.giveItem(p, xi.item.LIZARD_GLOVES)
                p:addTitle(xi.title.LIZARD_SKINNER)
            end),

        -- ============ Inline gil grants ============
        -- Rosel: correct-prince path gives 200 gil (over-grant vs 100).
        quest(sq, q.ROSEL_THE_ARMORER,          'scripts/quests/sandoria/Rosel_the_Armorer',
            function(p) p:addGil(200) end),
        -- Warding Vampires: 900 gil inline; .reward has only title.
        quest(sq, q.WARDING_VAMPIRES,           'scripts/quests/sandoria/Warding_Vampires',
            function(p) p:addGil(900) end),
        -- The Sweetest Things: 400 * GIL_RATE inline; .reward has no gil.
        quest(sq, q.THE_SWEETEST_THINGS,        'scripts/quests/sandoria/The_Sweetest_Things',
            function(p) p:addGil(400 * xi.settings.main.GIL_RATE) end),

        -- ============ Inline fame grants ============
        -- Spice Gals: +40 SANDORIA fame on first completion; .reward.fame = 0.
        quest(sq, q.SPICE_GALS,                 'scripts/quests/sandoria/Spice_Gals',
            function(p) p:addFame(xi.fameArea.SANDORIA, 40) end),

        -- ============ Trial by Ice → Shiva (NPC-driven, no Quest:new) ============
        -- Reward NPC Gulmama in Northern SanDoria. Hand-implemented recipe
        -- with full 6-option over-grant (4 items + 10k gil + spell + fame + title).
        {
            kind = 'quest', log = sq, qid = q.TRIAL_BY_ICE,
            apply = function(p)
                npcUtil.completeQuest(p, sq, q.TRIAL_BY_ICE, {})
                p:addFame(xi.fameArea.SANDORIA, 30)
                p:addTitle(xi.title.HEIR_OF_THE_GREAT_ICE)
                npcUtil.giveItem(p, xi.item.SHIVAS_CLAWS)
                npcUtil.giveItem(p, xi.item.ICE_BELT)
                npcUtil.giveItem(p, xi.item.ICE_RING)
                npcUtil.giveItem(p, xi.item.BOTTLE_OF_RUST_B_GONE)
                p:addGil(10000)
                p:addSpell(xi.magic.spell.SHIVA)
                return { status = 'applied' }
            end,
        },
    }
end

return m
