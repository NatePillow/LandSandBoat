-----------------------------------
-- SINGLEPLAYER override of scripts/actions/spells/trust/prishe.lua's
-- spellObject.onMobSpawn. Gambits are priority-ordered; this body fully
-- owns Prishe's spawn behavior.
--
-- REBASE AUDIT: diff this against upstream's onMobSpawn body to spot new
-- gambits/mods worth porting:
--   diff <(awk '/spellObject\.onMobSpawn/,/^end$/' scripts/actions/spells/trust/prishe.lua) \
--        <(awk '/registerSpawn.*function/,/^end\)/' modules/singleplayer/lua/trust_overrides/prishe.lua)
-- Last reconciled: 2026-06-16 (upstream baeabac590)
-----------------------------------

local m = Module:new('trust_override_prishe')

xi.singleplayer.trust.registerSpawn('PRISHE', function(mob)
    xi.trust.teamworkMessage(mob, {
        [xi.magic.spell.ULMIA] = xi.trust.messageOffset.TEAMWORK_1,
        [xi.magic.spell.CHERUKIKI] = xi.trust.messageOffset.TEAMWORK_2,
        [xi.magic.spell.KUKKI_CHEBUKKI] = xi.trust.messageOffset.TEAMWORK_3,
        [xi.magic.spell.MAKKI_CHEBUKKI] = xi.trust.messageOffset.TEAMWORK_4,
        [xi.magic.spell.MILDAURION] = xi.trust.messageOffset.TEAMWORK_5,
    })

    mob:addGambit(ai.t.PARTY, { ai.c.HPP_LT, 25 }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.CURE })

    if (mob:getMainLvl() > 69) then
        mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.WARCRY })
    end

    if (mob:getMainLvl() > 29) then
        mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.BERSERK })
    end

    local power = mob:getMainLvl() / 5
    mob:addMod(xi.mod.STR, power)
    mob:addMod(xi.mod.DEX, power)
    mob:addMod(xi.mod.VIT, power)
    mob:addMod(xi.mod.MND, power)
    mob:addMod(xi.mod.ATT, mob:getMainLvl())
    mob:addMod(xi.mod.ACC, mob:getMainLvl())
    mob:addMod(xi.mod.EVA, mob:getMainLvl())
    mob:addMod(xi.mod.STORETP, 25)

    mob:setTrustTPSkillSettings(ai.tp.ASAP, ai.s.RANDOM)
end)

return m
