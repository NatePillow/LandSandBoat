---
name: feedback-ui-label-casing
description: Convert lowercase XML/internal identifiers to human-readable Title Case labels in UI surfaces
metadata:
  type: feedback
---

When surfacing internal keys (lowercase XML section names like `midmagic`, `idlegear`, `inputcommands`, etc.) in addon UI, render them as Title Case labels for humans, not raw lowercase.

**Why:** User explicitly asked for this during Phase C UI design (Swap Logic editor for autoequip). Raw lowercase tag names look like debugging output; Title Case matches the visual polish of the rest of the UI.

**How to apply:**
- Keep the raw key internally (state, persistence, XML round-trip).
- Have a `DISPLAY_LABEL` table that maps key → human label and use it everywhere a label is rendered (list items, headers, breadcrumbs, modal titles).
- Follow AshitaCast canonical naming where it exists: `premagic` → "Precast", `midmagic` → "Midcast", `aftercast` → "Aftercast". For others, drop the prefix and Title Case: `idlegear` → "Idle Gear", `gearlock` → "Gear Lock", `preja` → "Pre JA", `midws` → "Mid WS", `inputcommands` → "Input Commands".
- Same rule applies to other addons (autolot groups, automog tabs that surface XML keys, etc.).
