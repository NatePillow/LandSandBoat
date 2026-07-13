---
name: cascade-intentional-exceptions
description: Three bulk mirrors in bots_progression_cascade are INTENTIONAL utility-system exceptions to the "reward acts only" rule, confirmed by user. Do not propose deleting these when auditing the cascade.
metadata:
  type: feedback
---

**Rule:** the cascade has three bulk-mirror mechanisms that would look like violations of [[cascade-no-bulk-value-mirror]] on inspection, but are DELIBERATE utility-system tedium-reduction exceptions. Confirmed by user 2026-07-05. Do not question or propose removal on future audits.

**The three exceptions:**

1. **`sync_hidden_trust_spells_to`** (bots_progression_cascade.lua:1066) — bulk-copies primary's 8 hidden-trust-quest spells to headless by presence check. Defensible because trust spells have exactly one source per spell (their specific HiddenQuest) so `hasSpell` = quest done. Kept even though it's technically a state-mirror because it's a stable invariant.

2. **`sync_teleports_to`** (:1539) — bulk-copies homepoint/outpost/survival-guide/waypoint/abyssea/campaign/eschan bits. Many of these are ambient-play acts (walk to Rabao, touch homepoint crystal) not quest rewards. Kept because forcing the user to re-run every teleport unlock on every alt is textbook mindless-repetition tedium.

3. **`AF1_COFFER_ITEMS`** mirror (:1317 sync_af_items_to) — bulk-copies 30 canonical AF1 head+legs pieces. These are BCNM Treasure Coffer drops (Castle Oztroja / Davoi / Beadeaux etc.), not quest rewards. Kept because coffer farming across 15 jobs × 2 pieces on every alt is dumb timesink.

**Why:** the [[singleplayer-rules]] refinement is "tedium = repetition of content, not playing the game." These three cases are specifically about utility-system unlocks — mechanics that once unlocked stay unlocked forever, whose "acquisition act" is grindy/repetitive by design in retail. Cascading them is tedium-reduction on unlock-the-world plumbing, not fabrication of gameplay rewards. Analogous to how the cascade also skips prereqs for job unlocks — same "over-grant on utility unlocks, not on play rewards" principle.

**How to apply:**
- When re-auditing the cascade under strict "no bulk value mirror" framing, exempt these three explicitly.
- Do NOT propose replacing them with per-quest recipe apply closures or live-wrap tracking. They are correct as-is.
- If a new utility-system mirror is being considered (e.g. crafting skill floors, chocobo license, mount unlocks), treat it as the same class and check with user before adding.
- Fame, gil, titles from named-quest rewards, currencies, mission rewards — all NON-exempt; those follow [[cascade-no-bulk-value-mirror]] and [[cascade-sync-button-authoritative]] strictly.

Linked: [[cascade-no-bulk-value-mirror]] (the general rule these are exceptions to), [[cascade-full-rewards]] (what per-quest recipes must deliver), [[singleplayer-rules]] (tedium definition backing the exception).
