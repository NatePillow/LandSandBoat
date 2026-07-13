---
name: addon-loading-ux-convention
description: All Ashita addons in this project must surface backend-data wait states (banner + button gating) so end users can distinguish "loading" from "broken"
metadata:
  type: project
---

Every Ashita addon UI in this project (`singleplayer/client/addons/<name>/`) must follow the same pattern for surfacing "waiting on backend data" states. The goal is end-user debuggability: a user must always be able to tell whether the addon is *loading* something or *broken*.

## Required behavior

1. **Connection-level wait (A):** until `autoutil.unlocked` flips (0x150 server-ident received), the addon banner shows `Waiting on: server handshake` and primary action buttons are dimmed.
2. **Per-data-source wait (B):** every data source the addon depends on (char roster, alliance roster, configs, gear XML, inventory snapshot, job info, etc.) gets a named entry in the banner — *specific labels*, not "loading…". A bug report saying "stuck on Waiting on: gear XML" is far more actionable than "addon is hung".
3. **Button gating:** while *any* required source is pending, buttons that consume that data are rendered via `dim_button` (alpha 0.35, click swallowed). Buttons that don't need the data (Reset, Close, Refresh) stay active.

## Shared plumbing (lives in `singleplayer/client/addons/libs/autoutil.lua`)

- `autoutil.pending_descriptors` — array of `{ label, ready }` for connection-wide sources.
- `autoutil.pending_sources(extras)` — returns list of pending labels (standard + extras).
- `autoutil.draw_pending_banner(extras)` — renders a yellow status line and separator at the top of the addon window; returns true if anything is pending.
- `autoutil.all_ready(extras)` — boolean shortcut for button gating.
- `autoutil.dim_button(label, enabled, fn, w)` — promoted out of `autobots_ui.lua`.

## How to apply to an addon

After `imgui.Begin(...)`:

```lua
local addon_extras = {
    { label = 'gear XML', ready = function() return autoequip.xml_root ~= nil end },
}
autoutil.draw_pending_banner(addon_extras)
local ready = autoutil.all_ready(addon_extras)
autoutil.dim_button('Reload Sets', ready, function() M.reload_config() end, 130)
```

## Why this rule exists

Without it, the user can't tell whether an empty list / blank tab means "still fetching" or "broken". This pattern was set up after the user explicitly asked for an indicator on autoequip ("had to click Reload Sets, not sure if was just loading in background, we need some kind of indicator when all these addons are waiting for BE data so user knows it isn't just broken"). The pattern is **mandatory for every new or modified addon UI** — not opt-in.

## How to apply (future work)

- When porting a new addon: implement the banner + gating from the start. No "I'll add it later".
- When touching an existing addon's UI: if the file doesn't have a banner yet, add it as part of the change. Don't ship UI patches that leave loading state hidden.
- New backend data sources go through the descriptor pattern, not ad-hoc text in the addon.

Related: [[ashita-addon-layout]] (where libs/autoutil.lua lives and how it's required).
