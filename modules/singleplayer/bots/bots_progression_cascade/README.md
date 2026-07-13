# bots_progression_cascade — per-area recipe files

This directory holds the per-area recipe tables that drive the account-wide progression cascade for the singleplayer bot fork. The framework itself (factories, sync API, live-wrap, orchestration, sync_teleports_to, sync_hidden_trust_spells_to, AF1 coffer mirror) lives in the sibling file `../bots_progression_cascade.lua`. Each file in this directory registers its area's recipes into `xi.singleplayer.bots.bots_progression_cascade.recipes.<area>`.

## What is the cascade for?

When a primary character presses "Sync Quests" or "Sync Missions" in the AutoBots UI, the cascade walks primary's completed quest/mission history and applies each corresponding recipe to every headless character in the alliance. The goal is that **every headless character ends up identical to a fresh character who completed those quests/missions themselves** — same fame, gil, items, key items, titles, spells, currency, container size, job unlocks, weaponskill unlocks, rank, teleport bits, everything.

This is tedium reduction — a user with 5 headless bots shouldn't have to re-run "Trial by Earth" five times. See `feedback-singleplayer-rules.md` and `feedback-cascade-full-rewards.md` in the repo memory for the guiding philosophy.

## Architecture (three-part cascade)

1. **Recipe pass** (this directory) — hand-authored per-quest/per-mission entries with `apply(target)` closures that deliver everything the source quest hands out, including inline grants that live outside the `.reward` block. Recipes are the **single source of truth** for what a quest gives.

2. **Registry walk** (`registry_walk_target` in the framework file) — for the ~99% of quests that use `Quest:new`, calls `obj:complete(target)` which dispatches the quest's static `.reward` block via `npcUtil.completeQuest`. Automatically covers `.reward.item / .reward.gil / .reward.fame / .reward.title / .reward.keyItem / .reward.bayld / .reward.exp` and the mission equivalents. Skips anything the recipe pass already handled to avoid double-dispatch.

3. **Intentional bulk mirrors** (framework file) — three utility-system exceptions that are NOT reward-act driven but ARE cascaded per user policy:
   - `sync_hidden_trust_spells_to` — the 8 HiddenQuest trust spells
   - `sync_teleports_to` — homepoints, outposts, survival guides, waypoints, abyssea, campaign, eschan
   - `AF1_COFFER_ITEMS` mirror — the 30 canonical AF1 head/legs coffer-drop pieces
   See `feedback-cascade-intentional-exceptions.md`.

## Sync-button vs live-wrap

The **UI Sync buttons are authoritative** over the full back-catalog. They work when a user creates a headless months into their playthrough on a character that wasn't in the alliance when the original quests were completed. Recipes must work end-to-end via that path.

The **live-wrap** (`ensure_cascade_wrap` in framework) is a QoL bonus that hooks `npcUtil.completeQuest` / `completeMission` so primary's real-time completions replay to alliance headless without waiting for a button press. It **dispatches through the same recipe apply closure**, so the two paths deliver identical results. If the live-wrap breaks, the button path is unaffected.

Never propose replacing recipe transcription with live-wrap of primitive grants (`addGil`/`addFame`/`addCurrency` etc.) as the "core solution" — that only cascades forward from wrap-time and silently misses the back-catalog. See `feedback-cascade-sync-button-authoritative.md`.

## NO bulk value mirrors for reward-act state

Do NOT write `sync_X_to` functions that walk `xi.fameArea` or `xi.title` and copy primary's current accumulated value to target. Fame, gil, and titles all accumulate from many sources — quest rewards, mission rewards, kill fame, NPC turn-ins, loot sales, exploration achievements. Only the quest/mission reward sources are the cascade's responsibility. Bulk-copying total values over-grants headless with state they didn't earn from any specific reward act. See `feedback-cascade-no-bulk-value-mirror.md`.

Two historical bulk mirrors (`sync_fame_to`, `sync_titles_to`) were deleted when comprehensive per-quest recipes landed.

## Scope

Comprehensive recipe coverage is maintained for content through **Treasures of Aht Urhgan (ToAU)** — the last-in-scope expansion. Post-ToAU content is out of scope for new recipe work:

**In scope (full recipe coverage):** Bastok / Sandy / Windurst / Jeuno / otherAreas / outlands / hiddenQuests / tutorial / ahtUrhgan (ToAU) quests. Nation missions (Bastok / Sandy / Windy) / RoTZ / CoP / ToAU missions.

**Keep-existing only** (structural job/spell unlocks kept, no new inline-grant transcription):
- `crystalwar.lua` — WotG-added Scholar unlock (A_Little_Knowledge)
- `adoulin.lua` — SoA-added Geomancer unlock (Dances_with_Luopans) + Coalition action KIs
- `missions_soa.lua` — SoA Pioneer_Registration (structural KI)

**Out of scope entirely (no coverage):**
- Abyssea quests
- WotG missions
- SoA missions (except Pioneer_Registration)
- ACP / AMK / ASA "mini-expansions" (2009-2010 add-on scenarios)
- RoV (Rhapsodies of Vana'diel)
- TVR (The Voracious Resurgence)

If a future user wants to extend coverage into any of these expansions, follow the analysis procedure below and add per-area files as needed.

## Registering a recipe

Each file in this directory follows the same shape:

```lua
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_<area>')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local quest   = cascade.quest    -- factory exposed on module table
local mission = cascade.mission

do
    local bq = xi.questLog.BASTOK
    local q  = xi.quest.id.bastok

    cascade.recipes.bastok = {
        quest(bq, q.WELCOME_TO_BASTOK, 'scripts/quests/bastok/Welcome_to_Bastok'),

        quest(bq, q.THE_DOORMAN, 'scripts/quests/bastok/WAR_AF1_The_Doorman',
            function(p)
                -- transcribed inline grants from the source quest script here
                p:addGil(500)
                p:addFame(xi.fameArea.BASTOK, 30)
            end),
    }
end

return m
```

### The `quest()` factory and its `source` argument

`quest(logId, questId, source, apply)` registers one quest recipe. The cascade only replays it when the primary has that quest completed (`hasCompletedQuest`). The `source` argument says where the base `.reward` block comes from and accepts three forms:

- **A script-path string** (the usual case) — `require`d at apply time and its `.reward` replayed via `npcUtil.completeQuest` (gil / item / fame / title / keyItem / exp).
- **An inline reward table** — e.g. `{ title = xi.title.HEIR_TO_THE_HOLY_CREST }`. Use when the reward is trivial and there's no quest script to point at.
- **`nil`** — no base reward; every act lives in the `apply` closure. Use for unlocks whose completion happens in a **battlefield or NPC** rather than a standalone quest script (e.g. **DRG** via *The Holy Crest*, **RUN** via *Children of the Rune*).

The optional `apply(target)` closure delivers grants that live outside the `.reward` block (`unlockJob`, inline fame / key items, etc.).

Load order: alphabetical filename load makes `../bots_progression_cascade.lua` (parent-level, shorter path) load BEFORE anything in this subdirectory, so `cascade.quest` and `cascade.mission` are already exposed by the time subdir files register their recipes.

## How to audit an area for inline grants (procedure for future sessions)

Given how many quests each expansion has (LSB tracks ~1000 quest/mission Lua files), an audit is best delegated to parallel Explore-agent runs. This is the procedure that produced the initial ToAU-and-earlier coverage:

### 1. Enumerate all inline-grant call sites

For each quest/mission Lua file in the area, find every call to:

- `player:addGil(N)` — direct gil
- `npcUtil.giveCurrency(player, kind, N)` — 'gil', 'imperial_standing', 'cruor', 'bayld', 'sparks'
- `player:addCurrency(kind, N)` — same currencies
- `player:addFame(area, N)` — inline fame (NOT `.reward.fame`)
- `player:addTitle(id)` — inline title (NOT `.reward.title`)
- `player:setRank(N)` / `player:setRankByNation(nation, N)` — cross-nation rank
- `player:addKeyItem(id)` / `npcUtil.giveKeyItem(player, id)` — inline KIs (some are setup, some are reward)
- `player:addItem(id, [qty])` / `npcUtil.giveItem(player, id)` — inline items
- `player:addSpell(id)` — inline spells (e.g., avatar spells)
- `player:changeContainerSize(inv, delta)` — bag expansions
- `player:setLevelCap(N)` — LB caps
- `player:unlockJob(job)` — job unlocks
- `player:addLearnedWeaponskill(id)` — WS unlocks
- `player:setPetName(petType, id)` / `player:unlockAttachment(id)` — PUP-related unlocks
- `player:setCampaignAllegiance(N)` — Campaign alignment
- Cross-log completion: `player:completeMission(log, mid)` / `player:addMission(log, mid)` / `player:addQuest(log, qid)`

### 2. Classify each hit

- **REWARD-ACT (cascade this):** fires as part of quest completion — near `npcUtil.completeQuest`, `quest:complete(player)`, `mission:complete(player)`, or in a terminal `onEventFinish` handler that ends the quest. Also: mid-mission structural KIs that gate later progression (e.g. CoP Mothercrystal Lights) count as reward-act because we always want alt to have them.
- **SETUP-ACT (do NOT cascade):** fires when quest starts (`onTrigger` of first section), or mid-quest to advance progression (KIs later `delKeyItem`'d by the quest itself), or in a helper NPC's dialog before the quest is accepted.
- **UNCLEAR:** mark with a note. Post-completion follow-up branches (typically in `QUEST_COMPLETED` section) usually shouldn't cascade because the primary earned those on repeat trades that headless would never do; but sometimes they represent the actual first-completion payoff. Investigate case-by-case.

Two heuristics for classification:
- If the KI/item is `delKeyItem`'d or `confirmTrade`'d before `quest:complete` fires → SETUP.
- If the grant fires in the SAME `onEventFinish` handler as `quest:complete(player)` → REWARD-ACT.

### 3. Handle branching / player-choice rewards per singleplayer-rules

The [[singleplayer-rules]] memory says "over-grant on variants of a single reward act." When the source quest gives ONE of several options (branching gil/item choices, race-based RSE, gender-based DNC AF, ring choice, augmented earring picker), the recipe should give ALL variants to headless — not pick one. Applies to:

- Trial by Earth's 4-item/gil/spell/title menu
- Waking Dreams' 4 items + 15k gil + spell
- Divine Interference / Waking the Colossus 3-item + gil + spell menu
- Apocalypse Nigh's 4 earrings
- CoP 8-4 Dawn's 3 rings (Rajas/Sattva/Tamas)
- ToAU 46 Imperial Coronation's 4 rings/standard
- All race-based RSE and gender-based AF pieces
- Etc.

Skip the runtime option-picking logic; just deliver every variant.

### 4. Transcribe into the recipe apply closure

Extend or create the recipe entry for that quest with an `apply` closure that hand-transcribes the exact amounts. Example:

Source quest `scripts/quests/bastok/Fallen_Comrades.lua` has `quest.reward = { fame = 8, fameArea = xi.fameArea.BASTOK, title = ... }` and inline `player:addFame(xi.fameArea.BASTOK, 112)` at line 64 in the completion handler. Recipe:

```lua
quest(bq, q.FALLEN_COMRADES, 'scripts/quests/bastok/Fallen_Comrades',
    function(p)
        p:addFame(xi.fameArea.BASTOK, 112)  -- inline fame boost on top of reward.fame=8
    end),
```

The registry walk delivers `.reward.fame = 8` (the small base grant). The apply closure adds the 112 fame boost that only fires inline. Together = 120 fame, matching what a primary earns on first completion.

### 5. Delegated audit — fanning out Explore agents

For a whole new area/expansion, the efficient path is to delegate discovery to parallel Explore agents. Each agent gets:
- A scoped folder or two (e.g., `scripts/quests/newarea/` — 50-100 files)
- The list of grant patterns above
- The reward-act vs setup-act classification rules
- Instructions to write findings to a scratchpad `.md` file with per-quest sections

The parent session consumes the scratchpad files and writes the recipe transcriptions area-by-area. This isolates the discovery reads from the main conversation context.

**Important:** Explore agents do not have Write tool access. Prompt them to return findings inline as their final message; the parent captures those to a scratchpad file via `Write` before consuming.

### 6. Verify a recipe against its source

To check that a recipe correctly captures its source quest's inline grants, grep the source Lua for the reward-classified call sites and cross-reference against the recipe's apply closure. Any missing amount is an under-grant; any extra is a bug.

## Related memory files

- `feedback-cascade-full-rewards.md` — recipes deliver the FULL quest reward, not "structural bits only"
- `feedback-cascade-sync-button-authoritative.md` — Sync button drives the cascade, live-wrap is a bonus
- `feedback-cascade-no-bulk-value-mirror.md` — never bulk-copy accumulated fame/gil/title state
- `feedback-cascade-intentional-exceptions.md` — the three utility-system bulk mirrors that ARE kept
- `feedback-singleplayer-rules.md` — tedium = repetition, over-grant on variants of a single reward act

## Adding a new expansion (future work)

If a future session extends coverage past ToAU:

1. Add per-area file(s) in this directory (e.g., `abyssea.lua`, `missions_wotg.lua`)
2. Follow the audit procedure above to enumerate inline grants
3. Update this README's Scope section
4. If the expansion adds new currencies not currently in `npcUtil.completeQuest`'s reward-field surface (cruor, sparks, etc.), remember those currencies aren't dispatched via `.reward` — always require recipe transcription
5. Cross-check with `feedback-cascade-intentional-exceptions.md` before adding any new bulk mirrors — most cases should be per-quest recipes instead
