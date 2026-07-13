-----------------------------------
-- Server-side AI: WHM-focused healer role. Ported from client-side.
-- Decision tree is `tick(bot)` — a priority cascade run from the per-bot tick.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('role_heal')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.heal = xi.singleplayer.bots.heal or {}
local role_heal = xi.singleplayer.bots.heal

-----------------------------------
function role_heal.on_load(bot)
end

-----------------------------------
--    Runs the heal priority cascade.
-----------------------------------
function role_heal.tick(bot)
    if xi.singleplayer.bots.ai_util.is_force_rested(bot) then return end
    -- Run pre-cast checks first (handles linkdead / casting / moving / resting)
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.tick then xi.singleplayer.bots.ai_equip_swap.tick(bot) end
    if xi.singleplayer.bots.magic.process_pre_cast_checks(bot) then return end

    -- Full cascade lives on ai_magic so /WHM-sub role files (role_smn,
    -- future ones) can reuse it after their own priorities. build_whm_ctx
    -- computes primary/activeTarget/state/healScope/cureTier/*/log with
    -- an 'AutoHeal'-tagged logger so grepping still works.
    local ctx = xi.singleplayer.bots.magic.build_whm_ctx(bot, 'AutoHeal')
    xi.singleplayer.bots.magic.whm_cascade(bot, ctx)
end

return m
