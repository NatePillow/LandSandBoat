---
name: cascade-sync-button-authoritative
description: HARD RULE — bots_progression_cascade is driven by UI Sync buttons over the FULL back-catalog. Live-wrap of npcUtil / entity methods is a nice-to-have and MUST NOT be the core cascading solution. Design as if live-wrap doesn't exist. Chronic misread on my part across multiple sessions.
metadata:
  type: feedback
---

**Rule:** the authoritative cascade mechanism is the client-side UI buttons — "Sync Quests", "Sync Missions", "Sync Teleports". These fire packets that walk primary's full completion history, and for every completed quest/mission/currency-grant primary has, apply the FULL reward set to each headless. That must work end-to-end, on demand, with zero dependence on any runtime wrap.

**Why:** Sync happens whenever the user wants — often right after creating a new headless, on a character who wasn't in the alliance when the original quest was completed, or before the primary ever plays with that headless. There is *no* moment where "primary and headless are both in the alliance at quest-completion time" is guaranteed. If the cascade only works via a live wrap that fires during real-time completion, it silently fails to cascade anything primary did before headless existed, which is the *common case*, not the edge.

**How to apply:**
- When designing a cascade fix, ask "does this work when the user presses Sync tomorrow morning after creating headless #5?" If the answer requires that primary re-play the game or re-complete a quest, the design is wrong.
- **Recipe apply closures are the SINGLE SOURCE OF TRUTH** for what each quest/mission gives. Every inline grant from the source quest — fame amounts, gil amounts, currency amounts, titles, KIs, items, spells — is hand-transcribed from `player:addGil(N)` / `player:addFame(area, N)` / `player:addCurrency(kind, N)` / `player:addTitle(id)` / `player:addItem` / `npcUtil.giveCurrency` / `npcUtil.giveKeyItem` calls found in the quest's section handlers. This is the back-catalog fill-in and it's the whole ballgame.
- **Maintenance concern is basically nil.** This is a 25-year-old MMORPG whose 75-era rewards were frozen ~a decade ago. Upstream LSB tracks retail values which don't change. So the one-time transcription pain has essentially zero ongoing drift — do it right once and move on.
- The registry-walk pass (`registry_walk_target` at bots_progression_cascade.lua:1189) covers `.reward` block dispatch for the ~99% of quests that use `Quest:new` — but only for what lives IN `.reward`. Everything inline outside `.reward` requires a recipe entry with the transcribed grants.
- **Live-wrap is a single `completeQuest`/`completeMission` wrap that dispatches through the RECIPE apply closure** — not a bunch of per-primitive wraps around addGil/addFame/addTitle etc. Recipe = truth; wrap consults recipe when it exists; falls back to plain completeQuest replay for recipe-less registry-walk-only quests. Minimizes surface area and keeps behavior symmetric between button-path and live-path.
- Bulk value mirrors (`sync_fame_to`, `sync_titles_to`) exist because they were an alluring shortcut to cover the back-catalog cheaply. They over-grant with non-quest state. See [[cascade-no-bulk-value-mirror]]. The correct fix is not "add more bulk mirrors" or "live-wrap the primitive" — it is "transcribe inline grants into the recipe's apply closure so the button-driven walk delivers them per-quest."

**Concrete chronic mistake:** across at least two sessions, I have proposed "live-wrap `player:addGil`/`addFame`/`addCurrency` at first login" as the primary fix for the gil/currency delivery gaps, ignoring that this only cascades forward from wrap-time. The button-driven cascade is the authority; recipes with transcribed inline grants are the mechanism; live-wrap is an optional bonus.

Linked: [[cascade-full-rewards]] (what to deliver), [[cascade-no-bulk-value-mirror]] (don't shortcut with primary's accumulated state), [[singleplayer-rules]] (tedium = repetition, not play).
