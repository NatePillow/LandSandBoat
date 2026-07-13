-----------------------------------
-- SINGLEPLAYER override of scripts/actions/spells/trust/gessho.lua's
-- spellObject.onMobSpawn. Gambits are priority-ordered; this body fully
-- owns Gessho's spawn behavior.
--
-- REBASE AUDIT: diff this against upstream's onMobSpawn body to spot new
-- gambits/mods worth porting:
--   diff <(awk '/spellObject\.onMobSpawn/,/^end$/' scripts/actions/spells/trust/gessho.lua) \
--        <(awk '/registerSpawn.*function/,/^end\)/' modules/singleplayer/lua/trust_overrides/gessho.lua)
-- Last reconciled: 2026-06-16 (upstream baeabac590)
-----------------------------------

local m = Module:new('trust_override_gessho')

xi.singleplayer.trust.registerSpawn('GESSHO', function(mob)
    xi.trust.teamworkMessage(mob, {
        [xi.magic.spell.NAJA_SALAHEEM] = xi.trust.messageOffset.TEAMWORK_1,
        [xi.magic.spell.ABQUHBAH] = xi.trust.messageOffset.TEAMWORK_2,
    })

    mob:addMobMod(xi.mobMod.CAN_PARRY, 1)

    mob:addMod(xi.mod.MAIN_DMG_RATING, xi.trust.modGrowthValMax(mob, 35))
    mob:addMod(xi.mod.DOUBLE_ATTACK, xi.trust.modGrowthValMax(mob, 15))
    mob:addMod(xi.mod.ACC, xi.trust.modGrowthValMax(mob, 200))
    mob:addMod(xi.mod.EVA, xi.trust.modGrowthValMax(mob, 125))
    mob:addMod(xi.mod.FASTCAST, 30)
    mob:addMod(xi.mod.ENMITY, 10)

    local lvl = mob:getMainLvl()

    if lvl >= 5 then
        mob:addGambit(ai.t.SELF, { ai.c.ALWAYS, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.PROVOKE })
    end

    if lvl >= 40 then
        mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.YONIN }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.YONIN })
    end

    mob:addGambit(ai.t.SELF,   { ai.c.NOT_STATUS, xi.effect.COPY_IMAGE }, { ai.r.MA, ai.s.HIGHEST,  xi.magic.spellFamily.UTSUSEMI })
    mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.BLINDNESS  }, { ai.r.MA, ai.s.HIGHEST,  xi.magic.spellFamily.KURAYAMI }, 30)
    mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.SLOW       }, { ai.r.MA, ai.s.HIGHEST,  xi.magic.spellFamily.HOJO     }, 30)

    mob:addListener('WEAPONSKILL_USE', 'GESSHO_WEAPONSKILL_USE', function(mobArg, target, skill, tp, action, damage)
        if skill:getID() == xi.mobSkill.SHIBARAKU_TRUST then -- Shibaraku
            -- You have left me no choice. Prepare yourself!
            xi.trust.message(mobArg, xi.trust.messageOffset.SPECIAL_MOVE_1)
        end
    end)

    -- Shadows are represented by xi.effect.COPY_IMAGE, but with different icons depending on the tier
    mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.COPY_IMAGE }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.UTSUSEMI })

    mob:addGambit(ai.t.SELF, { ai.c.NOT_HAS_TOP_ENMITY, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.PROVOKE })

    mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.BLINDNESS }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.KURAYAMI }, 60)
    mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.SLOW }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.HOJO }, 60)

    mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.YONIN }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.YONIN })

    mob:setTrustTPSkillSettings(ai.tp.ASAP, ai.s.RANDOM)

    local power = mob:getMainLvl() / 5
    mob:addMod(xi.mod.ENMITY, power)
    mob:addMod(xi.mod.STR, power)
    mob:addMod(xi.mod.AGI, power)
    mob:addMod(xi.mod.EVA, mob:getMainLvl())
    mob:addMod(xi.mod.HASTE_MAGIC, 1000)
    mob:addMod(xi.mod.SPELLINTERRUPT, mob:getMainLvl())
    mob:setMod(xi.mod.SILENCERES, 100)
end)

return m
