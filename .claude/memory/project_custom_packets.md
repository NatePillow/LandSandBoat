---
name: custom-packet-convention
description: How custom C2S and S2C packets are numbered and categorized in LandSandBoat
metadata: 
  node_type: memory
  type: project
  originSessionId: cefa8b64-bf76-4cf4-94f2-b3e91d8abae0
---

Custom packets share a single incrementing opcode space across C2S and S2C directions.

- **0x150 range**: systems-level (server ident, generic relay — do not use for features)
- **0x160 range**: specific feature functionality — use this range for new features

Last used opcode: **0x1A8** (S2C `CHAR_PROFILE` — reply to C2S 0x1A7 GET_CHAR_PROFILE. Fixed-size packet carrying jobs/levels, race/face, HP/MP, exp, base+bonus stats (STR..CHR), combat stats (Atk/Def/Acc/Eva/Ratk/Racc), elemental MEVA, and equipment slot itemIds for one character. Powers the automog Status tab. Total packet 140 bytes (PacketSize 0x46). Added 2026-06-20.)

Recent additions:
- 0x1A7 C2S `GET_CHAR_PROFILE` — one-shot request for the full Status tab snapshot. Payload: char CharName[16] + uint8 Padding[4]. Auth: target = requester or a headless they parent. Server replies with 0x1A8. Total 24 bytes (PacketSize 0x0C).

**Next available: 0x1A9** (as of 2026-06-20)

> **PREFER REUSING A VACATED OPCODE OVER 0x1A9.** Scroll to the "Retired"
> sections below and look for a hole that fits the new packet's
> conceptual neighborhood. Hole-fill keeps the 0x150-0x1FF space from
> draining; in this fork (client + server ship together) the
> stale-client risk that normally argues against hole-fill is zero.
> Only fall back to monotonic Next-available if no hole is a clean
> conceptual match.

Recent additions worth knowing about:
- 0x176 HEADLESS_COMMAND added subcommands 0x0E SYNC_QUESTS and 0x0F SYNC_MISSIONS (no new opcode — extends the namespace/subcmd dispatcher inside the existing 0x176)
- 0x1A2 AUTOEQUIP_COPY_XML_RESULT — reply to 0x1A1
- 0x1A3 SYNC_ACK — see above

**Maximum opcode: 0x1FF** (511). Enforced by:
- `src/map/enums/packet_c2s.h` and `packet_s2c.h`: `enum_range<>` hard-codes `max = 511`
- `src/map/packet_system.cpp`: `PacketSize[512]` array; parser masks incoming opcodes with `0x1FF`

So the addressable custom-packet space is 0x150 → 0x1FF, currently ~125 opcodes still free past the last-used.

**How to apply:** When adding a new custom packet (C2S or S2C), first scan the deprecated/holes list below for a vacant opcode in the 0x160+ range — **prefer re-using a hole over monotonic counting** so the addressable space (0x150–0x1FF, only ~125 left) doesn't drain. Only if no hole is appropriate should you take `Next available` and increment. Either way, update the "last used" / "next available" lines and remove the hole entry if you filled one.

**Why re-use vacated opcodes:** The 0x150–0x1FF space is finite (enforced at `enum_range<>` and `PacketSize[512]`). Counting monotonically while leaving deprecation gaps means we'll hit 0x1FF with most of the space unreachable. Filling a hole is safe as long as no live client still emits the old opcode for the deprecated meaning — when removing a packet, the addon-side `_OPCODE` constant and call sites get deleted in the same change, so a clean rebuild has no stale emitters. Risk only exists if we expect end-users running mismatched client versions against this server, which we don't (singleplayer fork, client + server ship together).

**How to apply (hole-fill):** Pick a deprecated opcode from the list below, verify (1) no current `.cpp` / `.lua` references the old name, (2) the deletion date is at least one full rebase cycle in the past (so any stashed work-in-progress branches have surfaced), then add your new packet under that opcode. Replace the `(deprecated, …)` line with the new packet's description and date. If you can't satisfy (1) or (2), take Next available instead.

**Deprecation / holes policy** (2026-06-17, hole-fill preference reaffirmed 2026-06-22): packets get retired when their owning addon is removed or when functionality consolidates elsewhere — most often onto a loopback HTTP endpoint (e.g. the whole AH family collapsed into `/ah/*`, taking 0x162, 0x163, 0x198 and 0x199 with it). When a packet is deleted, its opcode becomes a "hole" in the 0x160+ space. **Filling holes with new packets is the DEFAULT here** — not the exception. The "stale client emitting old opcode" risk that normally argues against hole-fill doesn't apply because client + server ship together in this fork; a clean rebuild has no stale emitters. When deleting a packet, remove: the .h/.cpp pair, the entry in `src/map/packets/c2s/CMakeLists.txt` (or s2c/), the enum entry in `packet_c2s.h` (or s2c), the registration in `src/map/singleplayer/packet_registry.h`, and any addon-side `_OPCODE` constants and call sites. The opcode then appears as a gap in this index — leave a `- 0xNNN: (deprecated, removed YYYY-MM-DD, replaced by 0xMMM)` line so future-you knows it's intentionally vacant and available for hole-fill.

**Retired** (#233, all 2026-06-17):
- 0x164 AUTOBOX (deprecated, removed, replaced by 0x196 AUTOMOG_BOX_PULL — primary's own box is pulled by passing primary's name as the target through the cross-char path)
- 0x16B ITEM_BULKXFER + 0x16C BULKXFER_RESULT (deprecated, removed, replaced by 0x194 AUTOMOG_TRANSFER — intra-char moves use 0x194 with srcChar == dstChar, no separate primary-only path needed)
- 0x171 ITEM_TRADE — HOLE-FILLED 2026-06-22 as EQUIP_BOT_ITEM (cross-char equip used by automog Status tab for primary AND headless via the same call shape; deprecated/replaced-by line below; was originally retired 2026-06-17 and consolidated into 0x194 AUTOMOG_TRANSFER)
- 0x172 ITEM_TRADE_RESULT (still vacant; was the reply pair to 0x171, no longer needed because EQUIP_BOT_ITEM uses the existing 0x1A8 CHAR_PROFILE as the implicit ack)
- 0x161 FAST_SYNTH (deprecated, removed, synth logic moved INTO 0x19A AUTOMOG_SYNTH self-contained handler — 0x19A no longer uses automog_proxy::dispatch since it only ever wrapped one inner opcode. synthutils::doInstantSynth now takes a SynthOffer and runs the full resolution+commit inline, no animation, no state machine. The addon still builds an 0x161-shape inner body for 0x19A — server reinterprets via local InnerSynth struct.)

**Hole-fill additions:**
- 0x171 C2S `EQUIP_BOT_ITEM` (re-used 2026-06-22, was ITEM_TRADE). Payload: char CharName[16] + uint16 ItemId + uint8 SlotId + uint8 Padding. Same auth model as 0x1A7 (target = requester or a headless they parent). Server walks the target's equip-bearing containers (inventory + wardrobes 1..8) for ItemId, calls charutils::EquipItem on the found location, then pushes a fresh S2C 0x1A8 CHAR_PROFILE so the addon's char_profile_cache picks up the new equipment without a separate poll. Same packet for primary and headless (vanilla 0x173 EQUIP_BY_ID has no target-char field so we couldn't reuse it for cross-char). Total 24 bytes (PacketSize 0x0C).

**Inventory retired** (2026-07-09, replaced by loopback HTTP):
`0x16D INV_REQUEST` + `0x16E INV_CAPS` (local player) and `0x18F GET_CHAR_INV` +
`0x190 CHAR_INV` (cross-char) and `0x1A6 SORT_CHAR_INV` all collapsed into
`src/map/singleplayer/char_http.cpp`:
- `GET /chars/<name>/inventory` — caps + every occupied slot, one response
- `POST /chars/<name>/sort-inventory` — op_registry, drained in post_tick

**Why**: the map server only flushes a char's outbound packet queue when a
client packet arrives (`send_parse` is called from the receive path in
`map_networking.cpp`), and each flush is capped at `kMaxPacketPerCompression`
(32) packets. `0x16D` pushed **one 0x020 ITEM_ATTR per item** across all 18
containers, so a few hundred items meant tens of client round-trips — that was
the multi-second automog inventory load. Compounding it, every addon requiring
`libs/inv_cache.lua` has its own Lua state and issued its own independent dump.

`GET /chars/<name>/inventory` is DB-only, so it answers off the HTTP thread.
`char_inventory` is write-through and gil is a normal row (location 0, slot 0,
itemId 65535). **Caps need care**: four bags are not `char_storage` columns and
must be reconstructed exactly as `charutils::LoadChar` does — LOC_STORAGE (2) is
the sum of *installed* furnishings' storage (installed = bit 6 of `extra[1]`),
LOC_TEMPITEMS (3) is a hardcoded 50, LOC_MOGSAFE2 (9) shares the `safe` column,
LOC_RECYCLEBIN (17) is a hardcoded 10.

The read is unauthenticated, matching `GET /chars` and `GET /ah/listings?for=`.
`0x18F` *did* gate on `PSession->parentCharId`, which has no DB equivalent. The
sort keeps that gate because it mutates: it runs on the main thread via
op_registry and re-checks ownership there.

`libs/inv_cache.lua` still consumes retail `0x020` / `0x01E` deltas to keep the
local player's snapshot fresh after the initial fetch. A headless target has no
delta source and needs an explicit refetch.

**Config CRUD retired** (2026-06-19, replaced by loopback HTTP):
The entire chunked config-CRUD pipeline was deleted when the addons migrated to talking to the map server's in-process HTTP server (singleplayer/client/addons/libs/http_client.lua → src/map/singleplayer/config_http_server.cpp, port 51220). GET / PUT / DELETE on `/configs[/{cat}[/{name}]]` replaces all of:
- 0x17A C2S list_configs + 0x17B S2C config_list (chunked names)  → `GET /configs[/{cat}]`
- 0x17E C2S get_config_content + 0x17F S2C config_content (chunked body) → `GET /configs/{cat}/{name}`
- 0x180 C2S set_xml_subtree + 0x181 S2C set_xml_result → `PUT /configs/{cat}/{name}` (whole file)
- 0x182 C2S create_config_file + 0x183 S2C create_config_result → `GET` probe + `PUT` template
- 0x187 C2S delete_config_file + 0x188 S2C delete_config_result → `DELETE /configs/{cat}/{name}`
- 0x189 C2S set_config_file + 0x18A S2C set_config_result (chunked whole-file write) → `PUT /configs/{cat}/{name}`

The wire-zlib decode errors that haunted big AshitaCast XML transfers went away with the chunked pipeline. ~50× faster on a 100 KB autoequip file (~10 ms vs ~2.5 s). Server-side config_transfer.{h,cpp} + bots_config.lua + ai_equip_swap.set_subtree_equip + ai_lot.set_subtree_lot were all deleted alongside the packets.

**Proxy-vs-self-contained convention**: there is no longer ANY proxy user —
`automog_proxy` was deleted 2026-07-09 along with its sole caller 0x198
AUTOMOG_AH, and `getPacketHandler` (the rate-limit-bypassing handler lookup in
`packet_system.{h,cpp}` that existed only to serve it) went with them. Every
automog cross-char packet (0x194 AUTOMOG_TRANSFER, 0x196 AUTOMOG_BOX_PULL,
0x19A AUTOMOG_SYNTH) is self-contained. **New automog-style cross-char packets
must be self-contained** — if you find yourself wanting to re-dispatch an inner
opcode as another char, prefer a loopback HTTP endpoint instead.

**AH is HTTP, not packets (2026-07-09).** All AH interaction goes through
`src/map/singleplayer/auction_http.cpp`. Reads answer straight off the HTTP
thread (`GET /ah/listings?for=`, `GET /ah/stock?items=id:stack,...`); mutations
go through `op_registry` + post_tick drain (`POST /ah/{sell,buy,cancel}`).
Cross-char targeting rides the `for` field on the request, which is what let
the 0x198 proxy die.

**Never add an AH DB query to a packet handler** — it runs on the map tick
thread and will trip the inactivity watchdog. That is exactly what killed
0x162: its handler ran a `COUNT(*)` per ingredient group via `db::preparedStmt`
on the tick thread. `db` state is `thread_local`, so this was not lock
contention with the HTTP thread — the tick thread simply blocked on its own DB
round-trips. Note `0x16F ah_cat_query` / `0x170 ah_cat_result` still do
main-thread SQL and are the next watchdog candidate.

**Existing custom packets (0x160+):**
- 0x160 S2C: alliance_effects
- 0x161: (deprecated, removed 2026-06-17, replaced by 0x19A AUTOMOG_SYNTH self-contained inline synth)
- 0x162: HOLE-FILLED 2026-07-11 as AUTOMOG_CHANGE_LOOK (C2S; was AH_QUERY; changes target char race/face/size; Flags bit0=race/bit1=face/bit2=size; S2C result 0x163). Chosen as earliest consecutive free pair in the 0x160+ feature band (0x154/0x155 are earlier but sit in the reserved 0x150-0x15F infra band).
- 0x163: HOLE-FILLED 2026-07-11 as AUTOMOG_CHANGE_LOOK_RESULT (S2C; was AH_QUERY_RESULT; status result pair for 0x162; 0=ok 1=no-target 2=not-owned 3=engaged 4=out-of-range 6=noop)
- 0x164: (deprecated, removed 2026-06-17, replaced by 0x196 AUTOMOG_BOX_PULL)
- 0x165 C2S: autoscroll
- 0x166 S2C: autoscroll_result
- 0x167 S2C: enmity
- 0x168 C2S: autowarp
- 0x169 C2S: autoinvite
- 0x16a C2S: battlefield_enter
- 0x16b: (deprecated, removed 2026-06-17, replaced by 0x194 AUTOMOG_TRANSFER)
- 0x16c: (deprecated, removed 2026-06-17, replaced by 0x195 AUTOMOG_TRANSFER_RESULT)
- 0x16d: (deprecated, removed 2026-07-09, replaced by loopback HTTP `GET /chars/<name>/inventory`)
- 0x16e: (deprecated, removed 2026-07-09, caps now ship in the `GET /chars/<name>/inventory` body)
- 0x16f C2S: ah_cat_query (AH browse by category, with page number)
- 0x170 S2C: ah_cat_result (up to 30 items: id, count, min_price; HasMore flag for paging)
- 0x171: (deprecated, removed 2026-06-17, replaced by 0x194 AUTOMOG_TRANSFER)
- 0x172: (deprecated, removed 2026-06-17, replaced by 0x195 AUTOMOG_TRANSFER_RESULT)
- 0x173 C2S: equip_by_id (bulk equip up to 16 items by item ID; server does container lookup)
- 0x174 S2C: equip_by_id_result (Count + uint16 SuccessMask, bit i set if Equipment[i] actually landed)
- 0x175 C2S: spawn_headless (reshaped 2026-06-07 to ConfigName[32] only; server reads singleplayer/config/alliance/<name>.json and drives spawn/party/trust via autospawn.lua)
- 0x176 C2S: headless_command (Namespace + Subcommand + Padding[2] + Payload[12]; AUTOBOTS namespace covers SET_BOT_MODE/ATTACK/DISENGAGE/SET_ROLE)
- 0x178 S2C: headless_state (per-bot HP/MP/role/target update pushed to primary's queue)
- 0x179 S2C: headless_event (cross-cutting bot event: 0x01 LOG_MESSAGE Tag[16]+Msg[44], 0x02 DPS_RESET, 0x03 CONFIG_CHANGED configName[60])
- 0x17A: (deprecated, removed 2026-06-19, replaced by loopback HTTP `GET /configs[/{cat}]` — see Config CRUD retired block above)
- 0x17B: (deprecated, removed 2026-06-19, replaced by loopback HTTP)
- 0x17C S2C: dps_update (per-bot DPS snapshot — CharId + IsFinal + TotalDamage + ActiveMs + 6 categories × {Damage,Hits,Misses}; pushed every 2s while bot engaged + final summary on disengage)
- 0x17D C2S: use_food_config (ConfigName[32]; server reads singleplayer/config/food/<name>.json and dispatches bot:useItem on each linked headless via xi.auto.item.use_food_from_config)
- 0x17E: (deprecated, removed 2026-06-19, replaced by loopback HTTP `GET /configs/{cat}/{name}`)
- 0x17F: (deprecated, removed 2026-06-19, replaced by loopback HTTP)
- 0x180: (deprecated, removed 2026-06-19, replaced by loopback HTTP `PUT /configs/{cat}/{name}` — addon serializes whole file in memory and PUTs once)
- 0x181: (deprecated, removed 2026-06-19, replaced by loopback HTTP)
- 0x182: (deprecated, removed 2026-06-19, replaced by loopback HTTP `GET` probe + `PUT` template)
- 0x183: (deprecated, removed 2026-06-19, replaced by loopback HTTP)
- 0x184 C2S: lot_list_action (Action[1] + Padding[3] + ItemId[4] + BotName[16]; Action 1=ADD 2=REMOVE 3=CLEAR. ADD/REMOVE mutate the autolot lot-list set for a given (primary, item_id); CLEAR drops the whole item entry. Wider payload than 0x176 lets us carry full 15-char FFXI names. Server-side state has a ~500ms grace window so a burst of per-bot ADDs all land before any bot acts.)
- 0x185 C2S: list_alliance_pcs (header-only, no payload; server walks the requester's alliance and replies with one 0x186. Used by autobots BF picker on the rising edge of in_battlefield detection — trust-vs-PC filtering is authoritative on the server since CCharEntity-only traversal excludes trusts naturally.)
- 0x186 S2C: alliance_pc_list (Count[1] + Padding[3] + Entries[18]{Name[15] + PartyNo[1]}; single packet — alliance maxes at 18 chars. PartyNo is 1/2/3 indicating which party in the alliance the PC belongs to. Reply to 0x185.)
- 0x187: (deprecated, removed 2026-06-19, replaced by loopback HTTP `DELETE /configs/{cat}/{name}`)
- 0x188: (deprecated, removed 2026-06-19, replaced by loopback HTTP)
- 0x189: (deprecated, removed 2026-06-19, replaced by loopback HTTP `PUT /configs/{cat}/{name}`)
- 0x18A: (deprecated, removed 2026-06-19, replaced by loopback HTTP)
- 0x18B C2S: list_bot_spells (BotName[16] + GroupFilter[1] + Padding[3]; per-bot spell roster filtered by group. GroupFilter 0=magic non-trust, 1=trust. Server runs charutils::hasSpell across MAX_SPELL_ID for the target so we only see what they've actually learned. Authorized iff target is requester or a headless owned by them (same gate as 0x1A7).)
- 0x18C S2C: bot_spells_list (BotName[16] + GroupFilter[1] + IsFinal[1] + Count[1] + Padding[1] + Entries[14]{SpellId[u16] + Name[30]}; chunked. Routes by (BotName, GroupFilter) so concurrent fetches for different chars don't collide. Replaced the earlier 0x18B/0x18C trust list which returned every trust in the spell DB regardless of who knew it.)
- 0x18D: (deprecated, removed 2026-06-20, replaced by loopback HTTP `GET /chars` — see Char-roster CRUD retired block below)
- 0x18E: (deprecated, removed 2026-06-20, replaced by loopback HTTP `GET /chars`)
- 0x18F: (deprecated, removed 2026-07-09, replaced by loopback HTTP `GET /chars/<name>/inventory`)
- 0x190: (deprecated, removed 2026-07-09, chunked reply pair to 0x18F/0x1A6)
- 0x1A6: (deprecated, removed 2026-07-09, replaced by loopback HTTP `POST /chars/<name>/sort-inventory`)
- 0x191 C2S: set_autoskill (BotName[16] + Mode[1] + SpellCount[1] + Padding[2] + SpellIds[16] (u16); Mode 0=Off/1=RA/2=Magic. Routes to xi.auto.skill.set_override_for_bot which validates target ownership and flips start_magic / start_ranged / stop. autoai.lua runCombatTick checks xi.auto.skill.state[id].active before role dispatch — when active, the normal role tick is skipped and autoskill's own onBotTick override drives all actions.)
- 0x192 S2C: autoskill_state (BotName[16] + Mode[1] + Padding[3]; server push after every override change. luautils::OnSetAutoskill echoes this back after dispatching. Autobots' AutoSkill tab mirrors into rows[] for radio state; autobots also populates autoutil.autoskill_state for the Active Config Info "Skill:" line.)
- 0x193 C2S: list_autoskill (header-only; routes to xi.auto.skill.push_overrides_to(primary). Walks autoskill.state, finds bots owned by requester with active overrides, fires 0x192 for each via CCharEntity:pushAutoskillState binding. Fired by autobots on the AutoSkill tab's Refresh button and on every 0x150 server-ident receive so caches start synced even when overrides predate the addon opening.)
- 0x198: (deprecated, removed 2026-07-09, replaced by loopback HTTP `/ah/*` — was AUTOMOG_AH, the proxy wrapper. `utils/automog_proxy.{h,cpp}` and `getPacketHandler` in `packet_system.{h,cpp}` were deleted with it.)
- 0x199: (deprecated, removed 2026-07-09, result pair to 0x198)
