---
name: http-op-registry
description: Generic async-op pattern for HTTP-triggered work that mutates main-thread state (op_registry + post_tick drain)
metadata:
  type: project
---

Any HTTP-triggered work that has to mutate `CCharEntity` / inventory / gil (main-thread-only state) uses this pattern:

1. **HTTP handler** (`src/map/singleplayer/*_http.cpp`, runs on httplib's worker pool) — validate synchronously, build an op-specific payload struct, call `op_registry::enqueue(kind, payload)`, return **202 Accepted** with `{ "opId": "<id>" }`.

2. **Post-tick applier** (`src/map/singleplayer/*_http.cpp::drainOps()`, called from `post_tick.cpp`) — walks pending ops, casts payload back out, applies the mutation, calls `op_registry::markSuccess(opId, msg)` or `markFailed(opId, msg)`.

3. **Client** — call `http_client.await_op(post_path, body, opts, onDone)`. Under the hood it POSTs, receives `opId`, polls `GET /ops/<id>` every 500ms until non-pending, calls `onDone(result, err)`.

4. **Client UX** — `loading_overlay.begin(key, label)` before firing, `loading_overlay.done(key)` in the completion callback. Any tab that renders `if loading_overlay.is_locked(key) then loading_overlay.render(key); return end` at its top locks itself while an op is in flight.

**Reference implementation:** the AH stack (`auction_http.cpp` + `autobuy.lua` + `autosell.lua` + `automog.lua`'s AH tab) is the pattern to copy. Reads (`GET /ah/listings`) are synchronous DB, no op_registry involvement. Writes (`POST /ah/{sell,buy,cancel}`) all go through op_registry.

**Threading contract:**
- Op payload structs are captured by value (not pointer) so a logout/zone-out between enqueue and drain can't leave a dangling `CCharEntity*`.
- Applier runs *inside* the registry mutex — do NOT re-enter `enqueue`/`query` from the applier.
- The applier is the ONLY code allowed to touch main-thread-only state during drain.

**Records TTL:** 5 minutes after Success/Failed. Pending records are never GC'd — a stuck pending is a bug worth seeing.

**opId shape:** monotonic uint64 as a decimal string. Reset on server restart — in-flight clients see a `404` from `/ops/<id>` and treat as failed.

**Endpoints today (as of 2026-07-08):**
- `POST /ah/sell`   → `ah_sell`   op
- `POST /ah/buy`    → `ah_buy`    op (listingId != 0 = specific row; else cheapest match on itemId/isStack)
- `POST /ah/cancel` → `ah_cancel` op
- `GET  /ah/listings?for=<char>` — sync DB read, my active listings
- `GET  /ops/<opId>` — polling target for `await_op`

**HTTP AH replaced the retail 0x04E AUC path** that automog used to proxy through 0x198 AUTOMOG_AH. Retail packet path unchanged (walk to a real AH NPC still works via upstream `auctionutils::*`). 0x198 still handles SHOP_BUY (0x083) and AH_QUERY (0x162); the 0x04E entry was removed from `kAllowedInnerOpcodes`.
