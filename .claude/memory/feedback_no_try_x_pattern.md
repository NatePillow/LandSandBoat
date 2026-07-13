---
name: no-try-x-pattern
description: Role-tick cascades use pure predicate + action-in-body, NOT try_X helpers that check-and-fire in a single conditional
metadata:
  type: feedback
---

In `modules/singleplayer/bots/role_*.lua` cascades, every branch is shaped
as `pure_predicate(bot) then log; do_action(bot)` — the check is
side-effect-free, the cast happens inside the body. Examples already in
the codebase:

- `sleeping_whm(bot)` then `wake_up_whm(bot)`
- `provoke_is_up(bot)` then `provoke(bot)`
- `flash_is_up(bot)` then `flash(bot)`
- `can_cast_pld_cure(bot)` then `cast_pld_healing_spell(bot)`
- `can_cast_utsusemi(bot)` then `cast_utsusemi(bot)`

Do NOT introduce `try_X(bot)` helpers that conflate the check with the
action and return a boolean indicating "did I fire something?" The one
existing example (`try_bash`) was something I introduced earlier and the
user tolerated — not a convention to copy or extend.

When a function's predicate logic needs context the action also wants
(e.g. "what's the next missing debuff?"), expose two functions:
- `can_cast_X(bot)` — pure boolean wrapping the lookup-then-non-nil check
- `cast_next_X(bot)` — does the lookup again and fires

The duplicate lookup is cheap at FFXI tick scale (a few bots per second)
and far cheaper than the readability cost of side-effect-hiding `try_X`.

**Why:** When the user reviewed NIN dispatch in role_tank / role_melee and
saw `if try_engaged_tick(...) then return end`, their complaint was
"check then use within the block" is the codebase pattern, and `try_bash`
was MY earlier mistake spreading further. Spreading anti-patterns is
worse than the original infraction.

**How to apply:** Any time I'm tempted to write a function that checks
preconditions and fires the action returning a bool — split into pure
`can_X` predicate and side-effectful `do_X` action, then use them in
classic `elseif can_X(bot) then log; do_X(bot)` cascade form. Use temp
locals at the top of the function for shared context (job/role checks)
that several branches need; this matches how role_tank precomputes
`cureTier` before the cascade.
