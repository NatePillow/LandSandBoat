---
name: feedback-singleplayer-rules
description: LSB singleplayer fork operates by singleplayer rules — fun is the goal, tedium is the enemy. Over-grant, skip prereqs, slam things complete when it makes the experience better.
metadata:
  type: feedback
---

The LSB singleplayer fork plays by singleplayer rules. **Fun is the name of the game; tedium is the enemy.**

**Why:** This is a single-user offline experience, not a retail server. There are no other players to balance against, no economy to protect, no progression curve to gatekeep. The classic "you must grind X to earn Y" logic exists because retail FFXI was a social MMO with longevity goals. None of that applies here.

**What "tedium" ACTUALLY means (chronic misread on my part):** tedium = doing the same mindless content over and over. It is *not* "playing the game." Running a quest once is play. Running the same quest a second time on an alt to catch up their progression is tedium — that's what cascades/sync buttons eliminate. But playing the game (killing mobs, doing NPC turn-ins, exploring, farming) is *the game itself*, not tedium to route around. The cascade replays specific completion-driven **reward acts** (this quest gave 500 gil + 30 fame + a title), not primary's total accumulated state (primary has 5000 Bastok fame from mixed sources → do NOT sync 5000 to headless). "Over-grant by default" applies to *variants of a single reward act* (choose-one-of-N rewards, gender/race variants), NOT to fabricating rewards headless didn't earn from any specific act.

**How to apply:**
- When designing systems that can over-grant vs under-grant, **default to over-grant.** Examples: gender/race variant quest rewards → give all variants; "choose one of N" rewards → give all options; story-gated content → just slam the flag complete.
- When a check exists for "did the player meet the prereq," but the user is in singleplayer and meeting the prereq is itself tedious, **skip the prereq.** Example: cascading a completed quest to an alt that "couldn't have completed it" because their level/job/story state doesn't match — just slam it. The alt inherits the flag and the reward.
- When deciding between "elegant generic system" and "explicit per-feature handling that's clear and reviewable," **prefer the explicit, reviewable one.** This is a project where surface area and clarity beat completeness.
- When a feature would force the user to do the same setup-grind multiple times across multiple characters, **collapse it.** Sync buttons, account-wide flags, headless-bot inheritance — all of these eliminate per-character tedium.
- **Out of scope:** classic FFXI balance concerns, "is this fair," "would a retail player complain." Don't bring up retail-style trade-offs as objections. They don't apply.

Linked: [[project-lsb-singleplayer]] (project context — singleplayer fork facts), [[feedback-build-cadence]] (related: don't pile on busywork the user didn't ask for).
