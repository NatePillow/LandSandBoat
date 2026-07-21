# Server-side bot AI — directory notes

**Before working here, read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).** It's the
orientation map: the two-layer state model (`alliance` singleton + per-bot scratch),
the per-tick decision flow, the alliance config schema, role derivation, and the
C++ engine extensions. It won't auto-load — this pointer exists so it gets read.

Runtime gotchas for this subtree are captured as project memories (auto-indexed in
the main `MEMORY.md`): alliance-config schema pitfalls, the config-HTTP-server
setup, "the mob" = `alliance.allianceTarget` (not primary/assist), filewatcher
`touch`-after-edit, one-statement-per-line + elseif cascades. Prefer those over
re-deriving.
