---
name: feedback-build-cadence
description: "Dev workflow batches many changes (ideas/fixes/requirements) then verifies them together in dedicated testing sessions — code sits written-but-unbuilt between, that's normal. ONE build at the end of a series, never interleaved/background; don't nag about building. Reason: CPU usage + workflow."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: c6c8bbba-e2aa-4795-b432-790a04c8f0c8
---

When pushing through a multi-task workstream (server-side packet plumbing, Lua edits, addon changes, etc.), do not fire interleaved builds after each piece — run ONE build at the very end, after every Lua + C++ edit across all the planned tasks is in.

**Dev workflow — why builds are rare and why that's fine:** The user works in batches — bang out a bunch of ideas / bug fixes / requirements across a working session, THEN verify them together in dedicated, longer testing sessions later (which may be a while off). So code is *expected* to sit written-but-unbuilt for a stretch; that is the normal state, not a loose end to resolve. Do NOT push to build or test between changes, do NOT treat "unverified" as a problem to fix now, and do NOT nag about building. When a series of edits is done, note it's ready to verify whenever the next testing session happens, and move on to the next item in the batch.

**Why:** The user explicitly flagged it as chewing up CPU when I kicked off a verify build after #110's server-side edits before moving to #110's addon edits / #111 / #112 / etc. ("do one build at the end, stop running them off in parallel, its chewing up CPU"). LSB's xi_map link step is heavy and each rebuild redoes a lot of work even with incremental.

**How to apply:**
- During a planned series of tasks, complete all edits across server + addon for every task in the series before kicking off any build.
- A single verify build at the *end* of the series is the correct cadence.
- Exception: if I genuinely need to confirm something compiles before depending on it in later code (rare — usually I can read the existing patterns), say so out loud and ask before firing the build.
- Background-task builds count: even one run-in-background build is "running off" if there's still active edit work to do that doesn't depend on its result.
- **NEVER run builds in a background Bash task or off-thread in a subagent.** Background/off-thread builds slow the whole machine to a crawl.
- **Even foreground main-context builds have crashed the session.** Observed: a foreground `cmake --build` from main-context Bash took the terminal/session down. So foreground isn't a safety guarantee either.
- **Default: ask the user to run the build themselves.** When you reach the end-of-series build point, do the edits, then surface a one-liner like "ready to build — please run `cmake --build build -j` and share the result." Don't fire it yourself unless the user explicitly says to.
- Even when the user does ask you to run it, stay alert: if the session is already heavily loaded (deep context, lots of files held open), prefer offering to let them run it.
