# Final Fantasy XI Single Player Mod

*This is user-facing documentation. For readers in a professional context, please see the technical analysis at [DIARY.md](DIARY.md)* 

This is a level 75 cap era version of FFXI updated to provide a single player experience. Support through Zilart and CoP is underway. Support for ToAU is likely, and other expansions are TBD. For gameplay videos, click [here](https://www.youtube.com/channel/UCHYGYv2hTlIhsI1JFeOa9Wg).

- [Major Changes](#major-changes)
- [Installation](#installation)
- [Quickstart Tips](#quickstart-tips)
- [Headless Characters](#headless-characters)
- [Addon Suite](#addon-suite)
- [Combat Addons](#combat-addons)
  - [autobots](#autobots)
  - [autoequip](#autoequip)
  - [autolot](#autolot)
  - [autodps](#autodps)
- [Utility Addons](#utility-addons)
  - [automog](#automog)
  - [autowarp](#autowarp)
- [Changelog](#changelog)

---

# Major Changes

* Philosophy
  * This projects aims to maximize fun, minimize tedium, and open up content. The golden age of FFXI has much to be fond of, but at the same time, it's true that a vast majority of players did not get to experience the vast majority of content.
  * Pick what role and character you want to play and fill the rest of your party with competent teammates that appear in camp instantly.
* Headless Characters
  * Full server-side character entities that join your alliance and act autonomously. They are indistinguishable from a player char; they have inventory, gear, spells, recasts, status effects, and live in the zone instance like everyone else.
  * Log into your headless characters like normal characters. You don't need to remain a static character while progressing from the Dunes to Qufim and beyond.
  * They can fulfill all the major roles, including tanking, off-tanking, skillchain partners, magic bursting, healing, buffing, debuffing, crowd control, stun orders, provoke orders, and pulling.
  * Customizable AI exposed via a large number of options across core job functions, battle and walking formations, item usage, and more.
  * Repeating job quests, limit breaks, and everything else multiple times across characters is tedious, and so an optional progression cascade system has been put in place. When activated, progression on the primary character is replicated across all alliance members.
* Trust Updates
  * Up to 5 trusts can be summoned per party at the start of the game.
  * Trusts can be summoned in alliances.
  * Trusts can be summoned in all battlefields (BCNM, ENM, missions, etc).
  * Several trust spells are available at the start of the game and all of these default Trusts have updated and improved AI.
* Economy
  * Crafting supplies, scrolls, some quest rewards, some tedious NM drops, ammo, and ninja tools are available for sale on the auction house and restock with a 15-minute delay.
  * Most items put on the auction house will be purchased based on factors including mob level, craft skill, and NM-only status.
  * Various quality of life updates, including expanded shop hours, hourly guild point item refresh, permanently available conquest items, and more.
* Era, Flavor, and Quality of Life
  * Advanced Start: Optionally start at rank 10 in all nations, at Divine Might, at Dawn, and with all homepoint and survival guide teleports.
  * 75-era tuning: no more sweet spot mechanic, Leaping Boots instead of Bounding Boots, era-specific modules included, pre-tuned LSB settings, and more.
  * Drop rates: Increased across the board, from NMs to BCNMs, to eliminate mindless farming. 
  * Treasure Chests & Coffers: All spawn points active simultaneously.
  * ... And more

---

# Installation

TODO

---

# Quickstart Tips

* Regular mob drops are now a legitimate source of gil in the early game, particularly scrolls and equipment.
* You and your merry band are going to need drops from NMs, and many NMs can be defeated while they give substantial experience. You can, and should, gain a large number of levels simply hunting drops.
* There is no need to have multiple characters with crafting skills, as there are easy ways to organize items across an entire alliance. There is a restock delay for items sold on the auction house, however, so start building up crafting skills early on.
* TODO

---

# Headless Characters

You define an alliance in the autobots config editor — each character's name and role assignment — then spawn it from the addon UI. The server loads each named character, zones them in next to you, and they start acting on their own. Provoke, sleep, and stun orders are automatically generated based on roles and jobs.

## Roles

| Role      | Purpose                                                                                                                                                                      |
|-----------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Tank`    | Hold hate, peel adds, handle job specific functions, and open/close skillchains when the tank is part of the chain. Support included for multi-tank parties.                 |
| `Melee`   | Damage dealer — arc around the mob, fire skillchains, handle off-tanking and provoke orders, and complete any job specific functions like SATA, Chi Blast, Spirit Link, etc. |
| `Healer`  | WHM-style — cure HP, status removal, raise, regen, bar spells, Protectra/Shellra, and nuking and RDM duties as needed.                                                       |
| `Rdm`     | RDM-style — Refresh, Haste, priority enfeebler, priority sleeper, and healing and nuking duties as relevant.                                                                 |
| `Nuker`   | BLM-style — magic-burst nukes, casual nukes, and healing and RDM duties as needed.                                                                                           |
| `Brd`     | BRD-style — song rotation (ballads / marches / minuets / etc.), Pianissimo, debuffing, sleeping, and backup healing.                                                         |
| `Smn`     | SMN-style — avatar summon, blood-pact rotation, and backup healing.                                                                                                          |

## AI Customization

TODO: Rewrite this into something more useful, maybe a table.

* The autobots **Alliance AI** tab carries alliance-wide settings that don't fit a specific role: headless aggro mode, stun behavior, multi-engage toggle, skillchain start / stop mob-HP thresholds, primary-character AI (off / combat-only), puller selection with range / con / nearby-name filters, and walking + battle formation choice.
* Status card toggles contain per-character tactical toggles render as a card grid on the autobots **Status** tab — these are knobs that change the bot's per-tick behavior without changing role assignment: SATA mode (combined / split / SA-only), heal scope (party / alliance assist / alliance main), add-control (provoke / flash / both), THF RA cadence (Off / 5s / 10s / 15s / 20s / 30s), SMN avatar selection, and tank nudge.
* Per-role item-usage policy is configured in the autobots **Item AI** tab. Each combat role (Tank / Melee / Heal / RDM / Nuke / BRD / SMN) has independent HP / MP / Status mode toggles:
    * **HP / MP modes:** `Off` / `NM Only` / `Always`. Thresholds are hardcoded at 20%; the character burns its strongest-tier potion/ether (Hyper → Max → X → Hi → base for HP; Hyper → Pro → Super → Hi → base for MP).
    * **Status mode:** `Off` / `NM Only` / `Always` / `Poison`. The last is a narrow "use a status-cure item only on rest-blocking afflictions" — its name reflects that Poison is the only currently item-curable rest blocker.
    * **Per-status checkboxes:** Poison / Silence / Blind / Paralyze / Curse / Disease (the engine-curable subset). Specific items (Antidote / Echo Drops / Eye Drops / Holy Water) fire first; Remedy is the fallback **and** the preferred choice when 2+ Remedy-curable statuses are stacked.
    * **Melee MP** items are gated server-side to DRK / BLU mainjobs.

## Sync features

The autobots Controls tab carries three progression-cascade buttons. These will "copy" quest, mission, and teleport progression from the primary character and apply them to all headless characters in the alliance. This is the defense against the tedium of managing an alliance full of real characters.

| Button             | What it copies                                                                                                                                                          |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Sync Quests**    | Primary's completed quests (recipe-driven), plus the AF1 coffer item set.                                                                                               |
| **Sync Missions**  | Nation / Zilart / CoP mission completion bits.                                                                                                                          |
| **Sync Teleports** | All 13 `TELEPORT_TYPE` bitfields — home points, survival guides, waypoints, Eschan portals, Abyssea conflux, Runic portal, Past Maw, Campaign zones, Outpost teleports. |

---

# Addon Suite

The addon suite was created for Ashita v3. Addons are only unlocked against a server running the single player fork, otherwise they are inert. All addons support headless characters. A character selector is placed at the top of relevant addons where headless characters can be selected and their details viewed and updated. In particular, automog and autoequip will allow you to manage headless characters without logging into them.

Gear swapping is driven by an internal mechanism that uses AshitaCast v3 XML configuration files stored under `config/AshitaCast` and thus no gear swap addon is required. In fact, traditional gear swap addons require a full client up and running, which is not available to headless characters. Support for the XML configurations includes the standard rule blocks such as `<precast>` and `<midcast>` and the full set of conditionals. An additional `<gearlock>` block is supported and can be used to set style locks, however some advanced features such as variables are not supported. These XML files can be edited via autoequip addon UI, and manually created XML files can be placed directly into the server directory.

In addition to the addon UI, some features also have chat command equivalents, although commands are likely to become deprecated and eventually removed.

| Addon                   | Purpose                                                                                                                                            |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| [autobots](#autobots)   | Alliance launchpad and headless AI settings. A compact Quick Menu offers quick access to core commands while taking up limited screen real estate. |
| [autoequip](#autoequip) | View current equipment and update gear swap sets and logic, with support for headless characters.                                                  |
| [automog](#automog)     | Your Mog House on the go. Access all containers and transfer between them, access the auction house for buying and selling activities.             |
| [autolot](#autolot)     | Automatically lot and pass for configured items and groups.                                                                                        |
| [autodps](#autodps)     | Per-character DPS tracking with party/alliance roll-up.                                                                                            |
| [autowarp](#autowarp)   | Teleport a named player or enemy to your position. Largely a debug tool that will vanish before full release.                                      |

---

# Combat Addons

---

## autobots

The alliance launchpad and central UI for the headless-character system. Six tabs:

**Quick Menu** — Compact UI with a minimal footprint that provides the most commonly used features. This includes: Start / Stop Actions, Start / Stop Movement, Start / Stop Pulling, Attack / Finish, Use Food, Summon Trusts, and the primary AI, walking, and battle formation selectors.

**Controls** — Alliance management and one-shot actions such as: Spawn / Despawn Alliance, Summon Trusts, Give Signet, Start / Stop Actions and Movement, Pause / Resume Skillchains, Use Food, the Sync Quests / Sync Missions / Sync Teleports cascade, party / alliance battlefield entry, and a temporary debug section. The right column shows the active/selected config info and the Alliance / Food config selectors (with New and Delete buttons to manage files, and Edit buttons that open the editors to create and update configs).

**Skill Ups** — Per-character skill-up settings: Off / Ranged / Magic plus a spell picker. When active, typical role behavior for a headless character is disabled, and instead headless focus on skillups.

**Alliance AI** — Alliance-wide settings such as: headless aggro mode, stun behavior, multi-engage, skillchain start / stop mob-HP thresholds, primary-character AI (off / combat-only), and battle and walking formation selectors. The right column is the puller config (which headless character pulls, the yalm and difficulty ranges, and nearby-name filter).

**Item AI** — Per-role item-usage policy. Each combat role gets independent Health / Mana / Status item-mode toggles.

**Status** — Per-character card grid showing status effect icons and tactical toggles (SATA mode, heal scope, add-control, THF RA cadence, SMN avatar, tank nudge, etc).

### Commands

| Command                                           | Description                                                                                  |
|---------------------------------------------------|----------------------------------------------------------------------------------------------|
| `/autobots` \| `/autobots ui` \| `/autobots show` | Toggle the AutoBots window.                                                                  |
| `/autobots start [<config>]`                      | Spawn the alliance from the named config; with no arg, "Start Actions" (resume AI).          |
| `/autobots stop`                                  | "Stop Actions" — pause combat AI alliance-wide; bots stay spawned and movement is preserved. |
| `/autobots despawn`                               | Despawn every headless owned by you.                                                         |
| `/autobots attack`                                | Engage your current target across the alliance.                                              |
| `/autobots finish`                                | Flag nukers / RDM to burn the current target until it dies.                                  |
| `/autobots food [<config>]`                       | Feed every headless per the food config; with no arg, list available food configs.           |
| `/autobots instance \| bcnm party \| alliance`    | Bring your party / alliance into your active battlefield.                                    |

### Alliance Config

Alliance configs are stored server-side and edited in-app via the **Edit** button in the config selector. The stored shape:

```json
{
  "alliance": [
    {
      "ptLeader": "Brutus",
      "members": ["Penelope", "Minerva", "Ruby", "Ollie", "Astrid"]
    },
    {
      "ptLeader": "Varunius",
      "members": ["Zariah"],
      "trusts": ["Shantotto", "Ulmia", "Joachim", "Karaha-Baruha"]
    },
    {
      "ptLeader": "Malfina",
      "members": ["Freya"],
      "trusts": ["Shantotto", "Ulmia", "Joachim", "Karaha-Baruha"]
    }
  ],
  "roles": {
    "tank":   ["Brutus"],
    "heal":   ["Penelope"],
    "rdm":    ["Minerva"],
    "nuke":   ["Ruby", "Ollie", "Astrid"],
    "melee":  ["Freya", "Zariah", "Varunius", "Malfina"]
  },
  "sc": [
    {
      "priority":  1,
      "openName":  "Freya",
      "openWS":    "Vorpal Thrust",
      "closeName": "Zariah",
      "closeWS":   "Dancing Edge"
    },
    {
      "priority":  2,
      "openName":  "Varunius",
      "openWS":    "Raging Rush",
      "closeName": "Malfina",
      "closeWS":   "Raging Fists"
    }
  ],
  "solo": {
    "Brutus":   "Seraph Blade"
  }
}
```

### Food Config

Food configs are stored server-side (edited via the same in-app config editor) and map character → food item name. Pressing **Use Food** in the autobots UI feeds character in one shot.

```json
{
  "Brutus": "Tavnazian Taco",
  "Freya": "Meat Mithkabob",
  "Varunius": "Meat Mithkabob",
  "Zariah": "Meat Mithkabob",
  "Malfina": "Meat Mithkabob",
  "Minerva": "Tropical Crepe",
  "Ruby": "Tropical Crepe",
  "Astrid": "Tropical Crepe",
  "Ollie": "Tropical Crepe",
  "Penelope": "Tropical Crepe"
}
```

---

## autoequip

Browse and edit gear across every character in your alliance from a single window. Three tabs:

**Current** — the live equipped-items list for the selected character (all 16 slots, with a job / level header). Each occupied slot has an unequip button; clicking a slot opens a per-slot picker that lists equippable candidates from inventory and every wardrobe, dims what the current job/level can't wear, and previews a green/red stat diff before you commit. Sourced from the server-side character profile, so it works for the primary **and** headless characters — you can gear a headless character from your own client.

**Gear Sets** — reads the AshitaCast XMLs in `config/AshitaCast/` and presents them as an editable table per character × job. Changes are written back to the on-disk XML and the server re-reads them on the next swap.

**Swap Logic** — a freeform raw-text editor for the rule blocks such as `<precast>`.

| Command                           | Description                                                  |
|-----------------------------------|--------------------------------------------------------------|
| `/autoequip` \| `/autoequip show` | Toggle the AutoEquip window.                                 |
| `/autoequip reload`               | Re-read the gear XML + swap logic for the current character. |

---

## autolot

Manages how and when characters automatically lot or pass items in the treasure pool. Characters will lot items based on static groups (always lot) or one-off assignments (lot until 1 copy owned). If an item in the treasure pool is lotted by another character and the character in question does not have that item on any of their lists or in any assigned groups, they will automatically pass said item. Two tabs:

**Pool & History** — a two-column view: the live treasure pool (read-only) on the left, and a Drop History of the last 100 unique items seen this session on the right. From a History row you can add an item to a group or open its **Lot List** to pick the characters who should lot that item until each owns one.

**Groups** — create and edit named item groups (persisted server-side) for bulk lot-list assignment.

| Command                       | Description                |
|-------------------------------|----------------------------|
| `/autolot` \| `/autolot show` | Toggle the AutoLot window. |
| `/autolot reload`             | Reload the saved groups.   |

---

## autodps

Per-character DPS tracking.

| Command                       | Description                |
|-------------------------------|----------------------------|
| `/autodps` \| `/autodps show` | Toggle the AutoDps window. |
| `/autodps hide`               | Hide the AutoDps window.   |
| `/autodps reset`              | Reset local DPS tracking.  |


---

# Utility Addons

---

## Config and Data Files

| File                            | Purpose                                                                                                                                      |
|---------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| `config/autoitem/items.csv`     | Item list for the new automated autoction house. Contains a list of items and whether to sell them, whether to buy them, and at what prices. |
| `config/autoitem/recipes.lua`   | Recipe definitions keyed by lowercase name.                                                                                                  |
| `config/autoitem/aliases.json`  | Recipe name aliases.                                                                                                                         |
| `config/autoitem/groups/*.json` | Item group definitions with per-item quantities                                                                                              |
| `config/alliance/*.json`        | Headless-alliance configs — stored server-side, edited via the autobots UI                                                                   |
| `config/food/*.json`            | Food assignments per character — stored server-side, edited via the autobots UI                                                              |
| `config/AshitaCast/*.xml`       | Per-character / per-job gear-swap XML (shared between client and server)                                                                     |

## Built-in Groups

TODO: These are not yet surfaced in any UI.

| Group               | Aliases                 | Items                                                           |
|---------------------|-------------------------|-----------------------------------------------------------------|
| Gobbiebag Part I    | `gobbiebag i`, `gb1`    | Dhalmel Leather, Steel Ingot, Linen Cloth, Peridot              |
| Gobbiebag Part II   | `gobbiebag ii`, `gb2`   | Ram Leather, Mythril Ingot, Wool Cloth, Turquoise               |
| Gobbiebag Part III  | `gobbiebag iii`, `gb3`  | Tiger Leather, Gold Ingot, Velvet Cloth, Painite                |
| Gobbiebag Part IV   | `gobbiebag iv`, `gb4`   | Cermet Chunk, Darksteel Ingot, Silk Cloth, Goshenite            |
| Gobbiebag Part V    | `gobbiebag v`, `gb5`    | Bugard Leather, Paktong Ingot, Moblinweave, Rhodonite           |
| Gobbiebag Part VI   | `gobbiebag vi`, `gb6`   | H.Q. Eft Skin, Shakudo Ingot, Balloon Cloth, Iolite             |
| Gobbiebag Part VII  | `gobbiebag vii`, `gb7`  | Lynx Leather, Adaman Ingot, Rainbow Cloth, Deathstone           |
| Gobbiebag Part VIII | `gobbiebag viii`, `gb8` | Smildn. Leather, Electrum Ingot, Cilice, Angelstone             |
| Gobbiebag Part IX   | `gobbiebag ix`, `gb9`   | Peiste Leather, Orichalcum Ingot, Oil-Soaked Cloth, Oxblood Orb |
| Gobbiebag Part X    | `gobbiebag x`, `gb10`   | Griffon Leather, Molybdenum Ingot, Foulard, Angel Skin Orb      |

---

## automog

The economy and inventory hub for every character in your alliance from a single window.

**Status** — Per-character sheet for the selected char (primary or headless). The left column contains character details such as name, race, job, stats, combat skills, and magic skills. The right column contains gil, a Sort Inventory button (server-side, works for headless), delivery-box retrieval, learn and buy scrolls buttons, and two live editors: Change Job (swap main / sub job among unlocked jobs) and Change Look (change race, face, and size). Both editors work on the primary and on any owned headless.

**Inventory** — Browse any bag (inventory, sacks, satchel, wardrobes, etc.). Multi-select items and trade the selection to any party member, or drop selected items / all-of-type from main inventory.

**Transfer** — Move items between bags, with bulk-move helpers and support for bulk transfer between alliance members.

**Auction House** — Left: browse AH listings by top-level and sub-category. Equipment categories support job and level filters. Select a listing to buy at price-list price or at the live AH ask. Right: sell items from inventory to the AH by name with single/stack and quantity controls.

**Craft** — Left column: recipe list with search, favorites, sort by name or skill level, and collapsible Skills and Equipment filters. Craft mode is All (run until ingredients run out), Count, or HQ N (stop after N distinct HQ results). Right column: recipe detail with a Buy Ingredients action that purchases all missing ingredients from the AH in one shot.

**NM Hunter** — Browse notorious monsters within a specified level range, including their drops.

**History** — Timestamped log of status messages from all automog activities.

### Commands

| Command                                                     | Description                                                                                                |
|-------------------------------------------------------------|------------------------------------------------------------------------------------------------------------|
| `/automog` \| `/automog ui` \| `/automog show`              | Toggle the AutoMog window                                                                                  |
| **Delivery box**                                            |                                                                                                            |
| `/automog box`                                              | Retrieve all incoming delivery box items silently                                                          |
| **Buy**                                                     |                                                                                                            |
| `/automog buy item <item_id> single\|stack <qty>`           | Purchase an item by ID from the AH at price-list price                                                     |
| `/automog buy recipe <Recipe> [v<n>]`                       | Purchase all ingredients for a recipe from the AH; aborts if any ingredient is unavailable                 |
| `/automog buy partial <Recipe> [v<n>]`                      | Like `recipe`, but skips unavailable ingredients instead of aborting                                       |
| `/automog buy vendor <Item Name> single\|stack <qty>`       | Purchase from the targeted vendor NPC; must be within 6 yalms                                              |
| `/automog buy group <Group Name>`                           | Purchase all items in a predefined group JSON from the AH                                                  |
| `/automog buy scrolls`                                      | Purchase all unlearned spells for the current job/level from the AH                                        |
| `/automog buy stop`                                         | Cancel any pending buy operation                                                                           |
| **Sell**                                                    |                                                                                                            |
| `/automog sell <item name> single\|stack <qty>`             | List matching inventory items on the AH at the configured price                                            |
| `/automog sell stop`                                        | Cancel pending listings                                                                                    |
| **Craft**                                                   |                                                                                                            |
| `/automog craft recipe <Name> [v<n>] [<count>\|all\|hq<N>]` | Start synthesis; stop after a count, `all` until ingredients run out, or `hq<N>` for N distinct HQ results |
| `/automog craft search <term>`                              | Search recipe list by partial name                                                                         |
| `/automog craft info <Name>`                                | Print all variants and ingredients for a recipe                                                            |
| `/automog craft alias add <alias> <Recipe> [v<n>]`          | Save a short alias for a recipe and optional variant                                                       |
| `/automog craft alias remove <alias>`                       | Remove a saved alias                                                                                       |
| `/automog craft alias list`                                 | List all saved aliases                                                                                     |
| `/automog craft stop`                                       | Stop the current synthesis run                                                                             |
| **Scrolls**                                                 |                                                                                                            |
| `/automog scrolls`                                          | Learn all learnable scrolls in inventory (skips already-known and wrong job/level)                         |
| **Drop**                                                    |                                                                                                            |
| `/automog drop <item name>`                                 | Queue all matching inventory stacks for dropping                                                           |
| `/automog drop stop`                                        | Cancel pending drops                                                                                       |

---

## autowarp

Debug tool with no plans to include in the full release. Teleport a named player (server-wide) or a named enemy (current zone) to your position.

| Command                   | Description                                                                                                              |
|---------------------------|--------------------------------------------------------------------------------------------------------------------------|
| `/autowarp player <name>` | Warp the named player to your position; triggers a zone change if they are in a different zone.                          |
| `/autowarp enemy <name>`  | Warp the named enemy in your current zone to your position; must be within 100 yalms; underscores are treated as spaces. |

---

# Changelog

TODO: This is very outdated and full of AI edits on top of a human rough draft. It needs a human deep dive. Also need to revert some changes now that a progression cascade system is in place.

> Items marked *(settings-gated)* are controlled by `settings/main.lua`, `settings/map.lua`, or `singleplayer.json` and can be toggled per-server.

* Headless Characters
    * Spawn a full alliance of bot-controlled characters from a single JSON config under `config/alliance/`
    * Seven combat roles — Tank, Melee, Healer, RDM, Nuker, Bard, Summoner — plus a Skillup role for magic skill grinding
    * Per-role item-usage policy (HP / MP / Status) configurable in the autobots **Item AI** tab
    * Alliance-wide AI knobs (aggro mode, stun behavior, multi-engage, SC HP thresholds, puller config, formation choice) in the **Alliance AI** tab
    * Per-character tactical toggles on the **Status** tab — SATA mode, heal scope, add-control, THF RA cadence, SMN avatar, tank nudge
    * **Sync Quests**, **Sync Missions**, and **Sync Teleports** buttons mirror your progress onto every headless on demand
    * Change any character's job (main / sub) and appearance (race / face / size) live from the automog **Status** tab — works on the primary and on headless bots
    * Gear any character slot-by-slot from autoequip's **Current** tab, with a live stat-diff preview, including headless bots
    * Battle formations (tight / spread / AoE / BRD Spread) station mages off the mob axis while melees arc behind
    * Walking formations (column / rows / camp) for travel and idle holding
    * Navmesh-aware character movement — bots no longer walk through walls
    * "Summon Trusts" button per party leader using the alliance config's trust list
    * "Give Signet" cascades the standard nation-guard signet onto every owned headless
    * "Stop Actions" / "Start Actions" pause and resume character AI without despawning
    * BCNM / Dynamis / Instance entry brings the selected subset of the alliance into your active battlefield
    * Smart consumable use — potions and ethers walk the strongest-to-weakest tier list; Remedy is preferred when 2+ Remedy-curable statuses are stacked
    * Out-of-combat mage cross-cure — Poison and other rest-blocking DoTs on party mages are cleared automatically so /heal on works
* Battle
    * Sweet spot mechanic nullified for ranged attacks
    * Sneak Attack no longer has a positional requirement
    * Experience reward no longer scaled down by party / alliance size
* Trusts
    * Up to 5 trusts per party from the start of the game
    * Trusts can be summoned in alliances and display correctly in the UI
    * Trust spells and abilities updated across the cast for fork-friendly behavior
    * Several trust AOE spells removed to reduce friendly fire and claim interference
    * No wait time before summoning trusts after inviting a PC
* Economy
    * Server-side replacement for ffxiahbot — the auction bot is built into LSB; `config/autoitem/items.csv` provides prices, stock, and per-item buy/sell flags
    * AH lists crafting supplies, scrolls, some quest rewards, some tedious NM drops, ammo, and ninja tools
    * AH buy/sell prices generally scale on mob level, craft skill, and NM-only status
    * Shops never close
    * Equipment of level 76+ excluded from AH listings
    * Sale notifications appear when your AH listings sell
    * Listing pagination — auctions browse without truncation at high counts
    * automog provides batch buy/sell, recipe ingredient purchasing (full or partial), vendor-proximity buy, and a stop/cancel control
* Transportation
    * `/welcome` warps the entire alliance to your position
    * All home points and survival guides unlocked from the start *(settings-gated)*
    * Home points can also heal you on use, single-player FF style *(settings-gated)*
    * autowarp warps any named player (server-wide) or enemy (current zone) to your position
* Missions
    * All three nation missions auto-completed at character creation, with rewards delivered *(settings-gated)*
    * Rise of the Zilart begins at Divine Might *(settings-gated)*
    * Chains of Promathia begins at Dawn *(settings-gated)*
* Quests
    * Full Speed Ahead minigame auto-skipped and marked successful (first mount unlocked)
    * Dark Knight Chaosbringer quests require 1 and 2 kills instead of 100 and 200
* Crafting
    * All crafting skills can be raised to 100
    * Crafting skill cap is 2× your character's highest job level (anti-grind for early game)
    * Increased GP redemption ceiling
    * Guild items reset every Vana'diel day
    * Craftmaster Ring granted at start (+10% HQ rate) *(settings-gated)*
    * Kupo Shield is a craftable item — Lvl 60 in all 8 crafts; one each of Tiger Leather, Glass Fiber, Silk Cloth, Platinum Ingot, Darksteel Ingot, Ebony Lumber, Kitron Macaron, Demon Arrowhead
    * automog brings recipe favorites, skill / equipment filters, "Buy Ingredients" one-shot, and an HQ-N mode (stop after N distinct HQ results)
* Drop Rates
    * Increased drop rates across the board to respect the player's time
    * All items roll individually; no group/exclusion mechanic remains
    * Generic equipment and scrolls have a smaller bump to avoid constant inventory clearing
    * Each Treasure Hunter level adds a linearly increasing bonus
    * Seals and rocks have no cooldown and a 60% drop rate
    * Padfoot always drops its rare reward
* Battlefields
    * Trusts usable in every battlefield
    * Drops greatly improved across BCNM (level 20/30/40/50/60), ENM (30/40/50/60/75), and the uncapped fates (Atropos, Clotho, Lachesis, Themis)
    * Some battlefields rebalanced with fewer mobs to be solo-achievable
    * Orbs have 10 uses, testimony items have 99 uses
* NM Spawning
    * `/psych` (emote) spawns any NM in the current zone
    * Many NMs respawn continuously after death for efficient farming
    * Lottery NMs spawn immediately, no placeholder kill required
    * NM time-of-death persists across server restarts, preventing rush-after-restart exploits
    * Mob spawn conditions nullified — no need to align weather / time / moon
    * Ship-bound mob spawn conditions also nullified
    * automog **NM Hunter** tab browses NMs by zone with respawn-window and key-item gating info, with a one-click spawn
* Item Updates
    * Royal Cloak now gives +2 MP/tick
    * Flute (NQ / +1 / +2) equippable by mage jobs
    * Warp Ring in starting inventory *(settings-gated)*
    * All three nation rings at start *(settings-gated)*
* Treasure Chests & Coffers
    * Every possible spawn location active simultaneously
    * 3-minute respawn at each location
* Medicine
    * Many medicines now stack (stack count is not shown in UI but they do stack)
    * Medicine no longer causes the medicated status
* Limit Breaks
    * Key items for fetch-style limit break quests granted at start *(settings-gated)*
* Conquest
    * All items available for purchase regardless of conquest rank
    * Regional NPCs always available regardless of conquest standing
    * Outposts marked safe — no enemy occupation gating
* Player & World
    * New-player linkshell auto-issued *(settings-gated)*
    * Player-login announcements broadcast to active sessions
    * World-first announcements for milestone kills and crafts
* Settings
    * LSB settings for main and map updated to be consistent with project goals
    * `singleplayer.json` toggles the new-character auto-completion suite (missions, KIs, rings, etc.)
