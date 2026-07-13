---
name: ninjutsu-mp-cost-is-tool-id
description: spell_list.mp_cost for SPELLGROUP_NINJUTSU spells holds the required tool's item ID, not an MP cost. Don't gate ninjutsu on MP affordability.
metadata:
  type: project
---

`spell_list.mp_cost` is repurposed by ninjutsu (`SPELLGROUP_NINJUTSU = 4`, i.e. `xi.magic.spellGroup.NINJUTSU`) to store the required **tool's item ID**, not an MP cost.

Examples:
- Utsusemi: Ichi (338) → `mp_cost = 1179` (Shihei item id)
- Other ninjutsu tiers follow the same pattern for their respective tools.

**Why:** ninjutsu consumes tools, not MP. Engine's `spell::CanUseSpell` handles the tool check authoritatively. The DB column was reused so the existing spell-table row format didn't need a new column.

**How to apply:**
- Never call `bot:getMP() < spell:getMPCost()` on a ninjutsu spell — it almost always returns true and silently rejects every ninjutsu cast.
- Branch on `spell:getSpellGroup() == xi.magic.spellGroup.NINJUTSU` before any MP-affordability check.
- Tool presence should be checked separately (e.g. `ai_item.have_shihei(bot)` for Utsusemi).
- `bot:canUseSpell(spellId)` already validates the tool — prefer that over hand-rolled checks where possible.

Same column may also be unusual for other groups; not yet confirmed for SONG/TRUST/SUMMONING, but those don't typically come up in the bot AI cast gates. Audit before assuming `mp_cost` is real MP for any non-WHITE/BLACK/BLUE/GEOMANCY group.

Related: [[feedback-never-silence-logs]] — this bug was invisible until we instrumented the gate; the spell silently never appeared in pick lists.
