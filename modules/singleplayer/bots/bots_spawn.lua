-----------------------------------
-- Bot spawn module
--
-- Entry point for the reshaped 0x175 SPAWN_HEADLESS packet. The C++ handler
-- forwards the config name here; this module:
--   1) Loads the combined JSON at config/alliance/<name>.json
--   2) Walks the alliance array to derive the spawn list (every char whose
--      name doesn't match the primary's — primary already exists in-world).
--      The primary may appear ANYWHERE in the config (any pt's leader or
--      member); placement is name-driven, not position-driven.
--   3) Calls primary:spawnHeadless(name, idx) per spawn entry
--   4) Forms parties + (if >1) alliance via primary:formAllianceFromSpec
--   5) Queues per-party trust casts on each headless party leader whose
--      party carries a `trusts` list (primary's own party trusts, if any,
--      are intentionally left to the primary's own /trust controls)
--   6) Stashes the parsed config + per-bot role tags at xi.singleplayer.bots.bots_config for the
--      runtime AI modules to read
--
-- Configs are reloaded fresh on every spawn request — edits at runtime take
-- effect on the next spawn without server restart.
-----------------------------------
require('modules/module_utils')
local json = require('modules/singleplayer/lib/json')
-----------------------------------
local m = Module:new('bots_spawn')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.bots_spawn = xi.singleplayer.bots.bots_spawn or {}
local bots_spawn = xi.singleplayer.bots.bots_spawn

-- The parsed combined JSON config is materialized into the alliance
-- singleton (xi.singleplayer.bots.alliance) at spawn time by
-- apply_alliance: roleMap derivation, sc / solo / pool /
-- assistCharId / mainEntity / battle+walking formation. No per-primary
-- config table is retained — alliance.* is the single source of truth.

bots_spawn.config_dir = bots_spawn.config_dir or 'singleplayer/config/alliance/'

-----------------------------------
-- Load + parse a combined config file. Returns the table on success or nil.
-----------------------------------
function bots_spawn.load_config(configName)
    -- Read from the server's in-memory config cache instead of touching
    -- disk per spawn. Cache is kept fresh against external edits by the
    -- 2s watcher poll (configcache::poll). 2s staleness is acceptable —
    -- realistic edit → spawn workflow has more than enough latency.
    local body = GetServerConfig('alliance', configName)
    if body == nil then
        printf('bot_spawn: config not found: alliance/%s.json', configName)
        return nil
    end
    local ok, parsed = pcall(json.decode, json, body)
    if not ok or type(parsed) ~= 'table' then
        printf('bot_spawn: failed to parse alliance/%s.json: %s', configName, tostring(parsed))
        return nil
    end
    return parsed
end

-----------------------------------
-- Resolve trust name → spell ID. The xi.magic.spell enum stores trust spells
-- in SHOUTY_CASE_WITH_UNDERSCORES (e.g. SHANTOTTO=896, KARAHA_BARUHA=936,
-- IRON_EATER=917, YORAN_ORAN_UC=980). JSON configs use friendly names like
-- "Shantotto", "Karaha-Baruha", "Iron Eater", "Yoran-Oran (UC)". Convert by:
--   - stripping parentheses
--   - collapsing runs of spaces/hyphens into single underscores
--   - uppercasing
-----------------------------------
function bots_spawn.resolve_trust_spell(name)
    if name == nil or name == '' then return 0 end
    if xi.magic == nil or xi.magic.spell == nil then return 0 end
    local key = name
        :gsub('[%(%)]', '')
        :gsub('[%s%-]+', '_')
        :upper()
    return xi.magic.spell[key] or 0
end
local resolve_trust_spell = bots_spawn.resolve_trust_spell

-----------------------------------
-- Walk the alliance array and collect the spawn list — every char that
-- isn't the requesting primary. The primary can sit anywhere in the spec
-- (party-1 leader, party-1 member, even a sub-party leader), so the only
-- thing we filter on is the name match. Returns an ordered list of names.
-----------------------------------
local function derive_spawn_list(allianceArr, primaryName)
    local out = {}
    for _, party in ipairs(allianceArr) do
        if party.ptLeader and party.ptLeader ~= '' and party.ptLeader ~= primaryName then
            table.insert(out, party.ptLeader)
        end
        if party.members ~= nil then
            for _, member in ipairs(party.members) do
                if member ~= primaryName then
                    table.insert(out, member)
                end
            end
        end
    end
    return out
end

-- True if charName sits anywhere in the alliance spec (any pt leader or member).
-- The requesting primary MUST be in the config it spawns: derive_spawn_list
-- excludes the primary by name and formAllianceFromSpec only wires the names it
-- finds in the spec, so a primary that isn't listed spawns a full headless
-- alliance it is not a member of and is left solo -- with runtime state still
-- naming it mainCharId. We reject that up front instead.
local function config_includes(allianceArr, charName)
    for _, party in ipairs(allianceArr) do
        if party.ptLeader == charName then
            return true
        end
        if type(party.members) == 'table' then
            for _, member in ipairs(party.members) do
                if member == charName then
                    return true
                end
            end
        end
    end
    return false
end

-----------------------------------
-- Spawn every trust in `trustNames` on `leader` immediately (no cast time, no
-- MP cost, no animation) — mirrors the Summon Trusts button's path through
-- summon_trusts_for_alliance. summonTrustDirect still enforces engine-side
-- guards (caster knows the spell, trust not already in party, recast clear).
-----------------------------------
local function queue_trusts(leader, trustNames)
    if leader == nil or trustNames == nil then return end
    for _, name in ipairs(trustNames) do
        local spellId = resolve_trust_spell(name)
        if spellId > 0 then
            leader:summonTrustDirect(spellId)
        else
            printf('bot_spawn: unknown trust name: %s', tostring(name))
        end
    end
end

-----------------------------------
-- Derive the AI role for a character from the config. Precedence:
--   heal  → Healer
--   rdm   → Rdm
--   nuke  → Nuker
--   assist (the first entry, i.e. the assist target) → Tank (→ role_tank)
--   sc1/sc2 opener/closer OR in solo dict → Melee (→ role_melee)
--   else  → Idle (no role module; bot just stands around)
-- provoke / stun are NOT primary roles — they're sub-behaviors driven by
-- secondary state (role_tank consults config.provoke for provoke-rotation,
-- role_nuke consults config.stun for stun-rotation, etc.).
-----------------------------------
local function name_in_list(name, list)
    if type(list) ~= 'table' then return false end
    for _, entry in ipairs(list) do
        if entry == name then return true end
    end
    return false
end

local function name_in_sc_array(name, scArr)
    if type(scArr) ~= 'table' then return false end
    for _, p in ipairs(scArr) do
        if p.openName == name or p.closeName == name then return true end
    end
    return false
end

local function derive_role(name, cfg)
    if cfg == nil then return xi.singleplayer.bots.Role.Idle end
    local roles = cfg.roles or {}
    if name_in_list(name, roles.heal) then return xi.singleplayer.bots.Role.Healer end
    if name_in_list(name, roles.rdm)  then return xi.singleplayer.bots.Role.Rdm    end
    if name_in_list(name, roles.nuke) then return xi.singleplayer.bots.Role.Nuker  end
    -- roles.brd is the Bard support list. Song maintenance + /WHM cures.
    -- Drives role_brd.tick which positions between front/back for the
    -- 2+2 song roster (#220).
    if name_in_list(name, roles.brd)  then return xi.singleplayer.bots.Role.Brd    end
    -- roles.smn is the Summoner support/DPS list. Avatar + BP rotation +
    -- /WHM cures. Drives role_smn.tick (#220).
    if name_in_list(name, roles.smn)  then return xi.singleplayer.bots.Role.Smn    end
    -- roles.tank is a single-element list (the assist target). Tank may also
    -- appear in cfg.sc / cfg.solo for WS firing — that's orthogonal to role.
    if name_in_list(name, roles.tank) then return xi.singleplayer.bots.Role.Tank end
    -- roles.melee is the canonical melee list. SC participation and solo WS
    -- assignment are EXTRA data for melees and the tank — chars in cfg.sc[]
    -- or cfg.solo MUST be in roles.melee OR be the roles.tank entry; the
    -- validator enforces it.
    if name_in_list(name, roles.melee) then return xi.singleplayer.bots.Role.Melee end
    return xi.singleplayer.bots.Role.Idle
end

-----------------------------------
-- Semantic config validation. Catches user-authored mistakes before they
-- become silent runtime failures: every char name referenced under roles,
-- sc, or solo must exist in some party's members or be a ptLeader; every
-- WS name (cfg.sc[].openWS/closeWS, cfg.solo[name]) must resolve via
-- GetWeaponskillByName; every trust name must resolve via xi.magic.spell.
-- Returns a list of error strings; empty list means valid.
-----------------------------------
function bots_spawn.validate_config(cfg)
    local errs = {}
    if type(cfg) ~= 'table' then
        table.insert(errs, 'config is not a table')
        return errs
    end

    -- Build the canonical "all char names in the alliance" set from the
    -- alliance array's leaders + members. Anything referenced elsewhere must
    -- be in this set.
    local known = {}
    if type(cfg.alliance) == 'table' then
        for _, party in ipairs(cfg.alliance) do
            if type(party.ptLeader) == 'string' and party.ptLeader ~= '' then
                known[party.ptLeader] = true
            end
            if type(party.members) == 'table' then
                for _, n in ipairs(party.members) do
                    if type(n) == 'string' then known[n] = true end
                end
            end
        end
    else
        table.insert(errs, 'alliance is missing or not a table')
    end

    local function check_char(label, n)
        if type(n) ~= 'string' or n == '' then
            table.insert(errs, string.format('%s: empty or non-string name', label))
        elseif not known[n] then
            table.insert(errs, string.format('%s: unknown char "%s"', label, n))
        end
    end

    local function check_ws(label, n)
        if type(n) ~= 'string' or n == '' then
            table.insert(errs, string.format('%s: empty or non-string WS name', label))
            return
        end
        -- ai_ability.resolve_ws_id handles the display-name → snake_case
        -- fallback that GetWeaponskillByName lacks ('Seraph Blade' →
        -- 'seraph_blade'). Same helper the runtime use_ws path uses.
        local resolver = xi.singleplayer.bots.ability
                     and xi.singleplayer.bots.ability.resolve_ws_id
        if (resolver and resolver(n) or 0) == 0 then
            table.insert(errs, string.format('%s: unknown WS "%s"', label, n))
        end
    end

    local function check_trust(label, n)
        if type(n) ~= 'string' or n == '' then
            table.insert(errs, string.format('%s: empty or non-string trust name', label))
        elseif resolve_trust_spell(n) == 0 then
            table.insert(errs, string.format('%s: unknown trust "%s"', label, n))
        end
    end

    -- roles.* lists must reference known chars. roles.tank supports 1..3
    -- entries: tank[1] is the assist target (whom other bots follow /
    -- assist:getTarget on), tank[2..N] are additional tanks that share
    -- the main-mob Provoke / Flash rotation and NIN wheel/debuff split.
    if type(cfg.roles) == 'table' then
        for roleName, list in pairs(cfg.roles) do
            if type(list) == 'table' then
                for i, n in ipairs(list) do
                    check_char(string.format('roles.%s[%d]', roleName, i), n)
                end
                if roleName == 'tank' and #list == 0 then
                    table.insert(errs, 'roles.tank must have at least one entry')
                end
            end
        end
    end

    -- Every SC participant and every solo-WS char must be either in
    -- roles.melee or the roles.tank entry; otherwise their role would
    -- resolve to Idle and the WS / SC pair would silently never fire.
    local meleeList = (type(cfg.roles) == 'table' and cfg.roles.melee) or {}
    local tankList  = (type(cfg.roles) == 'table' and cfg.roles.tank)  or {}
    local function in_ws_eligible_list(n)
        if type(n) ~= 'string' or n == '' then return false end
        for _, m in ipairs(meleeList) do if m == n then return true end end
        for _, m in ipairs(tankList)  do if m == n then return true end end
        return false
    end
    local function check_ws_eligible(label, n)
        if type(n) ~= 'string' or n == '' then return end
        if not in_ws_eligible_list(n) then
            table.insert(errs, string.format('%s: "%s" must be in roles.melee or roles.tank', label, n))
        end
    end

    -- cfg.sc is an array of pair objects.
    if cfg.sc ~= nil then
        if type(cfg.sc) ~= 'table' then
            table.insert(errs, 'sc is not an array')
        else
            for i, pair in ipairs(cfg.sc) do
                check_char(string.format('sc[%d].openName',  i), pair.openName)
                check_char(string.format('sc[%d].closeName', i), pair.closeName)
                check_ws  (string.format('sc[%d].openWS',    i), pair.openWS)
                check_ws  (string.format('sc[%d].closeWS',   i), pair.closeWS)
                check_ws_eligible(string.format('sc[%d].openName',  i), pair.openName)
                check_ws_eligible(string.format('sc[%d].closeName', i), pair.closeName)
            end
        end
    end

    -- cfg.solo is { [charName] = wsName }.
    if cfg.solo ~= nil then
        if type(cfg.solo) ~= 'table' then
            table.insert(errs, 'solo is not a table')
        else
            for soloName, soloWs in pairs(cfg.solo) do
                check_char(string.format('solo["%s"]', soloName), soloName)
                check_ws  (string.format('solo["%s"]', soloName), soloWs)
                check_ws_eligible(string.format('solo["%s"]', soloName), soloName)
            end
        end
    end

    -- Trusts live under cfg.alliance[*].trusts.
    if type(cfg.alliance) == 'table' then
        for partyIdx, party in ipairs(cfg.alliance) do
            if type(party.trusts) == 'table' then
                for i, n in ipairs(party.trusts) do
                    check_trust(string.format('alliance[%d].trusts[%d]', partyIdx, i), n)
                end
            end
        end
    end

    return errs
end

-----------------------------------
-- Main entry point. Called by the C++ 0x175 handler via luautils::OnBotSpawnFromConfig.
-----------------------------------
function xi.singleplayer.bots.bots_spawn_from_config(primary, configName)
    if primary == nil or configName == nil or configName == '' then return end

    local cfg = bots_spawn.load_config(configName)
    if cfg == nil then
        primary:printToPlayer(string.format('bot_spawn: config "%s" not found.', configName))
        return
    end

    if type(cfg.alliance) ~= 'table' or #cfg.alliance == 0 then
        primary:printToPlayer(string.format('bot_spawn: config "%s" has no alliance array.', configName))
        return
    end

    if not config_includes(cfg.alliance, primary:getName()) then
        primary:printToPlayer(string.format('bot_spawn: config "%s" does not include you (%s); spawn a config you are a member of.', configName, primary:getName()))
        return
    end

    local errs = bots_spawn.validate_config(cfg)
    if #errs > 0 then
        primary:printToPlayer(string.format('bot_spawn: config "%s" has %d validation error(s):', configName, #errs))
        for _, e in ipairs(errs) do
            primary:printToPlayer('  ' .. e)
            printf('bot_spawn validation: %s', e)
        end
        return
    end

    local primaryId = primary:getID()

    -- Spawn every bot. derive_spawn_list filters by NAME match against the
    -- primary, so primary's own entry (wherever it sits in the config —
    -- any pt's leader or member) is excluded; everyone else gets spawned.
    local primaryName = primary:getName()
    local spawnList   = derive_spawn_list(cfg.alliance, primaryName)
    local spawnedBots = {}

    for idx, name in ipairs(spawnList) do
        local bot = primary:spawnHeadless(name, idx - 1)
        if bot ~= nil then
            spawnedBots[name] = bot
        end
    end

    -- Form parties + alliance using the C++ binding. Build the spec to match
    -- what formAllianceFromSpec expects: { { leader=..., members={...} }, ... }
    local allianceSpec = {}
    for _, party in ipairs(cfg.alliance) do
        local members = {}
        if party.members ~= nil then
            for _, n in ipairs(party.members) do
                table.insert(members, n)
            end
        end
        table.insert(allianceSpec, { leader = party.ptLeader, members = members })
    end

    local ok = primary:formAllianceFromSpec(allianceSpec)
    if not ok then
        primary:printToPlayer(string.format('bot_spawn: party formation failed for "%s".', configName))
    end

    -- Queue trusts on each headless party leader whose pt carries a trusts
    -- list. spawnedBots is keyed by NAME and only holds entries we actually
    -- spawned this pass -- so a primary-led pt naturally falls through (the
    -- primary isn't in spawnedBots) without needing a position-based skip.
    -- (Previous `partyIdx > 1` guard silently dropped pt1 trusts whenever
    -- the primary was elsewhere in the config.)
    for _, party in ipairs(cfg.alliance) do
        if type(party.trusts) == 'table' and party.ptLeader then
            local leader = spawnedBots[party.ptLeader]
            if leader ~= nil then
                queue_trusts(leader, party.trusts)
            end
        end
    end

    -- Auto-assign AI roles. Each char's role is derived from cfg.roles +
    -- sc1/sc2/solo precedence. xi.singleplayer.bots.onSetRole flips the matching role
    -- module's active flag and fires on_load(bot). Without this step bots
    -- default to Idle and their tick is a no-op.
    --
    -- Headless bots: activate immediately (createHeadlessSession set their
    -- botMode=Full, so they tick from the next PostTick).
    --
    -- Primary: assign role but leave inactive — they keep full manual control
    -- until they opt in by flipping their botMode (via the addon UI). Once
    -- botMode != Off, runCombatTick auto-activates the pre-staged role on the
    -- first tick. The right role is already cached so opt-in is one click.
    for name, bot in pairs(spawnedBots) do
        xi.singleplayer.bots.onSetRole(bot, derive_role(name, cfg))
    end
    xi.singleplayer.bots.onSetRole(primary, derive_role(primaryName, cfg), { activate = false })

    -- Populate alliance-scope runtime state from the parsed config. Disk
    -- format is name-keyed (people read JSON); runtime is charId-keyed
    -- (Lua reads by entity). Conversion happens here at load so every
    -- consumer downstream can use IDs directly.
    xi.singleplayer.bots.alliance = xi.singleplayer.bots.alliance or {}
    local alliance = xi.singleplayer.bots.alliance
    alliance.mainCharId      = primaryId
    alliance.headlessCharIds = {}
    alliance.roleMap         = {}
    alliance.solo            = {}
    alliance.bot             = alliance.bot or {}

    -- Transient caches + formation state (was previously duplicated on the
    -- deleted xi.singleplayer.bots.primary table).
    alliance.mainEntity       = primary
    -- Active alliance config name (the disk JSON we spawned from). Read by
    -- bots.send_state_snapshot when the addon requests the state snapshot, so the
    -- AutoBots UI's "active config" indicator re-fills after /addon reload.
    -- Overwritten on each spawn; cleared on despawn-all.
    alliance.configName       = configName
    alliance.battleFormation  = alliance.battleFormation  or 'off'
    alliance.walkingFormation = alliance.walkingFormation or 'off'
    -- Replaces the old static singleplayer.HEADLESS_MOB_AGGRO setting (#XYZ):
    -- alliance-wide aggro mode, cascaded to each headless's m_aggroMode at
    -- spawn-finalize below and via the 0x176 SET_AGGRO_MODE handler. Default
    -- 'off' matches trust-like behavior (the prior setting's default).
    alliance.aggroMode        = alliance.aggroMode or 'off'
    alliance.campAnchor       = alliance.campAnchor

    -- Party / trust list captured for the resummon-all-trusts hook (0x176
    -- SUMMON_TRUSTS). Lightweight slice — only ptLeader+trusts are read by
    -- summon_trusts_for_alliance; full cfg.alliance is not retained.
    alliance.parties = {}
    for _, party in ipairs(cfg.alliance) do
        table.insert(alliance.parties, {
            ptLeader = party.ptLeader,
            trusts   = (type(party.trusts) == 'table') and party.trusts or {},
        })
    end

    for name, bot in pairs(spawnedBots) do
        local id = bot:getID()
        table.insert(alliance.headlessCharIds, id)
        alliance.roleMap[id] = derive_role(name, cfg)
        alliance.bot[id]     = alliance.bot[id] or {}
    end
    alliance.roleMap[primaryId] = derive_role(primaryName, cfg)
    alliance.bot[primaryId]     = alliance.bot[primaryId] or {}

    -- alliance.solo = { [charId] = wsName } — the canonical WS-assignment
    -- table for any bot that isn't in an SC pair. Tank may appear here too
    -- if cfg.solo lists them. ai_ability.get_ws walks alliance.solo first,
    -- then alliance.sc[] pairs.
    if type(cfg.solo) == 'table' then
        for soloName, soloWs in pairs(cfg.solo) do
            local bot = spawnedBots[soloName]
                or (primaryName == soloName and primary or nil)
            if bot ~= nil then
                alliance.solo[bot:getID()] = soloWs
            end
        end
    end
    -- alliance.assistCharId — runtime "who do other bots assist" cache. The
    -- tank IS the assist; we resolve cfg.roles.tank[1] to a charId here.
    alliance.assistCharId = 0
    if type(cfg.roles) == 'table' and type(cfg.roles.tank) == 'table' then
        local tankName = cfg.roles.tank[1]
        local tankBot  = spawnedBots[tankName]
            or (primaryName == tankName and primary or nil)
        if tankBot ~= nil then
            alliance.assistCharId = tankBot:getID()
        end
    end

    -- cfg.sc is an array of { openName, openWS, closeName, closeWS, priority? }.
    -- Resolve names to charIds at load so every downstream check is by id.
    alliance.sc = {}
    if type(cfg.sc) == 'table' then
        local function bot_by_name(n)
            return spawnedBots[n] or (primaryName == n and primary or nil)
        end
        for idx, p in ipairs(cfg.sc) do
            local openBot  = bot_by_name(p.openName)
            local closeBot = bot_by_name(p.closeName)
            if openBot and closeBot then
                table.insert(alliance.sc, {
                    openCharId  = openBot:getID(),
                    openName    = p.openName,
                    openWS      = p.openWS,
                    closeCharId = closeBot:getID(),
                    closeName   = p.closeName,
                    closeWS     = p.closeWS,
                    priority    = p.priority or idx,
                })
            else
                printf('bot_spawn: sc[%d] skipped - unresolved char (open=%s close=%s)',
                    idx, tostring(p.openName), tostring(p.closeName))
            end
        end
        table.sort(alliance.sc, function(a, b) return a.priority < b.priority end)
    end

    -- Build the candidate pools (provoke / stun / rdmSleep / blmSleep) from
    -- the spawned bots' jobs. Decisions consult these every tick.
    if xi.singleplayer.bots.pool and xi.singleplayer.bots.pool.compile_pools then
        xi.singleplayer.bots.pool.compile_pools(primary, spawnedBots)
    end

    -- Re-apply the alliance's current aggro mode to every freshly-spawned
    -- headless. Their m_aggroMode is fresh-zero in C++, so this cascade is
    -- what propagates a non-default ('full') choice across a respawn — and
    -- it's a cheap no-op when the alliance is in the default 'off' state.
    bots_spawn.set_alliance_aggro_mode(primary, alliance.aggroMode)

    -- Apply the bot's <gearlock> set once at spawn finalize. equip_gearlock
    -- both equips the real items (so stats apply) AND pins the visual via
    -- applyStyleLock so other clients always see the user's intended "park"
    -- look regardless of mid-fight gear swaps. No-op when a bot's XML has
    -- no <gearlock> section. Despawn fires the same call (bots_listeners)
    -- so the saved equipment matches the locked look the user just saw.
    if xi.singleplayer.bots.ai_equip_swap
       and xi.singleplayer.bots.ai_equip_swap.equip_gearlock
    then
        for _, bot in pairs(spawnedBots) do
            if bot and bot.isHeadless and bot:isHeadless() then
                xi.singleplayer.bots.ai_equip_swap.equip_gearlock(bot)
            end
        end
    end

    -- Force-push the Status tab snapshot immediately so the autobots addon
    -- fills in within a tick instead of waiting up to PUSH_INTERVAL_MS
    -- (~2s) for the first scheduled push to fire. Without this the user
    -- sees "No headless bots in alliance" briefly even after assembly is
    -- complete and bots are ticking — old behavior was up to ~9s.
    if xi.singleplayer.bots.bots_status
       and xi.singleplayer.bots.bots_status.force_push
    then
        xi.singleplayer.bots.bots_status.force_push(primary)
    end

    printf('bot_spawn: spawned %d bots for primary %s using config "%s"',
        #spawnList, primaryName, configName)
end

-----------------------------------
-- #230 — diff-based "Update Alliance" path.
--
-- Replaces the despawn-everyone-then-respawn flow with a 3-way diff:
--   DROP         = was in old, not in new → destroyAsHeadless
--   ADD          = in new, not in old → spawnHeadless + party placement
--   KEEP_RESHAPE = in both, party leader changed → partyRemoveMember + partyAddMember
--   KEEP_STATIC  = in both, same party → untouched (role may flip via onSetRole)
--
-- Falls back to the full-rebuild path (bots_spawn_from_config) on:
--   * config load / validation failure
--   * any alliance member having hate (refuses the update entirely)
--   * primary's own party assignment changes between old and new configs
--   * party-count change (1pt ↔ 2pt ↔ 3pt) where falling through is safer
--     than half-applied alliance composition reshape; engine bindings exist
--     (attachToAlliance / detachFromAlliance) but the full path is well-trod
--
-- Per-bot scratch is wiped for ALL bots (KEEP, ADD, primary) and rebuilt
-- fresh, per user spec — config changes are too structural to safely
-- preserve cooldown timers / SC pair indices / pending commands.
-----------------------------------

-- Map current-state name → leader name of the party that name is in.
-- Walks alliance.headlessCharIds + primary; resolves each entity's PParty
-- leader by name. Bots whose live entity can't be resolved (zone race,
-- offline session) are dropped from the map — they get caught as DROP
-- and re-spawn into the new config without surprise side effects.
local function build_old_party_map(primary)
    local out = {}
    local A   = xi.singleplayer.bots.alliance or {}
    local function record(ent)
        if ent == nil or ent.getName == nil then return end
        local name = ent:getName()
        if name == nil or name == '' then return end
        local leader = ent.getPartyLeader and ent:getPartyLeader() or nil
        local leaderName = (leader and leader.getName) and leader:getName() or name
        out[name] = leaderName
    end
    record(primary)
    if type(A.headlessCharIds) == 'table' then
        for _, charId in ipairs(A.headlessCharIds) do
            record(GetPlayerByID(charId))
        end
    end
    return out
end

-- Map new-config name → leader name. Each cfg.alliance entry contributes
-- the leader (mapped to itself) and every member (mapped to the leader).
local function build_new_party_map(cfg)
    local out = {}
    for _, party in ipairs(cfg.alliance) do
        if party.ptLeader and party.ptLeader ~= '' then
            out[party.ptLeader] = party.ptLeader
            if type(party.members) == 'table' then
                for _, member in ipairs(party.members) do
                    if member and member ~= '' then
                        out[member] = party.ptLeader
                    end
                end
            end
        end
    end
    return out
end

local function any_has_hate(primary)
    local function f(ent)
        if ent == nil or ent.getNotorietyList == nil then return false end
        local nl = ent:getNotorietyList() or {}
        return #nl > 0
    end
    if f(primary) then return primary:getName() end
    local A = xi.singleplayer.bots.alliance or {}
    if type(A.headlessCharIds) == 'table' then
        for _, id in ipairs(A.headlessCharIds) do
            local b = GetPlayerByID(id)
            if f(b) then return b:getName() end
        end
    end
    return nil
end

-- Resolve a name to its current live entity. Walks primary + alliance
-- headlessCharIds. Returns nil if not found.
local function find_entity_by_name(primary, name)
    if primary ~= nil and primary:getName() == name then return primary end
    local A = xi.singleplayer.bots.alliance or {}
    if type(A.headlessCharIds) == 'table' then
        for _, id in ipairs(A.headlessCharIds) do
            local b = GetPlayerByID(id)
            if b ~= nil and b:getName() == name then return b end
        end
    end
    return nil
end

function bots_spawn.update_alliance_diff(primary, configName)
    if primary == nil or configName == nil or configName == '' then return end
    local primaryName = primary:getName()
    local primaryId   = primary:getID()

    -- 1. Load + validate the new config. Any failure falls through to the
    --    full-rebuild path so the user gets a working alliance even when
    --    they hand us garbage.
    local cfg = bots_spawn.load_config(configName)
    if cfg == nil then
        primary:printToPlayer(string.format('update_alliance: config "%s" not found.', configName))
        return
    end
    if type(cfg.alliance) ~= 'table' or #cfg.alliance == 0 then
        primary:printToPlayer(string.format('update_alliance: config "%s" has no alliance array.', configName))
        return
    end
    local errs = bots_spawn.validate_config(cfg)
    if #errs > 0 then
        primary:printToPlayer(string.format('update_alliance: config "%s" has %d validation error(s):', configName, #errs))
        for _, e in ipairs(errs) do
            primary:printToPlayer('  ' .. e)
            printf('update_alliance validation: %s', e)
        end
        return
    end

    -- 2. Hate gate. Refuse if anyone is engaged — half-applying a reshape
    --    mid-fight produces silent weirdness (notoriety pointing at no-
    --    longer-present bots, claim re-assignment, etc.).
    local hate_name = any_has_hate(primary)
    if hate_name ~= nil then
        primary:printToPlayer(string.format(
            'update_alliance: %s has hate — disengage and try again.', hate_name))
        return
    end

    -- 3. Build old / new maps and compute partitions by name set.
    local old_map = build_old_party_map(primary)
    local new_map = build_new_party_map(cfg)

    -- Helper: tear down everyone before calling the full rebuild path.
    -- bots_spawn_from_config doesn't despawn on its own (the C++ side used
    -- to do that before Lua was called); since we're invoking from Lua now
    -- we have to do it ourselves on the fallback paths.
    local function fallback_full_rebuild(reason)
        printf('update_alliance: full rebuild — %s', reason)
        local A = xi.singleplayer.bots.alliance or {}
        if type(A.headlessCharIds) == 'table' then
            -- Copy the list first; destroyAsHeadless mutates the session
            -- container and indirectly the alliance state.
            local to_destroy = {}
            for _, id in ipairs(A.headlessCharIds) do table.insert(to_destroy, id) end
            for _, id in ipairs(to_destroy) do
                local b = GetPlayerByID(id)
                if b ~= nil and b.destroyAsHeadless then b:destroyAsHeadless() end
            end
        end
        return xi.singleplayer.bots.bots_spawn_from_config(primary, configName)
    end

    -- Composition check: party count change falls back to the full path.
    -- The diff handles ADD/DROP within an existing N-party shape; going
    -- 1pt→2pt or 2pt→3pt would need to call attachToAlliance for the new
    -- party's leader at the right moment, and detachFromAlliance + cleanup
    -- in the shrink direction. Until each individual path is stress-tested
    -- separately, fall back here keeps the button reliable.
    local A = xi.singleplayer.bots.alliance or {}
    local old_party_count = (type(A.parties) == 'table') and #A.parties or 0
    if old_party_count ~= #cfg.alliance then
        return fallback_full_rebuild(string.format('party count %d → %d',
            old_party_count, #cfg.alliance))
    end

    -- Primary's party assignment changing is a structural rewrite — falling
    -- back is cheaper than handling primary-as-pt-leader vs primary-as-member
    -- transitions in-place.
    if old_map[primaryName] ~= new_map[primaryName] then
        return fallback_full_rebuild(string.format(
            'primary "%s" pt assignment changed (%s → %s)',
            primaryName, tostring(old_map[primaryName]), tostring(new_map[primaryName])))
    end

    -- Partition names.
    local drop_names, add_names, keep_names, reshape_names = {}, {}, {}, {}
    for name in pairs(old_map) do
        if new_map[name] == nil then
            if name ~= primaryName then  -- never drop primary
                table.insert(drop_names, name)
            end
        else
            table.insert(keep_names, name)
            if old_map[name] ~= new_map[name] then
                table.insert(reshape_names, name)
            end
        end
    end
    for name in pairs(new_map) do
        if old_map[name] == nil then
            table.insert(add_names, name)
        end
    end

    -- 4. Per-party room arithmetic — verify the diff fits before we mutate
    --    anything. For each party in the new config, count how many of its
    --    members will be present after the diff applies. Reject the whole
    --    update if any party would exceed 6.
    local per_party_target = {}  -- ptLeader → projected member count (incl. leader)
    for _, party in ipairs(cfg.alliance) do
        local n = 1  -- leader
        if type(party.members) == 'table' then n = n + #party.members end
        per_party_target[party.ptLeader] = n
        if n > 6 then
            primary:printToPlayer(string.format(
                'update_alliance: config "%s" pt "%s" has %d members (>6 cap).',
                configName, party.ptLeader, n))
            return
        end
    end

    -- 5. Apply DROP. Live-entity resolution first; can't iterate while
    --    destroying. Engine handles cascading party cleanup (empty party
    --    dissolves and detaches from alliance automatically).
    local drop_entities = {}
    for _, name in ipairs(drop_names) do
        local ent = find_entity_by_name(primary, name)
        if ent ~= nil then table.insert(drop_entities, ent) end
    end
    for _, ent in ipairs(drop_entities) do
        if ent.destroyAsHeadless then ent:destroyAsHeadless() end
    end

    -- 6. Apply KEEP_RESHAPE party moves.
    --    For each reshape, partyRemoveMember from current leader's party,
    --    then partyAddMember to the new leader's party. The leader entity
    --    for both ends must be alive at the moment of the call. Reshapes
    --    fire AFTER drops so a slot vacated by DROP is available to absorb
    --    a reshape into it.
    for _, name in ipairs(reshape_names) do
        local subject     = find_entity_by_name(primary, name)
        local old_leader  = find_entity_by_name(primary, old_map[name])
        local new_leader  = find_entity_by_name(primary, new_map[name])
        if subject and old_leader and new_leader then
            -- Remove first; the new leader's party room check (in
            -- partyAddMember) gates the add. If the add fails, the bot is
            -- now party-less — they'll be detected as "primary-orphaned"
            -- on the next pass; for v1 just log loudly so we can spot it.
            old_leader:partyRemoveMember(subject)
            new_leader:partyAddMember(subject)
        else
            printf('update_alliance: reshape %s skipped (subject=%s old_leader=%s new_leader=%s)',
                name, tostring(subject), tostring(old_leader), tostring(new_leader))
        end
    end

    -- 7. Apply ADD. Order matters: add NEW pt leaders first so subsequent
    --    members can join their pre-existing party. A new bot whose pt
    --    leader is a KEEP'd existing entity (common case) goes into the
    --    member branch directly.
    local add_leaders_present_in_old = {}  -- name → true; their pt leader exists already
    local add_new_leaders            = {}  -- name → true; this bot IS a new pt leader
    for _, name in ipairs(add_names) do
        if new_map[name] == name then
            add_new_leaders[name] = true
        else
            add_leaders_present_in_old[name] = true
        end
    end

    -- spawnHeadless takes a slot index; reuse the addon-default ordering
    -- by counting how many headless exist + the order we add.
    local A_now = xi.singleplayer.bots.alliance or {}
    local slot_base = (type(A_now.headlessCharIds) == 'table') and #A_now.headlessCharIds or 0
    local next_slot = slot_base
    local spawnedBots = {}  -- name → entity, includes both added leaders and added members

    -- 7a. Spawn brand-new pt leaders. Each forms a singleton party, then
    --     attaches to primary's alliance (which is guaranteed to exist by
    --     the time we get here since we required ≥1 KEEP).
    for name, _ in pairs(add_new_leaders) do
        local bot = primary:spawnHeadless(name, next_slot)
        next_slot = next_slot + 1
        if bot ~= nil then
            spawnedBots[name] = bot
            bot:formPartyAlone()
            bot:attachToAlliance(primary)
        else
            printf('update_alliance: ADD leader spawn failed for "%s"', name)
        end
    end

    -- 7b. Spawn pt members. Each joins their pt leader's party. Leader
    --     may be a KEEP (still alive) or a just-added new leader (in
    --     spawnedBots). Members of a brand-new pt come second so the
    --     leader's party already exists.
    for name, _ in pairs(add_leaders_present_in_old) do
        local bot = primary:spawnHeadless(name, next_slot)
        next_slot = next_slot + 1
        if bot ~= nil then
            spawnedBots[name] = bot
            local leader_name = new_map[name]
            local leader_ent  = spawnedBots[leader_name] or find_entity_by_name(primary, leader_name)
            if leader_ent ~= nil then
                leader_ent:partyAddMember(bot)
            else
                printf('update_alliance: ADD member "%s" — no leader entity for "%s"', name, leader_name)
            end
        else
            printf('update_alliance: ADD member spawn failed for "%s"', name)
        end
    end

    -- 8. Wipe + rebuild alliance.*. Per user spec, all per-bot scratch
    --    gets cleared on every update — KEEP bots get fresh scratch too,
    --    cleaner than trying to preserve cooldowns / SC pair indices /
    --    pending commands across config-shape changes.
    xi.singleplayer.bots.alliance = xi.singleplayer.bots.alliance or {}
    local alliance = xi.singleplayer.bots.alliance
    alliance.mainCharId      = primaryId
    alliance.mainEntity      = primary
    alliance.configName      = configName
    alliance.headlessCharIds = {}
    alliance.roleMap         = {}
    alliance.solo            = {}
    alliance.sc              = {}
    alliance.parties         = {}
    alliance.bot             = {}

    -- Build the full name → entity map for everyone in the new alliance:
    -- KEEP bots (resolved live), ADD bots (just spawned), plus primary.
    local all_bots_by_name = {}
    for _, name in ipairs(keep_names) do
        if name ~= primaryName then
            local ent = find_entity_by_name(primary, name)
            if ent ~= nil then all_bots_by_name[name] = ent end
        end
    end
    for name, bot in pairs(spawnedBots) do
        all_bots_by_name[name] = bot
    end

    -- Capture pt / trust slice for SUMMON_TRUSTS reuse.
    for _, party in ipairs(cfg.alliance) do
        table.insert(alliance.parties, {
            ptLeader = party.ptLeader,
            trusts   = (type(party.trusts) == 'table') and party.trusts or {},
        })
    end

    -- Per-bot scratch + roleMap.
    for name, bot in pairs(all_bots_by_name) do
        local id = bot:getID()
        table.insert(alliance.headlessCharIds, id)
        alliance.roleMap[id] = derive_role(name, cfg)
        alliance.bot[id]     = {}  -- fresh
    end
    alliance.roleMap[primaryId] = derive_role(primaryName, cfg)
    alliance.bot[primaryId]     = {}

    -- alliance.solo
    if type(cfg.solo) == 'table' then
        for soloName, soloWs in pairs(cfg.solo) do
            local bot = all_bots_by_name[soloName] or (primaryName == soloName and primary or nil)
            if bot ~= nil then alliance.solo[bot:getID()] = soloWs end
        end
    end

    -- alliance.assistCharId
    alliance.assistCharId = 0
    if type(cfg.roles) == 'table' and type(cfg.roles.tank) == 'table' then
        local tankName = cfg.roles.tank[1]
        local tankBot  = all_bots_by_name[tankName] or (primaryName == tankName and primary or nil)
        if tankBot ~= nil then alliance.assistCharId = tankBot:getID() end
    end

    -- alliance.sc
    if type(cfg.sc) == 'table' then
        local function bot_by_name(n)
            return all_bots_by_name[n] or (primaryName == n and primary or nil)
        end
        for idx, p in ipairs(cfg.sc) do
            local openBot  = bot_by_name(p.openName)
            local closeBot = bot_by_name(p.closeName)
            if openBot and closeBot then
                table.insert(alliance.sc, {
                    openCharId  = openBot:getID(),
                    openName    = p.openName,
                    openWS      = p.openWS,
                    closeCharId = closeBot:getID(),
                    closeName   = p.closeName,
                    closeWS     = p.closeWS,
                    priority    = p.priority or idx,
                })
            end
        end
        table.sort(alliance.sc, function(a, b) return a.priority < b.priority end)
    end

    -- 9. Re-role everyone. KEEP bots may have different roles in the new
    --    config; ADD bots need their role attached for the first time.
    for name, bot in pairs(all_bots_by_name) do
        xi.singleplayer.bots.onSetRole(bot, derive_role(name, cfg))
    end
    xi.singleplayer.bots.onSetRole(primary, derive_role(primaryName, cfg), { activate = false })

    -- 10. Re-summon trusts ONLY for parties that gained a brand-new leader.
    --     KEEP parties' trusts persisted across the update (their pt leader
    --     and the trust spawns were untouched).
    for _, party in ipairs(cfg.alliance) do
        if add_new_leaders[party.ptLeader] and type(party.trusts) == 'table' then
            local leader = spawnedBots[party.ptLeader]
            if leader ~= nil then queue_trusts(leader, party.trusts) end
        end
    end

    -- 11. Re-compile candidate pools (provoke / stun / rdmSleep / blmSleep)
    --     from the new alliance composition. Pools are role-gated + ability-
    --     gated; the rebuild reflects role changes from this update.
    if xi.singleplayer.bots.pool and xi.singleplayer.bots.pool.compile_pools then
        xi.singleplayer.bots.pool.compile_pools(primary, all_bots_by_name)
    end

    -- 12. Re-apply aggro mode + gearlock for fresh ADD bots.
    bots_spawn.set_alliance_aggro_mode(primary, alliance.aggroMode or 'off')
    if xi.singleplayer.bots.ai_equip_swap and xi.singleplayer.bots.ai_equip_swap.equip_gearlock then
        for _, bot in pairs(spawnedBots) do
            if bot and bot.isHeadless and bot:isHeadless() then
                xi.singleplayer.bots.ai_equip_swap.equip_gearlock(bot)
            end
        end
    end

    -- 13. Force-push the status snapshot so the addon UI reflects the new
    --     composition within a tick instead of waiting on the next scheduled
    --     push. publish_state_snapshot also fires on the next onBotTick;
    --     this just shortens the visible blank window.
    if xi.singleplayer.bots.bots_status and xi.singleplayer.bots.bots_status.force_push then
        xi.singleplayer.bots.bots_status.force_push(primary)
    end
    if xi.singleplayer.bots.publish_state_snapshot then
        xi.singleplayer.bots.publish_state_snapshot(primary)
    end

    printf('update_alliance_diff: cfg="%s" drop=%d add=%d keep=%d reshape=%d',
        configName, #drop_names, #add_names, #keep_names, #reshape_names)
    primary:printToPlayer(string.format(
        'Alliance updated: %d dropped, %d added, %d kept (%d moved between parties).',
        #drop_names, #add_names, #keep_names, #reshape_names))
end

-- ============================================================
-- Alliance-wide broadcast helpers (called from luautils on 0x176 dispatch).
-- Currently just the FINISH action — set the per-bot nukeUntilDead flag on
-- every headless owned by this primary that has a magic state. Bots without
-- magic state (tanks, melee SC, etc.) are silently no-op.
-- ============================================================
-- Re-summon every trust defined in the active alliance config. Each non-primary
-- party leader (and the primary for party 1) fires summonTrustDirect per trust
-- name in its party block. Direct spawn (no cast time) — but the binding still
-- enforces: caster has the spell, trust not already in party, magic recast
-- not active. Failed casts log a debug line and continue.
function bots_spawn.summon_trusts_for_alliance(primary)
    if primary == nil then return end
    local primaryId = primary:getID()
    local A = xi.singleplayer.bots.alliance
    if A == nil or type(A.parties) ~= 'table' or #A.parties == 0 then
        primary:printToPlayer('bot_spawn: no active alliance config to summon trusts from.')
        return
    end

    -- Build name → leader entity. Primary's own party (alliance[1]) is led by
    -- the primary; other parties are led by headless bots already linked to us.
    local byName = {}
    byName[primary:getName()] = primary
    for _, member in ipairs(primary:getAlliance() or {}) do
        if member.isHeadless and member:isHeadless()
           and member.getParentCharId and member:getParentCharId() == primaryId
        then
            byName[member:getName()] = member
        end
    end

    local errMsg = {
        [1] = 'no spell',
        [2] = 'already in party',
        [3] = 'recast active',
        [4] = 'spawn failed',
        [5] = 'wrong type',
    }

    local total, ok = 0, 0
    for _, party in ipairs(A.parties) do
        if type(party.trusts) == 'table' and party.ptLeader then
            local leader = byName[party.ptLeader]
            if leader == nil then
                printf(string.format('bots_spawn.summon_trusts: leader "%s" not found', tostring(party.ptLeader)))
            else
                for _, trustName in ipairs(party.trusts) do
                    local spellId = resolve_trust_spell(trustName)
                    if spellId == 0 then
                        printf(string.format('bots_spawn.summon_trusts: unknown trust name "%s"', tostring(trustName)))
                    else
                        total = total + 1
                        local rc = leader:summonTrustDirect(spellId)
                        if rc == 0 then
                            ok = ok + 1
                        else
                            printf(string.format('bots_spawn.summon_trusts: %s -> %s (%s)',
                                party.ptLeader, trustName, errMsg[rc] or tostring(rc)))
                        end
                    end
                end
            end
        end
    end

    printf(string.format('bots_spawn.summon_trusts_for_alliance: %d/%d for %s', ok, total, primary:getName()))
end

-- Grant SIGNET to the primary + every owned headless, matching the gate-
-- guard overseer path in scripts/globals/conquest.lua (overseerOnEventFinish,
-- option == 1). Each member uses their OWN nation/rank to compute duration
-- so the result is "as though they each talked to their own nation's
-- guard." Strips competing INFLUENCE-flagged effects first (sigil/sanction)
-- to match the same sequence the overseer script uses.
function bots_spawn.give_signet_alliance(primary)
    if primary == nil then return end
    local primaryId = primary:getID()
    local granted   = 0
    local function grant(member)
        if member == nil or member.getNation == nil or member.addStatusEffect == nil then return end
        local pNation  = member:getNation()
        local pRank    = (member.getRank and member:getRank(pNation)) or 1
        local duration = (pRank + GetNationRank(pNation) + 3) * 3600 * 10
        if member.delStatusEffectsByFlag then
            member:delStatusEffectsByFlag(xi.effectFlag.INFLUENCE, true)
        end
        member:addStatusEffect(xi.effect.SIGNET, { duration = duration, origin = member })
        granted = granted + 1
    end
    grant(primary)
    for _, member in ipairs(primary:getAlliance() or {}) do
        if member.isHeadless and member:isHeadless()
           and member.getParentCharId and member:getParentCharId() == primaryId
        then
            grant(member)
        end
    end
    printf(string.format('bots_spawn.give_signet_alliance: granted to %d member(s) for %s',
        granted, primary:getName()))
end

-- ============================================================
-- Alliance-wide headless mob-aggro toggle. Replaces the prior static
-- singleplayer.HEADLESS_MOB_AGGRO setting. Called from luautils::OnBotSetAggroMode
-- (addon UI → 0x176 SET_AGGRO_MODE → here) and from the spawn-finalize path so
-- newly-spawned bots inherit the current alliance choice.
--
-- `mode` is the numeric wire value (0=Off, 1=Full, 2=Engaged). String form
-- lives on alliance.aggroMode for UI / debug; the per-bot m_aggroMode (read by
-- shouldSkipMobAggro on the C++ side) is the source of truth for aggro
-- decisions. We push the numeric mode to each headless via the setAggroMode
-- binding so the field updates without a packet roundtrip.
-- ============================================================
local AGGRO_MODE_LABELS = { [0] = 'off', [1] = 'full', [2] = 'engaged' }

function bots_spawn.set_alliance_aggro_mode(primary, mode)
    if primary == nil then return end
    if type(mode) ~= 'number' then return end
    local label = AGGRO_MODE_LABELS[mode]
    if label == nil then return end

    local alliance = xi.singleplayer.bots.alliance or {}
    xi.singleplayer.bots.alliance = alliance
    alliance.aggroMode = label

    local primaryId = primary:getID()
    local pushed    = 0
    for _, member in ipairs(primary:getAlliance() or {}) do
        if member.isHeadless and member:isHeadless()
           and member.getParentCharId and member:getParentCharId() == primaryId
           and member.setAggroMode
        then
            member:setAggroMode(mode)
            pushed = pushed + 1
        end
    end
    printf(string.format('bots_spawn.set_alliance_aggro_mode: %s (mode=%d) pushed to %d headless for %s',
        label, mode, pushed, primary:getName()))
end

function bots_spawn.finish_alliance(primary)
    if primary == nil then return end
    local primaryId = primary:getID()
    local count     = 0
    -- Per-bot scratch moved to alliance.bot[charId] in #221. The old reference
    -- to xi.singleplayer.bots.magic.state[id] was reading a table that no
    -- longer exists, so finish_alliance has been silently writing into the
    -- void since the consolidation — Finish was a no-op for both mages and
    -- (with the wsUntilDead addition) melees. Fixed: write through ensure_bot
    -- so role_nuke / role_rdm / role_melee see the same state they read.
    for _, member in ipairs(primary:getAlliance() or {}) do
        if member.isHeadless and member:isHeadless()
           and member.getParentCharId and member:getParentCharId() == primaryId
        then
            local s = xi.singleplayer.bots.ensure_bot(member:getID())
            s.nukeUntilDead = true   -- mages: cast casual_nuke each tick until target dies
            s.wsUntilDead   = true   -- melees: bypass SC gating, fire WS at ≥1000 TP each tick
            count = count + 1
        end
    end
    printf(string.format('bots_spawn.finish_alliance: flagged %d bot(s) for %s (ws+nuke until target dies)',
        count, primary:getName()))
end

return m
