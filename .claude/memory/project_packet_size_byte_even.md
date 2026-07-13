---
name: packet-size-byte-must-be-even
description: FFXI wire size byte is masked `& 0xFE` server-side, so packet total bytes must be a multiple of 4 (size byte even). Odd PacketSize registrations never match — packet silently bounces with "Bad packet size … FA"-style warnings. Pad the C++ struct to round up.
metadata:
  type: project
---

## The rule

A custom C2S packet struct's **total size in bytes must be a multiple of 4** so that `size_in_uint16s = total/2` is **even**.

If you violate this:
- The server registers `PacketSize[opcode] = oddValue`.
- The wire parser reads `SmallPD_Size = byte[1] & 0xFE` (always even).
- The comparison `PacketSize[opcode] == SmallPD_Size` can never be true.
- Every packet bounces with `Bad packet size <opcode> | … <evenSize> from user: …`.

Ashita rounds the addon's byte-array length up to the next valid multiple and sends size = roundedUp/2 (also even). So the server sees an even size byte one tick larger than what the C++ struct declares — that's how the symptom manifests.

## Why `& 0xFE`?

The 9th type bit (`type & 0x100`) is encoded in bit 0 of byte[1]. The high 7 bits of byte[1] carry the size in uint16 units. Mask `0xFE` extracts just the size field. So size is always even.

## How to size a packet

1. Add up the struct: `4 (header) + all fields`.
2. If total is **divisible by 4** → you're fine. `PacketSize = total / 2`.
3. If total is `multiple of 4 + 2` → add 2 more bytes of Padding to round up. Reset PacketSize.

## Hit list of fixes already applied

- `0x180 SET_XML_SUBTREE`: was 498 bytes (Padding[2]) → bumped to 500 (Padding[4]). PacketSize 0xF9 → 0xFA.
- `0x189 SET_CONFIG_FILE`: was 458 bytes (Padding[2]) → bumped to 460 (Padding[4]). PacketSize 0xE5 → 0xE6.

## Sanity check command

When registering a new packet, grep odd PacketSize values:

```
grep "PacketSize\[0x" src/map/singleplayer/packet_registry.cpp src/map/packet_system.cpp \
  | grep -E "= 0x[0-9A-F]*[13579BDF];"
```

Any hit is a latent broken packet — fix the struct before it bites in production.

Related: [[project-custom-packets]] tracks the singleplayer-fork opcode space (0x150–0x1FF).
