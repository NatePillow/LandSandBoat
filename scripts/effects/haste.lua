-----------------------------------
-- xi.effect.HASTE
-----------------------------------
---@type TEffect
local effectObject = {}

effectObject.onEffectGain = function(target, effect)
    -- Overwrites regular Flurry Effect
    target:delStatusEffect(xi.effect.FLURRY_II)

    -- Haste and Slow are mutually exclusive in retail FFXI — applying
    -- one removes the other. Without this delStatusEffect, bot AI's
    -- status-cure loop (sees SLOW → casts Haste → SLOW stays → casts
    -- Haste again → repeat) spammed Haste forever on slowed targets.
    target:delStatusEffect(xi.effect.SLOW)

    effect:addMod(xi.mod.HASTE_MAGIC, effect:getPower())
end

effectObject.onEffectTick = function(target, effect)
end

effectObject.onEffectLose = function(target, effect)
end

return effectObject
