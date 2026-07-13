---
name: cascade-full-rewards
description: HARD RULE — bots_progression_cascade delivers the FULL quest/mission reward to headless (fame, gil, items, KIs, titles, spells, container size, level cap). Not "structural bits only". Chronic recurring lapse.
metadata:
  type: feedback
---

Every time we discuss `modules/singleplayer/bots/bots_progression_cascade.lua` (task #178 origin), I default to framing it as "cascade covers the structural side effects that npcUtil.completeQuest doesn't dispatch from quest.reward" and imply headless shouldn't get fame/gil/items. The user has corrected this repeatedly. Codifying so it stops recurring.

**Rule:** the cascade's goal is to make the headless character *indistinguishable from a character who completed the quest themselves*. That means: fame, gil, items in `.reward`, key items, titles, spells, container size deltas, level caps, weaponskill unlocks, job unlocks, mid-quest addKeyItem grants — all of it. If a quest gives 10k gil + a Titan's Cudgel + 30 fame + the Titan spell, headless gets all four. Not just the spell.

**Why:** this is the singleplayer fork philosophy at work — [[singleplayer-rules]] applies here too. Fun > tedium, over-grant by default. The point of the cascade is *specifically* that alts don't grind. Trimming rewards to "just what's structurally required" would defeat the feature — a level-75 alt without any of their AF quest cash/fame/items is not caught up, they're a shell. Also the #181 graceful inventory-full path exists *specifically* because we're delivering full item rewards, not skipping them.

**How to apply:**
- When proposing a new recipe or a variant factory (e.g. a `quest_bare` for NPC-driven quests without a `Quest:new` source), the reward must still include fame/gil/items — either by hand-authoring the reward table in the recipe, or by lifting it from the quest's NPC scripts. "Skip items because the alt shouldn't re-trigger the cutscene" is wrong reasoning; the cutscene doesn't play on synthetic completion anyway.
- When auditing gaps ("what's missing from the cascade?"), the answer is a full-reward gap, not a "spell unlock" gap. Missing Alexander from the cascade means missing Alexander's spell AND whatever fame/items/gil Waking the Colossus + Divine Interference hand out.
- When explaining the cascade to the user, lead with "full reward parity" not "structural side effects". The `HUMAN-DEV-HATE NOTICE` block in the file talks about structural side effects because that's the *specific* problem of `unlockJob`/`addSpell`/`setLevelCap` being called inline outside `.reward` — but that's about *plumbing gaps*, not about *what should be delivered*. Fame/gil/items ARE delivered by npcUtil.completeQuest reading the `.reward` block; no special recipe work needed for those. The recipes exist to fill the gaps where `.reward` alone isn't enough — never to *reduce* what the alt gets.

Related: [[singleplayer-rules]] (fun > tedium principle underlying this).
