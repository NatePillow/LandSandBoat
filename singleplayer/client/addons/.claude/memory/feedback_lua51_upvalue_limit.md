---
name: lua51-60-upvalue-limit
description: Lua 5.1 (Ashita v3) caps a function at 60 upvalues; a giant addon render closure hit it. Symptom "function at line N has more than 60 upvalues" on /addon load. Fix - hang state on an existing captured table, or split the function.
metadata:
  type: feedback
---

**Lua 5.1 (the Ashita v3 runtime) allows at most 60 upvalues per function.** An
upvalue = any variable a function references from an ENCLOSING scope (module-level
`local`s, and — transitively — locals a nested function reaches through it). Hit the
cap and the addon fails to LOAD with:
`... .lua:N: function at line M has more than 60 upvalues`
(N = the register/return line; M = the offending function's line.)

**How autobots hit it:** `autobots_ui.lua`'s `ashita.register_event('render', ...)`
was ONE ~1450-line closure holding every tab's UI inline, so it captured exactly 60
module-level names. Adding a single new bare `local server_running` referenced inside
it made 61 → load failure.

**Two fixes, smallest first:**
1. **One-off / quick:** store the new state as a FIELD on a table the function already
   captures (e.g. `autobots_ui.server_running` instead of `local server_running`).
   Reusing an existing upvalue adds none. This is the band-aid — it does NOT create
   headroom, the function is still AT 60.
2. **Real fix (do this once you're at the cap):** split the function. Each cohesive
   block becomes its own MODULE-LEVEL function (a sibling, NOT nested — nesting doesn't
   help, the outer still needs the upvalue to pass down). Pass per-frame computed values
   in a small `ctx` table; each extracted function then captures only ITS subset and
   sits far under 60. autobots render was split into render_quick_tab / render_left_column
   / render_right_column + a slim dispatcher (2026-07, ~60→~21 in the event, ~30-40 each).

**Doing the split safely (untestable client Lua):** move each block VERBATIM (don't
retype 1000+ lines — a dropped/transposed line surfaces as a client crash on the user's
reload, not an error at your end). A Python script that slices exact line ranges and
writes the file is the reliable tool; assert the boundary lines before writing. Then
verify: imgui Begin/End · BeginGroup/EndGroup · BeginChild/EndChild · Push*/Pop* pairs
balance per-function (grep counts; note if/elseif/else colour pushes are N-push-1-pop
by design), and that each extracted fn's `BeginGroup..EndGroup` closes inside its own
`end`. Destructure ctx into same-named locals so the moved body needs zero edits.

Related Ashita footguns: [[swap-logic-size-debug]], [[imgui-style-stack-leak]],
[[imgui-createvar-reopen-leak]]. All four are load/crash-class, none caught by pcall.
