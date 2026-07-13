---
name: lua-one-statement-per-line
description: Everywhere in the codebase (all Lua modules, not just role_*.lua ticks), put each statement on its own line and prefer if/elseif/else with a terminal fallback over short-circuit `if X then Y; return end` chains
metadata:
  type: feedback
---

**Applies everywhere in the codebase** (all Lua under modules/, scripts/,
addons/, etc.) — not scoped to role tick cascades. The examples below
were pulled from a role_smn edit but the rule holds for every Lua file:

**1. One statement per line.** Do NOT chain multiple statements with `;` on one line.

Bad (my previous default):
```lua
if role_smn.can_use_ward(bot) then
    log('ward'); role_smn.cast_next_ward(bot); return
```

Good:
```lua
if role_smn.can_use_ward(bot) then
    log('ward');
    role_smn.cast_next_ward(bot);
```

**2. Prefer `if / elseif / else` cascade with a terminal fallback over
short-circuit `if X then Y; return end` chains.** The elseif chain
keeps the priority structure visually intact; a series of independent
`if X then ... return end` blocks flattens the priority and makes
insertion order matter in ways that aren't obvious.

Bad (short-circuit returns):
```lua
if role_smn.can_summon_avatar(bot) then
    log('engaged-summon'); role_smn.cast_summon_avatar(bot); return
end
if role_smn.can_mb_rage(bot) then
    log('mb-rage'); role_smn.cast_next_mb_rage(bot); return
end
-- fall-through fallback below
xi.singleplayer.bots.heal.tick(bot)
```

Good (elseif with terminal else):
```lua
if role_smn.can_summon_avatar(bot) then
    log('engaged-summon');
    role_smn.cast_summon_avatar(bot);
elseif role_smn.can_mb_rage(bot) then
    log('mb-rage');
    role_smn.cast_next_mb_rage(bot);
elseif role_smn.can_use_ward(bot) then
    log('ward');
    role_smn.cast_next_ward(bot);
else
    xi.singleplayer.bots.heal.tick(bot);
end
```

**Why:**
- Each line is a diff-friendly unit; git blame + PR review land cleanly on the exact statement changed
- Reordering branches doesn't require moving `return`s or worrying about which branch owns the fallback
- The elseif structure makes the priority order self-documenting: it's a single decision, not a bag of independent gates that happen to be ordered
- Matches the existing convention in [[no-try-x-pattern]] (pure predicate + action-in-body) — this is its formatting counterpart

**How to apply:**
- When writing or editing any role tick cascade
- When editing existing branches: split `log(); do(); return` into three lines even if the surrounding branches haven't been converted yet
- When adding a fallback path, extend the elseif with a terminal `else`; don't leave a bare statement after the `end`
- Follow the same semicolon-terminator style the surrounding code uses (Lua tolerates both; role_smn uses trailing `;`)
