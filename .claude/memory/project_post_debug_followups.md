---
name: post-debug-followups
description: Followup work parked until current addon/server debugging cycle settles — commands inventory and README/docs refresh
metadata:
  type: project
---

After the current debugging pass for the Ashita addon port (autoequip / autobots / automog / autospawn / BotPushLog signature work etc.) is complete, do these:

1. **Commands inventory & cleanup.** Walk every `ashita.register_event('command', ...)` handler across `singleplayer/client/addons/**/*.lua` plus every `/<name>` reference in `modules/singleplayer/lua/**`. Verify each command:
   - is still wired and reachable,
   - matches what the README/docs say about it,
   - has a sensible Usage line when invoked with no args.
   Likely cleanup spots: leftover dev-only `/autoequip` subcommands, `/autobots be-*` testing routes, the `/automog` family.
2. **README refresh.** Sweep `README.md`, `HEADLESS.md`, `HEADLESS_FOLLOWUP.md`, `DIARY.md` and any per-addon docs for stale references to: removed commands, the old `modules/singleplayer/addons/` path (now `singleplayer/client/addons/`), removed `ShowDebug`/`ShowWarning` Lua calls (now `printf`), and any of the `xi.bot` → `xi.auto` rename leftovers.

**Why:** the user explicitly asked to defer this until debugging is finished — interleaving doc edits while bug-fix patterns are still moving would just create churn. Bringing it up at the wrong time is what to avoid.

**How to apply:** in a future conversation where the user signals the debugging pass is winding down (no new red errors for a stretch, or they say "what's next"), surface this and ask whether to start. Don't unilaterally begin while bug reports are still flowing.
