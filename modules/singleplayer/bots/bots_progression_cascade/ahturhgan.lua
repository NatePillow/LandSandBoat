-----------------------------------
-- Aht Urhgan (ToAU) quest recipes for the account-wide progression cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
--
-- ToAU is the last-in-scope expansion for this cascade. Post-ToAU content
-- (WotG / SoA / minis / RoV / TVR) is deliberately out of scope for new
-- recipe work — see ../README.md § Scope.
--
-- ToAU quests carry the BLU/COR/PUP job unlocks, Alexander avatar, BLU/COR
-- level breaks, and the imperial-standing currency loop.
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_ahturhgan')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local quest   = cascade.quest

do
    local aq = xi.questLog.AHT_URHGAN
    local q  = xi.quest.id.ahtUrhgan

    cascade.recipes.ahturhgan = {

        -- ============ Job unlocks ============
        -- BLU unlock + Mark of Zahak KI + gesture KI (all inline, outside .reward).
        quest(aq, q.AN_EMPTY_VESSEL,       'scripts/quests/ahtUrhgan/An_Empty_Vessel',
            function(p)
                p:unlockJob(xi.job.BLU)
                p:addKeyItem(xi.ki.MARK_OF_ZAHAK)
                p:addKeyItem(xi.ki.JOB_GESTURE_BLUE_MAGE)
            end),

        -- COR unlock (inline).
        quest(aq, q.LUCK_OF_THE_DRAW,      'scripts/quests/ahtUrhgan/Luck_of_the_Draw',
            function(p) p:unlockJob(xi.job.COR) end),

        -- PUP unlock + Harlequin attachments + Animator (all inline).
        quest(aq, q.NO_STRINGS_ATTACHED,   'scripts/quests/ahtUrhgan/No_Strings_Attached',
            function(p)
                p:unlockJob(xi.job.PUP)
                p:unlockAttachment(xi.item.HARLEQUIN_FRAME)
                p:unlockAttachment(xi.item.HARLEQUIN_HEAD)
                npcUtil.giveItem(p, xi.item.ANIMATOR)
            end),

        -- ============ Limit breaks (cap 75 + Instant Warp scroll) ============
        quest(aq, q.THE_BEAST_WITHIN,               'scripts/quests/ahtUrhgan/BLU_LB_The_Beast_Within',
            function(p)
                p:setLevelCap(75)
                npcUtil.giveItem(p, xi.item.SCROLL_OF_INSTANT_WARP)
            end),
        quest(aq, q.BREAKING_THE_BONDS_OF_FATE,     'scripts/quests/ahtUrhgan/COR_LB_Breaking_the_Bonds_of_Fate',
            function(p)
                p:setLevelCap(75)
                npcUtil.giveItem(p, xi.item.SCROLL_OF_INSTANT_WARP)
            end),

        -- ============ Alexander avatar — over-grant all 5 reward options ============
        -- Player picks 1 of: 3 Colossus items, 10k gil, or Alexander spell.
        -- Both quests share the same 5-option reward pool.
        quest(aq, q.DIVINE_INTERFERENCE,   'scripts/quests/ahtUrhgan/Divine_Interference',
            function(p)
                p:addSpell(xi.magic.spell.ALEXANDER)
                npcUtil.giveItem(p, xi.item.COLOSSUSS_MANTLE)
                npcUtil.giveItem(p, xi.item.COLOSSUSS_EARRING)
                npcUtil.giveItem(p, xi.item.COLOSSUSS_TORQUE)
                p:addGil(10000)
            end),
        quest(aq, q.WAKING_THE_COLOSSUS,   'scripts/quests/ahtUrhgan/Waking_the_Colossus',
            function(p)
                p:addSpell(xi.magic.spell.ALEXANDER)
                npcUtil.giveItem(p, xi.item.COLOSSUSS_MANTLE)
                npcUtil.giveItem(p, xi.item.COLOSSUSS_EARRING)
                npcUtil.giveItem(p, xi.item.COLOSSUSS_TORQUE)
                p:addGil(10000)
            end),

        -- ============ Imperial Standing (currency) quests ============
        -- These live entirely outside .reward — npcUtil.completeQuest has no
        -- .reward.imperialStanding field.
        quest(aq, q.SOOTHING_WATERS,       'scripts/quests/ahtUrhgan/Soothing_Waters',
            function(p) p:addCurrency('imperial_standing', 500) end),
        quest(aq, q.FIST_OF_THE_PEOPLE,    'scripts/quests/ahtUrhgan/Fist_of_the_People',
            function(p) p:addCurrency('imperial_standing', 500) end),
        quest(aq, q.SAGA_OF_THE_SKYSERPENT, 'scripts/quests/ahtUrhgan/Saga_of_the_Skyserpent',
            function(p) p:addCurrency('imperial_standing', 1000) end),
        quest(aq, q.WHEN_THE_BOW_BREAKS,   'scripts/quests/ahtUrhgan/When_the_Bow_Breaks',
            function(p) p:addCurrency('imperial_standing', 500) end),
        quest(aq, q.EMBERS_OF_HIS_PAST,    'scripts/quests/ahtUrhgan/Embers_of_His_Past',
            function(p)
                p:addCurrency('imperial_standing', 500)
                npcUtil.giveItem(p, xi.item.MERCENARY_CAMP_ENTRY_SLIP)
            end),

        -- ============ Puppetmaster Blues — 3 PUP AF piece commissions ============
        -- Player picks 1 of 3 crafted AF pieces per commission cycle;
        -- CharVar bitmask `[AF]pupCrafted` tracks completion of each.
        -- Singleplayer over-grant (tedium reduction): give all 3 pieces +
        -- set the bitmask so the source treats it as "all crafted".
        quest(aq, q.PUPPETMASTER_BLUES,    'scripts/quests/ahtUrhgan/Puppetmaster_Blues',
            function(p)
                npcUtil.giveItem(p, xi.item.PUPPETRY_TOBE)
                npcUtil.giveItem(p, xi.item.PUPPETRY_DASTANAS)
                npcUtil.giveItem(p, xi.item.PUPPETRY_BABOUCHES)
                -- Set the AF-crafted bitmask (bits 1|2|3 = 0b1110 = 14 total)
                p:setCharVar('[AF]pupCrafted', 14)
            end),

        -- ============ Promotion: Lance Corporal — dynamic tier reward ============
        -- Source `getQuestReward` picks either Luminium (2 Imperial Gold Pieces)
        -- or Platinum (3-4 Imperial Mythril Pieces OR 1 Imperial Gold Piece,
        -- randomly). Singleplayer over-grant: deliver the top-tier bundle
        -- (Luminium + max Platinum) directly.
        quest(aq, q.PROMOTION_LANCE_CORPORAL, 'scripts/quests/ahtUrhgan/Promotion_Lance_Corporal',
            function(p)
                npcUtil.giveItem(p, { { xi.item.IMPERIAL_GOLD_PIECE,    2 } })
                npcUtil.giveItem(p, { { xi.item.IMPERIAL_MYTHRIL_PIECE, 4 } })
            end),
    }
end

return m
