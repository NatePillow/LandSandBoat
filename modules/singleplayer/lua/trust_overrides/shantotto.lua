-----------------------------------
-- SINGLEPLAYER override of scripts/actions/spells/trust/shantotto.lua's
-- spellObject.onMobSpawn. Gambits are priority-ordered; this body fully
-- owns Shantotto's spawn behavior.
--
-- REBASE AUDIT: diff this against upstream's onMobSpawn body to spot new
-- gambits/mods worth porting:
--   diff <(awk '/spellObject\.onMobSpawn/,/^end$/' scripts/actions/spells/trust/shantotto.lua) \
--        <(awk '/registerSpawn.*function/,/^end\)/' modules/singleplayer/lua/trust_overrides/shantotto.lua)
-- Last reconciled: 2026-06-16 (upstream baeabac590)
-----------------------------------

local m = Module:new('trust_override_shantotto')

xi.singleplayer.trust.registerSpawn('SHANTOTTO', function(mob)
    xi.trust.teamworkMessage(mob, {
        [xi.magic.spell.AJIDO_MARUJIDO] = xi.trust.messageOffset.TEAMWORK_1,
        [xi.magic.spell.STAR_SIBYL] = xi.trust.messageOffset.TEAMWORK_2,
        [xi.magic.spell.KORU_MORU] = xi.trust.messageOffset.TEAMWORK_3,
        [xi.magic.spell.KING_OF_HEARTS] = xi.trust.messageOffset.TEAMWORK_4
    })

    mob:addGambit(ai.t.TARGET, { ai.c.MB_AVAILABLE, 0 }, { ai.r.MA, ai.s.MB_ELEMENT, xi.magic.spellFamily.NONE })

    mob:addGambit(ai.t.TARGET, { ai.c.READYING_WS, 0 }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.STUN })
    mob:addGambit(ai.t.TARGET, { ai.c.READYING_MS, 0 }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.STUN })
    mob:addGambit(ai.t.TARGET, { ai.c.READYING_JA, 0 }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.STUN })
    mob:addGambit(ai.t.TARGET, { ai.c.CASTING_MA,  0 }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.STUN })

    mob:addGambit(ai.t.SELF, { ai.c.HPP_LT, 80 }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.DRAIN })
    mob:addGambit(ai.t.SELF, { ai.c.MPP_LT, 60 }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.ASPIR })

    mob:addGambit(ai.t.TARGET, { ai.c.NOT_SC_AVAILABLE, 0 }, { ai.r.MA, ai.s.RANDOM, xi.magic.spellFamily.NONE }, 10)

    local foundRedMage = false
    for _, entity in ipairs(mob:getMaster():getAlliance()) do
        if (entity:getMainJob() == xi.job.RDM) then
            foundRedMage = true
            break
        end
    end

    if not foundRedMage then
        mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.POISON }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.POISON }, 10)
        mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.BLIND }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.BLIND }, 10)
    end

    local power = mob:getMainLvl() / 5
    local lowPower = mob:getMainLvl() / 10
    mob:addMod(xi.mod.REFRESH, lowPower)
    mob:addMod(xi.mod.INT, power)
    mob:addMod(xi.mod.MATT, mob:getMainLvl())
    mob:addMod(xi.mod.MACC, mob:getMainLvl())
    mob:addMod(xi.mod.HASTE_MAGIC, 1000) -- 10% Haste (Magic)
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

    mob:setAutoAttackEnabled(false)

    mob:setMobMod(xi.mobMod.TRUST_DISTANCE, xi.trust.movementType.MID_RANGE)
end)

return m
