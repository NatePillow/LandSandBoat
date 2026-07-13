# Memory Convention

Project-specific memory files live in `.claude/memory/` in this repo (version controlled), not in `~/.claude/projects/`.

When writing a new memory file for this project:
1. Write the file to `.claude/memory/` in this repo
2. Reference it in `~/.claude/projects/-home-nate-Desktop-git-LandSandBoat/memory/MEMORY.md` using an absolute path
3. Do NOT create the file under `~/.claude/projects/.../memory/` directly

Addon-specific memories (Ashita API, specific addon bugs) go in `singleplayer/client/addons/.claude/memory/` instead, and are indexed in `~/.claude/projects/-home-nate-Desktop-git-LandSandBoat/memory/MEMORY.md` with their absolute paths as well.

Note: client-side artifacts (Ashita addons, eventually any other launcher copies) live under `singleplayer/client/` — **never** under `modules/`, which is the server's hot-reload watch root. The wider `singleplayer/` root also holds `config/`, `data/`, `docs/`, `scripts/Default.txt`, and the project README; only `modules/singleplayer/{lib,lua,sql}/` remains in `modules/` (proper LSB module content).
