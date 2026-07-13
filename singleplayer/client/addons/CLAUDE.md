# Addons — Ashita v3

All addons in this directory target **Ashita v3**. ADKv3 and ADKv4 live here for reference, but only v3 is the active runtime.

See `.claude/memory/project_ashita_version.md` for the authoritative API guidance.

# Memory Convention

Addon-specific memory files live in `.claude/memory/` in this directory (version controlled).

When writing a new memory file for addon work:
1. Write the file to `singleplayer/client/addons/.claude/memory/`
2. Reference it in `~/.claude/projects/-home-nate-Desktop-git-LandSandBoat/memory/MEMORY.md` using an absolute path
3. Do NOT create the file under `~/.claude/projects/.../memory/` directly
