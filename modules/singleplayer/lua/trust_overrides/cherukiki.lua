-----------------------------------
-- SINGLEPLAYER override of scripts/actions/spells/trust/cherukiki.lua's
-- spellObject.onMobSpawn. Gambits are priority-ordered; this body fully
-- owns Cherukiki's spawn behavior.
--
-- REBASE AUDIT: diff this against upstream's onMobSpawn body to spot new
-- gambits/mods worth porting:
--   diff <(awk '/spellObject\.onMobSpawn/,/^end$/' scripts/actions/spells/trust/cherukiki.lua) \
--        <(awk '/registerSpawn.*function/,/^end\)/' modules/singleplayer/lua/trust_overrides/cherukiki.lua)
-- Last reconciled: 2026-06-16 (upstream baeabac590)
-----------------------------------

local m = Module:new('trust_override_cherukiki')

xi.singleplayer.trust.registerSpawn('CHERUKIKI', function(mob)
    xi.trust.teamworkMessage(mob, {
        [xi.magic.spell.MAKKI_CHEBUKKI] = xi.trust.messageOffset.TEAMWORK_1,
        [xi.magic.spell.KUKKI_CHEBUKKI] = xi.trust.messageOffset.TEAMWORK_2,
        [xi.magic.spell.PRISHE] = xi.trust.messageOffset.TEAMWORK_3,
        [xi.magic.spell.TENZEN] = xi.trust.messageOffset.TEAMWORK_4,
    })

    -- TODO: Research numerous emotes
    -- TODO: Verify amount of Regen potency, Regen effect
    -- TODO: Is supposed to path erratically during battle
    -- TODO: Meteor casting with siblings
    -- TODO: Any intelligence with casting Silence on mobs?

    mob:addGambit(ai.t.MASTER, { ai.c.NOT_STATUS, xi.effect.REGEN }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.REGEN })
    mob:addGambit(ai.t.MELEE, { ai.c.NOT_STATUS, xi.effect.REGEN }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.REGEN })

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

    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.POISON }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.POISONA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.PARALYSIS }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.PARALYNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.BLINDNESS }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.BLINDNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.SILENCE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.SILENA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.PETRIFICATION }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.STONA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.DISEASE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.VIRUNA })
    mob:addGambit(ai.t.PARTY, { ai.l.OR(
        { ai.c.STATUS, xi.effect.CURSE_I },
        { ai.c.STATUS, xi.effect.CURSE_II },
        { ai.c.STATUS, xi.effect.BANE },
        { ai.c.STATUS, xi.effect.DOOM })
    }, { ai.r.MS, ai.s.SPECIFIC, xi.magic.spell.CURSNA })

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

    mob:addGambit(ai.t.SELF, { ai.c.STATUS_FLAG, xi.effectFlag.ERASABLE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.ERASE })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS_FLAG, xi.effectFlag.ERASABLE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.ERASE })

    local foundRedMage = false
    for _, entity in ipairs(mob:getMaster():getAlliance()) do
        if (entity:getMainJob() == xi.job.RDM) then
            foundRedMage = true
            break
        end
    end

    if not foundRedMage then
        mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.DIA }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.DIA }, 10)
        mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.PARALYSIS }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.PARALYZE }, 10)
        mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.SLOW }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.SLOW }, 10)
        mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.SILENCE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.SILENCE }, 10)
    end

    mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.BLINK }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.BLINK }, 60)
    mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.STONESKIN }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.STONESKIN }, 60)

    mob:addGambit(ai.t.PARTY_DEAD, { ai.c.ALWAYS, 0 }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.RAISE })

    -- BGwiki states 5/tick regen.
    mob:addMod(xi.mod.REGEN, 5)

    mob:setAutoAttackEnabled(false)

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
end)

return m
