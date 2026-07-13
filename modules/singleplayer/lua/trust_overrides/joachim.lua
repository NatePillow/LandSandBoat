-----------------------------------
-- SINGLEPLAYER override of scripts/actions/spells/trust/joachim.lua's
-- spellObject.onMobSpawn. Gambits are priority-ordered; this body fully
-- owns Joachim's spawn behavior.
--
-- REBASE AUDIT: diff this against upstream's onMobSpawn body to spot new
-- gambits/mods worth porting:
--   diff <(awk '/spellObject\.onMobSpawn/,/^end$/' scripts/actions/spells/trust/joachim.lua) \
--        <(awk '/registerSpawn.*function/,/^end\)/' modules/singleplayer/lua/trust_overrides/joachim.lua)
-- Last reconciled: 2026-06-16 (upstream baeabac590)
-----------------------------------

local m = Module:new('trust_override_joachim')

xi.singleplayer.trust.registerSpawn('JOACHIM', function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.SPAWN)

    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.POISON }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.POISONA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.PARALYSIS }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.PARALYNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.BLINDNESS }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.BLINDNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.SILENCE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.SILENA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.PETRIFICATION }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.STONA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.DISEASE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.VIRUNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.CURSE_I }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURSNA })

    mob:addGambit(ai.t.PARTY, { ai.c.HPP_LT, 40 }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.CURE })

    if (mob:getMainLvl() < 29) then
        mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.PAEON }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.ARMYS_PAEON })
    else
        mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.MARCH }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.MARCH })
    end

    if (mob:getMainLvl() < 25) then
        mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.MINNE }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.KNIGHTS_MINNE })
    else
        mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.BALLAD }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.MAGES_BALLAD })
    end

    --mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.MINUET }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.VALOR_MINUET })
    --mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.MADRIGAL }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.MADRIGAL })

    mob:addGambit(ai.t.TARGET, { ai.c.STATUS_FLAG, xi.effectFlag.DISPELABLE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.MAGIC_FINALE })

    mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.ELEGY }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.ELEGY })
    mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.REQUIEM }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.REQUIEM })

    mob:addGambit(ai.t.PARTY_DEAD, { ai.c.ALWAYS, 0 }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.RAISE })

    -- Try and ranged attack every 60s
    --mob:addGambit(ai.t.TARGET, { ai.c.ALWAYS, 0 }, { ai.r.RATTACK, 0, 0 }, 60)

    mob:setAutoAttackEnabled(false)

    mob:addMod(xi.mod.MAXIMUM_SONGS_BONUS, 2)

    local power = mob:getMainLvl() / 5
    local lowPower = mob:getMainLvl() / 10
    mob:addMod(xi.mod.MPP, 100)
    mob:addMod(xi.mod.REFRESH, lowPower)
    mob:addMod(xi.mod.MND, power)
    mob:addMod(xi.mod.CHR, power)
    mob:addMod(xi.mod.HASTE_MAGIC, 1000)
    mob:addMod(xi.mod.ENMITY, -power)

    if (mob:getMainLvl() > 50) then
        mob:addMod(xi.mod.FIRE_STAFF_BONUS, 3)
        mob:addMod(xi.mod.ICE_STAFF_BONUS, 3)
        mob:addMod(xi.mod.WIND_STAFF_BONUS, 3)
        mob:addMod(xi.mod.EARTH_STAFF_BONUS, 3)
        mob:addMod(xi.mod.THUNDER_STAFF_BONUS, 3)
        mob:addMod(xi.mod.WATER_STAFF_BONUS, 3)
        mob:addMod(xi.mod.LIGHT_STAFF_BONUS, 3)
        mob:addMod(xi.mod.DARK_STAFF_BONUS, 3)
    end

    mob:setMobMod(xi.mobMod.TRUST_DISTANCE, xi.trust.movementType.MID_RANGE)
end)

return m
