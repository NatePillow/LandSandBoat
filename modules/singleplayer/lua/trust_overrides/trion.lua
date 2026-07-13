-----------------------------------
-- SINGLEPLAYER override of scripts/actions/spells/trust/trion.lua's
-- spellObject.onMobSpawn. Gambits are priority-ordered; this body fully
-- owns Trion's spawn behavior.
--
-- REBASE AUDIT: diff this against upstream's onMobSpawn body to spot new
-- gambits/mods worth porting:
--   diff <(awk '/spellObject\.onMobSpawn/,/^end$/' scripts/actions/spells/trust/trion.lua) \
--        <(awk '/registerSpawn.*function/,/^end\)/' modules/singleplayer/lua/trust_overrides/trion.lua)
-- Last reconciled: 2026-06-16 (upstream baeabac590)
-----------------------------------

local m = Module:new('trust_override_trion')

xi.singleplayer.trust.registerSpawn('TRION', function(mob)
    xi.trust.teamworkMessage(mob, {
        [xi.magic.spell.CURILLA] = xi.trust.messageOffset.TEAMWORK_1,
        [xi.magic.spell.RAHAL] = xi.trust.messageOffset.TEAMWORK_2,
        [xi.magic.spell.HALVER] = xi.trust.messageOffset.TEAMWORK_3,
    })

    mob:setMobMod(xi.mobMod.CAN_SHIELD_BLOCK, 1)
    mob:setMobMod(xi.mobMod.CAN_PARRY, 3)

    if (mob:getMainLvl() > 29) then
        mob:addGambit(ai.t.SELF, { ai.c.NOT_HAS_TOP_ENMITY, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.SENTINEL })
    end

    -- PORTED FROM UPSTREAM (2026-06-16): use Trion's signature ROYAL_BASH mob
    -- skill instead of the generic SHIELD_BASH JA — higher damage, longer
    -- stun, on-theme. Single OR-gambit covers all four interrupt triggers
    -- (WS / MS / JA / cast). 60-cooldown matches upstream.
    mob:addGambit(ai.t.TARGET, { ai.l.OR(
        { ai.c.CASTING_MA,  0 },
        { ai.c.READYING_JA, 0 },
        { ai.c.READYING_MS, 0 },
        { ai.c.READYING_WS, 0 }) }, { ai.r.MS, ai.s.SPECIFIC, xi.mobSkill.ROYAL_BASH_TRUST }, 60)

    if (mob:getMainLvl() > 61) then
        mob:addGambit(ai.t.PARTY, { ai.c.HPP_LT, 60 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.RAMPART })
    end

    if (mob:getMainLvl() > 49) then
        mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.DEFENDER }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.DEFENDER })
    end

    local foundWhiteMage = false
    for _, entity in ipairs(mob:getMaster():getAlliance()) do
        if (entity:getMainJob() == xi.job.WHM) then
            foundWhiteMage = true
            break
        end
    end

    -- Quality of life update
    if not foundWhiteMage then
        mob:addGambit(ai.t.PARTY, { ai.c.NOT_STATUS, xi.effect.PROTECT }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.PROTECTRA })
        mob:addGambit(ai.t.PARTY, { ai.c.NOT_STATUS, xi.effect.SHELL }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.SHELLRA })
    end

    mob:addGambit(ai.t.TARGET, { ai.c.NOT_STATUS, xi.effect.FLASH }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.FLASH })
    mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.REPRISAL }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.REPRISAL })

    mob:addGambit(ai.t.PARTY, { ai.c.HPP_LT, 80 }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.CURE })

    -- PORTED FROM UPSTREAM (2026-06-16): Shield Mastery TP scales with level —
    -- block events grant more TP at higher tiers.
    local shieldMasteryPower = 0
    local lvl                = mob:getMainLvl()
    if lvl >= 96 then
        shieldMasteryPower = 40
    elseif lvl >= 75 then
        shieldMasteryPower = 30
    elseif lvl >= 50 then
        shieldMasteryPower = 20
    elseif lvl >= 25 then
        shieldMasteryPower = 10
    end
    mob:setMod(xi.mod.SHIELD_MASTERY_TP, shieldMasteryPower)

    local power = mob:getMainLvl() / 5
    local lowPower = mob:getMainLvl() / 10
    mob:addMod(xi.mod.REGEN, lowPower)
    mob:addMod(xi.mod.REFRESH, lowPower)
    mob:addMod(xi.mod.VIT, power)
    mob:addMod(xi.mod.MND, power)
    mob:addMod(xi.mod.CHR, power)
    mob:addMod(xi.mod.DEF, mob:getMainLvl())
    mob:addMod(xi.mod.ENMITY, power)
    mob:addMod(xi.mod.HASTE_MAGIC, 1000)
    mob:addMod(xi.mod.SPELLINTERRUPT, mob:getMainLvl())
    mob:setMod(xi.mod.SILENCERES, 100)

    -- PORTED FROM UPSTREAM (2026-06-16): shield/cast tank stats; survivability
    -- and bot longevity bumps. SHIELDBLOCKRATE 35 (higher than Curilla's 25)
    -- and FASTCAST 30 are Trion-specific.
    mob:setMod(xi.mod.SHIELDBLOCKRATE, 35)
    mob:addMod(xi.mod.FASTCAST,        30)
    mob:addMod(xi.mod.DMG,            -500) -- damage taken -5%
    mob:addMod(xi.mod.HPP,             10)
    mob:addMod(xi.mod.MPP,             10)
end)

return m
