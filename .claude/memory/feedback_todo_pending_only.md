---
name: feedback-todo-pending-only
description: TODO.md is a pending-only docket — never leave completed items in it, delete the entry when the work lands
metadata:
  type: feedback
---

**Rule:** `TODO.md` in the LSB repo is a docket of PENDING work only. Never write a completed / done entry there and never leave one after finishing. Delete the item as soon as the work merges (or immediately if it never should have been added in the first place).

**Why:** The user tracks open work by scanning TODO.md. Completed entries dilute the signal and imply the file is a changelog, which it isn't. Commit history + memory serves that purpose.

**How to apply:** When finishing a task that had a TODO entry, delete the entry in the same change as the code. Never add a `*(done)*` marker and leave the entry sitting — either the work is pending (keep the entry, no marker) or it's done (delete the entry).
