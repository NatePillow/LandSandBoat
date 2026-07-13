# Job 2-Hour Ability Audit (LSB Server Behavior)

Reference material for TODO #255 (bot 2hr handling pass). Every entry describes
what the LSB source ACTUALLY does, not retail lore. When LSB diverges from
retail, the divergence is called out inline. Bot AI relying on retail-shaped
2hr behavior needs to reconcile against this document.

## Cross-cutting mechanics

- **Script layout**: classic 2hrs live at `scripts/actions/abilities/<ability>.lua`
  (thin dispatchers) with concrete logic in `scripts/globals/job_utils/<job>.lua`.
  Later SoA/RoV abilities put the logic inline in the actions/abilities file.
- **Ability IDs**: `scripts/enum/job_ability.lua`.
- **Recast**: `sql/abilities.sql` stores recast in seconds. Every classic
  "2 hour" ability is actually **3600 s (1 h)** in LSB — the post-Abyssea
  1-hour cooldown is applied universally. Each `checkX` handler uniformly
  does `ability:setRecast(math.max(0, recast - mod(ONE_HOUR_RECAST)*60))`
  so gear granting that mod trims minutes off.
- **Detection**: there is NO ability-table flag identifying "this is a 2hr."
  The markers are (a) the `ONE_HOUR_RECAST`-mod recast reduction and (b)
  animation timing 2000. Bot AI enumerating 2hrs should either hardcode
  the ID list below or scan for the `ONE_HOUR_RECAST` pattern.
- **Buff-shape 2hrs**: almost always self-targeted, 30-180s duration.
  The effect script does the mod stacking, or the effect is a marker other
  engine systems check for.
- **Enum locations**: `src/map/status_effect.h`, `src/map/ability.h`.

## Ability index

| Job | Ability | ID | Recast | Shape |
|-----|---------|----|----|-------|
| WAR | Mighty Strikes    | 16  | 3600s | Self-buff 45s |
| MNK | Hundred Fists     | 17  | 3600s | Self-buff 45s |
| WHM | Benediction       | 18  | 3600s | Instant AoE heal |
| BLM | Manafont          | 19  | 3600s | Self-buff 60s |
| RDM | Chainspell        | 20  | 3600s | Self-buff 60s |
| THF | Perfect Dodge     | 21  | 3600s | Self-buff 30s (+gear) |
| PLD | Invincible        | 22  | 3600s | Self-buff 30s |
| DRK | Blood Weapon      | 23  | 3600s | Self-buff 30s (+gear) |
| BST | Familiar          | 24  | 3600s | Pet-target buff (permanent) |
| BRD | Soul Voice        | 25  | 3600s | Self-buff 180s |
| RNG | Eagle Eye Shot    | 26  | 3600s | Single-hit ranged attack |
| SAM | Meikyo Shisui     | 27  | 3600s | Self-buff 30s + 3000 TP |
| NIN | Mijin Gakure      | 28  | 3600s | Suicide AoE damage |
| DRG | Spirit Surge      | 29  | 3600s | Self-buff 60s + wyvern consume |
| SMN | Astral Flow       | 30  | 3600s | Self-buff 180s |
| BLU | Azure Lore        | 93  | 3600s | Self-buff 30s |
| COR | Wild Card         | 96  | 3600s | Party random effect (d6) |
| PUP | Overdrive         | 135 | 3600s | Pet-target buff 60s |
| DNC | Trance            | 181 | 3600s | Self-buff 60s + JP TP |
| SCH | Tabula Rasa       | 210 | 3600s | Self-buff 180s |
| GEO | Bolster           | 343 | 3600s | Self-buff 240s+ |
| RUN | Elemental Sforzo  | 356 | 3600s | Self-buff 30s |

---

## Per-job details

### WAR — Mighty Strikes (16)

Action script `scripts/actions/abilities/mighty_strikes.lua`; logic in
`scripts/globals/job_utils/warrior.lua:89`. Applies `xi.effect.MIGHTY_STRIKES`
to self, power=1, duration=45s. Effect script `scripts/effects/mighty_strikes.lua`
adds `CRITHITRATE +100` (guaranteed crits) on gain, removes on loss, plus
`ACC/RACC +2 per JP`. Engine also flags Mighty Strikes as unblockable at
`src/map/utils/battleutils.cpp:2533-34` (ignores guard/parry gates). Retail
behavior preserved.

### MNK — Hundred Fists (17)

Action script `hundred_fists.lua`; logic in `monk.lua:169`. Applies
`xi.effect.HUNDRED_FISTS`, power=1, duration=45s. Effect script only stacks
`ACC +2*JP`. The delay-quarter is engine-side: `src/map/entities/battleentity.cpp:546-549`
clamps weapon delay 1600-8000 then multiplies by 0.25 while the effect is up.
Note LSB has a second MNK 1-hr, **Inner Strength (ID 324)**, added in SoA —
separate button, separate recast, treat as its own JA.

### WHM — Benediction (18)

Action script `benediction.lua`; logic in `white_mage.lua:81`. Instant heal,
no status effect. Heal amount = `target:getMaxHP() * player:getMainLvl() / target:getMainLvl()`
(clamped to missing HP). Iterates a hard-coded `removables` list
(`white_mage.lua:8-21` — 41 status effects including Flash, Bind, Silence, all
elemental DoTs, all stat-downs, Petrification). Doom is separately rolled at
33%. Calls `updateEnmityFromCure` and `wakeUp`. Target defaults to caster in
ability data (`validTarget=1` is party AoE). TODO comment says Charm-removal
is only in Lamia13 Assault — not implemented.

### BLM — Manafont (19)

Action script `manafont.lua`; logic in `black_mage.lua:43`. Self-target
`xi.effect.MANAFONT` power=1 duration=60s. Effect script is empty; engine
checks `HasStatusEffect(EFFECT_MANAFONT)` in `magic_state.cpp:466` to skip MP
deduction and in `battleutils.cpp:1908/5883` to bypass silence penalties on
interrupt / MP-cost gates. So it truly zeroes spell MP cost while up.

### RDM — Chainspell (20)

Action script `chainspell.lua`; logic in `red_mage.lua:24`. Self buff
`xi.effect.CHAINSPELL` power=1 duration=60s. Effect script adds `UFASTCAST +150`
(uncapped fast cast → instant cast) + `MAGIC_DAMAGE +2*JP` on gain, removes on
lose. Engine `magic_state.cpp:492` also uses the flag to skip normal cast
interruption gates.

### THF — Perfect Dodge (21)

Action script `perfect_dodge.lua`; logic in `thief.lua:406`. Self buff
`xi.effect.PERFECT_DODGE` power=1, duration=`30 + player:getMod(PERFECT_DODGE)`
(gear/AF extends it). Effect script adds `MEVA +3*JP`. Engine dodging is
hardcoded: `attack.cpp:476` short-circuits every incoming attack to a dodge
while the effect is present.

### PLD — Invincible (22)

Action script `invincible.lua`; logic in `paladin.lua:144`. Self buff
`xi.effect.INVINCIBLE` power=1 duration=30s. Effect script adds `UDMGPHYS -10000`
and `UDMGRANGE -10000` (100% physical + ranged damage reduction). **Magic still
hits.** The `checkInvincible` handler adds `100 * JP` to enmity VE (jumbo hate
spike scaling with JP). Engine also groups it with SENTINEL for auto-taunt at
`battleutils.cpp:2136`.

### DRK — Blood Weapon (23)

Action script `blood_weapon.lua`; logic in `dark_knight.lua:75`. Applies
`xi.effect.BLOOD_WEAPON` to target (self by default), power=1,
duration=`30 + ENHANCES_BLOOD_WEAPON`. Effect script stores `ENSPELL=17`
(`ENSPELL_BLOOD_WEAPON`) and `ENSPELL_DMG=power` on the effect object. Note
the effect adds these mods to the effect itself, not the entity — they only
apply while the effect is up, and it doesn't overwrite other enspells
(including Soul Enslavement). Engine `battleutils.cpp:1430` reads the enspell
tag on every melee proc: on non-undead targets, converts full melee damage
into HP absorbed (`Action->addEffectParam = PAttacker->addHP(absorbed)`), with
`+2%*JP` bonus.

### BST — Familiar (24)

Action script `familiar.lua`; logic in `beastmaster.lua:405`. `checkFamiliar`
refuses if no pet, if pet already has `hasFamiliarBuffs` localvar, or if pet
is neither a jug pet nor charmed. On use calls
`xi.pet.applyFamiliarBuffs(player, pet)` at `pets.lua:150`, redirects animation
to pet via `action:ID(player, pet)` and messages `FAMILIAR_PC`.

**What Familiar actually gives in LSB (`pets.lua:150-187`)**: sets
`hasFamiliarBuffs=1` (prevents re-application); if PC + charmed, extends charm
25-30 min +bonus; if `FAMILIAR_BONUS` mod > 0 adds `HASTE_ABILITY +100` per
point; boosts pet MaxHP by 10% and heals to top (which also wakes the pet).

**Deviation from retail**: no ATK/DEF/EVA/ACC boost to the pet — the script
has a `TODO does familiar give some bonus resistance to crowd control?` and
stops there.

### BRD — Soul Voice (25)

Action script `soul_voice.lua`; logic in `bard.lua:26`. Self buff
`xi.effect.SOUL_VOICE` power=1 duration=180s. Effect script only adds
`SONG_SPELLCASTING_TIME +2*JP` (JP-only bonus). The "double song potency"
behavior isn't in the effect script or via a mod add — I did not find an
engine-side branch on `EFFECT_SOUL_VOICE`, only the `HasStatusEffect` check
as an enum.

**Deviation flag**: Soul Voice's classic doubled-song-potency effect may
currently be a marker with no consumer. Needs runtime verification before
bots plan around it.

### RNG — Eagle Eye Shot (26)

Action script `eagle_eye_shot.lua`; logic in `ranger.lua:148`. Not a buff — a
fired weaponskill-shaped attack. `checkEagleEyeShot` refuses unless a valid
ranged weapon (archery/marksmanship/throwing) + ammo is equipped. Use script:
single hit, `ignoreShadows = true` (bypasses Utsusemi/Blink per explicit
comment), fTP mod `5.0/5.0/5.0` with tp=1000 forcing that multiplier, all
`_wsc` stats 0, `enmityMult = 0.5`, `+3*JP` to `ALL_WSDMG_ALL_HITS` before
firing. Fires as `doRangedWeaponskill`. Marksmanship targets get animation +1
(gunshot vs. bowshot). Messages `JA_DAMAGE` on hit, `JA_MISS_2` on 0 hits.

### SAM — Meikyo Shisui (27)

Action script `meikyo_shisui.lua`; logic in `samurai.lua:84`. Self buff
`xi.effect.MEIKYO_SHISUI` power=1 duration=30s, AND `player:addTP(3000)`
immediately. Effect script only adds `SKILLCHAINDMG +200*JP` (base 10000 mod,
so 2% per JP). The main mechanic is engine-side: `weaponskill_state.cpp:114`
makes WSes cost only 1000 TP while up (so 3-WS chain from the 3000 TP dump
plus regen). `mobskill_state.cpp:154` similarly for mobs. `battleutils.cpp:1997`
prevents the caster from giving TP to targets while the effect is up.

### NIN — Mijin Gakure (28)

Action script `mijin_gakure.lua`; logic in `ninja.lua:46`. Not a buff —
offensive suicide.
`dmg = floor(HP * 0.8) * magicResist * targetMagicDamageAdj * (1 + 0.03*JP)`,
run through stoneskin, then
`target:takeDamage(dmg, player, SPECIAL, ELEMENTAL)`. Then
`player:setLocalVar('MijinGakure', 1)` and `player:setHP(0)` — kills self.
Deals no damage if the caster is already dead but that's not gated (relies on
`setHP(0)` to KO). Downstream: `charentity.cpp:2143/2169/2177/2183/2222/2407`
reads the `MijinGakure` localvar to skip XP loss on that death and grant
enhanced Reraise-shaped HP return when `MIJIN_RERAISE` mod is present
(Utsusemi Obi et al.).

### DRG — Spirit Surge (29)

Action script `spirit_surge.lua`; logic in `dragoon.lua:183`. Requires a live
wyvern (`abilityCheckRequiresPet`). Takes 25% of pet MaxHP as buff power for
the DRG's own +MaxHP; steals all wyvern TP
(`target:addTP(petTP); wyvern:delTP(petTP)`); computes STR boost =
`1 + floor(petLevel/5)`; then `despawnPet`. Resets Jump/High Jump/Super Jump
recasts (IDs 158/159/160). Applies `xi.effect.SPIRIT_SURGE` for 60s with
power=maxHPBoost, subPower=strBoost. Adds wyvern's remaining HP to DRG.

Effect script adds `HP=power`, `STR=subPower`, `ACC=+50`, `ATTP=+25`,
`DEFP=+25`, `HASTE_ABILITY +2500` (25%), `MAIN_DMG_RATING +1*JP`. Comment
cites bg-wiki: 25% wyvern-MaxHP boost vs. ffxiclopedia's 15%; LSB picked 25%.
Also, while SPIRIT_SURGE up, Jump applies a 20% DEFENSE_DOWN for 60s
(`dragoon.lua:244-250`).

**Ambiguity note**: DRG has three 1-hr candidates. Call Wyvern (ID 61) is
20-min recast per SQL and just spawns a wyvern — clearly not the 2hr. Fly
High (ID 336, SoA JP) is the 96-JP hour ability. Spirit Surge is the 75-era
2hr and what LSB treats as one; the check
`if ability:getID() == xi.jobAbility.SPIRIT_SURGE` inside
`abilityCheckRequiresPet` is the only ability that gets the `ONE_HOUR_RECAST`
mod discount, confirming its 2hr status.

### SMN — Astral Flow (30)

Action script `astral_flow.lua` — no `job_utils` indirection, logic is
inline in the action file. Self buff `xi.effect.ASTRAL_FLOW` power=1
duration=180s. Effect script calls `target:recalculateAbilitiesTable()` on
gain and lose (this is what exposes the BP:Rage AoE spells — Astral Flow
BPs like Meteor Strike, Judgment Bolt are marked `ADDTYPE_ASTRAL_FLOW` and
gated by `charutils.cpp:6958-6963` which refuses to give them unless the
effect is up). If PC, adds `+5*JP` to all seven pet stats.

Engine also nulls the avatar perpetuation cost while Astral Flow is up
(`status_effect_container.cpp:2259-2262`). `job_utils/summoner.lua:133` also
zeroes base MP cost on Astral Flow-tagged BPs. Note there's also **Astral
Conduit (ID 337)**, JP ability, 30s power=15 tick=1 — treated as a separate
1h JA, not the 2hr.

### BLU — Azure Lore (93)

Action script `azure_lore.lua`; logic in `blue_mage.lua:60`. Self buff
`xi.effect.AZURE_LORE` power=1 duration=30s. Effect script empty — buff is
a marker only. `scripts/globals/bluemagic.lua:269, 407, 433, 490` reads it:
if AZURE_LORE up (or CHAIN_AFFINITY), Blue Magic spells cost TP but at full
TP tier (max multipliers). `charentity.cpp:1484` also groups it with Chain
Affinity for TP-cost handling.

### COR — Wild Card (96)

Action script `wild_card.lua`; logic in `corsair.lua:280`. On self-target,
rolls d6 into `corsairRollTotal` localvar and posts via
`action:info(caster, roll)`. Calls C++ `caster:doWildCard(target, total)` —
`lua_baseentity.cpp:14904` forwards to `battleutils::DoWildCardToEntity`
which does the outcome table (recast reset / MP / TP restore per roll 1-6).
Message ID = `435 + floor((total-1)/2)*2`, animation `132 + total-1`.

AoE: hits each party member individually with the same total (script
iterates via engine's ability AoE dispatcher; each call re-fetches the same
`corsairRollTotal` localvar). Interesting quirk: if you use it on someone
else (not self), it applies the effect from your last stored roll number
without re-rolling.

### PUP — Overdrive (135)

Action script `overdrive.lua`; logic in `puppetmaster.lua:59`.
`checkOverdrive` requires an automaton pet. Applies `xi.effect.OVERDRIVE`
to self, duration=60s. Effect script (`effects/overdrive.lua`) adds
`OVERLOAD_THRESH +5000` to owner; on pet: `HASTE_MAGIC +2500` (25%),
`MAIN_DMG_RATING +30`, `RANGED_DMG_RATING +30`, `ATTP +50`, `RATTP +50`,
`ACC +100`, `RACC +100`, `EVA +50`, `MEVA +50`, `REVA +50`, `DMG -5000`
(pet takes 50% less damage while OD up), plus `+5*JP` to all seven pet
stats. Sets `overdrive=1` localvar on pet. On lose reverses all.

### DNC — Trance (181)

Action script `trance.lua` — inline, no `job_utils` indirection. Self buff
`xi.effect.TRANCE` power=1 duration=60s. Also grants `player:addTP(100 * JP)`
(JP-only immediate TP). Effect script empty. Zero-TP-cost behavior for
dances/steps is read via `hasStatusEffect(xi.effect.TRANCE)` in
`job_utils/dancer.lua:161, 216, 266, 520` — the ability check functions
there just skip the "not enough TP" branch when Trance is up. No engine-side
handling.

### SCH — Tabula Rasa (210)

Action script `tabula_rasa.lua` — inline. Computes
`regenbonus = 3*floor((level-10)/10)` and `helixbonus = floor(level/4)`
(SCH main only, min L20). If any JP, immediately restores `2%*JP of MaxMP`.
Resets recast on ability IDs 228 (Sublimation), 231 (unimplemented slot),
232 (Elemental Siphon). Applies `xi.effect.TABULA_RASA` for 180s with
power = `floor(helixbonus*1.5)`, subPower = `floor(regenbonus*1.5)`.

Effect script (`tabula_rasa.lua`) branches on active arts. **Under Light
Arts / Addendum White**: `BLACK_MAGIC_COST/CAST/RECAST -30`,
`LIGHT_ARTS_REGEN += ceil(regen/1.5)`,
`REGEN_DURATION += ceil(regen*2/1.5)`, `HELIX_EFFECT += helix`,
`HELIX_DURATION += 108`. **Under Dark Arts / Addendum Black**: mirror for
`WHITE_MAGIC_*`, `HELIX_EFFECT += ceil(helix/1.5)`, `HELIX_DURATION += 36`.
**Under no arts**: `-10%` cost/cast/recast to both schools, full regen and
helix bonuses.

**Deviation flag**: the "charge-free stratagem" behavior isn't visible in
code — no engine handler ties Tabula Rasa to stratagem consumption, so LSB
may not implement that fully.

### GEO — Bolster (343)

Action script `bolster.lua`; logic in `geomancer.lua:291`. Self buff
`xi.effect.BOLSTER` duration=`240 + BOLSTER_EFFECT mod`, tick=3s. Effect
script calls `bolsterOnEffectGain`: if target already has `COLURE_ACTIVE`
up (an active Indicolure), doubles its subPower via `indiPotency * 2`
localvar. `bolsterOnEffectLose` (`geomancer.lua:568-`) reads Bolster JP and
adjusts Luopan `GEO_POTENCY` / player Indi values back down.

So Bolster is NOT a stateful "next spell" boost; it retroactively doubles
active geo effects and does nothing to future ones except through the JP
tail.

### RUN — Elemental Sforzo (356)

Action script `elemental_sforzo.lua` — inline. Self buff
`xi.effect.ELEMENTAL_SFORZO` power=1 duration=30s. Effect script adds
`UDMGMAGIC -10000` (100% magic damage nullification). Explicit
`-- Todo: status resists` comment.

**Deviation flag**: the retail behavior of granting immunity to all
magic-inflicted status effects (Sleep, Stun, etc.) is NOT implemented; only
damage nullification is in.

---

## Non-2hr 1-hr abilities (adjacent-tier)

Multiple jobs have SoA/RoV-era JP abilities that share the `ONE_HOUR_RECAST`
mod tier. Bot AI should treat them as siblings on the same cooldown budget,
not as "the 2hr":

- **MNK Inner Strength** (324) — `monk.lua:25`, 1h JP ability.
- **DRK Soul Enslavement** (330) — `dark_knight.lua:27, 133`, 30s effect.
- **RDM Stymie** (327) — `red_mage.lua:16`.
- **NIN Mikage** (335) — `ninja.lua:37, 99`, 45s hit-count effect.
- **SAM Yaegasumi** (334) — `samurai.lua:21, 91`, 45s power=12 effect.
- **BRD Clarion Call** (332) — `bard.lua:17`, song-slot expansion.
- **BLM Subtle Sorcery** (326) — `black_mage.lua:16`.
- **DRG Fly High** (336) — SoA JP ability.
- **SMN Astral Conduit** (337) — separate button from Astral Flow.

## Explicitly NOT 2hrs (naming trap)

- **GEO Blaze of Glory** (350) — 10-min recast, L60 JA that adds a status
  effect to enhance the next geocolure. Ability filename resembles 2hrs.
- **BST Run Wild** (282) — 15-min recast, Abyssea BST JA. Actual BST 2hr
  remains Familiar.
- **MNK Perfect Counter** (253) — 1-min recast, MNK79 JA.
- **PLD Intervene, WAR Blood Rage, THF Larceny, etc.** — SoA-era 1h JPs
  using the same `ONE_HOUR_RECAST` mod handling.

---

## Design implications for bot 2hr AI (#255)

1. **No unified flag.** There is no ability-table field flagging "this is a
   2hr". The markers are (a) the `setRecast(getRecast() - ONE_HOUR_RECAST_mod*60)`
   pattern in the action script and (b) animation timing 2000. Bots should
   hardcode the ID list from this document or scan for the recast pattern.

2. **Multiple 1h buttons per job.** WAR, MNK, DRK, RDM, NIN, SAM, BRD, BLM,
   DRG, SMN, GEO, RUN all have 2+ separate 1-hr abilities sharing the
   `ONE_HOUR_RECAST` mod cadence. Bot AI needs a priority/mode selector per
   job, not "the 2hr" as a singleton.

3. **Trigger shapes vary sharply.** Rough clusters:
   - **Damage 2hrs** (Eagle Eye Shot, Mijin Gakure): one-shot use-and-forget.
     Trigger on burst-window / execute-threshold.
   - **Self-buff, brief window (30-60s)**: Mighty Strikes, Hundred Fists,
     Manafont, Chainspell, Perfect Dodge, Invincible, Blood Weapon, Meikyo,
     Trance, Elemental Sforzo, Overdrive. Trigger on combat crisis or DPS
     race.
   - **Self-buff, extended window (180s)**: Soul Voice, Astral Flow,
     Tabula Rasa. Trigger to open a fight or align with buff windows.
   - **Emergency heal**: Benediction. Trigger on party HP crash, gate by
     HPP-crossing hysteresis.
   - **Pet-target buff**: Familiar (permanent, one-shot per pet), Overdrive
     (60s). Trigger on pet spawn / burst.
   - **AoE variance**: Wild Card. Trigger on party TP+recast desync.
   - **Geo retroactive**: Bolster. Trigger AFTER Indi/Geo colures are up.

4. **Buff interactions matter.** Several 2hrs change downstream AI behavior:
   - Chainspell + Manafont: change casting cadence (instant + free MP) —
     AI should burn MP-hungry spells during window.
   - Meikyo: makes WSes cost 1000 TP — AI should spam WS not save TP.
   - Trance: zero-cost dances/steps — AI should keep applying steps.
   - Blood Weapon: full melee dmg → HP absorb — AI should stay engaged (no
     debuff casting) during window.

5. **LSB deviations to reconcile before wiring**:
   - **Familiar** gives only pet HP+10% + charm-timer + haste. NO retail
     ATK/DEF/EVA/ACC boost. Bots planning burst around Familiar retail
     breakpoints will be off.
   - **Elemental Sforzo** does damage nullification only, NOT status
     immunity.
   - **Soul Voice** effect script only adds JP-scaled cast time; no visible
     engine branch doubling song potency. Verify runtime before assuming
     doubled potency.
   - **Tabula Rasa** "charge-free stratagems" is not implemented in visible
     code.
   - **Astral Conduit** effect script is empty; only stored power/duration.
     If bots plan burst BP:R via Conduit, verify the engine actually consumes
     the flag before wiring it up.
