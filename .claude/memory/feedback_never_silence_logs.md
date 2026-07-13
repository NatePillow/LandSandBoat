---
name: feedback-never-silence-logs
description: Never silence log warnings/errors as a noise-reduction measure; always find and fix the root cause.
metadata:
  type: feedback
---

Never silence warnings or errors in logs as a way to reduce noise. The user wants the
log spam visible because that's how they see what's actually broken — silencing
covers up real issues.

**Why:** Reported directly during a session — when log spam appeared
(`luautils::GetEntityByID Mob doesn't exist`), I proposed adding the
`silenceWarning=true` arg at our singleplayer Lua call sites. User explicitly
rejected: "nah, dont silence errors, never silence errors, let the log spam
flow, we need to see issues, not cover themn up". Treating noisy logs as a
forcing function for root-cause fixes.

**How to apply:**
- Don't add `silenceWarning=true`, `--no-verify`, `noisy=false`, or equivalent
  flags to suppress in-flight warnings or errors.
- Don't wrap calls in `pcall` / try-catch to suppress the message.
- Don't reduce log level to hide the line.
- When a warning floods, treat it as a signal: find the offender (bad call site,
  stale ID, wrong API contract) and fix THAT.
- If a warning is genuinely cosmetic AND the upstream API can't be fixed, raise
  the trade-off explicitly and ask before silencing — never just do it.
