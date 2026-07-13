# Cascade Manifest Extraction

A procedure for an LLM agent (Claude session) to read LSB quest/mission scripts and emit a static manifest of completion rewards. Re-run when scripts change.

The manifest drives the **account-wide progression cascade** (`#178`): when any character completes a quest, every other character — including future alts and headless bots — inherits the completion + rewards. The runtime side only records *that* completions happened; this manifest tells the cascade *what to grant*.

---

## Goal

Produce `singleplayer/data/cascade_manifest.json` (or `singleplayer/data/...` post-reorg). One entry per quest, one per mission. Single source of truth for cascade rewards.

The output is read at first-login / alt-cascade time. The DB only stores `(log_id, quest_id, first_char_id, completed_at)` — it doesn't store rewards.

---

## When to run

- After non-trivial edits to `scripts/quests/**` or `scripts/missions/**`
- After changes to `scripts/globals/npc_util.lua` (the param shape may have shifted)
- After changes to `scripts/quests/jeuno/helpers.lua` (helper-class base rewards)
- Periodically as a sanity check (monthly cadence is fine — quest scripts are stable)

To run: paste this file's contents into a fresh Claude session with the prompt **"Execute this procedure."**

---

## Inputs

| Path | Purpose |
|---|---|
| `scripts/quests/**/*.lua` | ~533 quest scripts |
| `scripts/missions/**/*.lua` | ~396 mission scripts |
| `scripts/globals/interaction/quest.lua` | `Quest:new`, `Quest:complete` |
| `scripts/globals/interaction/mission.lua` | `Mission:new`, `Mission:complete` |
| `scripts/globals/npc_util.lua` | `npcUtil.completeQuest`, `npcUtil.completeMission` — the param contract |
| `scripts/quests/jeuno/helpers.lua` | Helper base classes: `UnlockingAMyth`, `BorghertzQuests`, `GobbiebagQuest` |
| `scripts/globals/quests.lua` | Per-area quest ID constants (`xi.quest.id.<area>.<NAME>`) |
| `scripts/globals/missions.lua` | Per-log mission ID constants (`xi.mission.id.<log>.<NAME>`) |
| `scripts/enum/quest_log.lua` | Numeric `log_id` per area (`xi.questLog.<AREA>`, e.g. `JEUNO = 3`) |
| `scripts/enum/fame_area.lua` | Numeric fame-area constants (`xi.fameArea.<AREA>`) |
| `scripts/enum/item.lua`, `scripts/enum/key_item.lua` | Numeric item / key-item IDs for reward resolution |

---

## Output schema

`singleplayer/data/cascade_manifest.json`:

```jsonc
{
  "schema_version": 1,
  "generated_at": "2026-06-10T00:00:00Z",
  "source_commit": "<git sha>",
  "quests": {
    "<LOG_ID>:<QUEST_ID>": {
      "log_id": 3,                        // numeric (e.g. xi.questLog.JEUNO == 3)
      "log_name": "JEUNO",                // human-readable
      "quest_id": 128,
      "quest_name": "IN_DEFIANT_CHALLENGE",
      "source_path": "scripts/quests/jeuno/LB01_In_Defiant_Challenge.lua",
      "helper_base": null,                // e.g. "xi.jeuno.helpers.BorghertzQuests" for helper-class quests; null if direct Quest:new
      "rewards": {
        "items":     [{ "id": 4321, "qty": 1 }, ...],   // numeric id; ALL branches if multi-choice
        "keyItems":  [1234, ...],         // numeric
        "fame":      30,
        "fameArea":  "JEUNO",
        "gil":       0,
        "bayld":     0,
        "title":     "HORIZON_BREAKER",   // title constant name (kept symbolic, not numeric)
        "var":       { "Quest[3][128]Var": 1 },
        "exp":       2000                 // OPTIONAL: emit only when non-zero. Captured for completeness; cascade ignores it today (per-char), but kept in case the policy changes.
      },
      "post_complete_grants": {
        "setLevelCap":           55,      // numeric or null
        "setNewMainJobMaxLevel": null,
        "unlockJob":             null,    // job constant name (e.g. "BRD") or null
        "unlockWeaponskill":     null,    // wsUnlock constant name (e.g. "BLADE_KAMU") or null — UnlockingAMyth helper + Axe the Competition
        "expandInventory":       null,    // inventory slots added (e.g. 5) or null — Gobbiebag questline (changeContainerSize)
        "addGil":                null     // post-complete addGil, separate from rewards.gil
      },
      "branching": null,                  // or { "type": "choose_one_of_many", "options": ["RAJAS_RING", "SATTVA_RING", "TAMAS_RING"] }
      "notes": "Helper-class quest; reward derived from UnlockingAMyth base."
    }
  },
  "missions": {
    "<LOG_ID>:<MISSION_ID>": {
      // same shape as quests, plus:
      "rank":        null,                // numeric or null
      "rankPoints":  null,
      "nextMission": null                 // [logId, missionId] or null
    }
  },
  "unparseable": [
    { "path": "scripts/quests/...", "reason": "No Quest:new() found", "category": "quest" }
  ]
}
```

**Branching rule:** in singleplayer, the player gets all options. Always flatten `branching.options` into `rewards.items` so the cascade just delivers everything. Keep `branching` populated for traceability.

---

## Procedure

### Step 0 — preflight

1. `cd /home/nate/Desktop/git/LandSandBoat`
2. `git rev-parse HEAD` → record as `source_commit`
3. `mkdir -p singleplayer/data`
4. Read these four contract files — the ground truth for the reward-param shape:
   - `scripts/globals/npc_util.lua` (`completeQuest` / `completeMission` param contract)
   - `scripts/globals/interaction/quest.lua` (`Quest:complete`)
   - `scripts/globals/interaction/mission.lua` (`Mission:complete`)
   - `scripts/quests/jeuno/helpers.lua` (helper base classes)

### Step 1 — discover candidate files

```bash
find scripts/quests -type f -name '*.lua' | sort > /tmp/quests.txt
find scripts/missions -type f -name '*.lua' | sort > /tmp/missions.txt
```

Both lists exclude `helpers.lua` and any pure-utility files. ~533 quests, ~396 missions expected.

### Step 2 — per-file extraction (quests)

For each file:

1. **Find the identity binding** — one of:
   - `local quest = Quest:new(<AREA>, <QID>)` → most common (~85%)
   - `local quest = xi.<area>.helpers.<HelperClass>:new(<args>)` → helper-class (~10%, all in `scripts/quests/jeuno/`)
   - Some quests have no `quest` binding at all (dominion ops, tutorials) — record as completion-only

2. **Resolve `(log_id, quest_id)`**:
   - Map `<AREA>` to numeric `log_id` via `xi.questLog.<AREA>` (constants in `scripts/enum/quest_log.lua` — e.g. `JEUNO = 3`)
   - Map `<QID>` to numeric via `xi.quest.id.<area>.<NAME>` (in `scripts/globals/quests.lua`)
   - `fameArea` constants are in `scripts/enum/fame_area.lua`; item / key-item IDs in `scripts/enum/item.lua` and `scripts/enum/key_item.lua`
   - Helper-class quests pass these through their base class; trace the `Quest:new(...)` call inside the helper

3. **Find `quest.reward`** — a module-level `quest.reward = { ... }` assignment. Extract these fields (anything missing → null/empty):
   - `item` — number, table `{ id, qty }`, or list of either. Always normalize to `items: [{id, qty}]`.
   - `itemParams` — pass through if present
   - `keyItem` — number or list → normalize to `keyItems: []`
   - `fame` and `fameArea` — numeric / area constant
   - `gil`, `bayld`, `exp` — numeric (`exp` does NOT cascade — capture for completeness, cascade ignores it)
   - `title` — title constant name
   - `var` — table of `(name, value)`

4. **Find the function calling `quest:complete(player)`** — usually inside `quest.sections[].onEventFinish`. Within that function (including the `if quest:complete(player) then ... end` block), look for these explicit grants:
   - `player:setLevelCap(N)` → `post_complete_grants.setLevelCap = N`
   - `player:setNewMainJobMaxLevel(N)` → same
   - `player:unlockJob(xi.job.X)` → record `"X"`
   - `player:addLearnedWeaponskill(xi.wsUnlock.X)` → `post_complete_grants.unlockWeaponskill = "X"`
     - The `UnlockingAMyth` helper (20 quests) and `Axe_the_Competition` grant a weaponskill, **not** an item/keyItem
   - `player:changeContainerSize(xi.inv.INVENTORY, N)` → `post_complete_grants.expandInventory = N`
     - The `Gobbiebag` questline (10 quests); the bag expansion is NOT an item reward
   - `player:addGil(N)` **outside** `quest.reward` → `post_complete_grants.addGil = N`
     - Example: `scripts/quests/windurst/Mihgos_Amigo.lua` has a CS-baked gil amount given after `quest:complete`

5. **Branching detection** — within the same flow function, look for:
   - A table of item IDs indexed by `option - N` (e.g., `ringItems[option - 4]`)
   - Conditional `npcUtil.giveItem` calls (`if option == 5 then giveItem(A) elseif ... `)
   - Examples to model on:
     - `scripts/missions/cop/8_4_Dawn.lua` — three rings (Rajas/Sattva/Tamas)
     - Search for similar pattern elsewhere

   When found:
   - Set `branching = { "type": "choose_one_of_many", "options": [...] }`
   - Flatten ALL options into `rewards.items` — singleplayer gives all

6. **Cleanup ops (ignore but log)** — these do NOT go in the manifest:
   - `player:delKeyItem(...)`
   - `player:confirmTrade()`
   - `player:setLocalVar('mustZone', 1)` / `quest:setMustZone(player)`
   - `player:setVar('Timer', ...)`
   They're safe no-ops on alts.

7. **Mid-quest grants are NOT completion rewards.** Only capture what is granted at or after `quest:complete(player)`. Specifically EXCLUDE:
   - Items / KIs handed out during mid-quest battlefield sections (e.g., `LB05_1_Shattering_Stars` grants `MAAT_MASHER` and `SCROLL_OF_INSTANT_WARP` mid-quest, neither is a completion reward)
   - KIs granted by an interim event option (e.g., `LB06_New_Worlds_Await` grants `LIMIT_BREAKER` via event option 4, mid-quest)
   - Optional KIs gated by user choice mid-quest (e.g., `Community_Service` grants `LAMP_LIGHTERS_MEMBERSHIP_CARD` outside `quest.reward`, behind an option gate)
   - "Begin" hooks adding chained quests (e.g., `Mysteries_of_Beadeaux_I` calls `addQuest(MYSTERIES_OF_BEADEAUX_II)` on begin — this is a state-machine transition, not a reward; the chained quest gets its own manifest entry)
   - Repeat-path grants (e.g., `Ducal_Hospitality` re-grants 4000 gil + fame on the repeat path via `giveCurrency`/`addFame`; capture the first-time reward only)
   - Currency SINKS (e.g., `The_Road_to_Aht_Urhgan` has `delGil(500000)` — that's a cost, not a reward)
   Note it in the entry's `notes` field for audit, but leave it out of `rewards` / `post_complete_grants`.

### Step 3 — per-file extraction (missions)

Identical to Step 2 but:

- Identity: `Mission:new(<LOG>, <MID>)` instead of `Quest:new`
- Look up via `xi.mission.log_id.<LOG>` and `xi.mission.id.<log>.<NAME>`
- `mission.reward` additionally accepts:
  - `rank` — numeric
  - `rankPoints` — numeric
  - `nextMission` — `{ logId, missionId }`
- A small subset of RoV missions call `player:completeMission(log, mid)` directly without going through `Mission:complete`. These show up with no `mission.reward` block. Record as completion-only (empty rewards).

### Step 4 — helper-class resolution

For files where identity is `xi.jeuno.helpers.<Class>:new(...)`:

1. Read `scripts/quests/jeuno/helpers.lua`
2. Find the class definition (e.g., `xi.jeuno.helpers.UnlockingAMyth = {}` and its `:new` method)
3. The helper may set `quest.reward` inside its `:new` based on constructor args (e.g., `BorghertzQuests` sets `quest.reward.item = params.handAFId`), OR grant outside `quest.reward` in the `quest:complete` block (e.g., `UnlockingAMyth` calls `addLearnedWeaponskill`)
4. Resolve args from the caller, evaluate symbolically against the helper, emit the resulting rewards
5. Set `helper_base` to the qualified name for traceability

Known helpers:
- `xi.jeuno.helpers.UnlockingAMyth` — sets **no** `quest.reward`. Grants `player:addLearnedWeaponskill(wsUnlock)` (job-specific) in the `quest:complete` block; the player keeps the traded-in vigil weapon (net zero). Record under `post_complete_grants.unlockWeaponskill`, NOT as an item/keyItem.
- `xi.jeuno.helpers.BorghertzQuests` — `quest.reward.item = params.handAFId` (AF gloves per job). The 2 optional AF pieces per job come from Treasure Coffers (`xi.treasure.onTrade`), not `quest.reward`, and are not captured.
- `xi.jeuno.helpers.GobbiebagQuest` — `quest.reward` carries only `fame`/`title`; the bag expansion is `player:changeContainerSize(xi.inv.INVENTORY, +5)` (and MOGSATCHEL) in the `quest:complete` block. Record under `post_complete_grants.expandInventory`, NOT as an item.

### Step 5 — known special cases

| Case | How to record |
|---|---|
| **Dominion ops** (`scripts/quests/abyssea/*Dominion_Op*.lua`) | `quest.reward = {}`. Completion is fired by `xi.abyssea.dominionOnMobDeath`, not `quest:complete`. Record entry with empty rewards. |
| **Tutorial / starter** | Often bypass standard flow. Manifest entries should have whatever rewards are statically discoverable + a note. |
| **Direct `player:completeQuest(...)` calls** without Quest:complete | Entry with empty rewards (the runtime hook still records the completion). |
| **Branching choice quests** (e.g., `Apocalypse_Nigh` 4 earrings, `cop/8_4_Dawn` 3 rings) | All options flattened into `items[]`. `branching.type = "choose_one_of_many"`, populate `options` with the symbolic names. |
| **Gender variants** (e.g., `DNC_AF2_The_Road_to_Divadom` grants `DANCERS_TIGHTS_M` or `_F`) | Both variants in `items[]`. `branching.type = "gender_variant"`, options name both. Same flatten-all rule. |
| **Race / RSE variants** (e.g., `The_Goblin_Tailor` — 7 races × 4 pieces, player gets 1 piece for their race) | All 28 items flattened into `items[]`. `branching.type = "race_and_choice_variant"`, options name the schema. ACCEPT the over-grant — singleplayer policy. |
| **CS-baked gil/items** | If grant is outside `quest.reward` after `quest:complete`, capture under `post_complete_grants`. |
| **`exp` reward** | Captured in `rewards.exp` (emit only when non-zero). Cascade explicitly excludes it (per-char by design), but kept in the manifest so the policy can change without re-extracting. |
| **Repeatable quests** (e.g., `Ducal_Hospitality`) | Capture FIRST-TIME reward only. Note the repeat-path grant in `notes`. |
| **DISABLED completion** (e.g., `Unlisted_Qualities` — `quest:complete` block commented out) | Record entry with empty rewards and a note explaining the disable reason + intended reward. Cascade no-ops on it; future re-extraction picks up the real reward when the code is re-enabled. |
| **Mog House / world-flag side effects** (e.g., `Pretty_Little_Things` calls `setMoghouseFlag`) | Out of cascade scope. Note in entry, do not emit. |

### Step 6 — emit manifest

Write the JSON to `singleplayer/data/cascade_manifest.json`. Pretty-print (2-space indent) for diff readability.

### Step 7 — verification (REQUIRED)

Sanity check by hand-checking these specific entries against source:

- `Forge_Your_Destiny` (SAM job quest) — expected: fame=30 / NORG, item=MUMEITO, title=BUSHIDO_BLADE, `unlockJob: "SAM"`
- `LB01_In_Defiant_Challenge` — expected: fame=30 / JEUNO, title=HORIZON_BREAKER, `setLevelCap: 55`
- `LB10_Beyond_Infinity` — expected: `setLevelCap: 99`
- `Unlocking_A_Myth_NIN` — helper-class resolved; expected: **no item/keyItem reward**, empty `rewards`; `post_complete_grants.unlockWeaponskill: "BLADE_KAMU"` (helper calls `addLearnedWeaponskill`)
- `cop/8_4_Dawn` — expected: branching populated with 3 rings, `items[]` contains all 3
- `bastok/1_1_The_Zeruhn_Report` — empty `mission.reward` (no static rewards)
- `Mihgos_Amigo` — expected: `post_complete_grants.addGil > 0`

If any verification entry doesn't match: stop, investigate, fix the procedure, re-run.

### Step 8 — report

End with a one-screen summary:
- Quest count / mission count parsed
- Unparseable count (and their reasons)
- Helper-class resolutions
- Branching cases found
- Diff vs previous manifest if one existed (additions, removals, changed rewards)

---

## Conventions reference (from the scan)

`npcUtil.completeQuest` params (the contract):

```
item        -> number | {id, qty} | [{...}]
itemParams  -> opaque, pass-through
keyItem     -> number | [number]
fame        -> number
fameArea    -> area constant
gil         -> number
bayld       -> number
exp         -> number (NOT cascaded)
title       -> title constant
var         -> { name = value }
```

`npcUtil.completeMission` additional fields:

```
rank        -> number
rankPoints  -> number
nextMission -> {logId, missionId}
```

Identity bindings observed:

```
Quest:new(area, qid)                                ~85% of quests
xi.jeuno.helpers.<Class>:new(<args>)                ~10% of quests (all jeuno)
no class binding / direct completeQuest calls       ~5%
Mission:new(log, mid)                               most missions
direct player:completeMission                       small subset of RoV
```

Post-complete grant functions (cascade-relevant):

```
player:setLevelCap(N)               LB quests; LB01→55, LB05→75, LB10→99 are the canonical examples
player:setNewMainJobMaxLevel(N)     late-game LBs
player:unlockJob(xi.job.X)          job advanced quests (BRD/BST/DNC/etc.) → unlockJob
player:addLearnedWeaponskill(ws)    UnlockingAMyth helper (20 quests) + Axe the Competition → unlockWeaponskill
player:changeContainerSize(inv, N)  Gobbiebag questline (10 quests) → expandInventory
player:addGil(N)                    quests where CS dialog bakes the gil
```

Post-complete cleanup functions (NOT cascaded — safe no-op on alts):

```
delKeyItem, confirmTrade, setMustZone, quest:setMustZone,
setLocalVar, setVar, addMission, setMissionStatus
```

---

## Known limitations

- **Conditional grants based on job/level** — if a quest has `if player:getMainJob() == X then unlockJob(Y)`, the manifest captures the symbol. The cascade applies it unconditionally to all alts. Acceptable in singleplayer.
- **Helper-class introspection** — the procedure trusts that `helpers.lua` mirrors the standard `quest.reward` shape. If a helper deviates (e.g., conditional rewards inside `:new`), the LLM must walk the helper's logic and emit accordingly.
- **Quest scripts changing behavior between calls to `quest:complete`** (e.g., a quest that calls complete twice with different rewards) — not seen in current scan, but possible. Record both reward sets if found; cascade unions them.
- **Quests that gate on character state at completion time** (e.g., "if you're not WHM you get X, else Y") — capture the union, accept slight over-granting on alts.

---

## Cascade application (out of scope here, but for context)

How the cascade actually applies the manifest at login time, briefly:

1. Trigger: first login per char (existing override hook), or detected via `char_cascade_state.last_quest_cascade_at`
2. Query: `SELECT log_id, quest_id, completed_at FROM account_quests WHERE completed_at > char.last_quest_cascade_at`
3. For each row:
   - Load manifest entry by `<log_id>:<quest_id>`
   - Mark `player:completeQuest(log, qid)` (sets the in-game flag)
   - Deliver `rewards.items` and `rewards.keyItems` via delivery box (not direct inventory)
   - Apply `rewards.fame` via `player:addFame(area, n)`
   - Apply `rewards.gil`, `rewards.bayld` via the respective currency add
   - Apply `rewards.title` via `player:addTitle`
   - Apply `post_complete_grants.setLevelCap` / `setNewMainJobMaxLevel` / `unlockJob` / `addGil` if set
   - Skip `exp` (per-char by design)
4. Update `char_cascade_state.last_quest_cascade_at = NOW()`

Same flow for missions including `rank`, `rankPoints`, `nextMission`.

---

## Future improvements

- Audit mode: run extraction and diff against runtime-captured grants (if any quest's first-completion sees different rewards than the manifest predicted, log a warning). Requires runtime instrumentation, not in initial scope.
- Generate the manifest from CI on quest-script changes, not just on demand.
