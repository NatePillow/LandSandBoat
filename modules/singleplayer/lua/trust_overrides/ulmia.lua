-----------------------------------
-- SINGLEPLAYER override of scripts/actions/spells/trust/ulmia.lua's
-- spellObject.onMobSpawn. Gambits are priority-ordered; this body fully
-- owns Ulmia's spawn behavior.
--
-- REBASE AUDIT: diff this against upstream's onMobSpawn body to spot new
-- gambits/mods worth porting:
--   diff <(awk '/spellObject\.onMobSpawn/,/^end$/' scripts/actions/spells/trust/ulmia.lua) \
--        <(awk '/registerSpawn.*function/,/^end\)/' modules/singleplayer/lua/trust_overrides/ulmia.lua)
-- Last reconciled: 2026-06-16 (upstream baeabac590)
-----------------------------------

local m = Module:new('trust_override_ulmia')

xi.singleplayer.trust.registerSpawn('ULMIA', function(mob)
    xi.trust.teamworkMessage(mob, {
        [xi.magic.spell.PRISHE] = xi.trust.messageOffset.TEAMWORK_1,
        [xi.magic.spell.MILDAURION] = xi.trust.messageOffset.TEAMWORK_2,
    })

    -- TODO: BRD trusts need better logic and major overhaul, for now they compliment each other
    mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.MADRIGAL }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.MADRIGAL })
    mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.MINUET }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.VALOR_MINUET })

    mob:addGambit(ai.t.TARGET, { ai.c.STATUS_FLAG, xi.effectFlag.DISPELABLE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.MAGIC_FINALE })

    mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.ELEGY }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.ELEGY })
    mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.REQUIEM }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.REQUIEM })

    mob:setAutoAttackEnabled(false)

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
