-----------------------------------
-- Orphan quest recipes for the account-wide progression cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
--
-- Some quests are structured as NPC-driven handlers rather than the
-- modern Quest:new class. They have valid completion IDs and reward
-- payoffs, but no Quest object registers into xi.QuestRegistry — so the
-- registry walk misses them, AND the standard cascade.quest() factory
-- can't source them (there's no `require(source)` module that returns a
-- reward-bearing table).
--
-- Recipes here hand-write the completion + reward delivery inline. They
-- integrate with the rest of the cascade normally: same kind='quest' /
-- log / qid / apply() shape, so maybe_apply and the live-wrap recipe
-- lookup pick them up like any other recipe.
--
-- Not covered here: `xi.tutorial` (11-stage CharVar state machine, no
-- fixed completion bit — needs presence-proxy detection). Deliberate skip;
-- headless bots miss a small starter-item bundle but no structural gate.
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_orphans')

local cascade = xi.singleplayer.bots.bots_progression_cascade

do
    local sq   = xi.questLog.SANDORIA
    local sqid = xi.quest.id.sandoria
    local jq   = xi.questLog.JEUNO
    local jqid = xi.quest.id.jeuno

    cascade.recipes.orphans = {

        -- ============ Flyers for Regine (Sandy sidequest) ============
        -- Regine dispatches completion inline via npcUtil.completeQuest with
        -- a proper reward table. We reproduce that call. The [ffr]deliveryMask
        -- var isn't cascaded — it's a per-run bit tracker used only by the
        -- delivery mechanics; headless not carrying it just means they can't
        -- re-run the quest as if mid-delivery, which is fine.
        {
            kind = 'quest',
            log  = sq,
            qid  = sqid.FLYERS_FOR_REGINE,
            apply = function(p)
                local ok = npcUtil.completeQuest(p, sq, sqid.FLYERS_FOR_REGINE, {
                    gil   = 440,
                    title = xi.title.ADVERTISING_EXECUTIVE,
                })
                if ok == false then
                    return { status = 'error' }
                end
                return { status = 'applied' }
            end,
        },

        -- ============ Full Speed Ahead! (Jeuno — Batallia raptor mount) ============
        -- Mapitoto uses the raw player:completeQuest() binding (no reward
        -- table) followed by inline giveKeyItem calls. We do the same. The
        -- CHOCOBO_COMPANION rider-choice reward is intentionally NOT delivered
        -- here — that path requires trading a chocobo whistle and giving it
        -- for free undermines the flavor of the choice.
        {
            kind = 'quest',
            log  = jq,
            qid  = jqid.FULL_SPEED_AHEAD,
            apply = function(p)
                p:completeQuest(jq, jqid.FULL_SPEED_AHEAD)
                npcUtil.giveKeyItem(p, xi.ki.TRAINERS_WHISTLE)
                npcUtil.giveKeyItem(p, xi.ki.RAPTOR_COMPANION)
                return { status = 'applied' }
            end,
        },

        -- ============ Hidden crafted-AF chains (CharVar/item-proxy) ============
        -- These 3 chains use CharVars (SCH Loussaire) or HiddenQuest state
        -- (CorArtifact / DncArtifact) — no standard hasCompletedQuest bit.
        -- Recipes use custom hasPrimary/hasTarget predicates that the
        -- enhanced maybe_apply reads (item-presence proxy). Over-grant is:
        -- give all 3 pieces + set completion CharVar so source treats it
        -- as "all crafted" going forward.

        -- SCH crafted AF via Loussaire (Bastok Markets [S]).
        -- Detection: primary owns any of the 3 SCH AF pieces implies they've
        -- engaged with the chain; over-grant all 3 + set AF_SCH_COMPLETE.
        {
            kind = 'quest', log = jq, qid = 0,  -- log/qid unused for custom-check recipes
            hasPrimary = function(p)
                return p:hasItem(xi.item.SCHOLARS_LOAFERS)
                    or p:hasItem(xi.item.SCHOLARS_PANTS)
                    or p:hasItem(xi.item.SCHOLARS_GOWN)
                    or p:getCharVar('AF_SCH_COMPLETE') > 0
            end,
            hasTarget = function(t)
                return t:getCharVar('AF_SCH_COMPLETE') > 0
            end,
            apply = function(p)
                npcUtil.giveItem(p, xi.item.SCHOLARS_LOAFERS)
                npcUtil.giveItem(p, xi.item.SCHOLARS_PANTS)
                npcUtil.giveItem(p, xi.item.SCHOLARS_GOWN)
                p:setCharVar('AF_SCH_COMPLETE', 1)
                p:setCharVar('AF_SCH_BOOTS', 4)
                p:setCharVar('AF_SCH_PANTS', 4)
                p:setCharVar('AF_SCH_BODY',  4)
                return { status = 'applied' }
            end,
        },

        -- Crafted Corsair Artifact (hidden 'CorArtifact').
        -- Detection: primary owns any of the 3 COR AF pieces.
        {
            kind = 'quest', log = jq, qid = 0,
            hasPrimary = function(p)
                return p:hasItem(xi.item.CORSAIRS_GANTS)
                    or p:hasItem(xi.item.CORSAIRS_BOTTES)
                    or p:hasItem(xi.item.CORSAIRS_FRAC)
            end,
            hasTarget = function(t)
                return t:hasItem(xi.item.CORSAIRS_GANTS)
                   and t:hasItem(xi.item.CORSAIRS_BOTTES)
                   and t:hasItem(xi.item.CORSAIRS_FRAC)
            end,
            apply = function(p)
                npcUtil.giveItem(p, xi.item.CORSAIRS_GANTS)
                npcUtil.giveItem(p, xi.item.CORSAIRS_BOTTES)
                npcUtil.giveItem(p, xi.item.CORSAIRS_FRAC)
                return { status = 'applied' }
            end,
        },

        -- Crafted Dancer Artifact (hidden 'DncArtifact', gender-adjusted).
        -- Detection: primary owns any of the 3 DNC AF pieces (either gender).
        -- Delivery: gender-adjusted for the TARGET, not primary.
        {
            kind = 'quest', log = jq, qid = 0,
            hasPrimary = function(p)
                return p:hasItem(xi.item.DANCERS_TIARA_M)   or p:hasItem(xi.item.DANCERS_TIARA_F)
                    or p:hasItem(xi.item.DANCERS_BANGLES_M) or p:hasItem(xi.item.DANCERS_BANGLES_F)
                    or p:hasItem(xi.item.DANCERS_TOE_SHOES_M) or p:hasItem(xi.item.DANCERS_TOE_SHOES_F)
            end,
            hasTarget = function(t)
                local male = t:getGender() == 0
                return t:hasItem(male and xi.item.DANCERS_TIARA_M or xi.item.DANCERS_TIARA_F)
                   and t:hasItem(male and xi.item.DANCERS_BANGLES_M or xi.item.DANCERS_BANGLES_F)
                   and t:hasItem(male and xi.item.DANCERS_TOE_SHOES_M or xi.item.DANCERS_TOE_SHOES_F)
            end,
            apply = function(p)
                local male = p:getGender() == 0
                npcUtil.giveItem(p, male and xi.item.DANCERS_TIARA_M     or xi.item.DANCERS_TIARA_F)
                npcUtil.giveItem(p, male and xi.item.DANCERS_BANGLES_M   or xi.item.DANCERS_BANGLES_F)
                npcUtil.giveItem(p, male and xi.item.DANCERS_TOE_SHOES_M or xi.item.DANCERS_TOE_SHOES_F)
                return { status = 'applied' }
            end,
        },
    }
end

return m
