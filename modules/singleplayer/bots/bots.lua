-----------------------------------
-- bots — central state + dispatch registry for the bot AI system.
--
-- Holds the Role / BotMode enums, the alliance singleton + its candidate
-- pools, the consolidated per-bot scratch table (alliance.bot[charId]), the
-- accessor pair (ensure_bot / get_bot_state), the role dispatcher
-- (runCombatTick), and the onBotTick / onCommand / onSetRole override
-- registrations. All per-bot state lives in alliance.bot[charId]; no
-- module-local state tables.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('bots')

xi                   = xi                   or {}
xi.singleplayer      = xi.singleplayer      or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
local bots = xi.singleplayer.bots

-- Role enum. Used by alliance.roleMap, role dispatch in runCombatTick,
-- and isMageRole/isMeleeRole predicates in ai_util.
xi.singleplayer.bots.Role = {
    Idle    = 0,
    Tank    = 1,  -- assist target / puller — runs role_tank.tick
    Healer  = 2,  -- runs role_heal.tick
    Nuker   = 3,  -- runs role_nuke.tick
    Rdm     = 4,  -- runs role_rdm.tick
    Melee   = 5,  -- skillchain participant / DD — runs role_melee.tick
    Skillup = 6,  -- magic-skill grind rotation — runs role_skillup.tick
    Brd     = 7,  -- songs + /WHM support — runs role_brd.tick (#220)
    Smn     = 8,  -- avatar + BP rotation + /WHM support — runs role_smn.tick (#220)
}

-- BotMode enum. Set per CCharEntity by 0x176 SET_MODE; gates onBotTick
-- behavior in C++ (post_tick.cpp) and inside the Lua tick chain below.
xi.singleplayer.bots.BotMode = {
    Off          = 0,  -- everything off
    CombatOnly   = 1,  -- combat AI on, movement off ("Stop Movement")
    Full         = 2,  -- both on ("Start Actions")
    MovementOnly = 3,  -- combat AI off, movement on ("Stop Actions")
}

-- Live runtime state homes:
--   * xi.singleplayer.bots.alliance             — singleton alliance state (defined below)
--   * xi.singleplayer.bots.alliance.bot[charId] — per-bot scratch (lazy-init via bots.ensure_bot)

-----------------------------------
-- Alliance state. Singleton — one human player + their bots = one alliance.
-- Populated at spawn by bots_spawn from the disk JSON in
-- singleplayer/config/alliance/<name>.json. See README's "Disk config
-- schema" + "Role derivation" sections for shape and rules.
-----------------------------------
bots.alliance = {
    -- Static state

    -- The human player's charId.
    mainCharId       = 0,
    -- Flat list of spawned bot IDs. Built at spawn by bots_spawn.
    headlessCharIds = { },
    -- charId -> Role. Built at spawn from cfg.roles + derive_role. O(1)
    -- "what role does this bot have" lookups. headlessCharIds is the
    -- canonical "who is in the alliance" list; roleMap is purely
    -- additional facts about an already-known charId.
    roleMap = {},

    -- CANDIDATE POOLS — populated at spawn (#216 — implementation pending).
    -- Pool entries are charIds; the runtime filters out ineligible bots,
    -- sorts the remainder by the pool's sort key, picks the top.
    --
    -- Sort keys:
    --   * provokePool                       — HP% desc. Highest-HP tank
    --                                         absorbs the next pull; getting
    --                                         hit drops HP; next cycle picks
    --                                         someone else. Fairness emerges.
    --   * stunPool / rdmSleepPool / blmSleepPool — MP% desc. Same mechanism.
    --
    -- Eligibility filters apply BEFORE sort:
    --   * alive (not isDead / KO)
    --   * in zone (lookup not nil)
    --   * in range (per-spell or melee range for Provoke)
    --   * off recast (PRecastContainer)
    --   * not mid-cast (engine state)
    --   * for spells only: not silenced/muted, has the spell,
    --     enough MP to actually cast (spellInfo:getMPCost() — no extra
    --     floor beyond that for spell pools)
    --
    -- Floors:
    --   * provokePool: HP% >= 30% — below that the tank is too fragile
    --                  to absorb another mob.
    --   * stunPool / rdmSleepPool / blmSleepPool: none beyond "enough
    --                  MP to cast." MP% is a sort key, not a gate.
    --
    -- Tiebreak: pool-array index (earlier-listed bot wins on tied %).
    --
    -- Sleep precedence: try rdmSleepPool first, fall back to blmSleepPool.
    -- A brdPool slot will eventually live between them (#217) but is NOT
    -- implemented yet.
    --
    -- DEFERRED to follow-up tasks:
    --   * brdPool — Bards Lullaby in sleep rotation (#217).
    --   * Sleepga AoE decision branch — separate from single-target pools,
    --     fires on add-density precondition (#218).
    --   * WHM Repose — light-based sleep, mob-resist-dependent (#218).
    --   * Dark-resist mob preference — spell-variant pick layer, not a pool
    --     concern (#219).
    --   * Richer tiebreak (claim/buff/gear) — revisit on observed bad
    --     behavior; not high priority.
    provokePool   = {},
    stunPool      = {},
    bashPool      = {},  -- PLDs with Shield Bash + DRKs with Weapon Bash; pick-one-per-mob-TP-move
    rdmSleepPool  = {},
    blmSleepPool  = {},

    -- Window flags for interrupt pools. Set on mob SkillStart, consumed by
    -- role ticks until something fires or the window elapses. Decouples the
    -- "trigger" event from the "fire" tick so a busy stunner/basher at the
    -- instant of SkillStart doesn't whiff the interrupt — next tick someone
    -- else (or themselves, post-cast) can still cover it.
    stunWindowUntilMs = 0,
    bashWindowUntilMs = 0,

    -- Per-mob sleep cast reservation. Keyed by add mob id → expiresAtMs.
    -- Set when a sleeper begins casting Sleep/Sleep II/Sleepga/etc on a
    -- specific add so the next-tick picker won't pile a second sleeper
    -- onto the same in-flight target. Cleared by:
    --   * MAGIC_USE listener on the caster (cast finished, hit or miss)
    --   * MAGIC_INTERRUPTED listener on the caster
    --   * lazy prune in get_next_sleep_target when expiry passes
    -- Expiry = cast time + 1.5s buffer, so a caster dying mid-cast still
    -- frees the slot in bounded time without needing a death listener.
    sleepInFlight = {},

    -- Dynamic state. Single per-bot table keyed by charId. Holds ALL per-bot
    -- scratch — ticker dispatch fields, ability state, magic state, role
    -- state, lot state, rest state, movement state. bots.ensure_bot(charId)
    -- lazy-inits to the schema below.
    bot = {},

    -- Single source of truth for "what is the alliance fighting".
    --   * Written by ATTACK command (player /be-attack).
    --   * Cleared by mob-death sweep in bots_listeners.poll.
    --   * Auto-populated from peelable threats in ai_threat.ensure_alliance_target
    --     when empty (so an idle alliance picks up a new add automatically).
    allianceTarget = 0,

    -- Multi-engagement mode (#173). When true, each of the 3 alliance
    -- sub-parties fights its own mob simultaneously. When false, the
    -- entire alliance funnels onto `allianceTarget` (legacy behavior).
    -- Toggled by the client autobots addon "Multi-engage" switch (Phase 2).
    -- get_current_mob_target(bot) dispatches on this: false → allianceTarget,
    -- true → partyAssistTargetId[bot's party slot 1..3]. See get_party_slot.
    multiEngageMode = false,

    -- Per-party mob targets. Only consulted when multiEngageMode = true.
    -- Index 1 = primary's party (whoever's party contains mainCharId).
    -- Index 2/3 = other parties, sorted by their leader's charId ascending
    -- (deterministic via get_party_slot).
    -- Seeded to allianceTarget on all 3 slots when multiEngageMode flips true.
    -- Cleared to 0 when a party's mob dies (mirrors allianceTarget hygiene).
    partyAssistTargetId = { 0, 0, 0 },

    -- Multi-tank rotation state. Tracks the last time a tank in each
    -- scope (party-slot 1..3, or slot 1 for alliance-wide when multi-engage
    -- is off) fired its main-mob Provoke / Flash. Rotation interval is
    -- 30_000 / tank_count (Provoke) or 45_000 / pld_count (Flash), so
    -- multiple tanks stagger instead of dumping recasts simultaneously.
    -- Add-Provoke / Flash-add bypass rotation — urgency wins over spacing.
    lastProvokeAtMs = { 0, 0, 0 },
    lastFlashAtMs   = { 0, 0, 0 },

    -- (nmMode retired — ai_ability.is_nm is now always engine-autodetect.)

    -- Puller AI — when pullerCharId != 0 AND walkingFormation == 'camp', the
    -- named bot scouts for VT/IT mobs within pullerRange of the camp anchor
    -- and brings them home for the alliance. See ai_puller.lua.
    -- Set via SET_PULLER / SET_PULLER_RANGE subcommands on 0x176.
    pullerCharId = 0,
    pullerRange  = 50,  -- yalms; server clamps SET_PULLER_RANGE to [5, 255]
    pullerMinCon = 5,   -- EXPCHAIN value: 0=TW, 1=EP, 2=DC, 3=EM, 4=T, 5=VT, 6=IT
    pullerMaxCon = 6,
    pullerResumeMpp = 60, -- min heal-role (WHM/Healer, or RDM backup) MP% before
                          -- the puller resumes; SET_PULLER_RESUME_MPP, clamp [0,100]
    pullerNameFilter = {}, -- array of mob name strings; empty = no name restriction
    -- Puller Start/Stop toggle. Gates only the IDLE→SCOUTING transition —
    -- a pull already in flight (SCOUTING/PULLING/RETURNING/HANDOFF) finishes
    -- naturally on Stop. Fresh set_puller assignments start paused; user
    -- hits Start explicitly (Alliance AI tab). Toggled via SET_PULLER_PAUSED.
    pullerPaused = true,

    -- SC HP-percent thresholds (runtime-tunable via SET_SC_THRESHOLD on 0x176).
    -- Replaces the previous NM-gated hardcoded pairs in should_open_sc /
    -- should_solo_ws / sc_is_close.
    --   scStartHP  — opener stops trying when target HPP > this. Lets the
    --                initial WS burst land at full HP before SC engages.
    --   scStopHP   — opener stops trying when target HPP < this. Closer
    --                still closes if a SC is already in flight (this is
    --                opener-only — overkill avoidance, not a hard floor).
    --   scNoMoreHP — "no more SCs will open" gate. Used by solo melee to
    --                rescue-fire WS, and by sc_is_close to tell nukers /
    --                whm to stop holding MP for an MB that won't happen.
    -- Defaults 95 / 10 / 8.
    scStartHP  = 95,
    scStopHP   = 10,
    scNoMoreHP = 8,

    -- battle 'off' now means "freeze in combat"; 'legacy' is the old fall-
    -- through-to-pre-formation behavior. Default is 'off' so a freshly-
    -- spawned alliance holds position in combat unless the user explicitly
    -- picks a slot-ring formation (tight / spread) or opts into the legacy
    -- pre-formation behavior.
    battleFormation  = 'off',
    walkingFormation = 'off',  -- xi.singleplayer.bots.ai_formation key while travelling
    campAnchor       = nil,    -- { x = ..., z = ... } when walkingFormation == 'camp'

    -- Stun mode (replaces the legacy BOT_STUN_PERSIST_UNTIL_FIRED settings
    -- flag). Drives ai_magic.onMobSkillStart's handling of stunWindowUntilMs:
    --   'always' - window opens to math.huge on every mob WS start, stays
    --              open until a stunner fires (cleared by check_for_stun)
    --              or the alliance target dies / disengages (cleared by
    --              bots.set_alliance_target(0)). Gives the alliance a
    --              "control breather" at the cost of one extra stun cast.
    --              Default - matches the legacy flag's default value.
    --   'window' - window equals the mob's actual WS castTime (with a
    --              500ms minimum for instant moves). Strict interrupt
    --              window; if everyone is busy at the trigger instant,
    --              the interrupt is missed.
    -- Bash window is always strict (the gameplay rationale doesn't
    -- generalize the same way - see ai_magic.onMobSkillStart comment).
    stunMode = 'always',

    -- Built at spawn from cfg.solo. { [charId] = wsName } for melees who
    -- fire solo WSes (i.e. not part of any SC pair).
    solo = {},

    -- Built at spawn from cfg.sc. Array of pair objects, runtime order
    -- evolves via fan_rotate_sc_on_close (closer's WS land moves the
    -- pair to the back).
    sc = {
        -- array of objects:
        -- {
        --     priority = 1,
        --     openName = "Freya",
        --     openWS = "Vorpal Thrust",
        --     closeName = "Zariah",
        --     closeWS = "Dancing Edge"
        -- },
    },
}

-----------------------------------
-- Listener registry. Tracks bot:addListener identifiers per bot so a
-- single teardown call can unregister every listener across modules.
-----------------------------------
bots.listeners = bots.listeners or {}  -- [botId] = { [identifier] = true, ... }

-----------------------------------
-- Role module registry. Populated by each role module at load time so
-- the central dispatcher can iterate roles without hardcoding the list.
-----------------------------------
bots.role_modules = bots.role_modules or {}  -- [roleKey] = <module table>

-----------------------------------
-- Action-result sub-handler registry. The single canonical
-- xi.singleplayer.bots.onActionResult handler (added later) iterates this in declared
-- order, removing the load-order fragility we hit with three separate
-- addOverride callsites.
-----------------------------------
bots.action_handlers = bots.action_handlers or {}  -- list of { module = ..., fn = ... }

-----------------------------------
-- Per-bot state accessor. Lazy-inits the alliance.bot[charId] entry with the
-- full consolidated schema. All per-bot scratch lives here — there is no
-- module-local state table.
-----------------------------------
function bots.ensure_bot(charId)
    local s = bots.alliance.bot[charId]
    if s == nil then
        s = {
            -- ticker / dispatch
            role            = bots.Role.Idle,
            parentCharId    = 0,
            assistCharId    = 0,
            on_load_fired   = false,  -- once-per-bot marker; flipped true on first runCombatTick after the bot is opted in (BotMode != Off)
            -- ai_ability has no per-bot scratch anymore (#228 dropped the
            -- activeTargets / activeTargetOffTank cache in favor of runtime
            -- derivation via ai_util.assist_target + ai_threat.member_tier).
            -- ai_magic
            lastCastEnd              = 0,
            nextPosUpdate            = 0,
            followOn                 = false,
            -- stunReady GONE (#229): replaced by alliance.stunWindowUntilMs;
            -- ticks consume the window instead of a per-bot flag.
            casualNukingDelay        = 7,
            casualNukeDelayMultiple  = 1,
            casualNukingDelayUntil   = 0,  -- alias used by some sites; same semantics as casualNukingDelay+casualNukeDelayMultiple cooldown
            stopCastingUntil         = 0,
            spellLog                 = {},
            nukeHistory              = {},
            nukeUntilDead            = false,
            lastCasualNukeEnd        = 0,
            -- Casual-nuke rotation (role_nuke / role_rdm). Per-char, set from
            -- the Status card. Rotation = spells before repeat (0 = All); MB
            -- mode 'include'/'exclude' toggles whether SC-MB elements are used.
            casualNukeRotation       = 3,
            casualNukeMbMode         = 'include',
            -- role_melee
            sc_paused              = {},
            lastRaShotMs           = 0,
            thfRaDelay             = 15,
            chiBlastReadyForTarget = nil,
            sataInProgress         = false,
            -- Melee-side analog of nukeUntilDead. Set by bots_spawn.finish_alliance
            -- when the Finish button is clicked; consumed in role_melee.tick to
            -- bypass SC opener/closer gating and force-fire WS whenever the bot
            -- has ≥1000 TP and is engaged. Cleared together with nukeUntilDead
            -- in ai_magic.check_for_target_death when the alliance target dies.
            wsUntilDead            = false,
            -- role_heal scope toggle. Three modes (set via 0x176 SetHealScope):
            --   'party'          — default. Heal only own party (current behavior).
            --   'allianceAssist' — party as before + BLM-tier emergency cures on
            --                      alliance as lower-priority fallback.
            --   'allianceMain'   — WHM-tier cures + single-target status removal
            --                      widened to whole alliance. Curaga / Erase /
            --                      Protectra / Shellra remain party-only by
            --                      game mechanics (engine targets reject
            --                      cross-party).
            healScope              = 'party',
            -- role_skillup
            mode           = 'magic',
            rotation       = {},
            currentIndex   = 1,
            priorRole      = nil,
            -- ai_lot
            activeGroups           = {},
            namedItems             = {},
            activeLots             = {},
            -- ai_rest
            heal_override          = nil,      -- Player override. 'force_on' = stay seated until Heal Off clears it. nil = auto-rest runs.
            lastHealingAddMs       = 0,
            lastHealingDelMs       = 0,
            flickerWarnedMs        = 0,
            -- ai_command — single-slot pending command from primary's /bot chat verb.
            -- { kind, name, targetId, queuedAtMs, primaryId } | nil. Last-write-wins.
            pendingCommand         = nil,
            -- SATA scheduling — per-bot, applies only to THF roles. 'combined'
            -- = SA → TA → WS in one combo (current/default). 'split' alternates
            -- SA and TA across WSes so both hit damage windows over the 60s
            -- recasts. Eligibility (has SA AND TA) is enforced client-side
            -- before showing the toggle; server-side enforcement is in
            -- role_melee.use_weapon_skill's split branch.
            sataMode               = 'combined',
            selectedSata           = nil,        -- 'SA' | 'TA' | nil; flipped only when both were available
            lastSataUsed           = nil,
            -- PLD add-control mode. Set via 0x176 SET_ADD_CONTROL_MODE from
            -- the status-tab dropdown. Decides which tool the PLD uses on
            -- peelable adds:
            --   'provoke' (default) - Provoke handles adds (legacy behavior)
            --   'flash'             - Flash handles adds; Provoke skipped on adds
            --                         but still fires on the main alliance target
            --   'both'              - Both Provoke + Flash on adds (interleaves
            --                         across ticks - one ability per tick)
            -- Eligibility (has Flash) is enforced client-side before showing
            -- the dropdown; this state is read by role_tank.tick.
            addControlMode         = 'provoke',
            -- role_brd song-roster override (#252). Per-slot spell-id pin.
            -- Index 1..4 maps to SLOT_ORDER in role_brd: front_minuet,
            -- front_madrigal, back_ballad_a, back_ballad_b. 0 = "auto" =
            -- fall through to best_tier. Whole roster = {0,0,0,0} by default
            -- so a fresh BRD bot uses the family-best for every slot.
            songRoster             = { 0, 0, 0, 0 },
            -- NIN per-bot state (#249). lastOffensiveNinjutsuMs paces the
            -- 2s gap between wheel/debuff casts so autoattacks land in
            -- between. ninWheelIdx tracks the current position in the
            -- Fire→Ice→Wind→Earth→Lightning→Water elemental wheel.
            lastOffensiveNinjutsuMs = 0,
            ninWheelIdx            = 1,
            -- SMN per-bot state (#220).
            --   smnAvatarSpellId — user's dropdown pick (set via 0x176
            --     SET_SMN_AVATAR). Nil / 0 = "blank / auto" — no
            --     preference, role_smn.get_selected_avatar_spell falls
            --     through to best_solo_avatar (Garuda unless mob
            --     weakness + weather push a candidate to +20% bonus).
            smnAvatarSpellId = nil,
            -- ai_move
            lastMovedMs            = 0,
            stuckHistory           = {},
        }
        bots.alliance.bot[charId] = s
    end
    return s
end

-- Thin wrapper for the entity-keyed flavor that the per-tick code uses.
function bots.get_bot_state(entity)
    return bots.ensure_bot(entity:getID())
end

-----------------------------------
-- Hooks called from C++ (luautils.cpp).
-----------------------------------

-- Fires every PostTick (1s) for any char with m_botMode != Off.
-- Mode == Off means "Stop Actions": pause combat AI / movement, but allow
-- the override chain to still fire so utility ticks (ai_rest heal/rest,
-- auto-equip swap listeners, etc.) keep running while the user is camped.
-- Override hooks call super(...) first, then run their own tick after — so
-- bailing here only affects the autoai.lua portion, not other modules.
m:addOverride('xi.singleplayer.bots.onBotTick', function(entity, mode)
    -- Base is registered via addOverride (not direct assign) so any module
    -- loading before us that already chained gets composed in rather than
    -- stomped. super() runs whatever's already in the chain first; this
    -- file's body is the "base behavior."
    if super then super(entity, mode) end
    if entity == nil then return end

    local state    = xi.singleplayer.bots.get_bot_state(entity)
    local headless = entity:isHeadless()

    -- Zone-mismatch silent pause (#214). When a headless ends up in a
    -- different zone from its primary (server hiccup, instance restriction,
    -- disconnect race — the engine's moveOwnedHeadlessIntoPrimaryZone
    -- handles the normal zoning path), AI no-ops until they're co-located
    -- again. Primary's responsibility to manually warp them back; we just
    -- silently keep out of the way meanwhile.
    if headless then
        local primary = GetPlayerByID(entity:getParentCharId())
        if primary ~= nil
           and entity.getZone and primary.getZone
           and entity:getZone() ~= primary:getZone() then
            return
        end
    end

    -- Lazy-register PAI event listeners on first tick. Idempotent — the
    -- bot_listeners module guards with its own registered flag. Always
    -- runs so listeners are wired even while combat AI is paused.
    if xi.singleplayer.bots.bots_listeners and xi.singleplayer.bots.bots_listeners.register then
        xi.singleplayer.bots.bots_listeners.register(entity)
    end

    -- Publish the bot-state snapshot to the C++ HTTP cache. Runs for every
    -- primary tick regardless of BotMode — even in Off, the addon UI needs
    -- a live snapshot to render config. Headless ticks skip this; the
    -- publish keys on primary identity. Cheap: ~250 byte JSON encode per
    -- ~400ms primary tick.
    if not headless then
        bots.publish_state_snapshot(entity)
    end

    if mode == xi.singleplayer.bots.BotMode.Off then
        return
    end

    -- Tick-time polling for events without direct bot listeners
    -- (mob death, assist target tracking)
    if xi.singleplayer.bots.bots_listeners and xi.singleplayer.bots.bots_listeners.poll then
        xi.singleplayer.bots.bots_listeners.poll(entity)
    end

    -- Combat tick — runs in every mode EXCEPT MovementOnly. MovementOnly
    -- means "Stop Actions": bots follow primary in formation but don't
    -- cast, WS, or use JAs.
    if mode ~= xi.singleplayer.bots.BotMode.MovementOnly then
        xi.singleplayer.bots.runCombatTick(entity, state)
    end

    -- Movement tick — runs in Full and MovementOnly. Skipped in CombatOnly
    -- ("Stop Movement") and Off.
    --
    -- Headless-only movement. Primaries drive themselves — the old auto-
    -- step-into-melee path was setPos-based and jerky; we no longer try to
    -- auto-position a real PC client. The addon UI exposes only Off /
    -- CombatOnly for primaries (no Full / MovementOnly options).
    if headless
       and (mode == xi.singleplayer.bots.BotMode.Full
            or mode == xi.singleplayer.bots.BotMode.MovementOnly) then
        xi.singleplayer.bots.ai_move.runMovementTick(entity, state)
    end
end)

-- 0x176 ATTACK / DISENGAGE dispatched from the primary char.
m:addOverride('xi.singleplayer.bots.onCommand', function(primaryEntity, command, arg)
    if super then super(primaryEntity, command, arg) end
    if primaryEntity == nil then return end
    local primaryId = primaryEntity:getID()

    if command == 'ATTACK' then
        xi.singleplayer.bots.set_alliance_target(arg)
        BotPushLog(primaryEntity, 'BotAI', 'Engage target ' .. tostring(arg))
    elseif command == 'DISENGAGE' then
        xi.singleplayer.bots.set_alliance_target(0)
        BotPushLog(primaryEntity, 'BotAI', 'Disengage')
        -- Propagate to all linked bots
        for botId, st in pairs(bots.alliance.bot) do
            if st.parentCharId == primaryId then
                local bot = GetPlayerByID(botId)
                if bot ~= nil then bot:disengage() end
            end
        end
    end
end)

-- Role → ported module map. Used by onSetRole + runCombatTick.
local function roleModule(role)
    if role == xi.singleplayer.bots.Role.Tank    then return xi.singleplayer.bots.tank    end
    if role == xi.singleplayer.bots.Role.Melee   then return xi.singleplayer.bots.melee   end
    if role == xi.singleplayer.bots.Role.Healer  then return xi.singleplayer.bots.heal    end
    if role == xi.singleplayer.bots.Role.Nuker   then return xi.singleplayer.bots.nuke    end
    if role == xi.singleplayer.bots.Role.Rdm     then return xi.singleplayer.bots.rdm     end
    if role == xi.singleplayer.bots.Role.Skillup then return xi.singleplayer.bots.skillup end
    if role == xi.singleplayer.bots.Role.Brd     then return xi.singleplayer.bots.brd     end
    if role == xi.singleplayer.bots.Role.Smn     then return xi.singleplayer.bots.smn     end
    return nil
end

-- 0x176 SET_ROLE on a named bot. Updates the bot's role; dispatch via
-- runCombatTick + roleModule() handles which module's tick to run.
--
-- opts.activate (default true) decides whether to fire on_load NOW or
-- defer it. Today the only caller that passes activate=false is
-- bots_spawn for the primary at spawn time: stage the role so dispatch
-- is wired up, but skip on_load until the player opts in by flipping
-- BotMode != Off. The deferred fire happens on the first runCombatTick
-- after opt-in, gated by state.on_load_fired on the per-bot scratch
-- (see runCombatTick below). Both the immediate fire and the deferred
-- fire flip on_load_fired = true, so it runs exactly once per bot.
m:addOverride('xi.singleplayer.bots.onSetRole', function(botEntity, role, opts)
    if super then super(botEntity, role, opts) end
    if botEntity == nil then return end
    opts = opts or {}
    local activate = opts.activate
    if activate == nil then activate = true end

    local state = xi.singleplayer.bots.get_bot_state(botEntity)
    state.role = role

    if activate then
        state.on_load_fired = true
        local nextMod = roleModule(role)
        if nextMod ~= nil and nextMod.on_load ~= nil then
            nextMod.on_load(botEntity)
        end
    end
end)

-----------------------------------
-- Combat tick + alliance/assist resolution helpers. Public on
-- xi.singleplayer.bots so ai_move can call them from runMovementTick.
-----------------------------------

-- Resolve the bot's parent CharId once and cache it on per-bot state.
function bots.get_primary_for_bot(bot, state)
    if state.parentCharId == 0 then
        if bot:isHeadless() then
            state.parentCharId = bot:getParentCharId()
        else
            state.parentCharId = bot:getID()
        end
    end
end

function bots.get_assist(state)
    -- Per-bot override (rarely set explicitly).
    if state.assistCharId ~= 0 then
        return GetPlayerByID(state.assistCharId)
    end
    -- Alliance-level assist (Tank role) populated at spawn from
    -- cfg.roles.tank[1]. Single source of truth — no per-primary cache,
    -- no per-call name lookup.
    return bots.get_assist_entity()
end

-- Alliance-target accessors. allianceTarget is the single source of truth
-- for "what is the alliance fighting" — set by player command (ATTACK),
-- cleared by mob death (bots_listeners.poll), auto-populated from peelable
-- threats when empty (ai_threat.ensure_alliance_target).
-- Returns the assist entity — the Tank-role character the alliance assists.
-- charId is alliance.assistCharId (populated at spawn); we wrap with
-- GetPlayerByID so callers can dot straight into the entity.
function bots.get_assist_entity()
    local id = bots.alliance and bots.alliance.assistCharId or 0
    if id == 0 then return nil end
    return GetPlayerByID(id)
end

function bots.get_assist_charId()
    return bots.alliance and bots.alliance.assistCharId or 0
end

function bots.get_alliance_target_id()
    return bots.alliance and bots.alliance.allianceTarget or 0
end

function bots.set_alliance_target(id)
    if bots.alliance == nil then return end
    bots.alliance.allianceTarget = id or 0
    -- When clearing the alliance target (mob died / disengage / target
    -- switch), clear any open interrupt windows too. Critical for the
    -- 'always' stun mode (alliance.stunMode) — without this an infinite
    -- window from a fight where no stunner was ever available would bleed
    -- into the next fight. Same hygiene for bash for free.
    if (id or 0) == 0 then
        bots.alliance.stunWindowUntilMs = 0
        bots.alliance.bashWindowUntilMs = 0
    end
end

-----------------------------------
-- Multi-engagement (#173) setters. Called by Phase 2's toggle handler and
-- (eventually) per-party assist commands. See partyAssistTargetId comment
-- in the alliance table above for semantics.
-----------------------------------

-- Set a specific party's assist target. slot is 1/2/3.
function bots.set_party_assist_target(slot, id)
    if bots.alliance == nil then return end
    local A = bots.alliance
    A.partyAssistTargetId = A.partyAssistTargetId or { 0, 0, 0 }
    if slot >= 1 and slot <= 3 then
        A.partyAssistTargetId[slot] = id or 0
    end
end

-- Seed all 3 party assist targets from the alliance target. Called when
-- multiEngageMode toggles from false → true so all parties start on the
-- current mob, then user separates by assigning per-party targets.
function bots.seed_party_targets_from_alliance()
    if bots.alliance == nil then return end
    local A = bots.alliance
    A.partyAssistTargetId = { A.allianceTarget or 0, A.allianceTarget or 0, A.allianceTarget or 0 }
end

-- Set the multi-engage mode toggle. Seeds per-party targets when turning on.
-- primary param matches the alliance-wide-setter convention (unused today but
-- reserved for future per-primary permission gating if we ever run multiple
-- primaries in the same zone).
function bots.set_multi_engage_mode(primary, on)
    if bots.alliance == nil then return end
    local was = bots.alliance.multiEngageMode and true or false
    local now = on and true or false
    bots.alliance.multiEngageMode = now
    if now and not was then
        bots.seed_party_targets_from_alliance()
    elseif not now and was then
        -- Clearing per-party state when reverting to single-engage keeps
        -- the alliance state tidy; get_current_mob_target now ignores
        -- partyAssistTargetId anyway.
        bots.alliance.partyAssistTargetId = { 0, 0, 0 }
    end
end

-----------------------------------
-- Multi-engagement (#173) party-slot resolver.
--
-- Groups alliance members by their engine getPartyLeader(). Party 1 is
-- whichever engine-party contains the primary (alliance.mainCharId).
-- Parties 2 and 3 are the other two sub-parties, sorted by their leader's
-- charId ascending — deterministic and stable across ticks.
--
-- Returns 1/2/3 on success. Returns 1 as a safe fallback if the bot
-- couldn't be placed (e.g., alliance not yet formed, or bot outside the
-- alliance topology). Returning 1 vs nil keeps callers simple — every
-- resolvable path lands in a valid partyAssistTargetId slot.
--
-- Cost: iterates alliance members + does 1-3 leader-charId sorts. Cheap.
-- No cache; called only from get_current_mob_target which is per-tick
-- per-bot but the whole function is O(alliance_size) ~= 18.
-----------------------------------
function bots.get_party_slot(bot)
    if bot == nil or bot.getAlliance == nil then return 1 end
    local A = bots.alliance
    if A == nil then return 1 end

    local myLeader = bot.getPartyLeader and bot:getPartyLeader() or nil
    if myLeader == nil then return 1 end
    local myLeaderId = myLeader:getID()

    -- Walk alliance, group unique party leader IDs.
    local leaderIds = {}     -- set of leader charIds
    local seen = {}
    local alliance = bot:getAlliance() or {}
    for _, member in ipairs(alliance) do
        if member and member.getPartyLeader then
            local ml = member:getPartyLeader()
            if ml then
                local mid = ml:getID()
                if not seen[mid] then
                    seen[mid] = true
                    table.insert(leaderIds, mid)
                end
            end
        end
    end

    -- Determine party 1 = primary's party's leader.
    -- Fall back to alliance-leader charId if we can't resolve primary's party.
    local primaryLeaderId = nil
    local primary = A.mainCharId and GetPlayerByID(A.mainCharId) or nil
    if primary and primary.getPartyLeader then
        local pl = primary:getPartyLeader()
        if pl then primaryLeaderId = pl:getID() end
    end

    if primaryLeaderId == nil then
        -- No primary resolvable — use lowest leader charId as party 1 to keep
        -- ordering stable even without a primary anchor.
        table.sort(leaderIds)
        primaryLeaderId = leaderIds[1]
    end

    -- Build final ordering: primary's party first, then others ascending.
    local ordered = { primaryLeaderId }
    local others = {}
    for _, lid in ipairs(leaderIds) do
        if lid ~= primaryLeaderId then table.insert(others, lid) end
    end
    table.sort(others)
    for _, lid in ipairs(others) do table.insert(ordered, lid) end

    -- Find my leader's slot.
    for slot, lid in ipairs(ordered) do
        if lid == myLeaderId then return slot end
    end
    return 1  -- safe fallback
end

-----------------------------------
-- Resolve the mob this bot should currently be fighting.
--
-- Legacy path (multiEngageMode = false): everyone in the alliance targets
-- the same allianceTarget mob.
--
-- Multi-engage path (multiEngageMode = true): dispatches per bot's party
-- slot (1/2/3) → alliance.partyAssistTargetId[slot]. If the caller doesn't
-- pass `bot` under multi-engage mode, we fall back to the legacy alliance
-- target (safest — no bot-context = no way to know which party).
-----------------------------------
function bots.get_current_mob_target(bot)
    local A = bots.alliance
    if A and A.multiEngageMode and bot ~= nil then
        local slot = bots.get_party_slot(bot)
        local id = (A.partyAssistTargetId and A.partyAssistTargetId[slot]) or 0
        if id == 0 then return nil end
        return GetEntityByID(id)
    end
    local id = bots.get_alliance_target_id()
    if id == 0 then return nil end
    return GetEntityByID(id)
end

function bots.runCombatTick(bot, state)
    -- Side-effect: caches state.parentCharId for movement tick + role modules.
    bots.get_primary_for_bot(bot, state)

    -- Player-issued one-shot command (ai_command.dispatch queued from primary's
    -- /bot chat command). If the bot has a pendingCommand AND it fires this
    -- tick, role tick is skipped — the bot is now in a new action state from
    -- the manual command. If pending but the bot is mid-action, try_fire
    -- returns false and the role tick runs normally; the command stays queued.
    if xi.singleplayer.bots.ai_command and xi.singleplayer.bots.ai_command.try_fire then
        if xi.singleplayer.bots.ai_command.try_fire(bot, state) then
            return
        end
    end

    -- Puller AI overlay — runs on top of normal role tick for the designated
    -- puller bot. State machine in ai_puller drives scout/walk/pull/return.
    -- The puller's role tick (THF, BRD, etc.) still runs once we fall through.
    if bots.alliance ~= nil and (bots.alliance.pullerCharId or 0) == bot:getID()
       and xi.singleplayer.bots.ai_puller and xi.singleplayer.bots.ai_puller.tick
    then
        xi.singleplayer.bots.ai_puller.tick(bot)
    end

    local mod = roleModule(state.role)
    if mod == nil or mod.tick == nil then return end

    -- First-tick on_load: the primary uses opts.activate=false at spawn so
    -- on_load doesn't fire until they opt in via botMode. Reaching here
    -- means runCombatTick is running, so the bot is opted in — fire on_load
    -- once if it hasn't been yet. on_load_fired is a per-bot marker on the
    -- consolidated scratch (post-#221 there are no module-local state
    -- tables to probe for presence anymore).
    if not state.on_load_fired then
        state.on_load_fired = true
        if mod.on_load ~= nil then mod.on_load(bot) end
    end

    mod.tick(bot)
end

-----------------------------------
-- State snapshot — serialize the per-primary "alliance + per-bot config
-- state" into JSON and drop it on the loopback HTTP cache. Published
-- from onBotTick (~400ms cadence per primary); the AutoBots addon fetches
-- via GET /bot-state?for=<name> on unlock to re-seed its UI after a
-- reload (formations, thresholds, puller config, per-bot toggles).
--
-- Migrated off the legacy S2C 0x1A5 BOT_STATE_SNAPSHOT packet — that
-- packet was at the FFXI wire ceiling of 504 bytes and couldn't fit the
-- per-bot fields the Status tab needs (sataMode / healScope / role / ...).
-- HTTP has no length cap and evolves with addon UI growth.
--
-- Server-side build is keyed on `xi.singleplayer.bots.alliance`:
--   * Alliance-wide fields read from alliance.*
--   * Primary's bot mode read from CCharEntity::getBotMode
--   * Per-bot table walks alliance.bot[charId] and includes role config
--   * Role-AI policy walks alliance.rolePolicy (see ai_item.lua)
--
-- Keep the schema additive: addons treat unknown keys as ignorable and
-- missing keys fall back to local defaults.
-----------------------------------
local snapshot_json = require('modules/singleplayer/lib/json')

-- Resolve a charId to its in-zone name, or '' if the bot isn't currently
-- reachable. Used to surface the puller's name (alliance.pullerCharId is a
-- numeric ID; the UI wants a string to drive the dropdown selection).
-- Bots are CCharEntity — must use GetPlayerByID, not GetMobByID (which
-- indexes mob-side entity IDs and warn-spams every tick otherwise).
local function snapshot_name_for_char_id(charId)
    if not charId or charId == 0 then return '' end
    local ent = GetPlayerByID and GetPlayerByID(charId)
    if ent == nil then return '' end
    return ent:getName() or ''
end

-- Pull primary's m_botMode if available. The binding is exposed as
-- `:getBotMode()` on CCharEntity (returns the numeric mode 0..3). Wrapped
-- in pcall because the binding is recent and not every fork branch will
-- have it.
local function snapshot_read_primary_bot_mode(primary)
    if primary == nil or not primary.getBotMode then return 2 end -- default Full
    local ok, mode = pcall(function() return primary:getBotMode() end)
    if not ok or type(mode) ~= 'number' then return 2 end
    return mode
end

-- Alliance headless botMode. Sample from the first owned headless — they
-- all share the same mode after SET_ALLIANCE_MODE's setBotModeForOwnedBots
-- broadcast. Default 2 (Full) if the alliance is empty. Used by the addon
-- QM to pick Start/Stop labels for the collapsed Actions and Movement
-- buttons.
local function snapshot_read_alliance_bot_mode(A)
    if A == nil or type(A.headlessCharIds) ~= 'table' then return 2 end
    for _, charId in ipairs(A.headlessCharIds) do
        local bot = GetPlayerByID(charId)
        if bot ~= nil and bot.getBotMode then
            local ok, mode = pcall(function() return bot:getBotMode() end)
            if ok and type(mode) == 'number' then return mode end
        end
    end
    return 2
end

-- Normalize a trust display name for equality comparison. Matches the
-- transform bots_spawn.resolve_trust_spell uses to walk config JSON names
-- ("Yoran-Oran (UC)") to spell-enum keys (YORAN_ORAN_UC): strip parens,
-- collapse space/dash runs to underscore, uppercase. Comparing normalized
-- forms lets us match the JSON trust name against the actual in-world
-- getName() without hand-mapping every trust's canonical spelling.
local function normalize_trust_name(name)
    if name == nil or name == '' then return '' end
    return (name:gsub('[%(%)]', ''):gsub('[%s%-]+', '_')):upper()
end

-- Count of trust names in the active alliance config that aren't currently
-- in the primary's alliance. Zero => everyone's summoned => Quick Menu
-- Summon Trusts dims. We rebuild the byName lookup here rather than
-- reusing bots_spawn.summon_trusts_for_alliance's flow: this pass runs
-- every ~400ms and doesn't need the per-party leader routing summon needs.
local function snapshot_read_trusts_needed(primary, A)
    if primary == nil or A == nil or type(A.parties) ~= 'table' or #A.parties == 0 then
        return 0
    end
    local haveByNorm = {}
    if primary.getName then
        haveByNorm[normalize_trust_name(primary:getName() or '')] = true
    end
    for _, member in ipairs(primary:getAlliance() or {}) do
        if member and member.getName then
            haveByNorm[normalize_trust_name(member:getName() or '')] = true
        end
    end
    local needed = 0
    for _, party in ipairs(A.parties) do
        if type(party.trusts) == 'table' then
            for _, trustName in ipairs(party.trusts) do
                if not haveByNorm[normalize_trust_name(trustName)] then
                    needed = needed + 1
                end
            end
        end
    end
    return needed
end

-- Count of members in the active food config who currently lack any food
-- status effect. Zero => everyone's fed => Quick Menu Use Food dims.
-- Returns nil when the server has no foodConfigName recorded yet (fresh
-- session before the user has clicked Use Food once) — client treats
-- nil as "unknown, don't gate."
--
-- Mirrors ai_item.use_food_from_config's targeting: only counts config
-- entries whose name resolves to the primary or an owned headless.
local function snapshot_read_food_needed(primary, A)
    if primary == nil or A == nil then return nil end
    local configName = A.foodConfigName or ''
    if configName == '' then return nil end
    local body = GetServerConfig and GetServerConfig('food', configName) or nil
    if body == nil then return nil end
    local ok, cfg = pcall(function() return snapshot_json:decode(body) end)
    if not ok or type(cfg) ~= 'table' then return nil end
    local primaryId = primary:getID()
    local needed = 0
    for charName, _ in pairs(cfg) do
        local target = GetPlayerByName and GetPlayerByName(charName) or nil
        local isOurs = target ~= nil and (
            target:getID() == primaryId or
            (target.isHeadless and target:isHeadless()
             and target.getParentCharId and target:getParentCharId() == primaryId)
        )
        if isOurs and target.hasStatusEffect
           and not target:hasStatusEffect(xi.effect.FOOD)
        then
            needed = needed + 1
        end
    end
    return needed
end

-- Map xi.singleplayer.bots.Role enum int → wire-stable string key. Mirrors
-- the role names the addon already uses on the Role AI tab and per-bot
-- card-side renderers (lowercase 'tank' / 'melee' / 'heal' / 'rdm' /
-- 'nuke'). Idle / Skillup map to nil so they don't show as a normal
-- combat role.
local function role_name_from_enum(roleInt)
    local R = bots.Role or {}
    if roleInt == R.Tank   then return 'tank'   end
    if roleInt == R.Melee  then return 'melee'  end
    if roleInt == R.Healer then return 'heal'   end
    if roleInt == R.Rdm    then return 'rdm'    end
    if roleInt == R.Nuker  then return 'nuke'   end
    if roleInt == R.Skillup then return 'skillup' end
    if roleInt == R.Brd    then return 'brd'    end
    if roleInt == R.Smn    then return 'smn'    end
    return nil
end

-- Per-bot snapshot row. Keyed by `name` so the addon doesn't need to know
-- charIds. mainJob/subJob come from the live CCharEntity when reachable;
-- the persistent per-bot toggle state comes from alliance.bot[charId].
-- Static catalogue of BRD song spell IDs that the song-roster UI lets the
-- user pin to a slot. Listed by family in priority order. The role_brd
-- module's SONG_FAMILIES is the source of truth for which families slot 0
-- (Minuet), slot 1 (Madrigal), slot 2 (Ballad-a), and slot 3 (Ballad-b)
-- pull from — this catalogue widens that to "any song spell" so the user
-- can override a slot with e.g. Knight's Minne (DEF) or Mage's Ballad in
-- a Minuet slot if their setup wants it.
local BRD_SONG_CATALOGUE = {
    -- Minuet (ATK)
    xi.magic.spell.VALOR_MINUET,
    xi.magic.spell.VALOR_MINUET_II,
    xi.magic.spell.VALOR_MINUET_III,
    xi.magic.spell.VALOR_MINUET_IV,
    xi.magic.spell.VALOR_MINUET_V,
    -- Madrigal (ACC)
    xi.magic.spell.SWORD_MADRIGAL,
    xi.magic.spell.BLADE_MADRIGAL,
    -- March (HASTE)
    xi.magic.spell.ADVANCING_MARCH,
    xi.magic.spell.VICTORY_MARCH,
    xi.magic.spell.HONOR_MARCH,
    -- Ballad (MP regen)
    xi.magic.spell.MAGES_BALLAD,
    xi.magic.spell.MAGES_BALLAD_II,
    xi.magic.spell.MAGES_BALLAD_III,
    -- Minne (DEF)
    xi.magic.spell.KNIGHTS_MINNE,
    xi.magic.spell.KNIGHTS_MINNE_II,
    xi.magic.spell.KNIGHTS_MINNE_III,
    xi.magic.spell.KNIGHTS_MINNE_IV,
    xi.magic.spell.KNIGHTS_MINNE_V,
    -- Paeon (HP regen) — fallback for early levels
    -- (paeon spell IDs not enumerated yet here — extend when needed)
}

-- SMN avatar dropdown catalogue (#220). Used by the per-bot Status card
-- avatar dropdown — filtered against the SMN's hasSpell() to populate
-- only avatars/spirits the char has actually learned. Spirits are
-- listed because the dropdown drives auto-summon even though spirits
-- have no BPs (bot just keeps the spirit alive when one's selected).
local SUMMON_SPELL_CATALOGUE = {
    xi.magic.spell.FIRE_SPIRIT,
    xi.magic.spell.ICE_SPIRIT,
    xi.magic.spell.AIR_SPIRIT,
    xi.magic.spell.EARTH_SPIRIT,
    xi.magic.spell.THUNDER_SPIRIT,
    xi.magic.spell.WATER_SPIRIT,
    xi.magic.spell.LIGHT_SPIRIT,
    xi.magic.spell.DARK_SPIRIT,
    xi.magic.spell.CARBUNCLE,
    xi.magic.spell.FENRIR,
    xi.magic.spell.IFRIT,
    xi.magic.spell.TITAN,
    xi.magic.spell.LEVIATHAN,
    xi.magic.spell.GARUDA,
    xi.magic.spell.SHIVA,
    xi.magic.spell.RAMUH,
    xi.magic.spell.DIABOLOS,
}

-- Per-bot snapshot row. Keyed by `name` so the addon doesn't need to know
-- charIds. mainJob/subJob come from the live CCharEntity when reachable;
-- the persistent per-bot toggle state comes from alliance.bot[charId].
local function build_bot_snapshot_row(charId, st)
    local row = {
        name           = '',
        role           = role_name_from_enum(st.role),
        sataMode       = st.sataMode       or 'combined',
        healScope      = st.healScope      or 'party',
        healMode       = st.heal_override == 'force_on',
        addControlMode = st.addControlMode or 'provoke',
        thfRaDelay     = st.thfRaDelay     or 15,
        -- Casual-nuke config (role_nuke / role_rdm cards). rotation: 1..6, or
        -- 0 = All; mbMode: 'include' | 'exclude'.
        casualNukeRotation = st.casualNukeRotation or 3,
        casualNukeMbMode   = st.casualNukeMbMode   or 'include',
        -- Song roster override (0 = auto for that slot). Always 4 entries
        -- for wire-format stability even if the bot isn't a BRD.
        songRoster     = st.songRoster     or { 0, 0, 0, 0 },
        -- SMN avatar dropdown selection (0 = unset → Carbuncle default).
        -- Always included for wire-format stability even on non-SMN bots.
        smnAvatarSpellId = st.smnAvatarSpellId or xi.magic.spell.CARBUNCLE,
    }
    -- Live name + jobs from the engine. Bots are CCharEntity, so GetPlayerByID
    -- (= zoneutils::GetChar, a cross-zone charId lookup) resolves them in any
    -- loaded zone. Do NOT fall back to GetMobByID: it indexes TYPE_MOB|TYPE_PET
    -- by entity id, never returns a PC, warn-spams every tick on the miss, and
    -- could even return an unrelated mob that happens to share the id number.
    -- When the charId isn't a currently-live PC, row.name stays '' and the
    -- caller drops the row.
    local live = GetPlayerByID and GetPlayerByID(charId) or nil
    if live ~= nil then
        if live.getName    then row.name    = live:getName()    or '' end
        if live.getMainJob then row.mainJob = live:getMainJob() or 0  end
        if live.getSubJob  then row.subJob  = live:getSubJob()  or 0  end
        -- Known-songs list for the BRD song-roster dropdown population.
        -- Filter the catalogue to spells the bot has learned; the addon
        -- side adds an "Auto" sentinel entry (spell ID 0).
        if row.role == 'brd' and live.hasSpell then
            row.knownSongs = {}
            for _, spellId in ipairs(BRD_SONG_CATALOGUE) do
                if live:hasSpell(spellId) then
                    table.insert(row.knownSongs, spellId)
                end
            end
        end
        -- Known-summons list for the SMN avatar dropdown population.
        -- Same shape as knownSongs — addon side adds an "Auto" option
        -- (Carbuncle default).
        if row.role == 'smn' and live.hasSpell then
            row.knownSummons = {}
            for _, spellId in ipairs(SUMMON_SPELL_CATALOGUE) do
                if live:hasSpell(spellId) then
                    table.insert(row.knownSummons, spellId)
                end
            end
        end
    end
    return row
end

-- Gather full alliance + per-bot state into a plain Lua table; caller
-- serializes to JSON. Keys mirror what the addon-side UI state vars
-- consume so the seeder doesn't translate field names.
local function build_state_snapshot(primary)
    local A = xi.singleplayer.bots.alliance or {}
    local running = (type(A.headlessCharIds) == 'table') and (#A.headlessCharIds > 0)

    local snap = {
        -- Envelope. Bump on backward-incompatible schema changes; the addon
        -- treats unknown v as "use my local defaults" so old/new mismatches
        -- degrade rather than crash.
        v       = 1,
        running = running,

        -- Active configs. configName / foodConfigName are set by spawn /
        -- use_food_config; empty string = nothing active.
        configName     = A.configName     or '',
        foodConfigName = A.foodConfigName or '',

        -- Alliance-wide mode toggles.
        primaryBotMode   = snapshot_read_primary_bot_mode(primary),
        -- Alliance headless botMode. Sampled from any owned headless — they
        -- all share the same mode after SET_ALLIANCE_MODE broadcasts. Default
        -- 2 = Full when no headless exists. Drives Quick Menu's collapsed
        -- Start/Stop Actions + Start/Stop Movement buttons.
        allianceBotMode  = snapshot_read_alliance_bot_mode(A),
        -- Current commanded alliance mob. 0 = idle (no fight). Drives Quick
        -- Menu's collapsed Attack/Finish button label.
        allianceTargetId = A.allianceTarget or 0,
        aggroMode        = A.aggroMode        or 'off',
        battleFormation  = A.battleFormation  or 'off',
        walkingFormation = A.walkingFormation or 'off',
        stunMode         = A.stunMode         or 'always',
        multiEngageMode  = A.multiEngageMode  or false,

        -- SC thresholds.
        scStartHP  = A.scStartHP  or 95,
        scStopHP   = A.scStopHP   or 10,
        scNoMoreHP = A.scNoMoreHP or 8,

        -- Puller config bundled under one key so the addon can read it
        -- atomically. nameFilter is the full array (no length cap at this
        -- layer — HTTP transport, no 499-byte ceiling to dodge).
        puller = {
            name       = snapshot_name_for_char_id(A.pullerCharId),
            range      = A.pullerRange  or 50,
            minCon     = A.pullerMinCon or 1,
            maxCon     = A.pullerMaxCon or 6,
            resumeMpp  = A.pullerResumeMpp or 60,
            nameFilter = (type(A.pullerNameFilter) == 'table') and A.pullerNameFilter or {},
            paused     = (A.pullerPaused == nil) or (A.pullerPaused and true or false),
        },

        -- Camp anchor (formation walking-mode anchor point) — nil-able. Addon
        -- renders the camp-set/camp-clear UI off this presence.
        campAnchor = (type(A.campAnchor) == 'table') and { x = A.campAnchor.x, z = A.campAnchor.z } or nil,

        -- Quick Menu button dim state. Server does the comparison because it
        -- has authoritative party state and can decode food/alliance configs
        -- reliably; client-side name matching against party slots proved
        -- fragile (display-name vs config-name variance).
        --   trustsNeeded  : trust names in the active alliance config not
        --                   present in the alliance; 0 => Summon Trusts dims.
        --   foodNeeded    : food-config members lacking any FOOD status;
        --                   0 => Use Food dims. nil => no active food config
        --                   known server-side; client keeps button live.
        trustsNeeded = snapshot_read_trusts_needed(primary, A),
        foodNeeded   = snapshot_read_food_needed(primary, A),

        -- Role-AI policy (item-usage decisions per role × type). Flattened
        -- via ai_item.role_ai_snapshot() which integer-indexes role keys
        -- and mode values — matches the addon-side role_ai_tab.apply_snapshot
        -- contract. Empty when ai_item isn't loaded yet.
        rolePolicy = (xi.singleplayer.bots.ai_item and xi.singleplayer.bots.ai_item.role_ai_snapshot)
                       and xi.singleplayer.bots.ai_item.role_ai_snapshot() or {},

        -- Per-bot rows. Indexed array so the addon can iterate in stable
        -- order; lookup by name is the addon's responsibility (single hash
        -- build on receipt).
        bots = {},
    }

    -- Walk every bot in the alliance scratch. The order is whatever pairs()
    -- yields — the addon sorts client-side if it needs deterministic UI
    -- order. Skip rows whose live name couldn't be resolved (sub-tick
    -- spawn races, primary not in same zone, etc.) — addons key on name
    -- so a nameless row is unaddressable.
    if type(A.bot) == 'table' then
        for charId, st in pairs(A.bot) do
            local row = build_bot_snapshot_row(charId, st)
            if row.name ~= '' then
                snap.bots[#snap.bots + 1] = row
            end
        end
    end

    return snap
end

-- Build + serialize + publish to the C++ bot-state cache. Called from
-- onBotTick once per primary per tick (~400ms). HTTP handler reads from
-- the cache when the addon hits GET /bot-state?for=<name>.
-- pcall around encode + publish so a runtime error here doesn't strand
-- the tick chain.
function bots.publish_state_snapshot(primary)
    if primary == nil then return end
    if not primary.publishBotState then return end
    local ok, body = pcall(function()
        return snapshot_json:encode(build_state_snapshot(primary))
    end)
    if not ok or type(body) ~= 'string' then
        printf(string.format('bots.publish_state_snapshot: encode failed: %s', tostring(body)))
        return
    end
    primary:publishBotState(body)
end

return m
