-----------------------------------
-- SINGLEPLAYER override of scripts/actions/spells/trust/lion.lua's
-- spellObject.onMobSpawn. Gambits are priority-ordered; this body fully
-- owns Lion's spawn behavior.
--
-- REBASE AUDIT: diff this against upstream's onMobSpawn body to spot new
-- gambits/mods worth porting:
--   diff <(awk '/spellObject\.onMobSpawn/,/^end$/' scripts/actions/spells/trust/lion.lua) \
--        <(awk '/registerSpawn.*function/,/^end\)/' modules/singleplayer/lua/trust_overrides/lion.lua)
-- Last reconciled: 2026-06-16 (upstream baeabac590)
-----------------------------------

local m = Module:new('trust_override_lion')

xi.singleplayer.trust.registerSpawn('LION', function(mob)
    -- TODO: Trust Synergy (Aldo/Lion/Zeid)
    -- https://www.bg-wiki.com/ffxi/Cipher:_Lion

    local kGrapeshot = 3198

    xi.trust.teamworkMessage(mob, {
        [xi.magic.spell.ZEID] = xi.trust.messageOffset.TEAMWORK_1,
        [xi.magic.spell.ALDO] = xi.trust.messageOffset.TEAMWORK_2,
        [xi.magic.spell.GILGAMESH] = xi.trust.messageOffset.TEAMWORK_3,
    })

    -- Stun all the things!
    mob:addGambit(ai.t.TARGET, { ai.c.READYING_WS, 0 }, { ai.r.WS, ai.s.SPECIFIC, kGrapeshot })
    mob:addGambit(ai.t.TARGET, { ai.c.READYING_MS, 0 }, { ai.r.WS, ai.s.SPECIFIC, kGrapeshot })
    mob:addGambit(ai.t.TARGET, { ai.c.READYING_JA, 0 }, { ai.r.WS, ai.s.SPECIFIC, kGrapeshot })
    mob:addGambit(ai.t.TARGET, { ai.c.CASTING_MA,  0 }, { ai.r.WS, ai.s.SPECIFIC, kGrapeshot })

    if (mob:getMainLvl() > 69) then
        mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.WARCRY })
    end

    if (mob:getMainLvl() > 29) then
        mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.BERSERK })
    end

    local power = mob:getMainLvl() / 5
    mob:addMod(xi.mod.STR, power)
    mob:addMod(xi.mod.DEX, power)
    mob:addMod(xi.mod.AGI, power)
    mob:addMod(xi.mod.ATT, mob:getMainLvl())
    mob:addMod(xi.mod.ACC, mob:getMainLvl())
    mob:addMod(xi.mod.EVA, mob:getMainLvl())
    mob:addMod(xi.mod.STORETP, 25)

    mob:setTrustTPSkillSettings(ai.tp.ASAP, ai.s.RANDOM)
end)

return m
