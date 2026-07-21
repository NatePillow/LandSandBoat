---
name: project-alliance-config-schema
description: alliance config (singleplayer/config/alliance/<name>.json) gotchas — role derivation is FIRST-MATCH-WINS (heal>rdm>nuke>tank>melee>idle); roles.tank is a single-element list and IS the assist target; every sc[].openName/closeName and every solo key MUST be in roles.melee OR be the tank; bots_spawn.validate_config ABORTS the spawn on any violation. Full schema in modules/singleplayer/bots/docs/ARCHITECTURE.md.
metadata:
  type: project
---

`singleplayer/config/alliance/<name>.json` shape: `alliance[]` (parties with `ptLeader` / `members` / `trusts`), `roles` (name → list), `sc[]` (SC pairs), `solo` (name → WS). Full annotated schema lives in `modules/singleplayer/bots/docs/ARCHITECTURE.md`.

Non-obvious rules that bite, all enforced by `bots_spawn.validate_config` (which **aborts the spawn** on any error):

- **Role derivation is first-match-wins** (`bots_spawn.derive_role`): `heal → rdm → nuke → tank → melee → else Idle`. A name in two role lists gets the earlier one.
- **`roles.tank` is a single-element list** — exactly one tank per alliance, and that char *is* the assist target every other bot follows for target selection.
- **SC/solo participants must be melee-or-tank**: every `sc[].openName` / `sc[].closeName` and every `solo` key must appear in `roles.melee` OR be the `roles.tank` entry. That's the *only* way the tank participates in SC / solo WSes. Violation reads like `sc[0].openName: "Freya" must be in roles.melee or roles.tank` and aborts.
- WS names resolve via `GetWeaponskillByName`; trust names via `xi.magic.spell.*`. Unresolvable → abort.

**Why:** `sc` and `solo` are WS *assignments*, orthogonal to role. It's easy to add a name there and forget it also needs a matching role-list entry — the spawn then silently refuses.

**How to apply:** when editing or generating an alliance config, cross-check every `sc`/`solo` name against `roles.melee`/`roles.tank` before spawning, and remember role order is priority, not additive.

[[feedback-bot-ai-assist-target]]
