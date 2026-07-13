---
name: Ashita version and ADK usage
description: Project targets Ashita v3; ADKv3 headers are the authoritative API reference; ADKv4 is off-limits
type: project
originSessionId: 5bbe189e-d4e3-4ade-9f49-4f040c54a4c7
---
This project runs on **Ashita v3**. All addon Lua code must use v3 API method names.

**Why:** ADKv4 exists in the repo for future porting work only — using v4 method names causes runtime nil-call errors since the v3 runtime doesn't expose them.

**How to apply:** When writing or modifying any Lua code that calls Ashita API methods (IPlayer, IParty, IEntity, etc.), verify method names against `ADKv3/Ashita.h` before using them. Do not reference `ADKv4/` for current work.

Known v4 → v3 gotchas (extend this list as new ones are caught):

| v4 (wrong) | v3 (correct) | Surface |
|---|---|---|
| `GetHPMax()` / `GetMPMax()` | `GetHealthMax()` / `GetManaMax()` | IPlayer |
| `ashita.register_event('d3d_present', fn)` | `ashita.register_event('render', fn)` | per-frame draw hook |

The render-event one bit us in 2026-06: autodps used `d3d_present` so its UI never drew, while every other addon used `render` and worked fine. Steering doc had the rule "use v3" but no concrete event-name list — symptom was silent (no error, just a window that never appeared), which made it hard to spot.

**Detection tip:** if an addon's `/<name>` toggles a var but nothing visually appears, grep `singleplayer/client/addons/<name>/*.lua` for `register_event('d3d_present'` — that's a sign it was ported from v4-shaped reference code.
