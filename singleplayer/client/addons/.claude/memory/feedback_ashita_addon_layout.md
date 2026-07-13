---
name: ashita-addon-layout
description: Ashita v3 addon dir convention — shared libs go in addons/libs/, never as lib.lua inside an addon's own folder
metadata:
  type: feedback
---

Ashita v3 addons follow a fixed dir convention:

- Each addon lives at `addons/<name>/` with an entry point `<name>.lua`.
- Sibling `<name>_ui.lua` / `<topic>_tab.lua` files inside the addon dir are allowed (precedent: `autobots/autobots_ui.lua`, `autoequip/gear_tab.lua`). **Load siblings by bare name**, e.g. `require('autobots_ui')`, `require('gear_tab')` — Ashita adds the addon's own dir to `package.path` as `<dir>/?.lua`. **Never use the dotted `require('<addon>.<file>')` form** — that resolves to `<dir>/<addon>/<file>.lua`, a subdir that doesn't exist.
- **Shared libraries live in `addons/libs/`**, never as `lib.lua` inside an addon's own folder. Other addons pull them in via `require('<libname>')` (e.g. `require('autoutil')`, `require('autoequip')`, `require('inv_cache')`), which resolves through `addons/libs/?.lua`.

**Why:** Mid-refactor I stashed the autoequip XML parser as `addons/autoequip/lib.lua` and called `require('autoequip.lib')`. Ashita's loader couldn't find it — `autoequip.lib` resolves to `addons/autoequip/lib.lua` only if you set up that path manually, and Ashita doesn't. The user pointed out the convention: shared libs always go in `addons/libs/`. The ffxi-ashita repo already had `addons/libs/autoequip.lua` (an older copy of the same parser), confirming the canonical location.

**How to apply:** When creating or moving Ashita addon code, never name a file `lib.lua` inside an addon dir, and never require `<addon>.lib`. If a helper is single-addon, keep it sibling and require `<addon>.<file>`. If it's shared between addons (or even just *might* be), put it under `addons/libs/<name>.lua` and require by bare name. When porting from ffxi-ashita, check `addons/libs/` first — the lib may already exist there and just need an update rather than a new copy.

Related: [[project-ashita-version]] (Ashita v3 target).
