-----------------------------------
-- crystalWar (WotG) quest recipes for the account-wide progression cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
--
-- Post-ToAU content — KEEP-EXISTING ONLY. Only the Scholar unlock lives
-- here because SCH is a 75-era-relevant job that happens to be added by
-- the WotG expansion. No other crystalWar quests should be extended
-- without expanding the cascade scope (see ../README.md § Scope).
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_crystalwar')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local quest   = cascade.quest

do
    local cq = xi.questLog.CRYSTAL_WAR
    local q  = xi.quest.id.crystalWar

    cascade.recipes.crystalwar = {

        -- SCH job unlock + delayed EMBRAVA/KAUSTRA spell grants.
        -- Spells fire on a post-complete return visit (SCH lvl 5+); the
        -- cascade delivers them here so headless doesn't have to re-visit.
        quest(cq, q.A_LITTLE_KNOWLEDGE, 'scripts/quests/crystalWar/A_Little_Knowledge',
            function(p)
                p:unlockJob(xi.job.SCH)
                p:addSpell(xi.magic.spell.EMBRAVA, { silentLog = true })
                p:addSpell(xi.magic.spell.KAUSTRA, { silentLog = true })
            end),
    }
end

return m
