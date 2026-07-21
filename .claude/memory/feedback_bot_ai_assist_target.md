---
name: feedback-bot-ai-assist-target
description: In bot AI, the alliance's current target is an INDEPENDENT state field (xi.singleplayer.bots.alliance.allianceTarget, a serverId) — NOT derived live from primary.currentTargetId, nor from the assist/tank's getTarget(). This is a payoff of the backend port (bot AI moved server-side, out of the old client-side Ashita addon). Read it via get_alliance_target_id() / ai_threat.alliance_target(bot). assist:getTarget() is only a SEED source now.
metadata:
  type: feedback
---

## The rule (current)

In bot AI code (`modules/singleplayer/bots/*.lua`), "the mob the alliance is fighting" is a **single, independent piece of state**:

- `xi.singleplayer.bots.alliance.allianceTarget` — a serverId (0 = none).

Read it, do not re-derive it:
- `xi.singleplayer.bots.get_alliance_target_id()` → the id (bots.lua) — returns 0 when none.
- `ai_threat.alliance_target(bot)` → the resolved entity (`GetEntityByID(id)`, nil when 0).

Write it only through the intended writers:
- `xi.singleplayer.bots.set_alliance_target(id)` (bots.lua) — also clears open interrupt / stun windows when clearing to 0.
- The player command path (`/be-attack`) — an explicit user pick always wins.
- The puller handoff (`ai_puller` calls `set_alliance_target` when it drops a pulled mob).
- `ai_threat.ensure_alliance_target(bot)` — the auto-populate path (below).

## What the backend port changed

"BE" = **backend**. This whole bot AI stack used to live client-side in the ffxi-ashita addon; it was ported to run server-side in LSB (`modules/singleplayer/bots/`). That backend port is what let us handle alliance targeting properly — the target now lives in server-authoritative state, **decoupled from any single character**:

- ORIGINAL (client-side Ashita): the addon packet-sniffed the assist's swing events to figure out "the mob" — no server state, no authority.
- EARLY PORT (wrong): "the mob" was read live from `primary.currentTargetId`.
- INTERIM (better, but still per-character): resolve it live from the assist's `getTarget()`.
- NOW: `alliance.allianceTarget` is its own field. It is NOT `primary.currentTargetId`, and it is NOT "whatever the assist/tank is swinging at" read live. Those characters only *seed* the field; once set, the state is authoritative and independent.

`primary.currentTargetId` is still the user's commanded target and can diverge — never use it as "the mob."

## How the field gets populated

`ai_threat.ensure_alliance_target(bot)` only writes when `allianceTarget == 0` (so a player command / puller handoff always wins). In priority order:
1. Player command already set it → left alone.
2. Assist is engaged → seed from `assist:getTarget()` (the "assist pulled something, fan out" case). This is the ONLY place assist:getTarget() feeds in now — as a seed, not the live source.
3. Otherwise → promote the most-vulnerable off-target threat (mage > low melee > medium > healthy > tank) so adds going for the back line get focused first.

It clears naturally on mob death (`bots_listeners` zeroes it when the dead id matches; `set_alliance_target(0)` also tears down interrupt windows).

## Why this matters / defensive habit

When writing bot-AI code that needs "the mob being fought," READ the alliance-target state (`get_alliance_target_id()` / `ai_threat.alliance_target(bot)`). Do NOT re-derive it from `primary.currentTargetId` and do NOT reach into the assist/tank to read their live `getTarget()` — that reintroduces the per-character coupling the port removed, and the two can diverge from the authoritative alliance target.

## Symptoms when you get this wrong

- RDM/WHM casts Haste/Cure long after the mob died (stale per-character target; alliance target already cleared)
- Headless don't focus the right mob when the user commands a target the assist couldn't engage
- Range checks pass against a corpse
- Sleep/AoE exclusion sleeps the actual main mob because the exclusion used the wrong reference instead of `allianceTarget`

## Linked

[[feedback-lsb-party-vs-alliance-scope]], [[feedback-build-cadence]], [[feedback-singleplayer-rules]]
