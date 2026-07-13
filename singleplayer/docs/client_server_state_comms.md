# Client ↔ Server State & Config Communications Audit

Catalog of every data flow between the singleplayer fork's map server and its
Ashita v3 client addons. Generated as the design input for **#231 — Push all
server-side bot state back to client addons** and the adjacent cleanup tasks
**#203** (data-retrieval audit) and **#230** (diff-based alliance update).

Scope: custom packet space `0x150–0x1FF` only. Upstream LSB packets are
mentioned only where the addons explicitly subscribe to them for context
(`0x00A` zone change, `0x075` battlefield, `0x028` trades, `0x150` ident
heartbeat).

> Some rows below were flagged by the auditing agent as possibly stale (e.g.
> `0x178 HEADLESS_STATE` is described as "Phase 3+, payload TBD"). Treat
> "TBD" rows as inventory hints, not confirmed wire shapes — re-verify
> against the enum + packet header before designing on top of them.

---

## 1. Configs

| Name / Purpose | Direction | Packet IDs | Trigger | Consumer / Cache | Push Model | Notes |
|---|---|---|---|---|---|---|
| Alliance config list (categories) | C2S req → S2C resp | `0x17A` → `0x17B` (chunked, 14/pkt) | `send_list_configs('')` on first server-ident unlock, manual refresh | `autoutil.server_configs[category]`; `on_config_list()` callbacks | One-shot per category on final chunk | **Speculative pre-fetch** on unlock. Cache reset is rising-edge on `server_configs_final[category]`. |
| Alliance config content | C2S req → S2C resp | `0x17E` → `0x17F` (chunked, 448B/pkt) | UI opens config editor | `autoutil.server_config_content[cat][name]` string; `on_config_content()` callbacks | Chunks accumulate in `config_content_pending`; concatenated on final | Never auto-cleared client-side. |
| Alliance config XML subtree write | C2S req → S2C ack | `0x180` → `0x181` | User saves a single `<set>` / subtree | `set_xml_callbacks[key]` → fires `(result, bytes_written)` | Single ACK after all chunks land | Result codes: 0=ok, 1=bad-cat, 2=not-found, 3=bad-subtree-path, 4=parse-failed, 5=write-error. Chunked send (400B/pkt). |
| Alliance config whole-file write | C2S req → S2C ack | `0x189` → `0x18A` | UI uploads full JSON config | `set_config_callbacks[cat\|name]` → `(result, bytes_written)` | Single ACK; atomic replace | Result codes mirror `0x181`. |
| Config file create | C2S req → S2C ack | `0x182` → `0x183` | "Create New" button | `create_config_callbacks[cat\|name]` → `(result, extension)` | Single ACK | Codes: 0=ok, 1=bad-cat, 2=exists, 3=write-err, 4=bad-ext. Template chosen server-side. |
| Config file delete | C2S req → S2C ack | `0x187` → `0x188` | "Delete" button | `delete_config_callbacks[cat\|name]` → `(result)` | Single ACK | Codes: 0=ok, 1=bad-cat, 2=not-found, 3=err. Server auto-discovers extension. |
| Food config selection | C2S **F&F** | `0x17D` | "Use food" button | None | Immediate apply; no reply | Server walks primary + headless, calls `bot:useItem()`. |

---

## 2. Bot state (per-bot + alliance settings)

All entries here are **fire-and-forget** (F&F). Server is authoritative but
emits no confirmation; addon UI mutates a local mirror on click and assumes
sync. This is the surface task #231 is intended to fix.

| Name / Purpose | Packet IDs | Trigger | Server-side field | Notes |
|---|---|---|---|---|
| Per-bot mode (Off/CombatOnly/Full) | `0x176` sub `0x01` | UI button per bot | `bot.m_botMode` | `autobots_ui.lua:288` typical send point |
| Per-bot role (Idle/Tank/Healer/Nuker/Rdm/Melee) | `0x176` sub `0x04` | Config load or UI | `bot.assignedRole` | |
| Per-bot SATA mode (Combined/Split) | `0x176` sub `0x13` | Config load or UI toggle | per-bot SATA schedule | |
| Per-bot heal mode (on/off + mages_only) | `0x176` sub `0x07` | "Heal On/Off" buttons | `bot.healMode`, `bot.healMagesOnly` | Two booleans paired in one 12B payload |
| Per-bot SC thresholds (start% / stop% / nomore%) | `0x176` sub `0x12` | Slider UI | `bot.scState.upperHp/lowerHp/noMoreHp` | one-of-three sent per call (which=0/1/2) |
| Alliance mode (Off/CombatOnly/Full/MovementOnly) | `0x176` sub `0x0B` | Stop/Start buttons | walks all headless | |
| Alliance NM mode (Off/On/Auto) | `0x176` sub `0x10` | NM selector | alliance `is_nm` | clamped [0,2] server-side |
| Formation (battle/walking + name) | `0x176` sub `0x0D` | Config load or button | primary + bots cascade | two params: kind(0/1) + name[12] |
| Puller designation | `0x176` sub `0x15` | "Set Puller" / blank to clear | `alliance.pullerCharId` | |
| Puller scan range (yalms) | `0x176` sub `0x16` | Range slider | `alliance.pullerRange` (clamped [5,255]) | |
| Puller difficulty window (min/max con) | `0x176` sub `0x17` | TW/EP/DC/EM/T/VT/IT radios | `alliance.pullerMinCon/MaxCon` | u8 pair, clamped [0,6], auto-swapped if reversed |
| Puller name filter (allow list) | `0x1A2` | UI checkbox Apply | `alliance.pullerNameFilter` (≤16 × 24B) | Dedicated 392B packet (4 header + 1 count + 3 pad + 16×24 names) because too big for 0x176's 12B payload |

### Puller nearby-names discovery (the one bot-state flow with a reply)

| Name / Purpose | Direction | Packet IDs | Trigger | Consumer / Cache | Notes |
|---|---|---|---|---|---|
| Puller nearby-names scan request | C2S req → S2C resp | `0x176` sub `0x18` → `0x1A4` | "Refresh" button | `autobots_ui.puller_nearby_names`, sorted desc by count; selection in `puller_selected_names`; **cleared on zone change (0x00A)** | Top-20 mob names within 255y of camp anchor. Addon merges across refreshes via `merge_puller_names()`. |

---

## 3. Bot command dispatch (one-shot actions)

All fire-and-forget; no reply.

| Name / Purpose | Packet IDs | Notes |
|---|---|---|
| One-shot bot action (ma/ja/ws/ra/item) | `0x1A0` | 64B opcode. `BotName[16] + ActionKind[8] + ActionName[32] + TargetId u32`. Server validates ownership + action existence. |
| Attack (uses player's current target) | `0x176` sub `0x02` | TargetId u32 from `AshitaCore:GetTarget()` |
| Disengage | `0x176` sub `0x03` | No payload |
| Despawn all | `0x176` sub `0x05` | Walks owned headless, destroys sessions |
| Fire all weapon skills | `0x176` sub `0x11` | Bypasses SC/MB window gates; TP ≥ 1000 + engaged still required |
| Finish (nuke until dead) | `0x176` sub `0x06` | Sets `nukeUntilDead=true` on owned headless |
| Spawn dead bots (raise + weakness) | `0x176` sub `0x0C` | Revive + homepoint loss + snap to primary |
| Summon trusts (direct) | `0x176` sub `0x09` | Reads active alliance config, fires `summonTrustDirect`. No recast/dup check. |
| SC pause (global/sc1/sc2) | `0x176` sub `0x0A` | Replaced legacy 0x151/0x152 relay path |

---

## 4. Alliance / world state

| Name / Purpose | Direction | Packet IDs | Trigger | Consumer / Cache | Notes |
|---|---|---|---|---|---|
| Server ident (fork detection heartbeat) | C2S req → S2C resp | `0x153` → `0x150` | Addon `load` event; periodic heartbeat | `autoutil.unlocked` bool, `autoutil.serverIdent` string | Heartbeat ~1Hz if any C2S traffic. **First 0x150 receipt triggers `send_list_configs('')`** for every category — main #203 target. |
| Alliance PC roster (online) | C2S req → S2C resp | `0x185` → `0x186` | Server-ident unlock; battlefield entry rising edge (0x075) | `autoutil.alliance_pcs[]` {name, party} | Single packet (alliance ≤ 18). PCs only — no trusts. **Never auto-cleared.** |
| Party status (per-member effects) | S2C push | `0x191` | Periodic + per-member-change from autostatus.lua | Fan-out via `party_status_callbacks[]`; no persistent cache | 6 members max; effects[32] u16 per member; stride 82B. |
| Character roster (online + offline) | C2S req → S2C resp | `0x18D` → `0x18E` (chunked, 28/pkt) | Addon load, refresh | `autoutil.char_names[]`, `autoutil.char_jobs[name]=mainjob byte` | Cleared on first chunk after prior `final=true`. Used by alliance editor + automog. |
| Instance entry result | S2C resp (to C2S 0x16A) | `0x1A0` | Server processes 0x16A | `autoutil.last_instance_enter_result = {status, branch, moved}` | Single-packet ACK. |
| Headless event broadcast (log messages) | S2C push | `0x179` | Server bot AI emits event | `autoutil.log(tag, msg)` direct fan-out | Per-event type. 0x01 LOG_MESSAGE: `Tag[16] + Message[44]`. |
| Headless state (per-bot HP/MP/engaged/mode) | S2C push | `0x178` | Periodic tick or major state change | dps/status tab read-through | **FLAGGED — agent marked exact payload as TBD; verify before designing on top.** |
| Alliance config hot-swap | C2S **F&F** | `0x176` sub `0x08` | Config dropdown "Load" | UI: `running_config_name` mirror | Despawns current bots (with save) + respawns from named JSON; brief flicker. |

---

## 5. Autoskill state

| Name / Purpose | Direction | Packet IDs | Trigger | Consumer / Cache | Notes |
|---|---|---|---|---|---|
| List autoskill overrides (re-sync) | C2S req → S2C resp | `0x193` → `0x192` (one per active override) | `send_list_autoskill()` on rising-edge unlock; manual refresh | `autoutil.autoskill_state[charName] = mode`; `on_autoskill_state()` callbacks | No chunking. Server replies with 0x192 for each owned active override. |
| Set autoskill override | C2S req → S2C broadcast | `0x191` → `0x192` | autoskill addon UI / config load | Same cache as above (push-on-change) | `BotName[16] + Mode[1] + SpellCount[1] + SpellIds[16] u16`. Mode: 0=Off, 1=RA, 2=Magic. **One of the few cases with a server-pushed state echo — model for #231.** |

---

## 6. Bot spells & inventory

| Name / Purpose | Direction | Packet IDs | Trigger | Consumer / Cache | Notes |
|---|---|---|---|---|---|
| Per-bot spell roster (grouped) | C2S req → S2C resp | `0x18B` → `0x18C` (chunked, 14/pkt) | UI expand or refresh | `autoutil.bot_spells[botName][groupFilter] = {entries, final, callbacks}` | groupFilter: 0=non-trust magic, 1=trust-only. Sorted by name on final. |
| Character inventory (container caps + items) | C2S req → S2C resp | `0x18F` → `0x190` | automog UI preview | automog.lua transient (not persistent) | Headless owned by requester only. |
| Job info (levels + unlocked mask) | C2S req → S2C resp | `0x19E` → `0x19F` | automog UI | `autoutil.char_job_info[name] = {current_mj, current_sj, unlocked_mask, levels[24]}` | Status byte: 0=ok, nonzero=error. |
| Change job (primary + headless) | C2S req → S2C ack | `0x19C` → `0x19D` | automog "Change Job" | `autoutil.last_change_job_status` | Flags bit 0=change MJ, bit 1=change SJ. Server gate: requester owns target. |

---

## 7. Automog ops + one-off RPC

| Name / Purpose | Direction | Packet IDs | Trigger | Consumer / Cache | Notes |
|---|---|---|---|---|---|
| Transfer item (primary ↔ headless) | C2S req → S2C ack | `0x194` → `0x195` | "Xfer" | `last_transfer_result` | Source+dest containers, item ID, count. |
| Box pull (mog → inv) | C2S req → S2C ack | `0x196` → `0x197` | "Pull from Box" | `last_box_pull_result` | Item ID + count. |
| AH transaction (buy/sell) | C2S req → S2C ack | `0x198` → `0x199` | "Buy"/"Sell" | `last_ah_result` | Uses in-process auction bot (#197). |
| Synth (craft item) | C2S req → S2C ack | `0x19A` → `0x19B` | "Synth" | `last_synth_result` | Validates recipe unlock, mats, cap. |
| Autoequip copy XML (template duplication) | C2S req → S2C ack | `0x1A1` → `0x1A2`* | autoequip UI "Copy" | `last_copy_xml_result = {dest_name, status}` | **FLAGGED — `0x1A2` is now the puller name-filter C2S; the autoequip copy result is likely a different ID after our recent renames. Re-verify against `packet_s2c.h`.** |
| Item bulk transfer (delivery box ops) | C2S req → S2C ack | `0x16B` → `0x16C` | automog bulk UI | result in packet | |
| Warp / position echo | C2S **F&F** (or one-way echo) | `0x168` | autowarp UI; `send_warp_self_sync()` on zone load | None (or WPOS echo for position correction) | **FLAGGED — agent's subcommand 1 listed as "?" — re-verify enum.** |
| Lot list action (autolot management) | C2S **F&F** | `0x184` | autolot UI Add/Remove/Clear | None; server: per-item bot whitelist | Action: 1=ADD, 2=REMOVE, 3=CLEAR. ItemId + BotName[16]. |
| Addon relay (inter-addon messaging) | Bi | `0x151` → `0x152` | Addon A sends prefix:payload, server bounces to addon B | `on_relay(prefix, fn)` registrations | Mostly deprecated; SC:PAUSE moved to 0x176 sub 0x0A. Stays for misc inter-addon msgs. |

---

## Fire-and-forget mutations — full list (the #231 surface)

These fields are sent once by the client and never confirmed. If the packet
drops or the server rejects (auth, OOB value), the addon UI silently diverges
from server state.

**Per-bot via 0x176:**
- SetBotMode (`0x01`), SetRole (`0x04`), SetSataMode (`0x13`), SetHealMode (`0x07`), SetScThreshold (`0x12`)

**Alliance via 0x176:**
- SetAllianceMode (`0x0B`), SetNmMode (`0x10`), SetFormation (`0x0D`), UpdateConfig (`0x08`)

**Puller:**
- SetPuller (`0x176` `0x15`), SetPullerRange (`0x176` `0x16`), SetPullerConRange (`0x176` `0x17`), SetPullerNameFilter (`0x1A2`)

**Commands (no reply expected by design):**
- Attack (`0x02`), Disengage (`0x03`), DespawnAll (`0x05`), FireAllWs (`0x11`), Finish (`0x06`), SpawnDead (`0x0C`), SummonTrusts (`0x09`), ScPause (`0x0A`), BotCommand (`0x1A0`), LotListAction (`0x184`), Warp (`0x168`)

---

## ACK summary

| Has dedicated result/ACK packet | No ACK (F&F or push-only) |
|---|---|
| `0x181` SET_XML_RESULT | All `0x176` subcommands |
| `0x183` CREATE_CONFIG_RESULT | `0x184` LOT_LIST_ACTION |
| `0x188` DELETE_CONFIG_RESULT | `0x168` WARP |
| `0x18A` SET_CONFIG_RESULT | `0x178` HEADLESS_STATE (push-only) |
| `0x1A0` INSTANCE_ENTER_RESULT (reply to `0x16A`) | `0x179` HEADLESS_EVENT (push-only) |
| `0x1A2` AUTOEQUIP_COPY_XML_RESULT *(verify — collides with name-filter C2S now)* | |
| `0x1A3` SYNC_ACK (`0x176` SYNC_QUESTS/SYNC_MISSIONS only) | |
| `0x192` AUTOSKILL_STATE (push on every `0x191` change) | |
| `0x19D` / `0x19F` / `0x195` / `0x197` / `0x199` / `0x19B` automog op results | |

---

## Cache invalidation rules

| Cache | Cleared On | Lifetime |
|---|---|---|
| `autobots_ui.puller_nearby_names` + `puller_selected_names` | Zone change (`0x00A`) | Per-zone scan session |
| `autoutil.server_configs[category]` | Rising-edge `final` re-request, manual refresh | Per-session |
| `autoutil.server_config_content[cat][name]` | Manual only | Session lifetime |
| `autoutil.alliance_pcs` | Manual only | Session lifetime |
| `autoutil.char_names`, `char_jobs` | Rising-edge `final` re-request | Session lifetime |
| `autoutil.bot_spells[name][group]` | Manual per-group | Session lifetime |
| `autoutil.autoskill_state[name]` | Push on every `0x191` (real-time sync) | Real-time |
| `autoutil.char_job_info[name]` | Manual per-char | Until next request |
| Party status | Never (fan-out only, no cache) | N/A |

Only **one** cache (`puller_nearby_names`) ties to zone change. Others are
session-lifetime; nothing is invalidated on alliance config swap, which is a
hole if a swap re-shapes the roster.

---

## Key observations (design input for #231)

1. **Most state mutations are fire-and-forget.** Every 0x176 subcommand is
   one-shot with no echo. Multi-client and addon-reload scenarios both lose
   the truth — the UI shows whatever was last clicked locally, not what the
   server actually has.

2. **Autoskill is the existing model for "do this right."** `0x191` SET
   triggers an immediate `0x192` echo to all listeners; `0x193` LIST asks
   for a full re-sync of all owned overrides. Same pattern would translate
   directly to bot config state: one SET-style C2S, one BROADCAST-style
   S2C echo, one LIST-style C2S for cold reads.

3. **Speculative pre-fetch on server-ident unlock.** First `0x150` triggers
   `send_list_configs('')` for every category from every addon — 5+ addons
   stack 5 separate full requests on unlock. This is the #203 target. The
   C++ side is already cache-served, so this is laziness/cleanliness, not
   watchdog risk. Refactor: `autoutil.ensure_configs_loaded(category)`
   deferred to UI open, dedupe per-session.

4. **Chunked responses already work.** Four flows already do chunk+reassemble
   (`0x17B`, `0x17F`, `0x18C`, `0x18E`). A new BotConfigState S2C can use
   the same primitive if the snapshot grows past one packet.

5. **Inter-addon relay (`0x151`/`0x152`) is mostly dead.** SC:PAUSE moved
   out. Worth checking whether anything still uses it before removing.

6. **Suggested protocol for #231:**
   - New S2C `BotConfigState` packet carrying the alliance snapshot
     (per-bot table + alliance scalars). Fields enumerated in #231 task body.
   - Push triggers: on connect (rising-edge unlock), on every state-mutating
     C2S (server echoes the new authoritative value), heartbeat 5–30s as a
     safety net.
   - Mirror the `0x191/0x192/0x193` triad: SET / STATE / LIST.
   - Replace per-field local mirrors (e.g. `status_tab.sata_modes_by_name`)
     with a single config-state cache keyed by bot id; renders read from
     cache.
   - Fold the puller nearby-names refresh into the snapshot stream — auto
     refresh becomes "server pushes new scan when it has one."

---

## Flagged for re-verification before designing

- **`0x178` HEADLESS_STATE** — agent could not pin the wire shape. Confirm whether currently wired or only planned.
- **`0x1A2`** — now the C2S puller-name-filter packet. Agent table also lists an `0x1A2` AUTOEQUIP_COPY_XML_RESULT (S2C); confirm whether autoequip-copy-result moved to a different ID after recent renames.
- **`0x168`** WARP subcommand inventory has an unknown ("subcmd 1=?"). Re-read the C2S handler.

---

## File references

- `singleplayer/client/addons/libs/autoutil.lua` — every `send_*` and `check_for_*` helper
- `singleplayer/client/addons/autobots/autobots.lua` — `incoming_packet` dispatch
- `singleplayer/client/addons/autobots/autobots_ui.lua` — UI button → send glue
- `src/map/enums/packet_c2s.h` / `packet_s2c.h` — opcode enums
- `src/map/singleplayer/packet_registry.cpp` — C2S handler registration
- `src/map/singleplayer/lua_hooks.cpp` — packet → Lua callback bridge
- `src/map/singleplayer/lua_bindings.cpp` — Lua → push-packet bindings
- `modules/singleplayer/bots/*.lua` — server-side state owners
