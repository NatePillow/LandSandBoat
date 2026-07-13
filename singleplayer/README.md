# Singleplayer LSB fork

A fork of LandSandBoat (Final Fantasy XI server emulator) targeting a single human player + headless AI alliance. The goal is the experience of FFXI's mid-game group content as one-player content, with headless bots filling out the alliance and a server-side AI driving their behavior.

This README is the project-level overview and TODO landscape. Module-specific docs live alongside the code:

- `modules/singleplayer/bots/docs/STATE.md` — state-table inventory and dedup history
- `modules/singleplayer/bots/docs/LISTENERS.md` — server-side listener wiring
- `modules/singleplayer/bots/docs/DEPS.md` — bot module dependency graph
- `singleplayer/docs/bar_spell_recommendations.md` — Bar* spell selection reference
- `singleplayer/docs/pricingupdate/README.md` — auction-bot pricing pipeline

## Layout

```
singleplayer/
  client/   Ashita addons + launcher assets (never under modules/, which is the server's hot-reload root)
  config/   Disk JSON: alliance/<name>.json + other server-side config
  data/     Static reference data
  docs/     Project docs
  scripts/  Custom scripts including Default.txt

modules/singleplayer/bots/
  bots.lua + bots_*.lua + ai_*.lua + role_*.lua
  Hot-reloaded by LSB's FileWatcher on touch
```

## Architecture (server-side bot AI)

Two state layers:

1. **Alliance (`xi.singleplayer.bots.alliance`)** — singleton shared across every bot in the player's alliance. Holds `allianceTarget`, `roleMap`, `headlessCharIds`, `sc[]` (skillchain pairs), `solo`, `parties` (party leaders + trust lists), `assistCharId`, `mainCharId`, `mainEntity`, formation state (`battleFormation`, `walkingFormation`, `campAnchor`), candidate pools (`provokePool`, `stunPool`, `rdmSleepPool`, `blmSleepPool`).
2. **Per-bot scratch (`xi.singleplayer.bots.alliance.bot[charId]`)** — lazy-inited by `bots.ensure_bot(charId)`. Single home for every per-bot tick field (ability/magic/role/lot/rest/move) — no module-local scratch tables.

Decision flow per bot per tick:
- `bots.runCombatTick(bot, state)` dispatches based on `alliance.roleMap[botId]`
- Each role module (`role_tank`, `role_heal`, `role_nuke`, `role_rdm`, `role_melee`, `role_skillup`) defines `tick(bot)` as a priority cascade
- Helpers in `ai_ability` / `ai_magic` / `ai_threat` / `ai_util` provide reusable predicates and actions
- Engine state is preferred over bot-side bookkeeping wherever possible (notoriety lists, status effects, target tracking)

## Disk config schema

`singleplayer/config/alliance/<name>.json`:

```json
{
  "alliance": [
    { "ptLeader": "Brutus",   "members": ["Penelope", "Minerva", "Ruby", "Ollie", "Astrid"] },
    { "ptLeader": "Varunius", "members": ["Zariah"],  "trusts": ["Shantotto", "Ulmia", "Joachim", "Karaha-Baruha"] },
    { "ptLeader": "Malfina",  "members": ["Freya"],   "trusts": ["Shantotto", "Ulmia", "Joachim", "Karaha-Baruha"] }
  ],
  "roles": {
    "tank":   ["Brutus"],
    "melee":  ["Freya", "Zariah", "Varunius", "Malfina", "Locke", "Edgar"],
    "heal":   ["Penelope"],
    "rdm":    ["Minerva"],
    "nuke":   ["Ruby", "Ollie", "Astrid"]
  },
  "sc": [
    { "priority": 1, "openName": "Freya",    "openWS": "Vorpal Thrust", "closeName": "Zariah",  "closeWS": "Dancing Edge" },
    { "priority": 2, "openName": "Varunius", "openWS": "Raging Rush",   "closeName": "Malfina", "closeWS": "Raging Fists" }
  ],
  "solo": {
    "Brutus": "Seraph Blade",
    "Locke":  "Wasp Sting",
    "Edgar":  "Penta Thrust"
  }
}
```

`bots_spawn.validate_config(cfg)` runs at load and checks every char name exists in some party's members, every WS resolves via `GetWeaponskillByName`, every trust resolves via `xi.magic.spell.*`. Validation errors abort the spawn.

### Role derivation

`bots_spawn.derive_role(name, cfg)` maps char names to `xi.singleplayer.bots.Role` values. Order matters — the first match wins:

1. `Role.Healer` ← in `roles.heal`
2. `Role.Rdm` ← in `roles.rdm`
3. `Role.Nuker` ← in `roles.nuke`
4. `Role.Tank` ← in `roles.tank` (single-element list; the tank IS the assist target)
5. `Role.Melee` ← in `roles.melee`
6. `Role.Idle` ← everything else

`roles.tank` is a single-element list — there's exactly one tank per alliance, and they're the char other bots assist for target selection. `roles.melee` is the canonical melee list — every melee DD must be listed there.

`cfg.sc[]` (SC pairs) and `cfg.solo` (solo WSes) are **WS assignments**, orthogonal to role. Every name in `cfg.sc[].openName/closeName` or `cfg.solo` keys must be in `roles.melee` OR be the `roles.tank` entry — that's how the tank gets to participate in SC or solo WSes. Validator errors look like `sc[0].openName: "Freya" must be in roles.melee or roles.tank` and abort the spawn.

## Roadmap / TODO landscape

The live source of truth is the in-session task list. Highlights of pending work below — task numbers reference that list.

### Engine-derivation refactor
Group of related cleanups moving bot-side state to engine reads where possible. Largely complete:

- ✅ `nm` → composite engine check (NM bit + battlefield + dynamis + notoriety scan)
- ✅ SC/MB state → `EFFECT_SKILLCHAIN` engine reads + `getStartTimeMs` Lua binding
- ✅ `activeAdds` / `newAdds` → stateless priority-chain rescan (`ai_threat.peelable_for`)
- ✅ `silenceTargets` → engine notoriety scan
- ✅ `currentTargetId` → `alliance.allianceTarget` (single source of truth, command preempts, assist leads when empty)
- ✅ Multi-pair SC config (`cfg.sc[]` array form, runtime `alliance.sc[]` with charIds + WS + priority)
- ✅ Disk config semantic validation

### Outstanding behavior / feature tasks

| # | Task |
|---|---|
| #173 | Multi-engagement mode (per-party mobs) |
| #178 | Account-wide progression cascade (quests, missions, items, KIs, fame, currency) |
| #180 | Custom AI for instance fights (BCNM/ENM/etc.) |
| #182 | Battle music swap — FF series homage |
| #198 | One-click backup of user/server-specific data |
| #203 | Audit client-side addon data-retrieval patterns |
| #205 | Auto-accept Raise on headless bots |
| #208 | Smart back-off for high-resist mobs after N failed casts |
| #210 | Rest/move sit-stand flicker: instrument + fix (in progress) |
| #217 | Add brdPool to sleep rotation (between RDM and BLM) |
| #218 | Sleepga + WHM Repose handling (separate from single-target pools) |
| #219 | Mob-specific spell variant selection (dark-resist etc.) |
| #220 | Expand Role enum (SMN / BUFF / tank subtypes) as role files land |
| #222 | Trivial-NM filter (low-priority watch item) |
| #230 | Diff-based alliance config update + granular config ops (replace_bot, move_bot) |

### Recently completed (post-#215 cohort)

Carried here so the in-session task list doesn't have to be the only source of truth:

- #216 runtime candidate pool compilation (provoke / stun / bash / rdmSleep / blmSleep)
- #221 collapse all per-bot state into `alliance.bot[charId]`
- #223 collapse `xi.singleplayer.bots.primary[]` into alliance singleton
- #224 rename `roles.assist` → `roles.tank` schema-wide
- #225 tank-as-SC-participant (shared SC predicates on `ai_ability`)
- #226 emit `WEAPONSKILL_STATE_ENTER` for player WSes via engine change
- #227 AshitaCast spec parity (variable expansion, rule features, re-triggers)
- #228 move assist observation to `ai_util`; drop `activeTargets` cache
- #229 add `bashPool` + unify stun/bash window-flag retry; busy-actioning filter

### #230 — Diff-based alliance update (design notes)

Replaces the current "Update Alliance" flow (despawn-everyone-then-respawn) with a diff-based update so unchanged bots survive and only the delta gets touched. Lays groundwork for future single-bot ops (`replace_bot`, `move_bot`, `set_role` via UI). Deferred until bot AI work stabilizes — user will revise addon UIs after.

**Current flow and the bug that motivated this (already fixed separately):**
`Update Alliance` fires 0x176 DESPAWN_ALL then 0x175 SPAWN_HEADLESS back-to-back. Server processes both on one thread in order, so timing isn't the issue — the despawn left primary in a singleton party (alliance auto-dissolved, but `primary->PParty != nullptr` because primary itself was never removed). Then `formAllianceFromSpec`'s fail-closed gate (`if leader->PParty != nullptr` at `lua_bindings.cpp:301`) rejected the new spec. Symptom: bots spawned but stayed un-allianced and visually orphaned. User fixed this immediate bug by auto-disbanding primary's singleton party post-despawn; this design item is the longer-term restructure.

**Identity model.** Name (1:1 with charId; configs are name-keyed on disk).

**Diff partitions, computed against `alliance.bot[]` keys and `alliance.parties[]`:**
- `DROP` = in old, not in new → despawn
- `KEEP` = in both → survive, possibly with party or role reshape
- `ADD` = in new, not in old → spawn fresh

For each `KEEP`, classify the change kind: party assignment, role, SC pair membership, solo entry, leader-of-party status, or no-op. Partition into `KEEP_STATIC` (no-op) and `KEEP_RESHAPE` (something differs).

**Order of operations (single transaction):**
1. Compute the diff in Lua against `alliance.bot[]` + `alliance.parties[]`.
2. **Validation gate**: refuse if ANYONE in the alliance has hate (primary or any headless). Mid-fight party reshuffles produce too much weird state. User-facing fail mode: chat message "alliance state inconsistent, despawn and try again" — no rollback attempted.
3. `DROP`: per-bot `destroyHeadlessByCharId`. Engine handles cascading party/alliance dissolution as members empty.
4. Resolve party survival: for each new-config party slot, decide whether to reuse an existing CParty object (the one whose KEEP bots dominate it) or create new.
5. `KEEP_RESHAPE`: move bots between parties via `RemoveMember` + `AddMember`. Leader changes use `setLeader` if a binding exists, else remove+add in correct order.
6. `ADD`: `createHeadlessSession` per name, then `AddMember` to target party (which may auto-create the party if it's a fresh slot).
7. Alliance composition changes: if new config has more or fewer parties than current, `addParty` / `removeParty` on the alliance object. Likely needs new Lua bindings.
8. **Wipe ALL per-bot state.** Every `alliance.bot[charId]` (even for KEEP bots), every pool, `alliance.sc`, `alliance.solo`, `alliance.roleMap`, `alliance.parties` — clear and rebuild from the new config. SC pair ordering, solo WS targets, role assignments are too deep for partial preservation. Cleaner than carrying through stale scratch.
9. Re-roleify every bot via `onSetRole` from the new config.
10. Recompile pools (`ai_pool.compile_pools`).
11. Repopulate alliance runtime state (`parties`, `solo`, `sc[]`, `assistCharId`, `headlessCharIds`, `roleMap`).

**Decisions locked in design pass:**
- Combat check: refuse if anyone (primary or headless) has hate.
- Failure mode: print to chat, no rollback. User runs Despawn + Spawn to recover.
- UI preview of diff: deferred. Addon UIs are getting revised after bot AI stabilizes.
- State preservation on `KEEP`: wipe everything, rebuild fresh. Config changes are too structural to safely preserve scratch.

**Engine surface to verify/add:**
- `bot:partyAddMember(target)` / `partyRemoveMember(target)` — should exist; verify before relying.
- `party:setLeader(name)` — verify; if missing, leadership transfer falls back to remove + re-add in new order (more packets but works).
- `alliance:addParty(party)` / `removeParty(party)` — likely NOT exposed. Engine has CAlliance methods but lua_baseentity bindings are uncertain. If absent and they need adding, this is the main C++ work item. Could also fall back to teardown+rebuild for alliance-composition changes specifically (i.e., diff handles within-composition changes; full rebuild for 1pt ↔ 2pt ↔ 3pt transitions).

**Convenience wrappers built on the same diff engine** (Phase 2 once base works):
- `bots_spawn.replace_bot(primary, oldName, newName)` — single-bot drop+add
- `bots_spawn.move_bot(primary, name, newPartyIdx)` — single-bot reshape
- `bots_spawn.set_role(primary, name, role)` — already exists (`onSetRole`); just wrap and add to addon dispatch

**Implementation phases:**
1. Same party-structure case only (no addParty / removeParty needed). Diff handles KEEP/ADD/DROP within existing party objects.
2. Convenience wrappers + UI dispatch via new 0x176 sub-opcodes.
3. Alliance composition changes (needs engine bindings if absent).
4. Leadership transfers without remove+add (Phase 4 polish if setLeader binding worth adding).

**Edge cases to handle in compute_diff/apply_diff:**
- Primary's party assignment changes between configs (e.g. pt1 → pt2 member). Validation rejects — primary stays where the config places them; if config moves primary, treat as full-rebuild-required.
- Dead bot at update time: KEEP it, just change role/party. Spawn Dead is a separate user action.
- Cross-zone KEEP bot: treat as drop+add. Reshaping a bot in a different zone risks half-applied party state.
- Concurrent presses: lock behind an `alliance.update_in_progress` flag.
- Pet/trust handling: kept bots' trusts stay with their original leader; if leader changes, new leader inherits via the standard trust-queueing on spawn.

### Sleep / crowd-control rotation (#216 / #217 / #218 / #219)

The locked design has four single-target candidate pools — `provokePool`, `stunPool`, `rdmSleepPool`, `blmSleepPool` — built at spawn from `alliance.roleMap` + job capability and re-sorted per decision.

| Pool | Sort key | Floor |
|---|---|---|
| `provokePool` | HP% desc | HP% >= 30% |
| `stunPool` | MP% desc | enough MP to cast |
| `rdmSleepPool` | MP% desc | enough MP to cast |
| `blmSleepPool` | MP% desc | enough MP to cast |

Sleep precedence: `rdmSleepPool` → (`brdPool` future, #217) → `blmSleepPool`. Stun: any eligible caster (MP%-sorted). Provoke: HP%-sorted; the 30% floor prevents auto-pulling onto a near-dead tank.

Pool membership is **role-gated** (Tank/Melee for Provoke; Healer/Nuker/Rdm/Skillup for Stun + Sleep; plus Melee-DRK for Stun), and within the role gate we verify the actual ability/spell exists on the bot at compile time via `hasJobAbility` / `hasSpell`. A bot too low-level to have the action is never in the pool.

**Limitation:** `compile_pools` runs at alliance spawn. A bot that levels up mid-alliance into a new ability/spell won't enter the pool until the next spawn. Mid-alliance level-ups are rare; documented and accepted instead of fixing with a re-compile-on-level hook.

### Multi-pair SC staggering + rotation

`alliance.sc[]` is an ordered array; index 1 is "first up." Two interlocking rules:

1. **Stagger.** Pair K holds its opener if ANY pair at index < K has both ends >850 TP (already close to firing). If no higher-priority pair is close, pair K can open. Ports the original Ashita SC2-waits-for-SC1 logic and generalizes to N pairs. Implementation: `ai_ability.higher_priority_close(bot)`, gates `role_melee.should_start_sc`.
2. **Rotation.** When a pair's closer fires their configured closeWS, that pair moves to the END of `alliance.sc[]`. Combined with the stagger, this gives round-robin scheduling: each pair gets first refusal, then steps aside. If the front pair can't fire (low TP, dead, zoning), the stagger naturally lets the next pair go — skip-ahead emerges. Implementation: `fan_rotate_sc_on_close` action listener in `ai_ability.lua`.

Initial order comes from the `priority` field in each pair (sorted ascending at spawn). Runtime order then evolves with each successful close.

### Rest vs movement

Policy locked: **chase always wins**. The followee walking outside `restRange` (12y) breaks the bot's rest unconditionally — explicit > clever, gameplay/control concern.

Flicker fix landed: `ai_move.stepToward` stamps `state.lastMovedMs` whenever it actually moves the bot. `ai_rest.tick_one` checks that timestamp before re-adding HEALING — within 2.5s of a step, it skips with a rate-limited log line `[ai_rest] <name> flicker-guard: skipping HEALING (moved <N>ms ago)`. Tunable via `REST_GRACE_MS` in `ai_rest.lua`. Still needs in-game verification (#210) — watch for the guard log to fire when the followee parks right at the comfort boundary.

Deferred (not in initial #216 scope):
- **#217** — `brdPool` for Lullaby. Instrument resources + song duration complicate it.
- **#218** — Sleepga AoE branch (precondition: N+ awake adds in radius). WHM Repose (light-based; mob-resist-dependent).
- **#219** — Mob-specific spell variant selection (e.g. bats resist dark sleep — prefer Repose). Belongs at the spell-pick layer, not the pool layer.

Tiebreak across all pools is pool-array index for now; revisit only on observed bad behavior.

### Group C (schema rework)

Status: largely complete. Remaining items deferred:
- **C1.2 RoleType expansion** — add SMN, BUFF, PLD/NIN/RUN split — deferred until a corresponding `role_*` file exists for each.
- **C2.3 pool compilation** — see #216 above.

## Memory / conventions

- Project memory files live in `.claude/memory/` (version controlled).
- Addon-specific memory lives in `singleplayer/client/addons/.claude/memory/`.
- Hard rule: never run destructive git operations. See `feedback_never_destructive_git.md`.
- Build cadence: one foreground build at end of a multi-task push; never background; ask the user to run when possible.
- Diagnostic logs stay un-gated until the root cause is identified.

## Engine extensions (LSB C++)

Added to support the bot AI:
- `lua_statuseffect.cpp` — `getStartTimeMs()` for ms-precision status-effect start time (the existing `getStartTime` floors to seconds, too coarse for the SC close window).
- `luautils.cpp` — `GetWeaponskillProperties(wsId)` returning `{ primary, secondary, tertiary }` SC properties so Lua can decode `EFFECT_SKILLCHAIN.getPower()` for multi-pair correctness.

Modules under `src/map/singleplayer/`:
- `auction_bot.cpp` — homegrown auction-house bot replacing ffxiahbot.

## Deployment Topics

Operational considerations that aren't obvious from the codebase but matter when running this fork in a real setup.

- **Config HTTP server — port `51220` (default), needs to be reachable.** The map process spins up a `cpp-httplib` listener (`src/map/singleplayer/config_http_server.cpp`) that addons hit for all config CRUD (alliance, food, equip, lot). This replaced the old chunked-packet `0x17E/0x180/...` pipeline that was throwing wire-zlib errors on big AshitaCast XMLs. Anything that gates inbound TCP needs the port opened **on the server host** for the client to reach it — firewall on the Linux host, VM network forwarding, cloud SG rules, etc.

  Both the bind address and port are settings so end-users can adjust without recompiling:
  - **Server side** — `settings/singleplayer.lua`:
    - `CONFIG_HTTP_BIND_ADDR` — `'127.0.0.1'` (same-machine only), `'0.0.0.0'` (VM/LAN), or a specific interface IP.
    - `CONFIG_HTTP_PORT` — change if `51220` collides with something on the host.
  - **Client side** — top of `singleplayer/client/addons/libs/http_client.lua`:
    - `http_client.HOST` — the IP the client uses to reach the server (often the same address you use for FFXI server: `127.0.0.1` same-machine, `10.0.2.2` under VirtualBox/QEMU NAT, the Ubuntu box's LAN IP under bridged networking).
    - `http_client.PORT` — must match `CONFIG_HTTP_PORT` on the server.
  - Sanity check from the client machine: `curl http://<HOST>:<PORT>/healthz` returns `ok`.
