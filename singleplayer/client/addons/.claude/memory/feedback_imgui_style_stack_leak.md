---
name: imgui-style-stack-leak
description: Lua errors between PushStyleVar/Color and the matching Pop leak into the global ImGui stack and dim every subsequent addon's render
metadata:
  type: feedback
---

Ashita addons share a single global ImGui context. The style stack (`PushStyleVar`/`PushStyleColor`) is part of that context and **does NOT unwind when a Lua render handler errors out**. A Push without its Pop stays on the stack across frames.

Addons render in alphabetical load order each frame: `autobots → autodps → autoequip → autolot → automog → autowarp`. If autobots leaks one `Alpha(0.5)` push, every later addon in the same frame and every frame after inherits the dimmed alpha — the whole UI looks faded, not just the addon that crashed. (autoskill was folded into autobots as a tab on 2026-06-21; it no longer renders independently.)

**Why:** Hit this on 2026-06-17 when `status_tab.lua:137` threw on `GetMemberSubJobLevel` (ADKv3 calls it `GetMemberSubJobLvl`). The crash happened between the stale-data `PushStyleVar(Alpha, 0.5)` at line 230 and the matching `PopStyleVar` at line 243. Each crashed render leaked one alpha push. After enough frames, the top-of-stack alpha was stuck at 0.5 and autoequip + automog + every other addon rendered dim. Fixing the underlying nil-method call stopped new leaks but the contaminated stack persisted until full Ashita restart — `/addon reload` doesn't reset ImGui state.

**How to apply:**
- Whenever there's any chance of a Lua error between a `PushStyleVar`/`PushStyleColor` and its `PopStyleVar`/`PopStyleColor` (e.g. a `render_row` helper, a Selectable inside a loop, anything that calls back into shared lib code), wrap the body in `pcall` so the Pop still runs.
- Pattern:
  ```lua
  if cond then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.5); end
  local ok, err = pcall(function() ... end);
  if cond then imgui.PopStyleVar(); end
  if not ok then autoutil.log('AddonName', 'error: ' .. tostring(err)); end
  ```
- Don't bother with pcall for tight Push/Text/Pop sequences where no user code runs in between — the noise isn't worth it.
- Diagnostic if the UI looks uniformly dim: check whether the first-alphabetical addon is throwing render errors. The contaminated stack survives reload; tell the user to restart Ashita.
- Related ADKv3 quirk that triggered this: `GetMemberMainJobLevel` exists but the sub-job version is `GetMemberSubJobLvl` (no "Level"). See [[ashita-version]].
