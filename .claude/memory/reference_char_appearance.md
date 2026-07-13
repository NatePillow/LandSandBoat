---
name: reference-char-appearance
description: How a character's appearance (race/face/hair/size/gender) is stored and encoded in LSB — tables, value ranges, the CharFace enum, and raceChange binding
metadata:
  type: reference
---

Character appearance in LSB (verified from code, not recall — FFXI encoding recall is unreliable).

## Where it's stored (3 places)
- **`char_look`** (`sql/char_look.sql`): `race`, `face`, `size` = the character MODEL itself (only place for these) + `head/body/hands/legs/feet/main/sub/ranged` = visible gear models, but those gear cols are DERIVED from `char_equip` (server rewrites them on equip change), so editing them directly is transient.
- **`char_style`** (`sql/char_style.sql`): the lockstyle/costume override for the same 8 gear slots (what the char APPEARS to wear regardless of real gear).
- **`chars.isstylelocked`** (0/1): flag deciding gear look source — 0 = real gear (char_look), 1 = costume (char_style). Caveat: lockstyle only shows gear the char OWNS (`charutils.cpp:2007` HasItem check).

## Value ranges (from `src/login/login_helpers.cpp:262-276` create-char validation)
- **race**: 1-8 — 1 HumeM, 2 HumeF, 3 ElvaanM, 4 ElvaanF, 5 TaruM, 6 TaruF, 7 Mithra, 8 Galka.
- **size**: 0-2 — 0 Small, 1 Medium, 2 Large.
- **face**: 0-15 — face model + hair color COMBINED (no separate hair column; hair is baked into this byte).

## Gender
Not a separate field — **gender is encoded by race** (races are gender-locked: Hume/Elvaan/Taru each have M and F; Mithra = female-only, Galka = male-only). "Change gender" = change race to the opposite-gender counterpart. Mithra/Galka have no opposite-gender flip.

## Face encoding — AUTHORITATIVE (`CharFace` enum, `src/map/entities/charentity.h:265`)
INTERLEAVED, not grouped. A/B pair of a face is CONSECUTIVE:
`face = (faceNumber-1)*2 + variant`, where even = A, odd = B.
```
Face1A=0 Face1B=1  Face2A=2 Face2B=3  Face3A=4 Face3B=5  Face4A=6 Face4B=7
Face5A=8 Face5B=9  Face6A=10 Face6B=11 Face7A=12 Face7B=13 Face8A=14 Face8B=15
```
A/B are the two hair-COLOR variants of the same face. (I once guessed "grouped" A=0-7/B=8-15 — WRONG; it's interleaved.)

## Applying a change
- DB edit to `char_look` needs a RELOAD to show — look is loaded into the entity at login (`charutils.cpp` ~469-517 loads char_look + isstylelocked; ~689 loads char_style) and pushed via spawn packets. For a headless bot: despawn/respawn.
- **`raceChange(race, face, size)`** Lua binding exists (`lua_baseentity.h:314` → `charutils::raceChange`, takes CharRace/CharFace/CharSize) — likely the clean path (DB write + live client refresh) instead of manual SQL + respawn. VERIFY it refreshes live + works on headless before relying on it.

## Built feature — automog "Change Look" (2026-07-11)
A **Change Look** section in the automog Inventory tab (under Change Job, own Apply button). Three cyclers (Race 1-8 / Face 0-15 as `NA`/`NB` / Size S/M/L), Apply active when any staged ≠ current, star `*` marks staged changes.
- **C2S 0x162 AUTOMOG_CHANGE_LOOK** (hole-filled from AH_QUERY): TargetCharName[16]+Race+Face+Size+Flags (bit0 race/bit1 face/bit2 size). **S2C 0x163 AUTOMOG_CHANGE_LOOK_RESULT** (hole-filled from AH_QUERY_RESULT): status 0 ok / 1 no-target / 2 not-owned / 3 engaged / 4 out-of-range / 6 noop. Ownership = `targetChar==PChar || session.parentCharId==PChar->id`. See [[project_custom_packets]].
- **Apply split** (`0x162_automog_change_look.cpp`): primary → `charutils::raceChange` (DB + gear cleanup + ForceRezone, which is client-safe for a real session). Headless → `refreshHeadlessLook` = raceChange MINUS ForceRezone (which would tear down the synthetic session): DB write + drop race-locked gear + mutate live `look.race/face/size` + `loc.zone->UpdateEntityPacket(ENTITY_DESPAWN)` then `ENTITY_SPAWN, UPDATE_ALL_CHAR` so nearby clients rebuild the model. **No core LSB edit.**
- **Current values sourced** by piggybacking race/face/size onto the existing 0x19F job-info reply (extended struct: +CurrentRace/Face/Size+pad, still ÷4), read at autoutil.lua bytes 53/54/55 into `char_job_info[name].current_race/face/size`. The Change-Look section reuses the same per-char fetch the Change-Job section already triggers.

Rename (chars.charname) stays OUT of scope — the name keys config/lot-lists/alliance references.
