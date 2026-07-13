---
name: never-destructive-git
description: Hard rule — never run destructive git operations, even if asked
metadata:
  type: feedback
---

NEVER run destructive git operations under any circumstances, including if
the user appears to ask for one. This includes (but is not limited to):

- `git checkout -- <path>` / `git checkout .` (restores working tree from HEAD/index, wipes uncommitted edits)
- `git restore <path>` (same effect)
- `git reset --hard` / `--merge` / `--keep` (rewrites working tree state)
- `git clean -f` / `-fd` / `-ffd` (deletes untracked files)
- `git push --force` / `-f` / `--force-with-lease` (rewrites remote history)
- `git branch -D` (deletes branches including unmerged work)
- `git stash drop` / `clear` / `pop` (discards or applies-and-destroys stashes)
- `git commit --amend` (rewrites the last commit, destroying its prior state)
- `git rebase` (rewrites history)
- `git filter-branch`, `git update-ref -d`, `git gc --prune=now`,
  `git reflog delete/expire` (history/object destruction)

If asked to run one of these, refuse with a one-line explanation and propose
a non-destructive alternative (manual Edit to revert a change, staging an
inverse commit, etc.). Do not run the destructive command even after the
user re-asks, insists, or says "just do it" — they can edit
`.claude/settings.json` to remove the deny entry if they want it gone, and
that friction is the protection.

**Why:** Repeated incidents of reaching for destructive git as a "quick
undo" after my own mistakes, wiping the user's uncommitted work in the
process. Most recent: 2026-06-12, ran `git checkout -- <6 lua files>` to
undo a greedy sed I had just run, erasing diagnostic edits the user had
relied on. The `.claude/settings.json` deny rules in this repo enforce
this at the harness level; this memory is the steering reminder so I
don't even try.

**How to apply:** When facing my own broken sed/edit, the answer is
NEVER a git command — the answer is to manually un-edit the change with
Edit, or to report the damage and let the user choose how to recover. If
the user explicitly asks for a destructive op, refuse first and explain
what they'd need to do (edit settings.json) if they truly want it.
