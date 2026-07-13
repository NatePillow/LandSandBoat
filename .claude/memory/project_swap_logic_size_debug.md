---
name: swap-logic-size-debug
description: RESOLVED — autoequip Swap Logic InputTextMultiline crash-on-click and won't-fill-width were both one bug — a missing buf_size arg in the Ashita v3 imgui.InputTextMultiline call.
metadata:
  type: project
---

RESOLVED 2026-07-11. Both symptoms of the autoequip Swap Logic editor —
(1) clicking into the text area crashed the client, and (2) the box never spanned
the pane width — were a single root cause: the `imgui.InputTextMultiline` call was
missing its `buf_size` argument.

## Root cause

Ashita v3's binding mirrors the C++ ImGui signature (verified in the ADK at
`/home/nate/Desktop/git/ffxi-ashita/ADKv3/imgui.h:310`):

```cpp
InputTextMultiline(const char* label, char* buf, size_t buf_size,
                   const ImVec2& size = ImVec2(0,0), ImGuiInputTextFlags flags = 0, ...)
```

The Lua binding expands the `ImVec2 size` into two number args (same as
`imgui.BeginChild('##id', w, h, border)` maps C++ `BeginChild(id, ImVec2, border)`).
So the real Lua signature is:

```
imgui.InputTextMultiline(label, buf, buf_size, size_x, size_y [, flags])
```

The broken call was `imgui.InputTextMultiline(label, buf, -1, h)`:
- `-1` landed in the **buf_size** slot → on click, ImGui allocates the edit buffer
  at size_t(-1) == SIZE_MAX → **crash**. (Renders fine; only activation allocates.)
- `h` landed in **size_x** → width was always the height value, which is why NO
  amount of `PushItemWidth` / explicit-width tuning ever worked (wrong slot).

## Fix (applied)

`singleplayer/client/addons/autoequip/swap_logic_tab.lua`, in `draw_section_editor`:

```lua
imgui.InputTextMultiline('##sl_text_' .. section_tag, buf, BUFFER_BYTES, -1, h)
```

`buf_size = BUFFER_BYTES` (65536, matches the CDSTRING var) → no bad allocation.
`size_x = -1` → fills to the pane's right edge (no PushItemWidth needed for the
multiline branch; the size arg drives it). `size_y = h` → fixed height. The old
`[SWAP-LOGIC-SIZE]` diagnostic log was already removed before this session.

## General lesson

Ashita v3 imgui functions follow the C++ ImGui signatures in `ADKv3/imgui.h`, with
`ImVec2` params expanded into consecutive number args in Lua. When a widget takes a
buffer, `buf_size` comes BEFORE the size args — check the ADK header rather than
guessing arg order. See [[project_ashita_version]] (target Ashita v3 / ADKv3) and
[[imgui-style-stack-leak]] (other Ashita imgui footguns).

## Voice note

This thread cost trust through prior blind guessing. The resolution came from
reading the ADK header the user pointed to, not iterating — keep that pattern:
verify the binding, then change once.
