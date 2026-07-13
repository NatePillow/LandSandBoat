---
name: imgui-createvar-reopen-leak
description: Ashita v3 footgun — CreateVar-ing a persistent ImGuiVar in a modal's open() WITHOUT delete-before-create orphans the old handle in the native var registry every reopen; accumulation crashes the client. Always delete-if-non-nil before CreateVar.
metadata:
  type: feedback
---

**Rule:** any long-lived `imgui.CreateVar` handle stored in addon state (CDSTRING
filter boxes, BOOLCPP, etc.) MUST be `DeleteVar`-guarded before it is re-created.
The delete-before-create idiom:

```lua
if state.foo_filter then imgui.DeleteVar(state.foo_filter); end
state.foo_filter = imgui.CreateVar(ImGuiVar_CDSTRING, 64);
```

**Why:** a `BeginPopupModal` closed by ESC / click-away does NOT run the addon's
`close_modal()` (which is where the DeleteVar lives), so the stored var handle stays
live. If the modal's `open()` then `CreateVar`s over it unconditionally, the previous
handle is orphaned in Ashita's native ImGuiVar registry. Every open/ESC cycle leaks
another set; the registry eventually corrupts and the client HARD-crashes — presenting
as "crashes on a LATER save/interaction," not deterministically on the first, which is
what makes it hell to pin (a full read-through audit found no deterministic crash in
the render/save/close path — the leak is the cause).

**The fix that shipped (2026-07-11):** `autobots/alliance_tab.lua` `open()` created
three CDSTRING vars (`pc_filter`, `trust_filter`, `ws_filter`) with NO guard while
`autobots/food_tab.lua` `open()` (the hardened reference, single `food_filter`) had
one at line ~173. Added the three delete-before-create guards to match. `close_modal()`
already DeleteVar+nils them on the Save/Cancel paths — the guard covers the ESC path
that bypasses close_modal.

**Deliberately NOT done:** adding an `else close_modal()` on the `BeginPopupModal`
false branch to catch ESC. food_tab proves the open()-guard alone bounds the orphan
count (≤ the var count between an ESC and the next open, reclaimed on reopen), so it's
unnecessary; and a frame-1 false positive (BeginPopupModal transiently false the frame
OpenPopup fires) could run close_modal and make the editor never open — a worse
regression than a rare crash, and unverifiable without a client build (user builds).

Client-only fix; test with `/addon reload autobots`. Related Ashita var/stack
footguns: [[swap-logic-size-debug]] (InputTextMultiline missing buf_size) and
[[imgui-style-stack-leak]] (Push/Pop leak on Lua error). Three distinct ways the
Ashita v3 imgui var/stack layer bites — all crash-or-corrupt, none caught by pcall.