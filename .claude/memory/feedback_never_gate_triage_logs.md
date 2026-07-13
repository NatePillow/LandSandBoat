---
name: feedback-never-gate-triage-logs
description: Triage diagnostic prints stay ungated until the issue is root-caused. Don't gate them behind DEBUG_LOGS or settings flags during active triage.
metadata:
  type: feedback
---

When adding diagnostic `printf` / log statements to debug a live issue, leave
them **ungated** — always firing — until the root cause is found. Do not gate
them behind `xi.settings.singleplayer.DEBUG_LOGS`, an `if debug then` block,
or any other on/off switch while the bug is still being triaged.

**Why:** Reported directly during a session — I added `[AutoNuke] tick bot=…
active=…` printfs to diagnose why BLMs weren't nuking, then gated them behind
`DEBUG_LOGS = false` "to keep them as a safety net." User had to flip the
flag to see anything, which defeats the entire purpose of a triage print.
User's words: "we only add logs to that when we're done triaging." Compounds
the same anti-pattern as `feedback_never_silence_logs.md` — silently hiding
information from the user.

**How to apply:**
- While debugging, every diagnostic print fires unconditionally. No
  `DEBUG_LOGS`, no `if verbose`, no `xi.settings.X.Y` gate.
- Only AFTER the issue is root-caused and the user confirms the fix, you may:
  - Comment out the print (preserve the line for future re-enable), or
  - Remove it entirely if the user asks.
  - Gating behind a flag is allowed at this stage ONLY if the user explicitly
    asks for that pattern.
- "Setting up the flag for next time" is exactly the wrong move during
  triage — it puts the user one step further from the data they need.
- If a print is too spammy mid-triage, rate-limit it (one line per bot per
  N seconds via a per-state timestamp), don't gate it.
- See also: [[feedback-never-silence-logs]] — same family of mistake.
