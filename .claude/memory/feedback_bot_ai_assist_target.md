---
name: feedback-bot-ai-assist-target
description: In bot AI code, "the mob" = assist:getTarget() — NEVER primary.currentTargetId. They can diverge and conflating them causes silent bugs (RDM casting Haste long after mob died, bots focusing wrong target, etc.)
metadata:
  type: feedback
---

## The rule

In `modules/singleplayer/lua/auto*.lua` bot AI code, "the mob the alliance is fighting" is whatever the **assist** is engaged with, accessed via `assist:getTarget()` (the engine's BattleTarget).

**`primary.currentTargetId` is NOT the same thing** — it's the user's commanded target (set by `/autobots attack`). The two can diverge:
- User picks mob A → `primary.currentTargetId = A`
- Assist can't engage A (out of range, dead, etc.) → assist's actual target is nil or something else
- All other headless follow the assist, not primary's command

So per-mob logic (combat detection, range checks against "the mob", sleep_add excluding the main mob, etc.) MUST resolve through the assist.

## How to look up "the mob" from a bot

```lua
function automagic.assist_target(bot)
    local primary = GetPlayerByID(bot:getParentCharId())
    local assist  = _resolve_assist(primary)  -- looks up assist name from primary.config.assist[1]
    if assist == nil or not assist:isEngaged() then return nil end
    local target = assist.getTarget and assist:getTarget() or nil
    if target == nil or target:isDead() then return nil end
    return target
end
```

Lives in `modules/singleplayer/lua/automagic.lua` (added in #193). Other modules should call through this.

## Why this happens repeatedly

The existing port code uses `primary.currentTargetId` heavily because it's the field that's most obvious in the per-primary state table. It got copy-pasted into role files and helpers during the port. When refactoring, easy to grab the same field without realizing it's the wrong abstraction.

**Defensive habit:** when writing bot-AI code that needs "the mob being fought," ask "should this still work if user clicked a mob that assist can't engage?" If the answer is yes, use `assist_target(bot)`, not `primary.currentTargetId`.

## Original ffxi-ashita parallel

Original packet-sniffed for the assist's swing events to populate `automagic.activeTargets[1]`. BE equivalent IS the assist's `getTarget()` — engine-authoritative, clears naturally on mob death (the engine disengages the assist).

## Symptoms when you get this wrong

- RDM/WHM casts Haste/Cure long after mob died (currentTargetId stale; assist already disengaged)
- Headless bots don't focus the right mob when user commands a target the assist couldn't engage
- Range checks pass against a stale `currentTargetId` pointing at a corpse
- Sleep_add tries to sleep the actual main mob because exclusion check uses wrong reference

## Linked

[[feedback-build-cadence]], [[feedback-singleplayer-rules]]
