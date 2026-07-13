-----------------------------------
-- Trust: Kayeel-Payeel
-----------------------------------
---@type TSpellTrust
local spellObject = {}

spellObject.onMagicCastingCheck = function(caster, target, spell)
    return xi.trust.canCast(caster, spell)
end

spellObject.onSpellCast = function(caster, target, spell)
    return xi.trust.spawn(caster, spell)
end

spellObject.onMobSpawn = function(mob)
    -- SINGLEPLAYER BEGIN
    if xi.singleplayer and xi.singleplayer.trust
       and xi.singleplayer.trust.maybeOverrideSpawn(mob, 'KAYEEL_PAYEEL') then return end
    -- SINGLEPLAYER END
    xi.trust.message(mob, xi.trust.messageOffset.SPAWN)
end

spellObject.onMobDespawn = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DESPAWN)
end

spellObject.onMobDeath = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DEATH)
end

return spellObject
