-----------------------------------
-- xi.effect.SLOW
-----------------------------------
---@type TEffect
local effectObject = {}

effectObject.onEffectGain = function(target, effect)
    -- Slow and Haste are mutually exclusive in retail FFXI — applying
    -- Slow on a Hasted target removes Haste. Symmetric counterpart to
    -- the delStatusEffect(SLOW) added to haste.lua.
    target:delStatusEffect(xi.effect.HASTE)

    target:addMod(xi.mod.HASTE_MAGIC, -effect:getPower())

    -- Immunobreak reset.
    target:setMod(xi.mod.SLOW_IMMUNOBREAK, 0)
end

effectObject.onEffectTick = function(target, effect)
end

effectObject.onEffectLose = function(target, effect)
    target:delMod(xi.mod.HASTE_MAGIC, -effect:getPower())
end

return effectObject
