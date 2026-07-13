---
name: project-packet-cmakelists
description: LSB's src/map/packets/{c2s,s2c}/CMakeLists.txt use explicit source lists, NOT glob — every new packet .cpp/.h MUST be added there or link fails with "undefined reference to ::validate/::process".
metadata:
  type: project
---

When adding a new C2S or S2C packet to LSB, register the .h and .cpp in the matching `src/map/packets/c2s/CMakeLists.txt` or `src/map/packets/s2c/CMakeLists.txt`. Both files are explicit `set(... PARENT_SCOPE)` lists, not globs.

**Why:** I added 0x194/0x195 (AUTOMOG_TRANSFER) and 0x196/0x197 (AUTOMOG_BOX_PULL) packet files and only updated `packet_system.cpp` (includes + parser registration). The build linked with `undefined reference to GP_CLI_COMMAND_AUTOMOG_TRANSFER::validate(...)` and `::process(...)` because the .cpp was never compiled — it wasn't in the c2s subdir's CMakeLists list. The map's top-level CMakeLists at `src/map/CMakeLists.txt` does use a glob_recurse in one place (line ~196 for module_files), but the packet sources flow through their own per-subdir explicit lists.

**How to apply:**
- For each new C2S packet, append both lines to `src/map/packets/c2s/CMakeLists.txt` before the `PARENT_SCOPE` closer:
  ```
  ${CMAKE_CURRENT_SOURCE_DIR}/0xNNN_name.h
  ${CMAKE_CURRENT_SOURCE_DIR}/0xNNN_name.cpp
  ```
- Same for S2C in `src/map/packets/s2c/CMakeLists.txt`.
- Also register in `src/map/packet_system.cpp`:
  - Include the C2S header at the top with the other `packets/c2s/` includes
  - In `PacketParserInitialize()` add `PacketSize[0xNNN] = …; PacketParser[0xNNN] = &ValidatedPacketHandler<GP_CLI_COMMAND_NAME>;`
- And the enum entries in `src/map/enums/packet_c2s.h` / `packet_s2c.h`.
- PacketSize is `total_bytes / 2` (bytes / 2 of (header + payload)) — e.g. BULKXFER at 40 bytes = 0x14, 72-byte transfer packet = 0x24, 20-byte box-pull = 0x0A.

**Packet IDs are single-purpose across both directions.** Even though `packet_c2s.h` and `packet_s2c.h` are *separate* enums, the LSB convention is that a given numeric ID (e.g. 0x16D) is used for one packet only — either C2S **or** S2C, not both. This avoids wire-level ambiguity for the 9-bit type field and keeps the codebase's "0xNNN means this packet" mental model intact. **Before allocating a new S2C ID, grep BOTH enums (and `packet_system.cpp` for `PacketSize[0xNNN]` registrations) to confirm the slot is unused in either direction.** I once tried to allocate 0x16D for an S2C result and was caught because 0x16D was already a C2S (INV_REQUEST); the S2C enum just happened to skip it. When the obvious adjacent slot is taken (e.g. 0x16B for a 0x16A result is taken by BULKXFER), allocate from the next clean range — most recently 0x1A0+ in our custom space.
