-----------------------------------
-- SINGLEPLAYER override of scripts/actions/spells/trust/iroha.lua's
-- spellObject.onMobSpawn. Gambits are priority-ordered; this body fully
-- owns Iroha's spawn behavior.
--
-- REBASE AUDIT: diff this against upstream's onMobSpawn body to spot new
-- gambits/mods worth porting:
--   diff <(awk '/spellObject\.onMobSpawn/,/^end$/' scripts/actions/spells/trust/iroha.lua) \
--        <(awk '/registerSpawn.*function/,/^end\)/' modules/singleplayer/lua/trust_overrides/iroha.lua)
-- Last reconciled: 2026-06-16 (upstream baeabac590)
-----------------------------------

local m = Module:new('trust_override_iroha')

xi.singleplayer.trust.registerSpawn('IROHA', function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.SPAWN)

    mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.HASSO }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.HASSO })

    mob:addGambit(ai.t.SELF, { ai.c.HAS_TOP_ENMITY, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.THIRD_EYE })

    mob:addGambit(ai.t.SELF, { ai.c.TP_LT, 1000 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.MEDITATE })

    if (mob:getMainLvl() > 69) then
        mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.WARCRY })
    end

    if (mob:getMainLvl() > 29) then
        mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.BERSERK })
    end

    local power = mob:getMainLvl() / 5
    mob:addMod(xi.mod.STR, power)
    mob:addMod(xi.mod.DEX, power)
    mob:addMod(xi.mod.ATT, mob:getMainLvl())
    mob:addMod(xi.mod.ACC, mob:getMainLvl())
    mob:addMod(xi.mod.STORETP, 25)

    mob:setTrustTPSkillSettings(ai.tp.ASAP, ai.s.RANDOM)
end)

return m
