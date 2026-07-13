---
name: ranged-weapon-lua-binding
description: Engine binding for ranged-weapon damage is `getRangedDmg` (no 'a' before 'ge'), NOT `getRangedDamage`. Typing it wrong silently false-routes — Lua's `and`-chain short-circuits when the method doesn't exist.
metadata:
  type: project
---

The engine Lua binding for ranged-weapon damage is **`getRangedDmg`**, registered in `src/map/lua/lua_baseentity.cpp` (SOL_REGISTER line ~21030). There is **no** `getRangedDamage` method.

**Why this keeps biting:** code like
```lua
if bot.getRangedDamage and (bot:getRangedDamage() or 0) > 0 then ... end
```
silently evaluates the guard to `nil` (method doesn't exist), the `and`-chain short-circuits, and the branch is dead. No runtime error, no warning — it just always reports "no ranged weapon" regardless of equipped gear. We hit this in `ai_puller.pick_pull_tool` (#208 follow-up) where a bot with crossbow + bolts equipped still logged "no Dia and no ranged weapon — idle".

**How to apply:** When writing ranged-weapon presence checks for bot AI, use `getRangedDmg`. The companion engine binding is `getAmmoDmg` (also no 'a'). Grep for `getRangedDamage` in `modules/singleplayer/` to catch regressions.
