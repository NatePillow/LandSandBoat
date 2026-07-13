
# Priority Items

* The necessity of multiple clients is absolutely untenable.
    * Move addon lua code server-side. There's no reason this needs to be client-side within this project, even if that is where it would naturally fit in the community tooling.
    * Swap out packet calls and ashitav3 calls for a BE equivalent; couple service classes
    * How can we activate/login characters without a client? How large of a BE component would that need to be?
        * Alliance characters need to have their sessions tied to the player session.
        * The BE can't blast out s2c packets for alliance characters.
    * How can we get the primary character access to other inventories, or to manually control movement via some kind of UI?
    * This needs to be a component that sits at edge right underneath the packet layer, executing the same methods triggered by the c2s packets.
    * It also needs to send s2c packets to the player session as needed.
    * Maybe the content that drives the system can be loaded via the module folder.
    * Maybe the same place the server ident is fired would serve as the right way to run loops.
* The necessity of a complicated client setup is also untenable.
    * Probably a default config of some sort for less savvy end-users. Install ashita and then drop *something* in.
    * It needs to be thin, real functionality needs to get moved to the BE.
* BE installation is also a roadblock.
    * How could this mod get packaged up with LSB in a way that's easy for end-users?
    * Wouldn't expect the average end-user to handle LSB setup as is, and then adding more complicated steps on top of that for this mod isn't going work.

---

# Docket

Open tasks tracked across the singleplayer fork. Status reflects current work-in-progress state, not retail-parity goals.

- **#173 — Multi-engagement mode (per-party mobs)** *(partial — paused pending puller playtest)*
  Allow each party within an alliance to engage its own mob simultaneously, instead of the whole alliance funneling onto the assist's single target. Foundational for multi-pull and add-handling at scale.
  Two-mode alliance toggle: `multiEngageMode = false` (legacy, whole alliance on one mob) vs `true` (each of 3 alliance sub-parties fights its own mob). One formation setting alliance-wide, applied per-party-mob independently. Cure isolation not enforced (parties in range coexist via existing 'party' heal scope). Puller cross-hate not an issue (FFXI mob-linking is idle-based, not aggro-based).
  Phase 1 DONE (#264): `alliance.multiEngageMode` + `alliance.partyAssistTargetId[1..3]` + `bots.get_party_slot(bot)` helper (party 1 = primary's party, 2/3 = other leaders sorted ascending by charId — deterministic Lua-only derivation, no C++ binding needed). `bots.get_current_mob_target(bot)` takes optional `bot` param and dispatches on mode: false → alliance target (unchanged), true → bot's party target. Backward-compat: all existing single-engage code paths unchanged when mode is off.
  Phase 2 DONE (#265): 0x176 subcommand `SET_MULTI_ENGAGE_MODE = 0x25` + `OnBotSetMultiEngageMode` C++ hook + `set_multi_engage_mode` Lua handler + client autoutil sender + Alliance-AI-tab toggle row + snapshot field ingestion. Server seeds all 3 party targets from allianceTarget on false→true, clears per-party state on true→false.
  Phase 3 PENDING (#266 — per-party puller): split `alliance.pullerCharId` into `alliance.partyPullerCharId[1..3]`, `ai_puller.tick` per-party lookup, 3 puller slots in Alliance AI tab. **Paused pending playtest of the current single-puller logic — user hasn't observed puller-mode work in practice yet, needs to verify baseline before extending.**
  Phase 4 PENDING (#267 — pool slicing): stun/sleep/BRD pools bucketed per-party when multi-engage is on. Provoke/bash naturally per-party via targeting; unchanged.
  Phase 5 PENDING (#268 — command routing + status UI): primary sets party 2/3 assist targets via chat command or addon button. Multi-party status blocks in UI. Deferred until BE work locks.

- **#180 — Custom AI for instance fights (BCNM/ENM/etc.)** *(pending)*
  Per-encounter AI overrides for instanced battles. Today the default cascade is generic; specific fights (Maat, sky gods, ENM mob types) benefit from fight-specific scripts.

- **#182 — Battle music swap — FF series homage** *(pending)*
  Swap battle music tracks for thematic moments and references to other FF games. Pure flavor; not gated by gameplay work.

- **#198 — One-click backup of user/server-specific data** *(pending)*
  Single command/UI button to snapshot the server's account database, character data, AH state, and any other player-affecting state into a portable archive for safe upgrades / rollbacks.

- **#219 — Mob-specific spell variant selection (dark-resist etc.)** *(pending)*
  Pick the right elemental spell family per-mob instead of firing a fixed pool. Today the AI walks its priority list and casts whatever's off recast, so a dark-resist NM eats Bio/Drain/Aspir into the wall while Fire/Blizzard would land. Needs mob-mod introspection (`FIRE_SDT`, `DARK_SDT`, etc.) at pick time, per-spell family gates in the sleep/enfeeble/nuke branches, and a fallback for mobs with no meaningful weakness. Related to #208 (back-off on repeated resist) but different — this is proactive selection, #208 is reactive give-up.

- **#253 — Post-75 era jobs (GEO + RUN) — parking lot** *(pending)*
  Placeholder for eventual role-file support for Geomancer and Rune Fencer. Both are post-75 additions and not on the near-term critical path. Deferred until the 75-era role coverage settles; would need indi/geo bubble management for GEO and rune rotation + Battuta / Vallation cadence for RUN.

- **#254 — 75-era stretch jobs (COR + SCH) — parking lot** *(pending)*
  Placeholder for role-file coverage of Corsair and Scholar. Both are technically 75-era but need bespoke resource-management logic (COR rolls with bust risk, SCH stratagem economy + arts swaps) that hasn't been designed yet. Not blocked on anything; just hasn't been prioritized against active job work.

- **#255 — Job 2hr handling pass (all jobs, single pass)** *(pending)*
  One coordinated pass to add 2-hour ability handling across every job: WHM Benediction, BLM Manafont, RDM Chainspell, THF Perfect Dodge, PLD Invincible, DRK Blood Weapon, BRD Soul Voice, RNG Eagle Eye Shot, SAM Meikyo Shisui, NIN Mijin Gakure, DRG Spirit Surge, SMN Astral Flow (+ AF Rage BPs currently deferred from role_smn), and later expansions. Wants alliance-aware fire triggers (Benediction on party HP crash, Invincible on tank HP crash, etc.) so 2hrs get spent when they actually matter, not autopiloted on cooldown. Single coordinated pass because most jobs share the same trigger-and-cast shape and doing them one-by-one grows drift between role files.

- **#274 — Idle-tick smart refresh of party status effects** *(pending)*
  During camp-idle time (out of combat, camp formation, no adds), have healers proactively refresh missing or expiring party buffs (Protect, Shell, Bar-X, Haste, Regen). Similar shape to the party-AoE range/move helper — scan party for members missing effect or with expiring effect, but idle-only, not tick-priority. Use `xi.spells.enhancing.getEffectId` to find the effect ID and check party members. Not needed during active fight (existing gate handles first cast); this fills the "buffs faded, WHM has effect too, party stays unbuffed forever" gap that current `can_protectra` / `can_shellra` self-status gates leave open.

- **#275 — Emergency mode: alliance response when tanks + melees all dead** *(pending)*
  Detect "no living melees left" (Tank + Melee roles alive = 0) alliance state and trigger emergency behavior for surviving mages: Sleepga/Sleep II on mob (WHM/RDM/BLM), 2hr fire (Manafont/Chainspell/Astral Flow BPs), WHM Benediction on the current aggro target, coordinated retreat toward primary if none of the above work. Task #276 patched the AoE→Spread fallback so mages at least have stable anchoring when tanks die, but the alliance still doesn't have a real "oh shit" response. This is a full design pass, deferred.

- **#277 — AoE-buff positioning lease-hold (smoothing)** *(optional — only if the stutter proves worth it)*
  Cosmetic smoothing for the WHM AoE-buff walk (bar spells, Protectra/Shellra). The mage steps toward the party centroid, gets yanked back toward its formation slot on any tick a cure/status branch preempts the positioning branch (because `roleMovementTarget` is consume-on-read), then steps forward again — visible forward/back stutter. Deferred fix: when a positioning branch sets `roleMovementTarget`, also stamp a short lease (`state.aoeHoldUntilMs`); in `ai_move`'s fallback, HOLD instead of running formation while the lease is live. Smooths the stutter *without* giving up consume-on-read (never latches a target). Full design + anchors in `.claude/memory/project_aoe_positioning_lease_hold.md`. Do NOT kill consume-on-read or loosen the `party_aoe_move_target` `anyOut` cast-gate. Only worth doing if longer observation shows the stutter actually delays buffs or reads as buggy.

- **#279 — Player-issued bot commands (`ai_command`) — issues + no UI + verb expansion** *(paused — has issues)*
  One-shot commands from the primary to a named headless. Full pipeline is built and loads: client `/bot <name> /<verb> "<thing>" [target]` (autobots.lua) → C2S 0x1A0 BOT_COMMAND → `luautils::OnBotIssueCommand` → `ai_command.dispatch` (queues `state.pendingCommand`) → `bots.runCombatTick` calls `ai_command.try_fire` before the role tick. Verbs: `ma` (spell), `ja` (ability), `ws`, `ra`, `item`. Target tokens: `<me>`, `<t>`, `<bt>`, party-member name.
  Three open threads: (1) **known issues** — user set this aside because it misbehaves in practice; needs root-cause (reproduce a failing `/bot` invocation, trace dispatch→try_fire). (2) **No UI** — everything is chat-only; `autoutil.send_bot_command` is called from exactly one place. A lightweight per-bot command row (verb dropdown + name box + "use my target" toggle + Fire) would slot into autobots_ui. (3) **Verb expansion** — emotes are the whole "silly fun" bucket and are ONE generic handler: `xi.emote[name:upper()]` → `bot:sendEmote(target, id, xi.emoteMode.MOTION, false)` covers all ~40 automatically (`sendEmote` binding confirmed in lua_baseentity.cpp). Optional `say`/`shout` verb for bot banter (real chat text is server-representable; slash commands are NOT — the client is the command interpreter, so only emotes/chat/combat map to server actions for a clientless bot).

---

# Open Items

* Documentation
    * Installation and usage
* Server-side replacement for ffxiahbot
    * How can this be done surgically to avoid conflicts with the upstream repo?
    * Would be great if, for sell_single=0 items, you could buy back only the stock you sold to it, and it would remain on sale indefinitely
    * Should be able to buy and sell instantly
* Addons
    * Combat support:
        * Finished: WAR, MNK, WHM, BLM, RDM, THF, PLD, DRK, RNG, SAM, DRG, NIN, SMN, BRD
        * Planned: COR, DNC
        * No support planned: BST
        * TBD: PUP, SCH, BLU, RUN, GEO
    * Several areas of additional support for economic/utility addons:
        * Access all vendors from the current zone
        * Sorting/organizing across all containers
        * Updating gear swap logic
        * autowarp should be expanded to include static warp points for the most remote regions to augment homepoints/survival guides
* Dynamis, Sky, Sea, Kings
    * TBD
* Mounts
    * How to get additional mounts?
    * Buy them in automog UI?
* BCNM - drop rates TODO
    * Uncapped
* ENM - drop rates TODO
    * 50
    * 60
    * 75
* Trusts
    * Need to find a way to move custom gambit code to module
