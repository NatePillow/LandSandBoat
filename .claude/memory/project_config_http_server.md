---
name: project-config-http-server
description: The map process runs a cpp-httplib config server (default port 51220) that all addons hit for config CRUD (alliance/food/equip/lot) + NM/char/sort/auction endpoints. Bind addr + port are settings; the client HOST/PORT must match. Replaced the old chunked 0x17E/0x180 packet pipeline. The port must be reachable ON THE SERVER HOST (firewall/NAT/SG).
metadata:
  type: project
---

The map server hosts a `cpp-httplib` listener (`src/map/singleplayer/config_http_server.cpp`, plus `char_http.cpp` / `auction_http.cpp`). Every addon does config CRUD and data reads over it — alliance / food / equip / lot configs, NM drops, char inventory, sort-inventory, auction. It replaced the old chunked-packet `0x17E/0x180/...` pipeline that threw wire-zlib errors on big AshitaCast XMLs.

**Settings (no recompile needed):**
- Server — `settings/singleplayer.lua`: `CONFIG_HTTP_BIND_ADDR` (`127.0.0.1` same-machine / `0.0.0.0` VM+LAN / a specific interface IP) and `CONFIG_HTTP_PORT` (default `51220`).
- Client — top of `singleplayer/client/addons/libs/http_client.lua`: `http_client.HOST` (IP the client uses to reach the server: `127.0.0.1` same-machine, `10.0.2.2` under VirtualBox/QEMU NAT, the box's LAN IP if bridged) and `http_client.PORT` (must equal the server's `CONFIG_HTTP_PORT`).

**Why:** any firewall / NAT / cloud SG that gates inbound TCP has to open the port **on the server host**, or addons silently can't reach config. This is the #1 non-obvious "why is nothing loading / configs won't save" cause in a fresh setup — it looks like an addon bug but it's networking.

**How to apply:** when addon config CRUD or data reads misbehave, sanity-check from the CLIENT machine first: `curl http://<HOST>:<PORT>/healthz` should return `ok`. If it hangs/refuses, it's bind-addr/port/firewall, not the addon.

[[project-http-op-registry]]
