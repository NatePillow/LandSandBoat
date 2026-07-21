# Singleplayer bot AI — architecture & config reference

Reference/orientation doc for the server-side bot AI. Read this when getting your
bearings on `modules/singleplayer/bots/`. (Non-obvious *gotchas* that bite at
runtime are also captured as project memories — `project_config_http_server`,
`project_alliance_config_schema` — so they surface automatically; this doc is the
fuller on-demand reference.)

## Where things live

```
singleplayer/
  client/   Ashita addons + launcher assets (never under modules/, the server's hot-reload root)
  config/   Disk JSON: alliance/<name>.json + other server-side config
  data/     Static reference data
  docs/     Project docs
  scripts/  Custom scripts including Default.txt

modules/singleplayer/bots/
  bots.lua + bots_*.lua + ai_*.lua + role_*.lua   (hot-reloaded by LSB's FileWatcher on touch)
  docs/     this doc
```

## State model (two layers)

1. **Alliance singleton** — `xi.singleplayer.bots.alliance`, shared across every bot in the player's alliance. Holds `allianceTarget` (the one authoritative "mob the alliance is fighting" — see the `feedback-bot-ai-assist-target` memory), `roleMap`, `headlessCharIds`, `sc[]` (skillchain pairs, charId + WS + priority), `solo`, `parties` (party leaders + trust lists), `assistCharId`, `mainCharId`, `mainEntity`, formation state (`battleFormation`, `walkingFormation`, `campAnchor`), and candidate pools (`provokePool`, `stunPool`, `bashPool`, `rdmSleepPool`, `blmSleepPool`).
2. **Per-bot scratch** — `xi.singleplayer.bots.alliance.bot[charId]`, lazy-inited by `bots.ensure_bot(charId)`. The single home for every per-bot tick field (ability / magic / role / lot / rest / move). No module-local scratch tables.

## Decision flow (per bot, per tick)

- `bots.runCombatTick(bot, state)` dispatches on `alliance.roleMap[botId]`.
- Each role module (`role_tank`, `role_heal`, `role_nuke`, `role_rdm`, `role_melee`, `role_skillup`) defines `tick(bot)` as a priority cascade.
- Helpers in `ai_ability` / `ai_magic` / `ai_threat` / `ai_util` provide reusable predicates and actions.
- **Engine state is preferred over bot-side bookkeeping** wherever possible — notoriety lists, status effects, target tracking are read from the engine rather than mirrored in Lua.

## Disk config schema

`singleplayer/config/alliance/<name>.json`:

```json
{
  "alliance": [
    { "ptLeader": "Brutus",   "members": ["Penelope", "Minerva", "Ruby", "Ollie", "Astrid"] },
    { "ptLeader": "Varunius", "members": ["Zariah"],  "trusts": ["Shantotto", "Ulmia", "Joachim", "Karaha-Baruha"] },
    { "ptLeader": "Malfina",  "members": ["Freya"],   "trusts": ["Shantotto", "Ulmia", "Joachim", "Karaha-Baruha"] }
  ],
  "roles": {
    "tank":   ["Brutus"],
    "melee":  ["Freya", "Zariah", "Varunius", "Malfina", "Locke", "Edgar"],
    "heal":   ["Penelope"],
    "rdm":    ["Minerva"],
    "nuke":   ["Ruby", "Ollie", "Astrid"]
  },
  "sc": [
    { "priority": 1, "openName": "Freya",    "openWS": "Vorpal Thrust", "closeName": "Zariah",  "closeWS": "Dancing Edge" },
    { "priority": 2, "openName": "Varunius", "openWS": "Raging Rush",   "closeName": "Malfina", "closeWS": "Raging Fists" }
  ],
  "solo": {
    "Brutus": "Seraph Blade",
    "Locke":  "Wasp Sting",
    "Edgar":  "Penta Thrust"
  }
}
```

`bots_spawn.validate_config(cfg)` runs at load: every char name must exist in some
party's members, every WS must resolve via `GetWeaponskillByName`, every trust via
`xi.magic.spell.*`. **Any validation error aborts the spawn.**

### Role derivation

`bots_spawn.derive_role(name, cfg)` maps char names to `xi.singleplayer.bots.Role`
values. **Order matters — first match wins:**

1. `Role.Healer` ← in `roles.heal`
2. `Role.Rdm`    ← in `roles.rdm`
3. `Role.Nuker`  ← in `roles.nuke`
4. `Role.Tank`   ← in `roles.tank` (single-element list; the tank IS the assist target)
5. `Role.Melee`  ← in `roles.melee`
6. `Role.Idle`   ← everything else

`roles.tank` is a single-element list — exactly one tank per alliance, and they're
the char other bots assist for target selection. `roles.melee` is the canonical
melee list; every melee DD must be listed there.

`cfg.sc[]` (SC pairs) and `cfg.solo` (solo WSes) are **WS assignments, orthogonal to
role**. Every name in `cfg.sc[].openName/closeName` or a `cfg.solo` key must be in
`roles.melee` OR be the `roles.tank` entry — that's how the tank participates in SC
or solo WSes. Validator errors read like
`sc[0].openName: "Freya" must be in roles.melee or roles.tank` and abort the spawn.

## Engine extensions (LSB C++)

Added to support the bot AI:

- `lua_statuseffect.cpp` — `getStartTimeMs()` for ms-precision status-effect start
  time. **The existing `getStartTime` floors to seconds — too coarse for the SC
  close window**, which is why the ms variant exists.
- `luautils.cpp` — `GetWeaponskillProperties(wsId)` returning
  `{ primary, secondary, tertiary }` SC properties, so Lua can decode
  `EFFECT_SKILLCHAIN.getPower()` for multi-pair SC correctness.
- `src/map/singleplayer/auction_bot.cpp` — homegrown auction-house bot replacing
  ffxiahbot.
- `lua_baseentity.cpp` — `sortInventory(locID)` server-side stack consolidation
  (the 0x03A equivalent for headless with no client); shared impl in
  `charutils::ConsolidateContainerStacks`.
