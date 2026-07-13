---
name: lsb-party-vs-alliance-scope
description: Rule for picking party vs alliance scope in autobots target searches. Drive scope from the FFXI spell-target restriction, not from the original Ashita addon's party-buff packet scope.
metadata:
  type: feedback
---

## The rule

**Scope is driven by the FFXI spell-target restriction, not by the original Ashita addon's iteration.**

The original Ashita addon iterated `automagic.partyStatus` (own-party buff packet 0x076) for many helpers. That's a packet-source restriction, not a spell-mechanic one. The LSB port has direct entity access via `bot:getParty()` / `bot:getAlliance()`, so we should match the spell mechanic.

## Why:
Bot logs were showing Regen cast at far-away alliance members → silent server-side fail because Regen can only target own-party → cascade re-enters next tick → log spam, zero effect. Other helpers (Cure, status removal) were fine on alliance because those spells DO have alliance range.

## How to apply:

**PARTY-scope (`bot:getParty()`)**:
- *Spell-mechanic party-only:*
  - `get_valid_regen_target` — Regen, Regen II, Regen III
  - `get_valid_refresh_target` — Refresh
  - `get_valid_haste_target` — Haste
  - (Single-target Protect, Shell, Bar* if ever added — currently only AoE Protectra/Shellra/Bar*, no iteration)
- *Decision-scope party (user judgment, not strict spell mechanic):*
  - `get_status_count_in_party` — drives `should_esuna` (>2 triggers Esuna) and Curaga-vs-Cure pick in `wake_up_members`. Curaga's target type IS Party; Esuna count is a "my party is overwhelmed" heuristic.
  - `get_blm_cure_tier` — BLM emergency cure should only fire for own-party HP crisis, not panic-cure other parties.
  - `get_player_with_lowest_hpp` — WHM healing target picker. Role-divided (each party has its own WHM).
  - `get_cure_tier` — WHM tier picker. Returns 'Curaga' (party target type only) when threshold met; alliance scope would mis-trigger Curaga on off-party low-HP and silently fail.

**Intentionally ALLIANCE-scope despite being PLD-only**:
- `get_heal_target_index` / `get_pld_cure_tier` / `cast_pld_healing_spell` — PLD cure target. With current single-mob/one-main-tank alliance setup, PLD cure-enmity stacks on the same mob the PLD tanks → free backup-heal across alliance with no hate downside. **Revisit when multi-engagement mode (per-party mobs) lands** — that's when cross-party hate steal becomes real and these should flip to party-scope (or behind a config flag). `cast_pld_healing_spell` MUST mirror `get_heal_target_index`'s scope so the returned index resolves to the right member.

**ALLIANCE-scope (`bot:getAlliance()`) — everything else**:
- Cure-target search (`get_player_with_lowest_hpp`, `get_cure_tier`, `get_blm_cure_tier`, `get_pld_cure_tier`, `get_heal_target_index`, `cast_pld_healing_spell`)
- Status removal (`get_player_indices_for_status`, `get_player_with_status`, `party_has_status`, `get_status_count_in_party`, `find_status_cure`)
- Wake-from-sleep (`get_sleeping_whm`, `sleeping_alliance`, `wake_up_alliance`)
- Raise (`get_dead_member_index`)
- Stun rotation (`get_stun_order_map`)
- Provoke rotation (`autoability.get_provoke_order_map`)
- RDM-sleep cooldown probe (`rdm_sleep_cooldown` — alliance can share assist on same mob pot)
- Name/job lookups in `autoutil.lua` (`get_member_index`, `get_member_job`, `get_member_name`, `get_member_names_with_job`, `get_party_server_ids`)
- TP gathering for SCs (`gather_tp_values`)
- Job-presence checks (`no_whm`, `no_blm`, `no_rdm` via `partyHasJob`)

## Authoritative source for cross-checks

`/home/nate/Desktop/git/ffxi-ashita/addons/libs/automagic.lua` — original Ashita addon. Watch out: a helper iterating `automagic.partyStatus` looks party-scoped because the source packet (0x076) was own-party-only, but that doesn't mean the SPELL is restricted to party. Always check the actual spell-target rule before mirroring.
