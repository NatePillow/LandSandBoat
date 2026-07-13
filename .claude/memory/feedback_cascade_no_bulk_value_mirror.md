---
name: cascade-no-bulk-value-mirror
description: HARD RULE — cascade must replay specific reward ACTS (this quest's fame/gil/title grant), NEVER bulk-copy primary's current accumulated fame/gil/title/currency values to headless. Bulk value mirrors over-grant with kill-fame/loot-gil/exploration-titles that headless didn't earn from any reward act.
metadata:
  type: feedback
---

**Rule:** the cascade delivers rewards from *specific completed quest/mission acts*, not from primary's current *accumulated state*. Never write code that reads `primary:getFame(area)` / `primary:getGil()` / `primary:hasTitle()` and syncs that value onto headless as a backstop.

**Why:** fame, gil, and titles all accumulate from many sources — quest rewards, mission rewards, kill fame, NPC turn-ins, loot sales, exploration achievements, event drops. Only the *quest/mission reward* sources are the cascade's responsibility. Playing the game (killing mobs, doing turn-ins, selling drops, exploring) is the game itself — not tedium to route around. See [[singleplayer-rules]] for the sharpened tedium definition. If primary has 5000 Bastok fame from mixed sources, bulk-mirroring 5000 to headless over-grants — headless earns fame from the game they play, plus catches up from the specific quest rewards they missed.

**The specific miss:** `bots_progression_cascade.sync_fame_to` (bots_progression_cascade.lua:1014) walks every `xi.fameArea` and does `if primary_fame > target_fame then target:setFame(area, primary_fame)`. This was justified in comments as "safe because fame is write-only monotonic (no delFame anywhere)." Monotonic-write safety is *not* the same as *correct*. Over-granting is a correctness bug, not a monotonicity bug. Same issue on `sync_titles_to` (:1051) — mirroring every title primary has grants exploration/NM/event titles headless didn't participate in.

**Correct pattern:**
- For quest/mission rewards defined in `.reward.fame` / `.reward.title`: registry walk's `obj:complete(target)` dispatches those correctly per-quest — no additional mirror needed.
- For inline `player:addFame` / `player:addGil` / `player:addTitle` / `player:addCurrency` calls in section handlers (which the registry walk misses because they're outside `.reward`): live-wrap those bindings at first login (same shape as the existing `completeQuest` wrap at :1671) so any primary grant replays to alliance headless in real time. Then delete the bulk mirrors.
- For back-catalog (primary completed quests before headless existed): recipes hand-code the inline grants into the recipe's `apply` closure. Missing an inline grant from the recipe = under-grant that specific quest, which is a per-recipe bug — better than a systemic over-grant.

**How to apply:**
- Never propose "walk everything primary has and mirror to target" as a "backstop" — the cascade doesn't have backstops, it has reward-act replays.
- When the user asks "does the cascade cover X," check specifically whether X is granted from a *reward act* the cascade replays. Don't hand-wave with "and the bulk mirror catches anything else."
- When writing recipes for legacy/unconverted quests, transcribe every inline `addFame` / `addGil` / `addTitle` / `addCurrency` grant into the recipe's `apply` closure with the exact amount from the source script — do not gesture at "the mirror will handle it."

Linked: [[cascade-full-rewards]] (the flip side: DO give the full reward the quest hands out — but from the quest, not from primary's state), [[singleplayer-rules]] (tedium = repetition, not playing).
