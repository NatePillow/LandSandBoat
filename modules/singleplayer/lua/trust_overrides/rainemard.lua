-----------------------------------
-- SINGLEPLAYER override of scripts/actions/spells/trust/rainemard.lua's
-- spellObject.onMobSpawn. Gambits are priority-ordered; this body fully
-- owns Rainemard's spawn behavior.
--
-- REBASE AUDIT: diff this against upstream's onMobSpawn body to spot new
-- gambits/mods worth porting:
--   diff <(awk '/spellObject\.onMobSpawn/,/^end$/' scripts/actions/spells/trust/rainemard.lua) \
--        <(awk '/registerSpawn.*function/,/^end\)/' modules/singleplayer/lua/trust_overrides/rainemard.lua)
-- Last reconciled: 2026-06-16 (upstream baeabac590)
-----------------------------------

local m = Module:new('trust_override_rainemard')

xi.singleplayer.trust.registerSpawn('RAINEMARD', function(mob)
    xi.trust.teamworkMessage(mob, {
        [xi.magic.spell.CURILLA] = xi.trust.messageOffset.TEAMWORK_1,
    })

    -- flurry, cures, dispel, dia, slow

    -- TODO: Selection based on enemy weakness
    mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.ENFIRE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.ENFIRE })

    mob:addGambit(ai.t.PARTY, { ai.c.HPP_LT, 50 }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.CURE })

    mob:addGambit(ai.t.MELEE, { ai.c.NOT_STATUS, xi.effect.HASTE }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.HASTE })

    mob:addGambit(ai.t.CASTER, {
        { ai.c.NOT_STATUS, xi.effect.REFRESH },
        { ai.c.NOT_STATUS, xi.effect.SUBLIMATION_ACTIVATED },
        { ai.c.NOT_STATUS, xi.effect.SUBLIMATION_COMPLETE },
    }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.REFRESH })

    mob:addGambit(ai.t.TANK, { ai.c.NOT_STATUS, xi.effect.REFRESH }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.REFRESH })

    mob:addGambit(ai.t.RANGED, {
        { ai.c.NOT_STATUS, xi.effect.FLURRY_II }, -- xi.effect.FLURRY_II is not a typo
        { ai.c.NOT_STATUS, xi.effect.HASTE }, -- No overwriting Haste
    }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.FLURRY })

    mob:addGambit(ai.t.TOP_ENMITY, { ai.c.NOT_STATUS, xi.effect.PHALANX }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.PHALANX_II })

    mob:addGambit(ai.t.TARGET, { ai.c.STATUS_FLAG, xi.effectFlag.DISPELABLE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.DISPEL })

    mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.DIA }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.DIA }, 60)
    mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.SLOW }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.SLOW }, 60)
    mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.EVASION_DOWN }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.DISTRACT }, 60)

    mob:addGambit(ai.t.PARTY, { ai.c.NOT_STATUS, xi.effect.PROTECT }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.PROTECT })
    mob:addGambit(ai.t.PARTY, { ai.c.NOT_STATUS, xi.effect.SHELL }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.SHELL })

    mob:setTrustTPSkillSettings(ai.tp.ASAP, ai.s.RANDOM)
end)

return m
