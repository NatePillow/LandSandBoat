---
name: project-lsb-sql-loader-wonky
description: LSB upstream's sql loading via modules/init.txt is wonky — sql files in module dirs are not actually loaded by the init.txt mechanism
metadata:
  type: project
---

LSB upstream's `modules/init.txt` advertises sql support ("Valid files are: *.cpp, *.lua, *.sql") but the current loader handling for sql is wonky — sql files inside module dirs aren't actually picked up the way cpp and lua are. They have to be loaded by dbtool or by hand.

**Why:** Known upstream LSB limitation; not yet fixed.

**How to apply:**
- Don't try to "fix" missing sql entries in `modules/init.txt` thinking they're a bug — they're absent because the loader can't act on them anyway.
- `modules/singleplayer/sql/` lives outside the init.txt mechanism on purpose. Same for other modules' sql dirs.
- If upstream fixes the loader, the `singleplayer/sql/` dir could move to `singleplayer/sql/` (see [[project-singleplayer-reorg]] / task #179) and be added to init.txt at the same time.
- Otherwise, leave sql handling alone and treat it as a separate dbtool flow.
