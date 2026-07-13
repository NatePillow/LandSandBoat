-----------------------------------
-- SINGLEPLAYER override of scripts/actions/spells/trust/karaha-baruha.lua's
-- spellObject.onMobSpawn. Gambits are priority-ordered; this body fully
-- owns Karaha Baruha's spawn behavior.
--
-- REBASE AUDIT: diff this against upstream's onMobSpawn body to spot new
-- gambits/mods worth porting:
--   diff <(awk '/spellObject\.onMobSpawn/,/^end$/' scripts/actions/spells/trust/karaha-baruha.lua) \
--        <(awk '/registerSpawn.*function/,/^end\)/' modules/singleplayer/lua/trust_overrides/karaha-baruha.lua)
-- Last reconciled: 2026-06-16 (upstream baeabac590)
-----------------------------------

local m = Module:new('trust_override_karaha_baruha')

xi.singleplayer.trust.registerSpawn('KARAHA_BARUHA', function(mob)
    -- TODO: Add logic so that Spirit Taker is used if lower on mana, instead of holding to close TP.
    xi.trust.teamworkMessage(mob, {
        [xi.magic.spell.STAR_SIBYL] = xi.trust.messageOffset.TEAMWORK_1,
        [xi.magic.spell.ROBEL_AKBEL] = xi.trust.messageOffset.TEAMWORK_2,
    })

    mob:addGambit(ai.t.PARTY, { ai.c.HPP_LT, 30 }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.CURE })

    if (mob:getMainLvl() < 16) then
        mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.SLEEP_I }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE })
        mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.SLEEP_II }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE })
        mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.LULLABY }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE })
    end

    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.SLEEP_I }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURAGA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.SLEEP_II }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURAGA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.LULLABY }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURAGA })

    mob:addGambit(ai.t.PARTY, { ai.c.HPP_LT, 65 }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.CURE })

    mob:addGambit(ai.t.PARTY, { ai.c.NOT_STATUS, xi.effect.PROTECT }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.PROTECTRA })
    mob:addGambit(ai.t.PARTY, { ai.c.NOT_STATUS, xi.effect.SHELL }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.SHELLRA })

    mob:addGambit(ai.t.PARTY, { ai.l.OR(
                                { ai.c.STATUS, xi.effect.CURSE_I },
                                { ai.c.STATUS, xi.effect.CURSE_II },
                                { ai.c.STATUS, xi.effect.BANE },
                                { ai.c.STATUS, xi.effect.DOOM })
                                }, { ai.r.MS, ai.s.SPECIFIC, xi.magic.spell.CURSNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.POISON }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.POISONA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.PARALYSIS }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.PARALYNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.BLINDNESS }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.BLINDNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.SILENCE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.SILENA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.PETRIFICATION }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.STONA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.DISEASE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.VIRUNA })

    local foundPartyRedMage = false
    for _, entity in ipairs(mob:getMaster():getParty()) do
        if (entity:getMainJob() == xi.job.RDM) then
            foundPartyRedMage = true
            break
        end
    end

    if not foundPartyRedMage then
        mob:addGambit(ai.t.MASTER, { ai.c.NOT_STATUS, xi.effect.HASTE }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.HASTE })
        mob:addGambit(ai.t.MELEE, { ai.c.NOT_STATUS, xi.effect.HASTE }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.HASTE })
    end

    -- Handle his Barelementra tracking --
    mob:addListener('TAKE_DAMAGE', 'KARAHA-BARUHA_TAKE_DAMAGE', function(mobArg, amount, attacker, attackType, damageType)
        local elemTable = {
            [xi.damageType.FIRE] = { effect = xi.effect.BARFIRE, spell = 66 },
            [xi.damageType.ICE] = { effect = xi.effect.BARBLIZZARD, spell = 67 },
            [xi.damageType.WIND] = { effect = xi.effect.BARAERO, spell = 68 },
            [xi.damageType.EARTH] = { effect = xi.effect.BARSTONE, spell = 69 },
            [xi.damageType.THUNDER] = { effect = xi.effect.BARTHUNDER, spell = 70 },
            [xi.damageType.WATER] = { effect = xi.effect.BARWATER, spell = 71 },
        }
        local elemData = elemTable[damageType]
        if elemData and not mobArg:getStatusEffect(elemData.effect) then
            mobArg:timer(30, function(mobBar)
                mobBar:castSpell(elemData.spell)
            end)
        end
    end)

    mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.BLINK }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.BLINK }, 60)
    mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.STONESKIN }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.STONESKIN }, 60)

    mob:addGambit(ai.t.PARTY_DEAD, { ai.c.ALWAYS, 0 }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.RAISE })

    local power = mob:getMainLvl() / 5
    local lowPower = mob:getMainLvl() / 10
    mob:addMod(xi.mod.REFRESH, lowPower)
    mob:addMod(xi.mod.MND, power)
    mob:addMod(xi.mod.MATT, mob:getMainLvl())
    mob:addMod(xi.mod.MACC, mob:getMainLvl())
    mob:addMod(xi.mod.HASTE_MAGIC, 1000)
    mob:setMod(xi.mod.SLEEPRES, 100)
    mob:setMod(xi.mod.LULLABYRES, 100)
    mob:setMod(xi.mod.SILENCERES, 100)
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

    mob:addListener('WEAPONSKILL_USE', 'KARAHA-BARUHA_WEAPONSKILL_USE', function(mobArg, target, wsid, tp, action)
        if wsid == 3336 then -- Howling Moon
        -- The light shall never fade!
            if math.random(1, 100) <= 25 then
                xi.trust.message(mobArg, xi.trust.messageOffset.SPECIAL_MOVE_1)
            end
        end
    end)

    if
        mob:getMPP() < 30
    then
        mob:setTrustTPSkillSettings(ai.tp.ASAP, ai.s.RANDOM)
    else
        mob:setTrustTPSkillSettings(ai.tp.CLOSER_UNTIL_TP, ai.s.HIGHEST, 3000)
    end
end)

return m
