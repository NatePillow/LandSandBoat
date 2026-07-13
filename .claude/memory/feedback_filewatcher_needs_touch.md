---
name: filewatcher-needs-touch
description: LSB Filewatcher does NOT reliably pick up Edit-tool modifications to Lua modules. Always `touch` the file after editing to force reload.
metadata:
  type: feedback
---

After editing any Lua file under `modules/`, `scripts/`, or `settings/`, run `touch <path>` to force the LSB Filewatcher to reload it. The watcher's mtime detection misses Edit-tool changes in practice — confirmed by direct testing (pre-compaction). The Edit completes, but the watcher's `popChangedLuaFilesList()` doesn't surface the change until something else nudges the file.

**Why:** Don't assume the watcher will reload just because mtime changed. Whether it's an Edit-tool quirk (write-then-rename pattern?) or inotify/poll behavior, the empirical truth is that touch is required.

**How to apply:** After every Edit/Write to a Lua file under the watched roots, follow with `touch <path>`. Especially important for files that previously FAILED to load (syntax error etc) — the watcher never registered them as loaded modules, so the load-retry is gated on a fresh mtime event.

[[feedback_build_cadence]] applies to C++ changes; this applies to Lua.
