-----------------------------------
-- xi.effect.LEAVEGAME
-----------------------------------
---@type TEffect
local effectObject = {}

local kinds =
{
    LOGOUT   = 1,
    SHUTDOWN = 3,
}

local messages =
{
    [kinds.LOGOUT]   = xi.msg.system.EXECUTING_LOGOUT,
    [kinds.SHUTDOWN] = xi.msg.system.EXECUTING_SHUTDOWN,
}

effectObject.onEffectGain = function(target, effect)
    -- If you're a GM or in a MH, you get disconnected immediately.
    if
        target:inMogHouse() or
        target:getGMLevel() > 0
    then
        target:leaveGame()
        return
    end

    -- addStatusEffect (non-Ex) forces the icon to the effect ID...
    if not target:hasStatusEffect(xi.effect.HEALING) then
        target:addStatusEffect(xi.effect.HEALING, { origin = target, tick = xi.settings.map.HEALING_TICK_DELAY, icon = 0, silent = true })
    end

    -- Note: Power stores the kind.
    -- Countdown reduced from retail's 30s to 5s for the singleplayer fork
    -- (the longer wait was retail-flavor, no functional value here). The
    -- 5s tick interval set at effect construction in
    -- src/map/packets/c2s/0x0e7_reqlogout.cpp means the first tick fires
    -- right at the announced disconnect time — onEffectTick below pulls
    -- the trigger on tick 1.
    target:messageSystem(messages[effect:getPower()], 5)

    -- Fire equip_gearlock on every HEADLESS attached to this primary so
    -- the gear they log back in wearing matches their XML <gearlock>. The
    -- primary is intentionally excluded here: equip_section on the primary
    -- would try to equip items the player may not own (gearlock is often
    -- a fashion-only set on a real char), would log "unknown item"
    -- failures, and would persist whatever weird state that left to
    -- char_equip — the user reported their actual gear gone on next
    -- login. The primary's visual lock is driven by the autoequip
    -- addon's apply_gearlock_lockstyle on XML load instead.
    if xi.singleplayer.bots and xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_gearlock then
        local primaryId = target:getID()
        for _, member in ipairs(target:getAlliance() or {}) do
            if member.isHeadless and member:isHeadless()
               and member.getParentCharId and member:getParentCharId() == primaryId
            then
                xi.singleplayer.bots.ai_equip_swap.equip_gearlock(member)
            end
        end
    end
end

effectObject.onEffectTick = function(target, effect)
    -- Note: The type of leavegame may change while it's ticking.
    -- Logout to Shutdown or vice versa.
    -- This has no bearing on the way the player gets disconnected
    -- but it does change the message displayed.
    --
    -- 5s total countdown (down from retail's 30s). The effect ticks every
    -- 5 seconds, so the first tick is exactly when the user's expected
    -- disconnect time arrives — pull the trigger immediately. No
    -- intermediate "in N seconds" messages because there's no N to count
    -- down to.
    target:leaveGame()
end

effectObject.onEffectLose = function(target, effect)
    target:delStatusEffect(xi.effect.HEALING)
end

return effectObject
