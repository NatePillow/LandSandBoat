---
name: automog inventory bug - do not repeat failed approaches
description: Documents broken state of automog.lua inventory reads and approaches that do NOT work, to avoid repeating them
type: feedback
originSessionId: d5e9bd39-ba54-4c53-8b8f-14e66933105f
---
Do NOT add a 0x1C packet cache to get_container_max in automog.lua. This was tried and confirmed broken by the user multiple times.

**Why:** The 0x1C packet is a mog-house packet. Its byte layout does NOT map container capacities for all 18 containers in the positions the cache code assumed. The result is that all container max values get cached as 0, causing every bag (inventory, satchel, case, sack, wardrobe, etc.) to appear empty in the transfer UI.

**Root cause confirmed (2026-05-14):** The working tree had added:
1. `container_max_cache = {}` table
2. An `if id == 0x1C then` handler that populated the cache by reading at fixed offsets from the packet
3. `get_container_max` checking the cache first before calling `GetContainerMax`

All three were removed. `get_container_max` now directly calls `GetContainerMax(bag_id)`, and `get_equippable_items` also uses `inv:GetContainerMax(bag_id)` directly.

**Ashita v3 container API facts (from ADKv3 headers):**
- `Enums::Containers::ContainerMax = 18` — all 18 IDs (0-17) are defined and supported
- `GetContainerMax(containerId)` returns `uint16_t` and reads from the game's `ffxi_inventory_t` memory
- The inventory struct has both `StorageMaxCapacity1[19]` (uint8_t) and `StorageMaxCapacity2[18]` (uint16_t)
- The API does legitimately support container IDs 10-16 (Wardrobe2–Wardrobe8)

**How to apply:** Never add 0x1C packet parsing as a workaround for GetContainerMax. If GetContainerMax returns 0 for a specific wardrobe ID that should have items, investigate what packet populates that container's capacity in the client memory rather than guessing at packet structure.
