---
name: FFXI client slash command knowledge is unreliable
description: Do not assert that a slash command is client-handled without verifying against a wiki or packet capture — training data on this topic has been wrong repeatedly
type: feedback
originSessionId: d5e9bd39-ba54-4c53-8b8f-14e66933105f
---
Do not claim that a specific FFXI slash command (e.g. `/warp`) is handled client-side unless it can be verified on an FFXI wiki or from packet capture evidence.

**Why:** Claimed `/warp` was a known client-side command that would never reach the server — this was wrong, and the same mistake was made in multiple separate sessions. The user confirmed it does not appear on any FFXI wiki pages.

**How to apply:** When discussing whether a `/command` reaches the server, default to "unknown — needs verification" rather than asserting client-side handling from training data. If the user has already tested it and it reaches the server, trust that over any prior assumption.
