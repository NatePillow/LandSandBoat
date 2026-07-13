---
name: project-aoe-positioning-lease-hold
description: Deferred fix for WHM AoE-buff positioning stutter (forward/back yank); lease-hold option, and why NOT to touch cast-gating
metadata:
  type: project
---

Deferred (evaluated 2026-07-11, chose to observe more first, no code written).

## Symptom
Mage (WHM) walking to the party centroid to land AoE buffs (bar spells, Protectra/Shellra) visibly steps forward, gets yanked back toward its mage slot, forward again — "a couple times before going all the way." User observed it stop, cast a cure, then keep walking. Cosmetic; the cast eventually happens. Not judged bad enough to fix yet.

## Root cause
AoE positioning sets `state.roleMovementTarget` (centroid of missing-effect party members) in `ai_magic.party_aoe_move_target` (`modules/singleplayer/bots/ai_magic.lua:1272`). That field is **consume-on-read** — `ai_move.lua:431-436` clears it every tick, so the role must re-set it every tick to keep walking. The positioning branches sit mid-cascade (`can_bar_spell` `ai_magic.lua:3269`, `can_protectra_or_shellra` `3284`), below all cure/status branches. On any tick a higher branch wins it casts and sets no movement target → `ai_move` falls through to formation → drags the mage back to its 15-17y slot. Next tick positioning re-fires → forward again. That alternation is the stutter.

Mostly benign: cures *should* preempt, and the dance is a self-gated one-shot (`can_protectra`/`can_shellra`/`can_bar_spell` only fire while the BOT itself lacks the effect; once it self-casts, the branch goes quiet).

## Why NOT to just kill consume-on-read
Consume-on-read is load-bearing safety (`ai_move.lua:428-430`): a forgotten/stale target costs one tick of wrong movement, never a permanent lock. Making `roleMovementTarget` sticky means every role must explicitly clear it in every no-longer-applies branch; any missed clear = a bot wandering to a stale coord until overwritten. Whole class of "why is this bot walking away" bugs. Do not do this to fix a cosmetic stutter. User agreed.

## The lease-hold option (the surgical fix if we ever implement)
Smooths the stutter WITHOUT giving up consume-on-read — it only suppresses the yank-back for a beat, never latches a target.
1. When a positioning branch sets `roleMovementTarget`, also stamp a short lease: `state.aoeHoldUntilMs = now_ms + ~1500` (~2-3 ticks). Use the existing ms pattern `math.floor(os.time()*1000 + (os.clock()%1.0)*1000)` (see `ai_util.lua:128`, `ai_move.lua:75`).
2. In `ai_move.lua`'s fallback (the `roleMovementTarget == nil` path, after line 436), if the lease is still live AND the bot is a mage role (`ai_util.isMageRole`), **hold** — `break` without stepping — instead of running formation.
- Effect: on a cure-preempted tick the mage stands still instead of being dragged back; it only ever HOLDS, never forces forward motion, so it can't fight a cure's in-progress cast or walk deeper into danger than it already chose. Auto-expires so formation safety resumes once the buff need ends.
- Cost: mage may linger near the cluster up to ~1.5s longer after finishing. Minor.

## Do NOT "fix" the cast-gating
`party_aoe_move_target` gates the cast on ALL missing members in range (`anyOut`, `ai_magic.lua:1296-1300`) but walks to the arithmetic-mean centroid. Tempting to loosen `anyOut` to "cast when the cluster is in range," but the self-gate means once the WHM self-casts the branch stops, so a straggler left out of range never gets a re-cast from this path (relies on the separate idle-tick smart-refresh). Strict `anyOut` is therefore protective — loosening makes straggler coverage WORSE. Leave it.
