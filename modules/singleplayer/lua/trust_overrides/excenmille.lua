-----------------------------------
-- SINGLEPLAYER override of scripts/actions/spells/trust/excenmille.lua's
-- spellObject.onMobSpawn. Gambits are priority-ordered; this body fully
-- owns Excenmille's spawn behavior.
--
-- REBASE AUDIT: diff this against upstream's onMobSpawn body to spot new
-- gambits/mods worth porting:
--   diff <(awk '/spellObject\.onMobSpawn/,/^end$/' scripts/actions/spells/trust/excenmille.lua) \
--        <(awk '/registerSpawn.*function/,/^end\)/' modules/singleplayer/lua/trust_overrides/excenmille.lua)
-- Last reconciled: 2026-06-16 (upstream baeabac590)
-----------------------------------

local m = Module:new('trust_override_excenmille')

xi.singleplayer.trust.registerSpawn('EXCENMILLE', function(mob)
    xi.trust.teamworkMessage(mob, {
        [xi.magic.spell.RAHAL] = xi.trust.messageOffset.TEAMWORK_1,
    })

    mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.SENTINEL }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.SENTINEL })

    mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.FLASH }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.FLASH })

    mob:addGambit(ai.t.PARTY, { ai.c.HPP_LT, 30 }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.CURE })

    if (mob:getMainLvl() > 69) then
        mob:addGambit(ai.t.SELF, { ai.c.PT_HAS_TANK, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.WARCRY })
    end

    -- DD Mode
    if (mob:getMainLvl() > 29) then
        mob:addGambit(ai.t.SELF, { ai.c.PT_HAS_TANK, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.BERSERK })
    end
    mob:addGambit(ai.t.TANK, { ai.c.HPP_LT, 35 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.PROVOKE })

    -- Tank Mode
    mob:addGambit(ai.t.TARGET, { ai.c.NOT_PT_HAS_TANK, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.PROVOKE })
    mob:addGambit(ai.t.SELF, { ai.c.NOT_PT_HAS_TANK, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.DEFENDER })
    mob:addGambit(ai.t.SELF, { ai.c.NOT_PT_HAS_TANK, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.RETALIATION })
    if (mob:getMainLvl() > 29) then
        mob:addGambit(ai.t.SELF, { ai.c.NOT_PT_HAS_TANK, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.SENTINEL })
    end

    local power = mob:getMainLvl() / 5
    mob:addMod(xi.mod.STR, power)
    mob:addMod(xi.mod.DEX, power)
    mob:addMod(xi.mod.VIT, power)
    mob:addMod(xi.mod.ATT, mob:getMainLvl())
    mob:addMod(xi.mod.ACC, mob:getMainLvl())
    mob:addMod(xi.mod.DEF, mob:getMainLvl())
    mob:addMod(xi.mod.STORETP, 25)

    mob:setTrustTPSkillSettings(ai.tp.ASAP, ai.s.RANDOM)
end)

return m
