---
name: party-menu-served-by-search-server
description: The vanilla FFXI "Party -> Member List" menu is served by the SEARCH server (not map), and headless bots were hidden from it by a client_addr filter
metadata:
  type: project
---

The vanilla FFXI **Party menu member list** (Main Menu -> Party -> Member List) is
NOT served by the map server. The client sends a `TCP_GROUP_LIST` request to the
**search server**, handled by `SearchHandler::HandleGroupListRequest`
(`src/search/search_handler.cpp:320`), which runs `CDataLoader::GetPartyList`
(`src/search/data_loader.cpp:529`) — a DB query over `accounts_sessions` JOIN
`accounts_parties`/`chars`/`char_stats`.

Consequences / gotchas:
- Debugging "party member X doesn't show in the menu" on the MAP server is a dead
  end. The on-screen party window (HP/MP bars) IS map-server (0x0DD GROUP_LIST /
  0x0C8 GROUP_TBL / 0x0DF GROUP_ATTR via CParty::ReloadParty), but the MENU list
  is search-server. They can diverge — a member can show on-screen but not in the
  menu, or vice versa.
- Headless bots were invisible in the party menu because `GetPartyList` carried
  `AND client_addr != 0` — the synthetic-row sentinel (headless accounts_sessions
  rows are written with client_addr=0 in bot_sessions.cpp createHeadlessSession).
  That filter is correct for `/search` find-players and the linkshell list, but it
  was WRONG on the party roster: your own party members must appear regardless of
  session type. Removed 2026-07-11 (data_loader.cpp:542, comment left in place so
  it isn't re-added). The `/search` count queries (data_loader.cpp:184,196), the
  find-players list (259), and GetLinkshellList (652) keep the filter intentionally.

Second, related fix (2026-07-11): a headless's `chars.pos_zone` was never updated —
it zones in-process (IncreaseZoneCounter, never SendToZone) and `SaveCharPosition`
writes pos_x/y/z but not pos_zone. Both `GetPartyList` (search) and the map's 0x0C8
GROUP_TBL read pos_zone for the member's location, so bots showed in the wrong zone
once the primary left the bots' last real-saved zone. Fixed via a single shared
helper `mapsessions::persistHeadlessPosZone(CCharEntity*)` (declared
map_session_container.h, defined bot_sessions.cpp) called after EVERY headless zone
hop — there are FOUR: createHeadlessSession (spawn), moveHeadlessToPrimaryZone
(follow primary on zone-in via 0x00A), moveBotIntoSenderZone (0x16a instance/dynamis
pull), and the 0x176 revive-here hop. Any new headless zone-hop path must call the
helper right after IncreaseZoneCounter or the Party menu zone drifts stale again.
The headless auto-follow trigger is `0x00a_login.cpp` (zoning re-runs 0x00A).

Third fix (2026-07-11): party-menu name COLORS. Every name rendered white — should
be blue for members, yellow/beige for the leader. The color comes from `flags1` bits
in the search party-list packet: `0x0008` = leader (yellow), `0x2000` = shares your
party/alliance (blue). Both were gated on the **request's** `PartyID` param
(`if (PartyID == PPlayer->id)` / `if (PartyID != 0)`), but the client sends
`PartyID = 0` when it opens the menu in **alliance mode** (only allianceid is set) —
so neither flag was ever set and all names went white. Fixed by deriving from each
row's OWN `accounts_parties` data: added `partyflag` to the `GetPartyList` SELECT,
read per-row `rowPartyID`/`rowPartyFlag`, set `0x0008` when
`rowPartyFlag & PARTY_LEADER(0x0004)` (kept the old `PartyID == id` OR for the
plain-party case), and set `0x2000` when the row's own `rowPartyID != 0`. `partyflag`
is reliably written by map (party.cpp GetMemberFlags on join, alliance.cpp on ally
ops); PARTY_LEADER = 0x0004, ALLIANCE_LEADER = 0x0008 in src/map/party.h. Same
search-server rebuild as the other two fixes.

Fixes in `src/search/` require rebuilding + restarting the **search server binary**
(separate from map and world); the pos_zone fix is in **map**. Both are needed for
the full fix. See [[custom-packet-convention]] for the map-side party packets, which
were all verified correct during this investigation.
