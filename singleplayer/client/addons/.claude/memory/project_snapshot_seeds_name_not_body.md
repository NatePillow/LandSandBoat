---
name: bot-state-snapshot-seeds-name-not-body
description: autobots /bot-state snapshot re-seeds config NAME only, not the partyConfig BODY, so the local `running` gate is nil after login/reload — buttons gated on it wrongly dim until the user re-picks a config
metadata:
  type: project
---

`autoutil.fetch_bot_state()` (GET /bot-state) fires **once per unlock** (rising
edge in autobots.lua incoming_packet 0x150), and `autobots_ui.apply_server_snapshot`
seeds the active config **name** (`snap.configName`) but deliberately NOT the
`partyConfig` body — the body is re-fetched lazily on the next picker interaction
(see the comment at apply_server_snapshot). Consequence: the local
`running = partyConfig ~= nil` gate is **false right after any login / `/addon
reload`** even while the alliance is live server-side. Any button gated purely on
local `running` is therefore reload-blind and stays dimmed until the user re-picks a
config.

This bit EVERY button gated on the render-time `running` flag (Attack/Finish,
Despawn, Heal On/Off, Sync Quests/Missions/Teleports, Give Signet, Summon Trusts,
Start/Stop Actions/Movement, ...) — surfaced first via Summon Trusts, but it was the
whole set.

Fix pattern (applied 2026-07-11): the snapshot already carries an authoritative
`snap.running` (server sets it true when `#A.headlessCharIds > 0`). Capture it into a
module-local `server_running` in apply_server_snapshot (`b(snap.running) or false`),
clear it in `on_stop()` (every despawn path calls on_stop), and fold it into the ONE
render-time definition:
`local running = (partyConfig ~= nil) or server_running;` (autobots_ui.lua ~873).
That single change makes all ~20 `running`-gated buttons reload-safe at once.
`partyConfig ~= nil` still covers mid-session spawn/stop (set via on_start/on_stop);
`server_running` covers the post-login/reload window before the body re-fetches.

Safe because every `partyConfig` dereference is nil-guarded: `has_any_sc(partyConfig)`
(SC pause button) and `collect_alliance_names(partyConfig)` (puller combo) both
return false/{} on a nil/non-table body, and the Config-Info panel degrades to
placeholders. So body-dependent widgets stay correctly dimmed until rehydration while
everything that only needs "is it live" lights up. This is a client-only change; test
with `/addon reload autobots`, no server build.
