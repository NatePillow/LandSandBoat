require 'imguidef';

local autoutil = require('autoutil');
local json     = require('json');
local food_tab      = require('food_tab');
local alliance_tab  = require('alliance_tab');
local status_tab    = require('status_tab');
local autoskill_tab = require('autoskill_tab');
local role_ai_tab   = require('role_ai_tab');
local autobots_ui = {};

-- Active main-window tab. 'quick' is the default — a single-row strip of the
-- most-used actions kept minimal so it stays out of the way. 'setup' shows
-- the existing config + selection UI; 'status' shows the live status-effect
-- grid populated by the 0x191 PARTY_STATUS push.
local active_tab = 'quick';

local _src        = ((debug.getinfo(1, 'S').source or ''):match('^@(.+)') or ''):gsub('[\\/][\\/]+', '/');
local _script_dir = _src:match('^(.*[/\\])[^/\\]+') or '';
local ASHITA_ROOT = _script_dir:match('^(.*[/\\])[Aa]ddons[/\\]') or '';

local foodConfigNames        = {};
local allianceConfigNames    = {};
local selectedAllianceConfig = nil;
local selectedFoodConfig     = nil;
local partyConfig            = nil;
-- Server-authoritative "alliance is running" (headless spawned), seeded from
-- the /bot-state snapshot. partyConfig only exists once the user has started/
-- re-picked a config THIS session — after a login or /addon reload it's nil
-- even while the alliance is live server-side. This survives the reload and is
-- OR'd into the render-time `running` flag so buttons that only need "is it
-- running" aren't wrongly dimmed. Cleared in on_stop().
--
-- Stored as a FIELD on the autobots_ui table (not a bare module local) on
-- purpose: the giant render function already captures 60 upvalues, Lua 5.1's
-- hard cap, so a new bare local pushed it to 61 ("more than 60 upvalues").
-- Reusing the already-captured autobots_ui table adds no upvalue.
autobots_ui.server_running   = false;

-- Single source of truth for "the alliance is live" (headless spawned).
-- partyConfig only exists once a config was started/re-picked THIS session;
-- server_running (from the /bot-state snapshot) covers the post-login/reload
-- window before the body rehydrates. Both the render event (to build ctx.running)
-- and render_picker_section call this instead of duplicating the expression.
local function alliance_is_running()
    return (partyConfig ~= nil) or autobots_ui.server_running;
end

-- Normalize a trust/char name for matching — mirror of the server's
-- normalize_trust_name (bots.lua): strip parens, collapse spaces/hyphens to
-- underscore, uppercase. Lets config trust names match alliance member display
-- names despite punctuation/spacing differences.
local function normalize_trust_name(name)
    if name == nil or name == '' then return ''; end
    return (name:gsub('[%(%)]', ''):gsub('[%s%-]+', '_')):upper();
end

-- LIVE count of config trusts NOT currently present in the alliance. Reads the
-- active config body (partyConfig) for the wanted trust names and Ashita's
-- party manager (slots 0..17) for who's actually here, matching by normalized
-- name. Returns nil when we don't have the config body (e.g. right after a
-- reload before it re-fetches) so the caller can fall back to the server
-- snapshot. This is what makes Summon Trusts re-light the instant a trust dies.
local function trusts_missing_count()
    local cfg = partyConfig;
    if type(cfg) ~= 'table' or type(cfg.alliance) ~= 'table' then return nil; end
    local present = {};
    local party = AshitaCore:GetDataManager():GetParty();
    if party ~= nil then
        for slot = 0, 17 do
            local nm = party:GetMemberName(slot);
            if nm ~= nil and nm ~= '' then present[normalize_trust_name(nm)] = true; end
        end
    end
    local missing = 0;
    for _, p in ipairs(cfg.alliance) do
        for _, tname in ipairs(p.trusts or {}) do
            if tname ~= '' and not present[normalize_trust_name(tname)] then
                missing = missing + 1;
            end
        end
    end
    return missing;
end

-- Formation selection state. The server is authoritative (set via 0x176
-- SET_FORMATION subcommand); these track the addon's last-known choice so
-- the dropdown reflects what we just sent. Defaults match the server-side
-- spawn defaults in autospawn.lua (both 'off' — user opts in via dropdown).
local battleFormation        = 'off';
local walkingFormation       = 'off';
-- Battle options: 'spread' = tank front, melee arc behind mob, mage cluster
-- perpendicular. 'tight' = tank front, melee fan on both sides, mages just
-- behind mob. 'off' = disable formation, use pre-formation movement.
-- Walking options:
--   'off'    = bots literally do not move
--   'assist' = legacy ad-hoc assist-based follow (no formation override)
--   'camp'   = assist leashed at anchor
--   'column' = single column behind primary
--   'rows'   = rank-and-file rows behind primary (was 'role')
-- 'off'    = bots don't move during combat (mirrors walking 'off' semantic)
-- 'legacy' = pre-formation chase-to-mob behavior (was the old 'off')
-- 'spread' / 'tight' = slot-ring formations
-- 'AoE'    = tank + melees identical to 'tight'; mages self-position on
--            a 36-sample ring around the mob at ~17y, biased toward the
--            direction of primary. For AoE-heavy fights where mage
--            survival trumps DPS uptime.
-- 'BRDSpread' = tank front, melees behind the mob, mages on a front-side
--            corner (~12y) so they cluster with the tank's side. A Bard-
--            friendly shape; song-coverage payoff lands with task #278.
local BATTLE_FORMATIONS  = { 'off', 'legacy', 'spread', 'tight', 'AoE', 'BRDSpread' };
-- 'off'    = no movement when idle (frozen at current spot)
-- 'legacy' = pre-formation assist-trailing behavior (was 'assist')
-- 'camp' / 'column' / 'rows' = formation system shapes
local WALKING_FORMATIONS = { 'off', 'legacy', 'camp', 'column', 'rows' };
-- Headless mob-aggro mode. Replaces the old singleplayer.HEADLESS_MOB_AGGRO
-- static setting — runtime alliance state, set via 0x176 SET_AGGRO_MODE.
-- 'off'  = trust-like (mobs ignore headless for proximity aggro)
-- 'full' = hard mode (mobs aggro headless like real players)
-- Picker order is the wire enum: index 1 → mode byte 0, etc. Extending
-- (sight-only/sound-only/magic-only) means appending to this table and
-- updating shouldSkipMobAggro on the server.
local aggroMode          = 'off';
-- 'engaged' = invisible to proximity aggro/link until the headless has a
-- battle target, then vanilla rules kick in. Lets a group travel through a
-- zone freely but still get linked onto by family mobs once a fight starts.
local AGGRO_MODES        = { 'off', 'full', 'engaged' };
-- Alliance-wide stun behavior. Replaces the legacy
-- BOT_STUN_PERSIST_UNTIL_FIRED settings flag. 'always' (default) = legacy
-- true: stun window persists until a stunner fires; 'window' = legacy
-- false: window equals the mob's actual WS castTime. See ai_magic.lua
-- onMobSkillStart for the runtime semantics.
local stunMode           = 'always';
local STUN_MODES         = { 'always', 'window' };
-- Multi-engagement (#173). 'off' = whole alliance funnels onto one mob
-- (legacy). 'on' = each of the 3 alliance sub-parties fights its own mob
-- simultaneously (per-party target resolution + eventually per-party
-- puller + sliced stun/sleep pools).
local multiEngageMode    = 'off';
local MULTI_ENGAGE_MODES = { 'off', 'on' };
local configName             = nil;
-- Cached body for the currently-selected (but not necessarily running)
-- alliance config. Populated by the picker's on_select handler so the right
-- column's info panel can display the selected config's roles even when it
-- isn't the active one. Cleared on deselect.
local selectedAllianceBody   = nil;
local ui_open                = nil;
-- New-file popup state, keyed by category. Each entry: { name_input = <imgui var>, error = '' }
local new_popup              = {};
-- Single alliance-wide SC-pause toggle. The original sc1_paused/sc2_paused
-- pair maps 1:1 onto the two-SC era; alliance configs now allow an arbitrary
-- number of SC pairs (see ai_ability.lua pairCount). One button toggles
-- ALL pairs via send_bot_sc_pause(0, paused) - scId 0 is the server-side
-- "all pairs" sentinel.
local sc_all_paused  = false;
-- NM mode tri-state: 0 = Off, 1 = On, 2 = Auto. Default Off — opt-in to
-- consumable burn (ethers) and the lowered SC HP gate. Server is authoritative;
-- this is a local mirror used to render which radio is selected. Resync on
-- on_stop() is not necessary — mode is alliance-wide and orthogonal to spawn.
-- nm_mode UI toggle dropped — `is_nm` is now always engine-autodetect
-- (Dynamis OR battlefield OR mob:isNM()). Role AI "NM Only" modes consume
-- that signal directly; the manual force-on / force-off override was a
-- niche dev tool and force-off was fully redundant with Role AI = Off.
-- Sync Quests / Sync Missions in-flight tracking. Each holds the os.time()
-- timestamp of the click (nil if idle). Cleared on server ACK (TODO: wire
-- when the s2c reply lands) OR after SYNC_SAFETY_TIMEOUT_S as a fallback so
-- a dropped ACK doesn't permanently dim the button.
local SYNC_SAFETY_TIMEOUT_S    = 30;
-- Sync state for the three Quick Menu cascade buttons (quests / missions /
-- teleports). Bundled into one table so the render callback only consumes
-- one upvalue instead of three — autobots_ui.lua had crossed Lua 5.1's
-- 60-upvalue cap on the giant render() closure and needed slack.
local sync_started = { quests = nil, missions = nil, teleports = nil };
local function sync_in_flight(started_at)
    if started_at == nil then return false; end
    if os.time() - started_at >= SYNC_SAFETY_TIMEOUT_S then return false; end
    return true;
end
function autobots_ui.clear_sync_quests_in_flight()    sync_started.quests    = nil; end
function autobots_ui.clear_sync_missions_in_flight()  sync_started.missions  = nil; end
function autobots_ui.clear_sync_teleports_in_flight() sync_started.teleports = nil; end
-- Primary's own m_botMode (Off=0, CombatOnly=1, Full=2). Defaults to Off
-- mirroring CCharEntity::m_botMode's default. We track locally because no
-- server-side push exists today; if you bounce zones the radial resets
-- visually but the server-side state still holds whatever was last sent.
local primary_bot_mode = 0;
-- Alliance headless botMode + current commanded mob. Drive the QM's
-- collapsed Start/Stop Actions, Start/Stop Movement, and Attack/Finish
-- buttons. Ingested from the server snapshot.
local alliance_bot_mode  = 2;  -- default Full
local alliance_target_id = 0;  -- 0 = no fight

-- QM button dim state driven by server-side comparison. Server counts
-- config trusts not in alliance (.trusts) and food-config members lacking
-- any FOOD effect (.food). Zero => dim; nil => unknown (snapshot hasn't
-- landed yet OR no active food/alliance config to compare against), keep
-- the button live so we don't false-dim. Bundled into a table (rather
-- than two separate file-scope locals) so the render function stays
-- under Lua 5.1's 60-upvalue ceiling.
local qm_needed = { trusts = nil, food = nil };

-- Quick Menu click debounce. After a QM button is clicked, that button's
-- key gets locked for QM_CLICK_LOCKOUT_S seconds; clicks during the lock
-- are ignored AND the button is dimmed to signal the wait. Prevents
-- frantic-clicking-through-state-swaps (Stop Actions → immediately Start
-- Actions → immediately Stop Actions...) that would otherwise race the
-- server's ~400ms snapshot update. Per-key so a click on Actions doesn't
-- lock Movement or Attack/Finish.
local QM_CLICK_LOCKOUT_S = 1.5;
local qm_click_lock_until = {};
local function qm_click_ok(key)
    return (qm_click_lock_until[key] or 0) <= os.clock();
end
local function qm_click_arm(key)
    qm_click_lock_until[key] = os.clock() + QM_CLICK_LOCKOUT_S;
end

autobots_ui.in_instance = false;
local bf_checked = {};  -- name -> bool; persists across frames but pruned to current roster

local function join_names(tbl)
    if not tbl or #tbl == 0 then return '--'; end
    return table.concat(tbl, ', ');
end

-- True when the alliance config (a partyConfig-shaped table) has at least
-- one pair with an opener name set. Used to gate the single alliance-wide
-- "Pause Skillchains" button — there's no point in showing it as actionable
-- when no pair is wired up. Reads the server-canonical `sc` ARRAY (arbitrary
-- count); the legacy sc1/sc2 keys are gone.
local function has_any_sc(body)
    if type(body) ~= 'table' or type(body.sc) ~= 'table' then return false; end
    for _, p in ipairs(body.sc) do
        if type(p) == 'table' and type(p.openName) == 'string' and p.openName ~= '' then
            return true;
        end
    end
    return false;
end

-- Flatten an alliance partyConfig into a unique, sorted list of bot names.
-- Used by the puller picker - the dropdown shows every owned headless that
-- the running config has assigned to any role. Returns {} when partyConfig
-- is nil (no alliance up) so the caller can dim the combo cleanly.
local function collect_alliance_names(body)
    local out, seen = {}, {};
    if type(body) ~= 'table' then return out; end
    local function add(t)
        if type(t) ~= 'table' then return; end
        for _, n in ipairs(t) do
            if type(n) == 'string' and n ~= '' and not seen[n] then
                table.insert(out, n);
                seen[n]  = true;
            end
        end
    end
    add(body['tank']);
    add(body['heal']);
    add(body['nuke']);
    add(body['rdm']);
    add(body['melee']);
    table.sort(out);
    return out;
end

-- Collect every sc%d+ pair from a config body, sorted by numeric suffix.
-- Used by the right-column "Active Config Info" panel to render one row per
-- SC pair. Reads the server-canonical `sc` ARRAY (body.sc = { { priority,
-- openName, openWS, closeName, closeWS }, ... }) — NOT the legacy sc1/sc2
-- keys, which the server never read and which the editor now migrates away.
-- Reading sc%d+ keys was why this panel was always empty. Each returned entry
-- is { idx = N, body = { openName, openWS, closeName, closeWS } }.
local function collect_sc_pairs(body)
    local out = {};
    if type(body) ~= 'table' or type(body.sc) ~= 'table' then return out; end
    for i, p in ipairs(body.sc) do
        if type(p) == 'table' then
            out[#out + 1] = { idx = p.priority or i, body = p };
        end
    end
    table.sort(out, function(a, b) return a.idx < b.idx; end);
    return out;
end

local function _uc(u)
    return bit.band(u,0xFF)/255, bit.band(bit.rshift(u,8),0xFF)/255,
           bit.band(bit.rshift(u,16),0xFF)/255, bit.band(bit.rshift(u,24),0xFF)/255;
end

local function sep()
    imgui.Dummy(0, 6);
    imgui.Separator();
    imgui.Dummy(0, 6);
end

local function calc_text_w(text)
    local a = imgui.CalcTextSize(text);
    if type(a) == 'number' then return a; end
    if type(a) == 'table'  then return a.x or a[1] or 0; end
    return #text * 7;
end

local function dim_button(label, enabled, action, w)
    w = w or 0;
    if not enabled then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    if imgui.Button(label, w, 0) and enabled then action(); end
    if not enabled then imgui.PopStyleVar(); end
end

-- Called from autobots load event. Picker entries are sourced from the server
-- via 0x17A/0x17B (autoutil.server_configs) — refresh_pickers below pulls them
-- in. The addon no longer reads local config dirs.
-- SC threshold input vars (CDSTRING + Apply button — InputText commit cadence
-- is per-keystroke; an Apply button keeps the user typing "9" toward "95"
-- from hitting the server as a clamp to 9). Initialized to the same defaults
-- declared on the server side (bots.lua alliance.scStartHP / scStopHP /
-- scNoMoreHP); if those move, update both sides together.
-- Bundled UI state — collapsed from individual locals into namespace tables
-- so the giant ashita.register_event('render', ...) closure stays under
-- Lua 5.1's 60-upvalue cap. Each table holds related per-control state;
-- the render function captures the table reference once instead of every
-- field separately. Keep new mutable state on these tables instead of
-- adding new top-level locals.
--
-- sc_state — Skillchain HP threshold inputs (95/10 server defaults).
--   start_input / stop_input : CDSTRING imgui vars (live editing buffer)
--   start_committed / stop_committed : last-applied values; drive the
--     Apply button's dim state when neither input differs from server.
-- The "no-more" HP value is computed as max(0, stop - 3) at Apply time.
local sc_state = {
    start_input     = nil,
    stop_input      = nil,
    start_committed = '95',
    stop_committed  = '10',
}

-- puller_state — Puller picker (Combo over alliance roster) + range +
-- con-range pickers. con values are EXPCHAIN 0..6 = TW/EP/DC/EM/T/VT/IT.
local PULLER_CON_LABELS = { 'TW', 'EP', 'DC', 'EM', 'T', 'VT', 'IT' };
local puller_state = {
    combo_idx   = nil, -- INT32 var backing Combo selected index
    range_input = nil, -- CDSTRING var, contents "50"
    mpp_input   = nil, -- CDSTRING var, resume-pull heal MP% (contents "60")
    min_con     = 1,   -- EP
    max_con     = 6,   -- IT
}

-- qm_state — Quick Menu row-4 combo backing vars. Each is an INT32 imgui
-- var holding 0-based index into its option list (MODE_LABELS for AI,
-- WALKING_FORMATIONS for walking, BATTLE_FORMATIONS for battle). Re-seeded
-- from canonical state every render so other tabs / packet pushes stay in
-- sync with combo display.
local qm_state = {
    ai_idx      = nil,
    walking_idx = nil,
    battle_idx  = nil,
}
-- Puller name-filter state. nearby_names accumulates entries from successive
-- 0x1A4 refreshes; cleared on zone change (see autobots.lua). selected_names
-- is the user's currently checked subset, sent server-side on Apply.
autobots_ui.puller_nearby_names = {}; -- ordered list { { name, count } }, sort desc by count
autobots_ui.puller_selected_names = {}; -- set: name -> true

-- One-shot HTTP refresh of the config-name picker lists. Called at addon
-- load + after any create/delete. Lists are cached in allianceConfigNames /
-- foodConfigNames so the per-frame refresh_pickers stays a free table read.
-- Defined BEFORE on_load so the load-time call resolves (Lua locals don't
-- forward-reference).
local function refresh_config_names_from_server()
    local http = require('http_client');
    local function fetch(cat, assign)
        http.get('/configs/' .. cat, function(code, body, _, err)
            if code == nil then
                autoutil.log('AutoBots', string.format(
                    'config list fetch failed [%s]: %s', cat, tostring(err)));
                assign({});
                return;
            end
            if code ~= 200 or body == nil then
                autoutil.log('AutoBots', string.format(
                    'config list fetch [%s]: HTTP %s', cat, tostring(code)));
                assign({});
                return;
            end
            local ok, parsed = pcall(json.decode, json, body);
            assign((ok and parsed and parsed.names) or {});
        end);
    end
    fetch('alliance', function(names) allianceConfigNames = names; end);
    fetch('food',     function(names) foodConfigNames     = names; end);
end

function autobots_ui.on_load()
    ui_open = imgui.CreateVar(ImGuiVar_BOOLCPP);
    sc_state.start_input     = imgui.CreateVar(ImGuiVar_CDSTRING, 4);
    sc_state.stop_input      = imgui.CreateVar(ImGuiVar_CDSTRING, 4);
    puller_state.combo_idx   = imgui.CreateVar(ImGuiVar_INT32);
    puller_state.range_input = imgui.CreateVar(ImGuiVar_CDSTRING, 4);
    puller_state.mpp_input   = imgui.CreateVar(ImGuiVar_CDSTRING, 4);
    qm_state.ai_idx          = imgui.CreateVar(ImGuiVar_INT32);
    qm_state.walking_idx     = imgui.CreateVar(ImGuiVar_INT32);
    qm_state.battle_idx      = imgui.CreateVar(ImGuiVar_INT32);
    imgui.SetVarValue(sc_state.start_input,     '95');
    imgui.SetVarValue(sc_state.stop_input,      '10');
    imgui.SetVarValue(puller_state.combo_idx,   0);
    imgui.SetVarValue(puller_state.range_input, '50');
    imgui.SetVarValue(puller_state.mpp_input,   '60');
    -- Seed the picker name lists from the server. Single sync GET pair —
    -- ~2 ms total over loopback. Refreshed after any create/delete inside
    -- the editor modals.
    refresh_config_names_from_server();
    -- AutoSkill tab — wire up its ImGuiVar + 0x192 row mirror callback.
    autoskill_tab.on_load();
end

-- HTTP /bot-state receive: re-seed every UI state var from the server's
-- authoritative snapshot. Fired once at unlock by autobots.lua so the
-- addon UI matches the server after /addon reload (formations, thresholds,
-- puller, active config names, primary AI mode, per-bot toggles, role-AI
-- policy).
--
-- Missing keys are left at their local default - the schema is additive,
-- so a snapshot built from a server that pre-dates a new field just keeps
-- the addon at its local default for that field. Type-checked on the way
-- in: a string field arriving as a number gets dropped rather than coerced,
-- so a malformed snapshot can't corrupt the UI vars.
function autobots_ui.apply_server_snapshot(snap)
    if type(snap) ~= 'table' then return; end

    local function s(v) return (type(v) == 'string')                                  and v or nil; end
    local function n(v) return (type(v) == 'number')                                  and v or nil; end
    local function b(v) if type(v) == 'boolean' then return v end; return nil; end

    -- Alliance running status. When the snapshot reports running=false the
    -- local partyConfig stays nil; we only fold in a config name (for UI
    -- display) when the server actually has one selected. Capture the
    -- authoritative running flag so buttons that only need "is the alliance
    -- live" (Summon Trusts) work right after a reload, before the partyConfig
    -- body has been re-fetched.
    autobots_ui.server_running = b(snap.running) or false;
    local cfg_name = s(snap.configName);
    if cfg_name and cfg_name ~= '' then
        configName             = cfg_name;
        selectedAllianceConfig = cfg_name;
        -- We don't have the partyConfig BODY in the snapshot - the addon's
        -- existing async picker-select path will re-fetch /configs/alliance/{name}
        -- on the next user interaction. For now, just mark the name; the
        -- partyConfig stays nil and the right column shows the config-info
        -- placeholders until the body lands.
    end

    -- Food config name.
    local food_name = s(snap.foodConfigName);
    if food_name and food_name ~= '' then
        selectedFoodConfig = food_name;
    end

    -- Alliance headless botMode + current commanded mob for QM buttons.
    local amode = n(snap.allianceBotMode);
    if amode and amode >= 0 and amode <= 3 then alliance_bot_mode = amode; end
    local atid  = n(snap.allianceTargetId);
    if atid then alliance_target_id = math.floor(atid); end

    -- QM dim counters: server-authoritative "how many are still needed."
    -- Assign directly so a "no active config" state (server sends nil)
    -- clears the previous value.
    qm_needed.trusts = n(snap.trustsNeeded);
    qm_needed.food   = n(snap.foodNeeded);

    -- Primary AI mode.
    local mode = n(snap.primaryBotMode);
    if mode and (mode == 0 or mode == 1) then  -- only Off/CombatOnly are surfaced for primary
        primary_bot_mode = mode;
    end

    -- Aggro mode (NM Mode dropped — engine autodetect, no UI toggle).
    local ag = s(snap.aggroMode);
    if ag then aggroMode = ag; end

    -- Stun mode (alliance-wide, replaces BOT_STUN_PERSIST_UNTIL_FIRED).
    local stun = s(snap.stunMode);
    if stun == 'always' or stun == 'window' then stunMode = stun; end
    -- Multi-engage snapshot ingestion. Server sends multiEngageMode as bool
    -- or 0/1; either mapping ends up in 'off' / 'on' locally.
    local me = snap.multiEngageMode;
    if type(me) == 'boolean' then
        multiEngageMode = me and 'on' or 'off';
    elseif type(me) == 'number' then
        multiEngageMode = (me ~= 0) and 'on' or 'off';
    elseif type(me) == 'string' and (me == 'on' or me == 'off') then
        multiEngageMode = me;
    end

    -- Formations.
    local bf = s(snap.battleFormation);
    if bf then battleFormation = bf; end
    local wf = s(snap.walkingFormation);
    if wf then walkingFormation = wf; end

    -- SC thresholds. CDSTRING vars store string text; convert int -> string
    -- on the way in so the InputText display matches what the user typed.
    -- Also refresh the committed-value mirror so the Apply button's
    -- dim/enable logic considers post-snapshot state as the new baseline.
    local ss = n(snap.scStartHP);
    if ss and sc_state.start_input ~= nil then
        local v = tostring(math.floor(ss));
        imgui.SetVarValue(sc_state.start_input, v);
        sc_state.start_committed = v;
    end
    local sp = n(snap.scStopHP);
    if sp and sc_state.stop_input ~= nil then
        local v = tostring(math.floor(sp));
        imgui.SetVarValue(sc_state.stop_input, v);
        sc_state.stop_committed = v;
    end
    -- scNoMoreHP is intentionally NOT seeded - it's a derived field
    -- (stop - 3, clamp 0) on the addon side now, so the snapshot value is
    -- informational only and would just get overwritten on the next Apply.

    -- Puller. Server now sends a bundled object { name, range, minCon,
    -- maxCon, nameFilter } instead of flat fields. The legacy flat keys
    -- are no longer emitted by the server.
    local puller = snap.puller;
    if type(puller) == 'table' then
        local pn = s(puller.name);
        if pn and pn ~= '' then
            -- Puller dropdown index is recomputed from the running partyConfig
            -- roster at render time, not stored here. Stash the name on the
            -- module-level helper so render can find it when the alliance
            -- roster arrives.
            autobots_ui.puller_pending_name = pn;
        end
        local pr = n(puller.range);
        if pr and puller_state.range_input ~= nil then
            imgui.SetVarValue(puller_state.range_input, tostring(math.floor(pr)));
        end
        local pmpp = n(puller.resumeMpp);
        if pmpp and puller_state.mpp_input ~= nil then
            imgui.SetVarValue(puller_state.mpp_input, tostring(math.floor(pmpp)));
        end
        local pmin = n(puller.minCon);
        if pmin and pmin >= 0 and pmin <= 6 then puller_state.min_con = pmin; end
        local pmax = n(puller.maxCon);
        if pmax and pmax >= 0 and pmax <= 6 then puller_state.max_con = pmax; end
        -- Paused flag drives the Start/Stop button state. Accept booleans,
        -- 0/1 numerics, and "true"/"false" strings — the JSON decoder in
        -- some Ashita builds coerces booleans to numbers or strings, and
        -- our earlier strict boolean check silently dropped the update
        -- (Alliance AI tab kept showing PAUSED after a Start click).
        if puller.paused ~= nil then
            local v = puller.paused;
            if type(v) == 'boolean' then
                puller_state.paused = v;
            elseif type(v) == 'number' then
                puller_state.paused = v ~= 0;
            elseif type(v) == 'string' then
                puller_state.paused = (v == 'true' or v == '1');
            end
        end
        -- Name filter (array of mob name strings). Replace the local mirror
        -- wholesale so the addon UI matches the server's current filter.
        if type(puller.nameFilter) == 'table' then
            autobots_ui.puller_name_filter = {};
            for _, mob_name in ipairs(puller.nameFilter) do
                if type(mob_name) == 'string' and mob_name ~= '' then
                    table.insert(autobots_ui.puller_name_filter, mob_name);
                end
            end
        end
    end

    -- Camp anchor (formation walking-mode anchor). Nilable — absent when no
    -- camp has been pinned. Render reads autobots_ui.camp_anchor.
    if type(snap.campAnchor) == 'table'
       and type(snap.campAnchor.x) == 'number' and type(snap.campAnchor.z) == 'number' then
        autobots_ui.camp_anchor = { x = snap.campAnchor.x, z = snap.campAnchor.z };
    end

    -- Role-AI policy. Format from ai_item.role_ai_snapshot() matches what
    -- role_ai_tab.apply_snapshot already consumes (integer-keyed role idx,
    -- integer mode values, statusFlags map).
    if type(snap.rolePolicy) == 'table'
       and role_ai_tab and role_ai_tab.apply_snapshot then
        role_ai_tab.apply_snapshot(snap.rolePolicy);
    end

    -- Per-bot rows. Array of { name, role, mainJob, subJob, sataMode,
    -- healScope, healMode, addControlMode, thfRaDelay }. status_tab owns
    -- the per-name mirrors for sata/heal/addctl/thfRa; it seeds itself.
    if type(snap.bots) == 'table'
       and status_tab and status_tab.apply_bot_state then
        status_tab.apply_bot_state(snap.bots);
        -- Role AI tab consumes the same bots[] array for the per-BRD
        -- song-roster section (#252) — picks out BRD rows and stashes
        -- their songRoster + knownSongs.
        if role_ai_tab and role_ai_tab.apply_bot_state then
            role_ai_tab.apply_bot_state(snap.bots);
        end
    end
end

-- Subscribe at load-time so autoutil's HTTP /bot-state dispatcher routes
-- decoded snapshots here. autoutil registers callbacks into a flat list,
-- so the addon's single subscription is all we need.
if autoutil.on_bot_state_snapshot then
    autoutil.on_bot_state_snapshot(function(snap)
        autobots_ui.apply_server_snapshot(snap);
    end);
end

-- 0x1A4 receive: merge a fresh server scan into the running cache. Newer
-- counts overwrite older ones (server is authoritative). Re-sort by count
-- desc so the UI list stays stable.
function autobots_ui.merge_puller_names(list)
    if list == nil then return; end
    local cache = autobots_ui.puller_nearby_names;
    -- Index existing cache by name for O(1) lookup.
    local byName = {};
    for i, row in ipairs(cache) do byName[row.name] = i; end
    for _, row in ipairs(list) do
        local idx = byName[row.name];
        if idx ~= nil then
            cache[idx].count = row.count;  -- server wins
        else
            table.insert(cache, { name = row.name, count = row.count });
        end
    end
    table.sort(cache, function(a, b) return a.count > b.count end);
end

function autobots_ui.clear_puller_name_cache()
    autobots_ui.puller_nearby_names   = {};
    autobots_ui.puller_selected_names = {};
end

-- Per-frame picker refresh. Cheap — just keeps the local snapshots
-- pointing at the latest cached lists. Population happens in
-- refresh_config_names_from_server() at boot + after CRUD ops.
local function refresh_pickers()
    -- no-op today; the cache lists are mutated directly. Kept as a hook
    -- in case future state needs per-frame derivation again.
end

-- Called from autobots unload event.
function autobots_ui.on_unload()
    if ui_open ~= nil then
        imgui.DeleteVar(ui_open);
        ui_open = nil;
    end
    for _, v in ipairs({ sc_state.start_input, sc_state.stop_input, puller_state.combo_idx, puller_state.range_input,
                          puller_state.mpp_input,
                          qm_state.ai_idx, qm_state.walking_idx, qm_state.battle_idx }) do
        if v ~= nil then imgui.DeleteVar(v); end
    end
    sc_state.start_input, sc_state.stop_input = nil, nil;
    puller_state.combo_idx, puller_state.range_input, puller_state.mpp_input = nil, nil, nil;
    qm_state.ai_idx, qm_state.walking_idx, qm_state.battle_idx = nil, nil, nil;
    -- new_popup is keyed by category ('alliance', 'food'); each entry holds
    -- a CDSTRING ImGuiVar for the name input. Clean them up so /addon reload
    -- doesn't leak the underlying buffers.
    for cat, state in pairs(new_popup) do
        if state.name_input ~= nil then imgui.DeleteVar(state.name_input); end
        new_popup[cat] = nil;
    end
    autoskill_tab.on_unload();
end

-- Called when a config is started. Pass nil for name when started via inline args.
function autobots_ui.on_start(name, cfg)
    configName             = name;
    selectedAllianceConfig = name;
    partyConfig            = cfg;
    sc_all_paused          = false;
    -- Shared single-source-of-truth for the active alliance config. Other
    -- tabs (status_tab, future Char Settings tab) read autoutil.activeAllianceConfig
    -- directly instead of duplicating their own caches.
    autoutil.activeAllianceConfig = cfg;
end

-- Called when autobots is stopped.
function autobots_ui.on_stop()
    partyConfig = nil;
    configName  = nil;
    autobots_ui.server_running = false;
    autoutil.activeAllianceConfig = nil;
end

-- Toggle window visibility. When opening (false→true), re-fetch the alliance
-- roster — autoutil.alliance_pcs is only auto-refreshed on BF rising edge,
-- so a user who spawned the alliance from open-world (or zoned since the
-- last fetch) would otherwise see the stale roster (often just primary).
function autobots_ui.toggle()
    if ui_open == nil then return end
    local was_open = imgui.GetVarValue(ui_open)
    imgui.SetVarValue(ui_open, not was_open)
    if not was_open then
        autoutil.send_list_alliance_pcs()
    end
end

-- ============================================================
-- Shared render helpers (Quick Menu + Setup both use these)
-- ============================================================

-- Internal identifiers (the values sent to server) stay lowercase, but labels
-- render Title Case so the UI reads as proper menu items.
-- Display-name overrides for formation values whose identifier doesn't
-- title-case into a nice label (e.g. 'BRDSpread' -> 'BRD Spread').
local FORMATION_LABELS = {
    BRDSpread = 'BRD Spread',
};

local function title_case(s)
    return FORMATION_LABELS[s] or (s:gsub('^%l', string.upper));
end

-- ADKv3 imgui has no BeginCombo binding, so formations render as a row of
-- RadioButtons. Used by both the Setup tab and the Quick Menu.
--
-- Spacing note: SameLine(X) is WINDOW-absolute, so using a fixed label-column
-- X inside a BeginGroup that started off-axis (Quick Menu's right column)
-- snaps the radios back to X=60 of the window and overlaps the left group.
-- Use only relative SameLine(0, gap) here so the row floats wherever the
-- enclosing group placed it. Labels are padded to equal width so radio
-- columns stay aligned across Walking/Battle rows.
--
-- Wrap: options exceeding PER_ROW spill onto continuation rows indented to
-- the first radio's X. Walking has 5 options → 4 + 1; battle has 3 → fits.
local FORMATION_PER_ROW = 4;
-- Map an AGGRO_MODES entry to its numeric wire byte (0=off, 1=full, ...).
-- 1-based table index minus 1 — matches the C++ payload byte directly.
local function aggro_mode_index(name)
    for i, n in ipairs(AGGRO_MODES) do
        if n == name then return i - 1; end
    end
    return 0;
end

-- Same shape for MULTI_ENGAGE_MODES (0=off, 1=on).
local function multi_engage_mode_index(name)
    for i, n in ipairs(MULTI_ENGAGE_MODES) do
        if n == name then return i - 1; end
    end
    return 0;
end

-- Same shape for STUN_MODES (0=always, 1=window).
local function stun_mode_index(name)
    for i, n in ipairs(STUN_MODES) do
        if n == name then return i - 1; end
    end
    return 0;
end

-- 1-based index of `val` in `tbl`, or 1 if absent. Used by Quick Menu's
-- Combo widgets to convert the canonical state (current formation name,
-- current AI mode int) into the INT32 index the Combo's backing var wants.
local function index_of_value(tbl, val)
    for i, v in ipairs(tbl) do
        if v == val then return i; end
    end
    return 1;
end

-- Variant of render_formation_row that puts the label on its OWN line above
-- the radio strip. Used by the AI Settings tab's Formation section; the
-- inline-label render_formation_row below still drives Quick Menu / Aggro
-- where the labels are short and same-line packing keeps the strip compact.
-- Shared radio strip for both formation-row variants. Emits one RadioButton
-- per option, FORMATION_PER_ROW per row. continuation_x re-indents wrapped rows
-- to line up under the first radio (inline-label variant); nil leaves wrapped
-- rows at the column's left edge (stacked-label variant).
local function render_formation_radios(current, options, idPrefix, on_change, continuation_x)
    for i, name in ipairs(options) do
        local positionInRow = (i - 1) % FORMATION_PER_ROW;
        if i > 1 and positionInRow == 0 and continuation_x ~= nil then
            imgui.SetCursorPosX(continuation_x);
        end
        if imgui.RadioButton(title_case(name) .. '##' .. idPrefix .. '_' .. name,
                             name == current) then
            on_change(name);
        end
        if i < #options and positionInRow < FORMATION_PER_ROW - 1 then
            imgui.SameLine(0, 8);
        end
    end
end

local function render_formation_row_stacked(label, current, options, idPrefix, on_change, tooltip)
    imgui.Text(label .. ':');
    -- Hover the label to see per-option descriptions. Preserves the formation
    -- doc that lived on the QM "Hover Over Me" label before the QM 3→2 row
    -- collapse — moved onto the specific dimension's label so each tooltip
    -- shows only its own options rather than a jammed-together block.
    if tooltip ~= nil and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip);
    end
    imgui.Dummy(0, 2);
    render_formation_radios(current, options, idPrefix, on_change, nil);
end

local function render_formation_row(label, current, options, idPrefix, on_change, tooltip)
    local padded = label .. ':';
    while #padded < 8 do padded = padded .. ' ' end
    imgui.Text(padded);
    -- Hover the label to see per-option descriptions. Same pattern as
    -- render_formation_row_stacked; parameter is optional so existing
    -- callers without docs stay quiet.
    if tooltip ~= nil and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip);
    end
    imgui.SameLine(0, 8);
    local radio_x = imgui.GetCursorPosX();
    render_formation_radios(current, options, idPrefix, on_change, radio_x);
end

-- Primary AI mode radio strip — Off / CombatOnly only. Full and MovementOnly
-- aren't offered for the primary because auto-movement was setPos-based +
-- jerky and we don't want to fight the player's own client input. Used by
-- Setup and the Quick Menu second row.
local MODE_LABELS = { [0] = 'Off', [1] = 'CombatOnly' };
local function render_primary_ai_picker()
    -- (The inline "Primary AI:" label was dropped — the AI Settings tab's
    -- section_label("Primary Character AI") above the picker already names
    -- the control, and the duplicate text was just visual noise. Quick
    -- Menu still gets its label via label_combo_cell, so this only affects
    -- the AI Settings tab.)
    for mode = 0, 1 do
        if imgui.RadioButton(MODE_LABELS[mode] .. '##pmode_' .. mode, primary_bot_mode == mode) then
            primary_bot_mode = mode;
            autoutil.send_bot_set_mode('', mode); -- empty name = self
        end
        if mode < 1 then imgui.SameLine(0, 10); end
    end
end

-- ============================================================
-- Render
-- ============================================================


-- ============================================================
-- Render tab bodies (extracted from the render closure below).
--
-- The render event used to be one ~1450-line closure; it captured 60
-- upvalues (Lua 5.1's hard cap) so it could no longer take a new local.
-- Each tab block is now its own module-level function that receives a
-- per-frame `ctx` of the computed gate values (running / can_* / has_*),
-- destructured back into same-named locals so the bodies are unchanged.
-- Persistent module state (alliance_bot_mode, qm_needed, formations, ...)
-- is still captured directly as upvalues by each function.
-- ============================================================

    -- Shared spawn flow (used by Spawn Alliance). Fires
    -- the 0x175 SPAWN_HEADLESS, fetches the config body for the active-info
    -- readout, and calls autobots_ui.on_start on receive so `running` flips
    -- true and the rest of the UI gates light up.
    local function spawn_selected_config()
        if not selectedAllianceConfig then return; end
        autoutil.send_spawn_headless(selectedAllianceConfig);
        local cfgName = selectedAllianceConfig;
        local http    = require('http_client');
        http.get('/configs/alliance/' .. cfgName, function(code, body)
            if code ~= 200 or body == nil then return; end
            local ok, parsed = pcall(json.decode, json, body);
            if not ok or type(parsed) ~= 'table' then return; end
            if type(parsed.roles) == 'table' then
                for k, v in pairs(parsed.roles) do
                    if parsed[k] == nil then parsed[k] = v; end
                end
            end
            autobots_ui.on_start(cfgName, parsed);
        end);
    end

local function render_quick_tab(ctx)
    local running           = ctx.running
    local can_start         = ctx.can_start
    local can_food          = ctx.can_food
    local can_summon_trusts = ctx.can_summon_trusts
    local has_groupmate     = ctx.has_groupmate
    local has_dead_member   = ctx.has_dead_member
    local can_spawn_fresh   = ctx.can_spawn_fresh
        -- 3-button-wide grid. W=200 leaves enough horizontal room in row 4
        -- for a "Primary AI:" label plus a Combo wide enough to display
        -- "CombatOnly" without truncation. Total grid width = 3W + 2*SPACING.
        local W       = 200;
        local SPACING = 8;  -- imgui default ItemSpacing.x; matches SameLine() gap
        local startX  = imgui.GetCursorPosX();

        -- Collapsed 2-row QM. BotMode quadrant: 0=Off, 1=CombatOnly (actions
        -- on/movement off), 2=Full (both on), 3=MovementOnly (movement on/
        -- actions off). Each collapsed state-swap button reads its label
        -- from the current alliance_bot_mode and toggles only its own axis.
        local am = alliance_bot_mode;
        local actions_on  = (am == 1) or (am == 2);
        local movement_on = (am == 2) or (am == 3);
        -- toggle_actions: preserves movement axis. 0↔1, 2↔3.
        local ACTIONS_FLIP  = { [0]=1, [1]=0, [2]=3, [3]=2 };
        -- toggle_movement: preserves actions axis. 0↔3, 1↔2.
        local MOVEMENT_FLIP = { [0]=3, [1]=2, [2]=1, [3]=0 };

        -- ---- Row 1: Actions | Movement | Pulling (all state-swaps) ----
        local actions_label = actions_on and 'Stop Actions##qm_actions'
                                          or 'Start Actions##qm_actions';
        dim_button(actions_label, running and qm_click_ok('qm_actions'), function()
            qm_click_arm('qm_actions');
            local new_mode    = ACTIONS_FLIP[am] or 2;
            alliance_bot_mode = new_mode;
            autoutil.send_bot_set_alliance_mode(new_mode);
        end, W);
        imgui.SameLine(0, SPACING);
        local movement_label = movement_on and 'Stop Movement##qm_movement'
                                            or 'Start Movement##qm_movement';
        dim_button(movement_label, running and qm_click_ok('qm_movement'), function()
            qm_click_arm('qm_movement');
            local new_mode    = MOVEMENT_FLIP[am] or 2;
            alliance_bot_mode = new_mode;
            autoutil.send_bot_set_alliance_mode(new_mode);
        end, W);
        imgui.SameLine(0, SPACING);
        -- Start/Stop Pulling. Enabled only when a puller bot has been
        -- assigned (via Alliance AI tab). Label reads puller_state.paused
        -- which we flip optimistically on click.
        do
            local paused = puller_state.paused ~= false;  -- default paused when unknown
            local label  = paused and 'Start Pulling##qm_pull'
                                    or 'Stop Pulling##qm_pull';
            dim_button(label, running and qm_click_ok('qm_pull'), function()
                qm_click_arm('qm_pull');
                puller_state.paused = not paused;
                autoutil.send_bot_set_puller_paused(not paused);
            end, W);
        end

        -- ---- Row 2: Attack/Finish | Use Food | Summon Trusts ----
        -- Show Finish ONLY while the player's live target <t> IS the mob the
        -- alliance was last commanded onto; any other target (or none) shows
        -- Attack. Finish flips wsUntilDead + nukeUntilDead so bots dump
        -- cooldowns until the target dies.
        --
        -- Keying the label off the LIVE client target (not alliance_target_id
        -- alone) is what makes it self-correct: alliance_target_id only re-seeds
        -- from the server at unlock, so when the mob died it stayed non-zero and
        -- the button was stuck on Finish. Now a mob dying / the user retargeting
        -- naturally changes <t> so the label falls back to Attack on its own.
        -- send_bot_attack commands the current <t> (server stores it as
        -- alliance.allianceTarget = mob:getID(), same id space as
        -- GetTargetServerId), so mirror <t> into alliance_target_id optimistically
        -- on Attack — the label flips to Finish immediately.
        local player_target = autoutil.get_current_target_server_id() or 0;
        if player_target ~= 0 and player_target == alliance_target_id then
            dim_button('Finish##qm_atkfin', running and qm_click_ok('qm_atkfin'), function()
                qm_click_arm('qm_atkfin');
                alliance_target_id = 0;
                autoutil.send_bot_finish();
            end, W);
        else
            dim_button('Attack##qm_atkfin', running and qm_click_ok('qm_atkfin'), function()
                qm_click_arm('qm_atkfin');
                alliance_target_id = player_target;
                autoutil.send_bot_attack();
            end, W);
        end
        imgui.SameLine(0, SPACING);
        dim_button('Use Food##qm_food', can_food and qm_click_ok('qm_food'), function()
            if not selectedFoodConfig then return; end
            qm_click_arm('qm_food');
            qm_needed.food = 0;
            autoutil.send_use_food_config(selectedFoodConfig);
        end, W);
        imgui.SameLine(0, SPACING);
        dim_button('Summon Trusts##qm_st', can_summon_trusts and qm_click_ok('qm_st'), function()
            qm_click_arm('qm_st');  -- debounce; live trust detection handles dim
            autoutil.send_bot_summon_trusts();
        end, W);

        -- Formation-tooltip hover label removed as part of the QM 3→2 row
        -- collapse (row-3 slot 3 now hosts Start/Stop Pulling). Formation
        -- names still appear in the Combos below.

        -- ---- Row 3: Primary AI | Walking | Battle ----
        --
        -- Each cell: label inline + Combo, label vertically centered
        -- against the Combo's frame via AlignTextToFramePadding(). The
        -- whole row sits in its own group per cell so SameLine spacing
        -- between cells doesn't fight the inline Text/Combo SameLine.
        --
        -- Re-seed each Combo's backing INT32 var from the canonical state
        -- every frame so changes from elsewhere (AI Settings tab radios,
        -- server pushes) stay in sync with the QM display.
        imgui.Spacing();
        imgui.Spacing();

        -- Title-cased label lists for the Combo's "\0"-separated strings.
        -- WALKING / BATTLE option arrays are lowercase wire values; the
        -- combos show them title-cased to match the AI tab radios.
        local function title_join(list)
            local parts = {};
            for _, n in ipairs(list) do table.insert(parts, title_case(n)); end
            return table.concat(parts, '\0') .. '\0';
        end
        local AI_LABELS_Z      = title_join({ MODE_LABELS[0], MODE_LABELS[1] });
        local AI_VALUES        = { 0, 1 };       -- maps combo idx to send_bot_set_mode arg
        local WALKING_LABELS_Z = title_join(WALKING_FORMATIONS);
        local BATTLE_LABELS_Z  = title_join(BATTLE_FORMATIONS);

        -- Single helper renders one cell: label + combo, both aligned to
        -- the combo's frame baseline. on_change(new_value) receives the
        -- selected entry from `options` and is responsible for both
        -- updating local state and dispatching the packet.
        local LABEL_GAP   = 6;
        local function label_combo_cell(label, options, options_z, var, current_value, on_change)
            local label_w = (function()
                local a = imgui.CalcTextSize(label);
                if type(a) == 'number' then return a; end
                if type(a) == 'table'  then return a.x or a[1] or 0; end
                return #label * 7;
            end)();

            imgui.BeginGroup();
            -- AlignTextToFramePadding shifts the next Text() down by the
            -- frame padding so it sits visually centered against the Combo
            -- on the SameLine that follows.
            if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end
            imgui.Text(label);
            imgui.SameLine(0, LABEL_GAP);
            imgui.PushItemWidth(W - label_w - LABEL_GAP);
            imgui.Combo('##' .. label, var, options_z);
            imgui.PopItemWidth();
            imgui.EndGroup();

            local newIdx = imgui.GetVarValue(var) + 1;
            local newVal = options[newIdx];
            if newVal ~= nil and newVal ~= current_value then
                on_change(newVal);
            end
        end

        -- Establish a frame-tall line baseline BEFORE the first cell. Without
        -- this, the first cell's AlignTextToFramePadding() has no prior frame
        -- on the line to align against and is a no-op - which left "Primary
        -- AI:" sitting at the bare text baseline (~3px higher than Walking
        -- and Battle, whose AlignTextToFramePadding worked because earlier
        -- cells' combos had already established the frame baseline). A
        -- zero-width Dummy with frame height seeds the line cleanly.
        do
            local frame_h = imgui.GetTextLineHeightWithSpacing and imgui.GetTextLineHeightWithSpacing() or 21;
            imgui.Dummy(0, frame_h);
            imgui.SameLine(0, 0);
        end

        -- Primary AI cell.
        imgui.SetVarValue(qm_state.ai_idx, index_of_value(AI_VALUES, primary_bot_mode) - 1);
        label_combo_cell('Primary AI:', AI_VALUES, AI_LABELS_Z, qm_state.ai_idx, primary_bot_mode,
            function(newVal)
                primary_bot_mode = newVal;
                autoutil.send_bot_set_mode('', newVal);  -- empty name = self
            end);

        imgui.SameLine(0, SPACING);

        -- Walking cell.
        imgui.SetVarValue(qm_state.walking_idx, index_of_value(WALKING_FORMATIONS, walkingFormation) - 1);
        label_combo_cell('Walking:', WALKING_FORMATIONS, WALKING_LABELS_Z, qm_state.walking_idx, walkingFormation,
            function(newVal)
                walkingFormation = newVal;
                autoutil.send_bot_set_formation(1, newVal);  -- kind 1 = walking
            end);

        imgui.SameLine(0, SPACING);

        -- Battle cell.
        imgui.SetVarValue(qm_state.battle_idx, index_of_value(BATTLE_FORMATIONS, battleFormation) - 1);
        label_combo_cell('Battle:', BATTLE_FORMATIONS, BATTLE_LABELS_Z, qm_state.battle_idx, battleFormation,
            function(newVal)
                battleFormation = newVal;
                autoutil.send_bot_set_formation(0, newVal);  -- kind 0 = battle
            end);

end

-- Left-column section helpers, shared by the per-tab left renderers below.
-- left_x is the column's left screen edge, refreshed each frame by
-- render_left_column; left_sep clips a divider to the 304px column width so it
-- doesn't bleed into the right column; section_label = rule + header. (These
-- were locals inside the old single render_left_column, hoisted so the split
-- per-tab renderers can share them.)
local left_x = 0
local section_head_text = autoutil.section_head
local function left_sep()
        local wx, wy = imgui.GetWindowPos();
        local wh     = imgui.GetWindowHeight();
        imgui.PushClipRect(left_x, wy, left_x + 304, wy + wh, true);
        sep();
        imgui.PopClipRect();
end
local function section_label(text)
        imgui.Dummy(0, 4);
        left_sep();
        section_head_text(text);
end

-- ── Controls tab ──
-- Buttons grouped by purpose under bold section labels; each section is its
-- own function below and render_controls_left just calls them in order. Rows
-- are two BTN_W-wide buttons; empty slots use imgui.Dummy(BTN_W,0) to keep the
-- two-column grid aligned.
local BTN_W = 148

local function render_controls_management(ctx)
    local running          = ctx.running
    local can_spawn_fresh  = ctx.can_spawn_fresh
    local can_summon_trusts = ctx.can_summon_trusts
    local has_groupmate    = ctx.has_groupmate
    -- ── Alliance Management ──
    -- First section of the Controls tab; no leading rule (section_head_text
    -- gives uppercase + bright + underline so it still reads as a header).
    section_head_text('Alliance Management');

    -- Spawn Alliance / Despawn Alliance.
    -- Spawn only enabled when a config is selected AND the primary is solo;
    -- has_groupmate covers both "bots already up" and "in a real PC party"
    -- so we never collide with an existing group.
    dim_button('Spawn Alliance', can_spawn_fresh, function()
        spawn_selected_config();
    end, BTN_W);
    imgui.SameLine();
    dim_button('Despawn Alliance##dsp', running, function()
        autoutil.send_bot_despawn_all();
        autobots_ui.on_stop();
    end, BTN_W);

    imgui.Spacing();
    -- Summon Trusts / Give Signet.
    -- Trusts: only useful when alliance running, and only the primary
    -- summons - the server handles the cascade. Signet: server walks every
    -- owned bot's nation/rank to pick per-bot durations.
    dim_button('Summon Trusts##st', can_summon_trusts, function()
        autoutil.send_bot_summon_trusts();
    end, BTN_W);
    imgui.SameLine();
    dim_button('Give Signet##gsig', running, function()
        autoutil.send_bot_give_signet();
    end, BTN_W);
end

local function render_controls_actions(ctx)
    local running          = ctx.running
    local can_food         = ctx.can_food
    -- ── Alliance Actions ──
    section_label('Alliance Actions');

    -- Start Actions / Stop Actions. BotMode quadrant after #207:
    --   0 Off          - primary; bots default to Full
    --   1 CombatOnly   - actions on, no move        ("Stop Movement")
    --   2 Full         - both on                    ("Start Actions" / "Start Movement")
    --   3 MovementOnly - no actions, movement on    ("Stop Actions")
    --
    -- Dim by current mode so the pair reads as state indicator (same
    -- mechanism the QM's collapsed state-swap buttons use, just split
    -- into two separate buttons here). actions_on = mode has actions
    -- flag; Start dims when already on, Stop dims when already off.
    do
        local am          = alliance_bot_mode;
        local actions_on  = (am == 1) or (am == 2);
        local movement_on = (am == 2) or (am == 3);

        dim_button('Start Actions##sa_on', running and not actions_on, function()
            alliance_bot_mode = 2;
            autoutil.send_bot_set_alliance_mode(2);  -- BotMode::Full
        end, BTN_W);
        imgui.SameLine();
        dim_button('Stop Actions##sa_off', running and actions_on, function()
            alliance_bot_mode = 3;
            autoutil.send_bot_set_alliance_mode(3);  -- BotMode::MovementOnly
        end, BTN_W);

        imgui.Spacing();
        -- Start Movement / Stop Movement. Start Movement maps to BotMode::Full
        -- (same as Start Actions) because the only way to re-enable movement
        -- after CombatOnly is to flip the whole mode; there's no per-axis
        -- "movement only" toggle that preserves the action-only state.
        dim_button('Start Movement##mv_on', running and not movement_on, function()
            alliance_bot_mode = 2;
            autoutil.send_bot_set_alliance_mode(2);  -- BotMode::Full
        end, BTN_W);
        imgui.SameLine();
        dim_button('Stop Movement##mv_off', running and movement_on, function()
            alliance_bot_mode = 1;
            autoutil.send_bot_set_alliance_mode(1);  -- BotMode::CombatOnly
        end, BTN_W);
    end

    imgui.Spacing();
    -- Attack / Finish.
    -- Attack: 0x176 AUTOBOTS ATTACK; server fans out to every linked headless.
    -- Finish: server flips wsUntilDead + nukeUntilDead so melees fire WS
    -- and mages casual-nuke each tick until the target dies, then auto-
    -- clears so bots resume normal AI.
    dim_button('Attack##atk', running, function()
        autoutil.send_bot_attack();
    end, BTN_W);
    imgui.SameLine();
    dim_button('Finish##fin', running, function()
        autoutil.send_bot_finish();
    end, BTN_W);

    imgui.Spacing();
    -- Pause Skillchains / Use Food.
    -- One button for ALL SC pairs (scId 0 fans out server-side). Replaces
    -- the per-pair Pause SC1 / Pause SC2 buttons because configs now allow
    -- an arbitrary number of pairs - see has_any_sc helper above.
    local hasSC = running and has_any_sc(partyConfig);
    local scLabel = sc_all_paused and 'Resume Skillchains##rsc'
                                   or 'Pause Skillchains##psc';
    dim_button(scLabel, hasSC, function()
        sc_all_paused = not sc_all_paused;
        autoutil.send_bot_sc_pause(0, sc_all_paused);  -- 0 = all pairs
    end, BTN_W);
    imgui.SameLine();
    dim_button('Use Food##food', can_food, function()
        if not selectedFoodConfig then return; end
        autoutil.send_use_food_config(selectedFoodConfig);
    end, BTN_W);

    imgui.Spacing();
    -- Heal On / Heal Off (alliance-wide).
    -- send_bot_set_heal_mode with no name arg targets every owned headless.
    -- The same API call with a bot name as second arg would flip a single
    -- bot, but no UI surfaces that today - callers wanting per-bot or
    -- per-role control would build the list and emit one packet per name.
    dim_button('Heal On##heal_on',  running, function()
        autoutil.send_bot_set_heal_mode(true);
    end, BTN_W);
    imgui.SameLine();
    dim_button('Heal Off##heal_off', running, function()
        autoutil.send_bot_set_heal_mode(false);
    end, BTN_W);
end

local function render_controls_sync(ctx)
    local running          = ctx.running
    -- ── Alliance Sync ──
    section_label('Alliance Sync');

    -- Sync Quests / Sync Missions cascade primary's quest/mission completion
    -- state onto every linked headless (server-side:
    -- xi.singleplayer.bots.bots_progression_cascade.sync_*). Requires alliance
    -- spawned. Each button dims while a sync is in flight; the "(...)" suffix
    -- is the in-flight indicator, cleared on ACK or after SYNC_SAFETY_TIMEOUT_S.
    local q_busy = sync_in_flight(sync_started.quests);
    local m_busy = sync_in_flight(sync_started.missions);
    local q_label = q_busy and 'Sync Quests (...)##sq'   or 'Sync Quests##sq';
    local m_label = m_busy and 'Sync Missions (...)##sm' or 'Sync Missions##sm';
    dim_button(q_label, running and not q_busy, function()
        autoutil.send_bot_sync_quests();
        sync_started.quests = os.time();
    end, BTN_W);
    imgui.SameLine();
    dim_button(m_label, running and not m_busy, function()
        autoutil.send_bot_sync_missions();
        sync_started.missions = os.time();
    end, BTN_W);

    -- Sync Teleports: cascade primary's full teleport surface (homepoints,
    -- survival guides, waypoints, abyssea conflux, eschan portals, runic
    -- portal, past maw, campaign, outposts) onto every linked headless.
    -- Same in-flight pattern as the rows above; ACK kind=2.
    local t_busy  = sync_in_flight(sync_started.teleports);
    local t_label = t_busy and 'Sync Teleports (...)##st' or 'Sync Teleports##st';
    dim_button(t_label, running and not t_busy, function()
        autoutil.send_bot_sync_teleports();
        sync_started.teleports = os.time();
    end, BTN_W);
end

local function render_controls_instance(ctx)
    -- ── Instance ──
    -- Pick the subset of the alliance that joins the active instance
    -- (BCNM / Dynamis / INSTANCED zone). Presets pre-check rows in the
    -- list below; Enter Selected fires 0x16A subcmd=2 (SPECIFIC) with the
    -- checked names. Server auto-detects which instance type is active
    -- and dispatches: BCNM -> InsertEntity, Dynamis -> in-process zone
    -- move into the static Dynamis zone, INSTANCED -> attach to sender's
    -- CInstance and zone in.
    -- NOTE: the in_instance flag only edges on the 0x075 BCNM-active
    -- packet, so the button currently dims outside BCNM contexts even
    -- when the server would happily handle a Dynamis pull. Server returns
    -- a chat error if the user clicks outside any instance, so relaxing
    -- the gate later is safe.
    section_label('Instance');

    -- Roster is server-driven (fetched via 0x185/0x186 on BF rising edge in
    -- autobots.lua). Authoritative PC-only list - trusts are naturally absent.
    -- Filter out the primary themselves: if they're operating this picker they
    -- are already in the instance, so checking a "join me to the instance" box
    -- for themselves is meaningless and just clutters the grid.
    local primary_party_name = '';
    do
        local party = AshitaCore:GetDataManager():GetParty();
        primary_party_name = party and party:GetMemberName(0) or '';
    end
    local inst_roster = {};
    for _, m in ipairs(autoutil.alliance_pcs or {}) do
        if m.name ~= primary_party_name then
            table.insert(inst_roster, m);
        end
    end

    -- Prune stale entries (alliance changed since last frame).
    if next(bf_checked) ~= nil then
        local present = {};
        for _, m in ipairs(inst_roster) do present[m.name] = true; end
        for nm in pairs(bf_checked) do
            if not present[nm] then bf_checked[nm] = nil; end
        end
    end

    local inst_enabled = autobots_ui.in_instance;
    if not inst_enabled then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end

    -- The Instance section's Alpha push spans ~60 lines including a
    -- per-row CreateVar/DeleteVar loop and the 0x1A0 ack-rendering branch.
    -- An error anywhere in that span (rare but seen as "the whole UI went
    -- dim across addons") strands the Alpha push on imgui's global style
    -- stack and contaminates every later addon's render. Wrap the body in
    -- pcall so the matching PopStyleVar below always fires regardless of
    -- inner failure. The error gets logged so we can chase root causes
    -- without a contaminated UI in the meantime.
    local _inst_ok, _inst_err = pcall(function()

    -- Row 1: presets that bulk-check rows. Alliance = check everyone; Party =
    -- check only own-party members and clear the rest.
    if imgui.Button('Alliance##inst_pa', BTN_W, 0) and inst_enabled then
        for _, m in ipairs(inst_roster) do bf_checked[m.name] = true; end
    end
    imgui.SameLine();
    if imgui.Button('Party##inst_pp', BTN_W, 0) and inst_enabled then
        for _, m in ipairs(inst_roster) do bf_checked[m.name] = (m.party == 1); end
    end

    -- Row 2: Enter Selected. Dim when nothing is checked OR not in an instance.
    local inst_selected_names = {};
    for _, m in ipairs(inst_roster) do
        if bf_checked[m.name] then table.insert(inst_selected_names, m.name); end
    end
    local can_enter = inst_enabled and (#inst_selected_names > 0);
    if not can_enter then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    if imgui.Button('Enter Selected##inst_es', BTN_W * 2 + 6, 0) and can_enter then
        autoutil.send_instance_enter(2, inst_selected_names);
        autoutil.last_instance_enter_result = nil;  -- clear so the new ack overwrites
    end
    if not can_enter then imgui.PopStyleVar(); end

    -- Surface the latest 0x1A0 ack so the user sees "Pulled 3 bot(s) into
    -- Dynamis" or "No active instance in this zone." instead of nothing.
    local r = autoutil.last_instance_enter_result;
    if r ~= nil then
        if r.status == 0 then
            local branch_label = (r.branch == 0 and 'battlefield')
                              or (r.branch == 1 and 'Dynamis')
                              or (r.branch == 2 and 'instance')
                              or '?';
            imgui.TextColored(0.6, 0.95, 0.6, 1.0,
                string.format('Pulled %d into %s', r.moved, branch_label));
        elseif r.status == 1 then
            imgui.TextColored(0.95, 0.6, 0.4, 1.0, 'No active instance to enter');
        elseif r.status == 2 then
            imgui.TextColored(0.95, 0.6, 0.4, 1.0, 'Sender has no instance assignment');
        elseif r.status == 3 then
            imgui.TextColored(0.95, 0.6, 0.4, 1.0, 'No zone state');
        end
    end

    -- Checkbox grid: 2 per row, in roster order (party 1 / 2 / 3 from Ashita).
    imgui.Dummy(0, 4);
    if #inst_roster == 0 then
        imgui.TextDisabled('(no alliance roster)');
    else
        for i, m in ipairs(inst_roster) do
            local v = imgui.CreateVar(ImGuiVar_BOOLCPP);
            imgui.SetVarValue(v, bf_checked[m.name] or false);
            imgui.Checkbox(m.name .. '##bf_' .. m.name, v);
            bf_checked[m.name] = imgui.GetVarValue(v);
            imgui.DeleteVar(v);
            if (i % 2) == 1 and i < #inst_roster then imgui.SameLine(160); end
        end
    end

    end); -- end pcall body
    if not _inst_ok then
        autoutil.log('AutoBots', 'instance section error: ' .. tostring(_inst_err));
    end

    if not inst_enabled then imgui.PopStyleVar(); end
end

local function render_controls_debug(ctx)
    local running          = ctx.running
    local has_dead_member  = ctx.has_dead_member
    -- ── Debug ──
    section_label('Debug');

    -- Raise Dead simulates the dead-bot homepoint -> /welcome sequence
    -- server-side: XP loss + Weakness + snap to primary. Enabled while
    -- running; harmless no-op if nothing is dead.
    dim_button('Raise Dead##raise', running and has_dead_member, function()
        autoutil.send_bot_spawn_dead();
    end, BTN_W);
    imgui.SameLine();
    imgui.Dummy(BTN_W, 0);  -- intentional blank to preserve the two-column grid
end

local function render_controls_left(ctx)
    render_controls_management(ctx)
    render_controls_actions(ctx)
    render_controls_sync(ctx)
    render_controls_instance(ctx)
    render_controls_debug(ctx)
end

local function render_ai_left(ctx)
    local running           = ctx.running
    local can_start         = ctx.can_start
    local can_food          = ctx.can_food
    local can_summon_trusts = ctx.can_summon_trusts
    local has_groupmate     = ctx.has_groupmate
    local has_dead_member   = ctx.has_dead_member
    local can_spawn_fresh   = ctx.can_spawn_fresh
    -- ── Alliance Settings ──
    -- First section in the tab - no leading divider (the tab strip already
    -- separates it from the window chrome).
    --
    -- Establish the left column at the same width as the Controls tab
    -- (which uses two 148-wide buttons + ~8px spacing = ~304px). Without
    -- this, AlwaysAutoResize shrinks the AI Settings tab narrower than
    -- Controls because none of its widgets are as wide as the two-button
    -- row. A zero-height Dummy of the same width plants a minimum-width
    -- marker without leaving a visible gap.
    imgui.Dummy(304, 0);
    -- First section of AI Settings; no leading rule.
    section_head_text('Alliance Settings');

    -- Headless Aggro toggle. 'off' = trust-like (no aggro), 'full' = mobs
    -- aggro headless like real PCs, 'engaged' = invisible until the headless
    -- has a battle target then vanilla rules apply.
    local AGGRO_TOOLTIP =
        'Headless aggro mode:\n' ..
        '  Off     - headless are trust-like; mobs never aggro them\n' ..
        '  Full    - headless are treated as real PCs; sight/sound/scent aggro applies\n' ..
        '  Engaged - no aggro until the headless has already engaged; vanilla rules apply after';
    render_formation_row('Headless Aggro', aggroMode, AGGRO_MODES, 'ag', function(name)
        aggroMode = name;
        autoutil.send_bot_set_aggro_mode(aggro_mode_index(name));
    end, AGGRO_TOOLTIP);

    -- Vertical breathing room between Headless Aggro and Stun Behavior -
    -- without it the two two-radio strips read as one row, which made the
    -- Stun Behavior label look like a continuation of Aggro's options.
    imgui.Dummy(0, 6);

    -- Stun Behavior toggle. Two options:
    --   Always - interrupt window stays open until a stunner fires or the
    --            alliance target dies. Costs one extra Stun cast per WS in
    --            exchange for never missing the interrupt - the legacy
    --            BOT_STUN_PERSIST_UNTIL_FIRED=true behavior, and the default.
    --   Window - window equals the mob's actual WS castTime (with a 500ms
    --            minimum for instant moves). Strict; misses if every stunner
    --            is busy when the WS starts. Legacy =false behavior.
    -- Bash window is always strict and not user-configurable.
    local STUN_TOOLTIP =
        'Stun interrupt window:\n' ..
        '  Always - window stays open until a stunner fires or the target dies;\n' ..
        '           can burn an extra Stun per WS but never misses the interrupt\n' ..
        '  Window - window equals the mob WS castTime (500ms min for instant moves);\n' ..
        '           strict, misses if every stunner is busy at WS start\n' ..
        '(Bash window is always strict and not configurable here.)';
    render_formation_row('Stun Behavior', stunMode, STUN_MODES, 'sm', function(name)
        stunMode = name;
        autoutil.send_bot_set_stun_mode(stun_mode_index(name));
    end, STUN_TOOLTIP);

    imgui.Dummy(0, 6);

    -- Multi-engagement toggle (#173). 'off' = whole alliance funnels onto one
    -- mob (legacy). 'on' = each of the 3 alliance sub-parties fights its own
    -- mob simultaneously. When flipped on, the server seeds all 3 party
    -- assist targets from the current alliance target.
    render_formation_row('Multi-engage', multiEngageMode, MULTI_ENGAGE_MODES, 'me', function(name)
        multiEngageMode = name;
        autoutil.send_bot_set_multi_engage_mode(multi_engage_mode_index(name));
    end);

    -- Skillchain Thresholds. Two user-editable HP% inputs - Start and Stop -
    -- and a derived "no-more" value (= max(0, stop - 3)) sent on Apply with
    -- the other two. The no-more field used to be user-editable but the
    -- correct delta-from-stop is well-known and exposing it added a
    -- footgun for users who'd set Stop=10 / NoMore=20 and break burn
    -- behavior. Now it's just stop minus three, clamped at zero.
    --   Start Mob HP%   - opener stops opening above this HP% (let burst land).
    --   Stop Mob HP%    - opener stops opening below this HP% (overkill).
    --   (derived nomore) - solo melees rescue-fire, nukers stop holding for MB.
    -- Apply commits all three on one click; per-keystroke send would clamp
    -- mid-type ("9" toward "95" would land as 9).
    --
    -- Layout: one row per control, all left-aligned. The previous two-
    -- inputs-on-one-row layout pushed the Apply button awkwardly far
    -- right because we were centering it on the gap between the inputs.
    -- Stacking keeps every label and the button in the same x-column.
    --
    -- section_label provides the clipped divider above the section so
    -- it separates cleanly from Alliance Settings without leaking the
    -- rule across the right column.
    section_label('Skillchain Thresholds (HP%%)');

    local INPUT_W   = 40;
    local LABEL_GAP = 6;

    -- Row 1: Start Mob HP%.
    if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end
    imgui.Text('Start Mob HP%%:');
    imgui.SameLine(0, LABEL_GAP);
    imgui.PushItemWidth(INPUT_W);
    imgui.InputText('##sc_start', sc_state.start_input, 4);
    imgui.PopItemWidth();

    imgui.Dummy(0, 4);

    -- Row 2: Stop Mob HP%.
    if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end
    imgui.Text('Stop Mob HP%%:');
    imgui.SameLine(0, LABEL_GAP);
    imgui.PushItemWidth(INPUT_W);
    imgui.InputText('##sc_stop', sc_state.stop_input, 4);
    imgui.PopItemWidth();

    imgui.Dummy(0, 6);

    -- Row 3: Apply, left-aligned at the row's starting X. Dimmed when
    -- the typed values match the last-committed snapshot so the button
    -- only "lights up" when there's actually a delta to send. Click is
    -- gated on the same condition to avoid no-op packet sends if the
    -- user mashes Apply.
    local current_start = imgui.GetVarValue(sc_state.start_input) or '';
    local current_stop  = imgui.GetVarValue(sc_state.stop_input)  or '';
    local sc_dirty = (current_start ~= sc_state.start_committed)
                  or (current_stop  ~= sc_state.stop_committed);
    if not sc_dirty then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    if imgui.Button('Apply##sc_apply', 80, 0) and sc_dirty then
        local start_v  = tonumber(current_start) or 95;
        local stop_v   = tonumber(current_stop)  or 10;
        local nomore_v = math.max(0, stop_v - 3);
        autoutil.send_bot_set_sc_threshold(0, start_v);
        autoutil.send_bot_set_sc_threshold(1, stop_v);
        autoutil.send_bot_set_sc_threshold(2, nomore_v);
        -- Snap the committed mirror to the just-sent values so the
        -- button dims immediately, not after the server round-trips a
        -- new snapshot.
        sc_state.start_committed = tostring(start_v);
        sc_state.stop_committed  = tostring(stop_v);
    end
    if not sc_dirty then imgui.PopStyleVar(); end

    -- ── Primary Character AI ──
    section_label('Primary Character AI');
    -- Sends 0x176 SET_BOT_MODE with an empty name (server treats empty name
    -- as self) so it only affects the primary's own m_botMode. Start/Stop
    -- Actions on Controls act on every owned headless instead.
    --   Off        - AI completely paused for primary.
    --   CombatOnly - AI runs role tick (cures / WS / spells) but doesn't move.
    -- Full / MovementOnly are deliberately omitted - auto-movement on the
    -- primary fights the player's own client input.
    render_primary_ai_picker();

    -- ── Formation ──
    -- Stacked label-above-radios layout. Walking has 5 options so it wraps
    -- to a second row (4 per row); Battle's 4 fit a single row.
    -- Hover 'Battle:' or 'Walking:' for per-option descriptions.
    section_label('Formation');
    local BATTLE_TOOLTIP =
        'Battle formations (in combat):\n' ..
        '  Off    - bots freeze in combat (no formation override)\n' ..
        '  Legacy - pre-formation chase-to-mob behavior\n' ..
        '  Spread - tank front, melee arc behind the mob, mages perpendicular\n' ..
        '  Tight  - tank front, melee fan to both sides, mages just behind the mob\n' ..
        '  AoE    - mages sample rays around the mob at max Cure range, pick a slot aligned with the primary';
    local WALKING_TOOLTIP =
        'Walking formations (out of combat):\n' ..
        '  Off    - bots freeze in place\n' ..
        '  Legacy - classic ad-hoc trailing of the assist\n' ..
        '  Camp   - assist holds at the camp anchor; adds still pulled in\n' ..
        '  Column - single column behind the primary\n' ..
        '  Rows   - rank-and-file rows behind the primary';
    render_formation_row_stacked('Battle',  battleFormation,  BATTLE_FORMATIONS,  'fb', function(name)
        battleFormation = name;
        autoutil.send_bot_set_formation(0, name); -- kind 0 = battle
    end, BATTLE_TOOLTIP);
    imgui.Dummy(0, 6);
    render_formation_row_stacked('Walking', walkingFormation, WALKING_FORMATIONS, 'fw', function(name)
        walkingFormation = name;
        autoutil.send_bot_set_formation(1, name); -- kind 1 = walking
    end, WALKING_TOOLTIP);

    -- (Puller Settings used to live here in the left column. It has been
    -- moved to the RIGHT column for the AI Settings tab — see the
    -- `if active_tab == 'ai'` branch below the divider. The left column
    -- now stops at Formations.)

end

local function render_skill_left(ctx)
    local running           = ctx.running
    local can_start         = ctx.can_start
    local can_food          = ctx.can_food
    local can_summon_trusts = ctx.can_summon_trusts
    local has_groupmate     = ctx.has_groupmate
    local has_dead_member   = ctx.has_dead_member
    local can_spawn_fresh   = ctx.can_spawn_fresh
    -- ── AutoSkill ──
    -- The roster + per-bot Off/RA/Magic radio + spell picker live in
    -- autoskill_tab.render(). It used to be the entire tab body (single
    -- column); now it just fills the LEFT column slot so the right
    -- column's Active/Selected Config Info anchor still shows. Floor
    -- the width with a Dummy so an empty roster doesn't collapse the
    -- column and shift the divider leftward.
    imgui.Dummy(304, 0);
    autoskill_tab.render();
end

local function render_left_column(ctx)
    left_x = imgui.GetCursorScreenPos()
    imgui.BeginGroup()
    if active_tab == 'controls' then
        render_controls_left(ctx)
    elseif active_tab == 'ai' then
        render_ai_left(ctx)
    elseif active_tab == 'skill' then
        render_skill_left(ctx)
    end
    imgui.EndGroup()
end

local function render_ai_right(ctx)
    local running           = ctx.running
    local can_start         = ctx.can_start
    local can_food          = ctx.can_food
    local can_summon_trusts = ctx.can_summon_trusts
    local has_groupmate     = ctx.has_groupmate
    local has_dead_member   = ctx.has_dead_member
    local can_spawn_fresh   = ctx.can_spawn_fresh
        -- First and only section in the right column for the AI tab;
        -- no leading rule.
        section_head_text('Puller Settings');

        -- Start/Stop row. Start begins scanning; Stop halts IDLE→SCOUTING
        -- so no NEW pull begins. An in-flight pull continues to natural
        -- completion — Stop is "no more mobs after this one," not a
        -- kill-switch. Fresh puller assignments start paused.
        --
        -- dim_button(label, enabled, action, w): true → clickable, false → dimmed no-op.
        do
            local paused = puller_state.paused ~= false; -- default paused when unknown
            -- Currently paused → Start enabled (unpause), Stop dimmed.
            -- Currently running → Start dimmed, Stop enabled (pause).
            -- The dim state carries the same info as an explicit
            -- PAUSED/RUNNING label — no separate text needed.
            dim_button('Start##puller_start', paused, function()
                puller_state.paused = false;
                autoutil.send_bot_set_puller_paused(false);
            end, 60);
            imgui.SameLine(0, 6);
            dim_button('Stop##puller_stop', not paused, function()
                puller_state.paused = true;
                autoutil.send_bot_set_puller_paused(true);
            end, 60);
        end

        imgui.Dummy(0, 6);

        -- Bot picker. Combo over the alliance roster (sourced from the running
        -- partyConfig). A blank "nobody" entry sits at index 1 so the user can
        -- explicitly clear the puller. Auto-sends on selection change — no
        -- Set button; Start/Stop live above. Blank entry sends empty name
        -- which turns puller behavior off.
        local roster = collect_alliance_names(partyConfig);
        local items;
        if #roster > 0 then
            items = { ' ' };
            for _, n in ipairs(roster) do table.insert(items, n); end
        else
            items = { '(no alliance up)' };
        end
        local labels = table.concat(items, '\0') .. '\0';
        local prev_idx = imgui.GetVarValue(puller_state.combo_idx);
        imgui.PushItemWidth(160);
        imgui.Combo('##puller_pick', puller_state.combo_idx, labels);
        imgui.PopItemWidth();
        local new_idx = imgui.GetVarValue(puller_state.combo_idx);
        if new_idx ~= prev_idx then
            local name = items[new_idx + 1] or '';
            if name:match('^%s*$') or name == '(no alliance up)' then
                name = '';
            end
            autoutil.send_bot_set_puller(name);
        end

        imgui.Dummy(0, 8);
        -- Range input. No Apply button — auto-send when the buffer settles.
        -- "Settles" = 750ms of no changes, so user typing "255" doesn't send
        -- 2 then 25 then 255. Tracks the last-observed buffer value and the
        -- time it last changed; sends when the parsed value differs from
        -- last-sent AND enough quiet time has passed since the last edit.
        imgui.Text('Range:'); imgui.SameLine(0, 6);
        imgui.PushItemWidth(40);
        imgui.InputText('##puller_range', puller_state.range_input, 4);
        imgui.PopItemWidth();
        imgui.SameLine(0, 4); imgui.Text('y');
        do
            local raw = imgui.GetVarValue(puller_state.range_input);
            local r   = tonumber(raw);
            if raw ~= (puller_state.range_last_buf or '') then
                puller_state.range_last_buf   = raw;
                puller_state.range_change_at  = os.clock();
            end
            local settled = (os.clock() - (puller_state.range_change_at or 0)) >= 0.75;
            if settled and r ~= nil and r >= 1 and r ~= (puller_state.last_sent_range or -1) then
                puller_state.last_sent_range = r;
                autoutil.send_bot_set_puller_range(r);
            end
        end

        imgui.Dummy(0, 8);
        imgui.Text('Pull Difficulty Range:');
        imgui.Dummy(0, 2);
        imgui.Text('Min');
        for i, label in ipairs(PULLER_CON_LABELS) do
            imgui.SameLine(0, 4);
            if imgui.RadioButton(label .. '##puller_min', puller_state.min_con == (i - 1)) then
                puller_state.min_con = i - 1;
                if puller_state.max_con < puller_state.min_con then puller_state.max_con = puller_state.min_con; end
                autoutil.send_bot_set_puller_con_range(puller_state.min_con, puller_state.max_con);
            end
        end
        imgui.Dummy(0, 2);
        imgui.Text('Max');
        for i, label in ipairs(PULLER_CON_LABELS) do
            imgui.SameLine(0, 4);
            if imgui.RadioButton(label .. '##puller_max', puller_state.max_con == (i - 1)) then
                puller_state.max_con = i - 1;
                if puller_state.min_con > puller_state.max_con then puller_state.min_con = puller_state.max_con; end
                autoutil.send_bot_set_puller_con_range(puller_state.min_con, puller_state.max_con);
            end
        end

        imgui.Dummy(0, 8);
        -- Resume-MP gate: the puller holds the next pull until the party's heal
        -- role (Healer, or RDM backup) is at least this MP% — and never pulls
        -- while that healer is dead. Auto-sends when the buffer settles (750ms).
        imgui.Text('Resume pull at heal MP:'); imgui.SameLine(0, 6);
        imgui.PushItemWidth(40);
        imgui.InputText('##puller_mpp', puller_state.mpp_input, 4);
        imgui.PopItemWidth();
        imgui.SameLine(0, 4); imgui.Text('%');
        do
            local raw = imgui.GetVarValue(puller_state.mpp_input);
            local v   = tonumber(raw);
            if raw ~= (puller_state.mpp_last_buf or '') then
                puller_state.mpp_last_buf  = raw;
                puller_state.mpp_change_at = os.clock();
            end
            local settled = (os.clock() - (puller_state.mpp_change_at or 0)) >= 0.75;
            if settled and v ~= nil and v >= 0 and v <= 100 and v ~= (puller_state.last_sent_mpp or -1) then
                puller_state.last_sent_mpp = v;
                autoutil.send_bot_set_puller_resume_mpp(v);
            end
        end

        imgui.Dummy(0, 8);
        imgui.Text('Name filter:');
        imgui.SameLine(0, 6);
        if imgui.Button('Refresh##puller_names_refresh', 70, 0) then
            autoutil.send_bot_request_puller_names();
        end
        imgui.SameLine(0, 6);
        if imgui.Button('Clear##puller_names_clear', 60, 0) then
            autobots_ui.puller_selected_names = {};
            autoutil.send_bot_set_puller_name_filter({});
        end
        -- Name filter now auto-sends on each checkbox toggle (no Apply button).
        -- Helper closure builds the current selection list and pushes to server.
        local function send_puller_name_filter_snapshot()
            local names = {};
            for _, row in ipairs(autobots_ui.puller_nearby_names) do
                if autobots_ui.puller_selected_names[row.name] then
                    table.insert(names, row.name);
                end
            end
            autoutil.send_bot_set_puller_name_filter(names);
        end

        local cache = autobots_ui.puller_nearby_names;
        if #cache == 0 then
            imgui.TextColored(0.65, 0.65, 0.65, 1.0, '  (no names yet - click Refresh)');
        else
            -- 0 width is fine here — we're inside the right column, so the
            -- child takes whatever content width is available without
            -- bleeding into the left column. Height fills the remaining
            -- vertical space in the right column (GetContentRegionAvail's
            -- second return = avail_h). Floor at 192 px (~12 checkbox rows)
            -- so the list never collapses smaller than the previous fixed
            -- 160 height even when the window is shortened. Pad subtracted
            -- to leave a small bottom margin so the child border doesn't
            -- visually butt against the window edge.
            local _, avail_h = imgui.GetContentRegionAvail();
            local list_h = math.max(192, (avail_h or 0) - 6);
            imgui.BeginChild('##puller_names_list', 0, list_h, true);
            for _, row in ipairs(cache) do
                local sel = autobots_ui.puller_selected_names[row.name] == true;
                local v = imgui.CreateVar(ImGuiVar_BOOLCPP);
                imgui.SetVarValue(v, sel);
                imgui.Checkbox(string.format('%s (%d)##puller_name_%s', row.name, row.count, row.name), v);
                local newVal = imgui.GetVarValue(v);
                imgui.DeleteVar(v);
                if newVal ~= sel then
                    autobots_ui.puller_selected_names[row.name] = newVal and true or nil;
                    -- Auto-apply: push the new filter state to the server on
                    -- each individual toggle. Tiny packet, no debounce needed
                    -- for the volume of checkbox clicks a user makes.
                    send_puller_name_filter_snapshot();
                end
            end
            imgui.EndChild();
        end

end

    -- Shared renderer for both remaining picker sections. Action buttons:
    --   New    — opens a popup to enter a name, then PUTs a '{}' template to
    --            the HTTP config endpoint
    --   Edit   — opens the form-based editor (alliance_tab / food_tab)
    --   Delete — confirm popup → DELETE the HTTP config endpoint
local function render_picker_section(title, category, names, selected, on_select)
    local running = alliance_is_running()
        imgui.Text(title);
        imgui.Dummy(0, 6);

        local popup_edit_id   = title .. '##edit_popup';
        local popup_delete_id = title .. '##delete_popup';

        local popup_new_id = title .. '##new_popup';
        if imgui.Button('New##' .. category, 96, 0) then
            if not new_popup[category] then
                new_popup[category] = {
                    -- CDSTRING / 16-byte buffer matches every other working
                    -- InputText in the addon set (food_tab filter, etc).
                    name_input = imgui.CreateVar(ImGuiVar_CDSTRING, 16),
                    error      = '',
                };
            end
            imgui.SetVarValue(new_popup[category].name_input, '');
            new_popup[category].error = '';
            -- Switch to BeginPopup (non-modal). The previous Begin-window-
            -- with-open_var approach didn't reliably receive keyboard input
            -- in Ashita v3 — the popup window wasn't grabbing focus from the
            -- parent autobots Begin scope. food_tab's pattern (BeginPopup
            -- non-modal + InputText inside) is known to work for filter
            -- typing, so we adopt it here.
            imgui.OpenPopup(popup_new_id);
        end
        imgui.SameLine();
        if not selected then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
        if imgui.Button('Edit##' .. category, 96, 0) and selected then
            if category == 'food' then
                food_tab.open(selected);
            elseif category == 'alliance' then
                alliance_tab.open(selected);
            else
                imgui.OpenPopup(popup_edit_id);
            end
        end
        imgui.SameLine();
        if imgui.Button('Delete##' .. category, 96, 0) and selected then
            imgui.OpenPopup(popup_delete_id);
        end
        if not selected then imgui.PopStyleVar(); end

        -- New-config popup: BeginPopup (non-modal) — same pattern food_tab
        -- uses for its filter InputText. Imgui anchors the popup to the
        -- cursor position when OpenPopup was called (i.e. just under the
        -- "New" button), which is "near the action" and doesn't require
        -- parent-window-position math. Closes on click-outside or ESC for
        -- free. The deferred state.needs_close flag handles the async
        -- coroutine path (Create button → HTTP probe + PUT → on success
        -- close the popup from this frame).
        local state = new_popup[category];
        if state and imgui.BeginPopup(popup_new_id) then
            if state.needs_close then
                state.needs_close = false;
                imgui.CloseCurrentPopup();
            else
                imgui.Text(string.format('New %s config name (max 10 chars):', category));
                imgui.PushItemWidth(280);
                -- 3-arg form (label, var, max_chars). The 2-arg form
                -- doesn't actually accept keystrokes in Ashita v3 — the
                -- widget displays its initial value but ignores typing.
                -- Every working InputText elsewhere in the addon set
                -- (autolot new-group name, gear_tab new-set name, automog
                -- filters, NM Hunter Min/Max) uses 3-arg, so adopt it
                -- here too. max_chars=16 matches the CDSTRING buffer
                -- size set above.
                imgui.InputText('##' .. category .. '_name', state.name_input, 16);
                imgui.PopItemWidth();
                if state.error ~= '' then
                    imgui.TextColored(1.0, 0.4, 0.4, 1.0, state.error);
                end
                if imgui.Button('Create##' .. category, 80, 0) then
                    local name = imgui.GetVarValue(state.name_input):gsub('%s+$', ''):gsub('^%s+', '');
                    if name == '' or name:match('[/\\.]') then
                        state.error = 'Invalid name (no path chars)';
                    elseif #name > 10 then
                        state.error = 'Name too long (max 10 chars)';
                    else
                        state.error = '';
                        -- Chained GET-probe + PUT-template via http.go() so the
                        -- two requests sequence without nested callbacks.
                        local http = require('http_client');
                        http.go(function()
                            local existsCode = http.get_sync('/configs/' .. category .. '/' .. name);
                            if existsCode == 200 then
                                state.error = 'already exists';
                                return;
                            elseif existsCode ~= 404 and existsCode ~= nil then
                                state.error = string.format('probe returned %s', tostring(existsCode));
                                return;
                            end
                            local code = http.put_sync('/configs/' .. category .. '/' .. name, '{}\n', 'application/json');
                            if code == 200 or code == 201 then
                                refresh_config_names_from_server();
                                state.needs_close = true;
                            else
                                state.error = string.format('create failed (HTTP %s)', tostring(code));
                            end
                        end);
                    end
                end
                imgui.SameLine();
                if imgui.Button('Cancel##' .. category .. '_new', 80, 0) then
                    imgui.CloseCurrentPopup();
                end
            end
            imgui.EndPopup();
        end

        -- Food and alliance categories use dedicated form editors above; no
        -- stub modal needed. Other categories (if added later) would need
        -- their own renderer wired here.

        -- Delete popup: confirm then DELETE the HTTP endpoint. On 204/404
        -- (file removed or already absent) refresh the local picker list.
        if imgui.BeginPopupModal(popup_delete_id, nil, ImGuiWindowFlags_AlwaysAutoResize) then
            imgui.Text(string.format('Delete %s "%s"?', category, tostring(selected)));
            imgui.TextDisabled('This permanently removes the file from the server.');
            if imgui.Button('Delete##' .. category .. '_del_go', 80, 0) and selected then
                local target = selected;
                local http   = require('http_client');
                http.delete_('/configs/' .. category .. '/' .. target, function(code, _, _, err)
                    if code == 204 or code == 404 then
                        refresh_config_names_from_server();
                        if category == 'alliance' and selectedAllianceConfig == target then
                            selectedAllianceConfig = nil;
                        elseif category == 'food' and selectedFoodConfig == target then
                            selectedFoodConfig = nil;
                        end
                    elseif code == nil then
                        autoutil.log('AutoBots', string.format('delete %s/%s: %s', category, target, tostring(err)));
                    else
                        autoutil.log('AutoBots', string.format('delete %s/%s: HTTP %s', category, target, tostring(code)));
                    end
                end);
                imgui.CloseCurrentPopup();
            end
            imgui.SameLine();
            if imgui.Button('Cancel##' .. category .. '_del_no', 80, 0) then
                imgui.CloseCurrentPopup();
            end
            imgui.EndPopup();
        end

        imgui.Dummy(0, 6);
        if #names > 0 then
            for i, name in ipairs(names) do
                if (i - 1) % 3 > 0 then imgui.SameLine(); end
                local is_selected = (name == selected);
                local is_running  = (category == 'alliance') and running and (name == configName) and not is_selected;
                -- Color priority (only one Push fires per button):
                --   1. selected  -> bright blue   (active picker choice)
                --   2. running   -> dark green    (alliance currently spawned with this config)
                --   3. default   -> very faint green wash (unselected config; just enough
                --                                  tint to read as "selectable" without
                --                                  competing with the bright blue / dark
                --                                  green of the selected / running states)
                if is_selected then
                    imgui.PushStyleColor(ImGuiCol_Button, 0.26, 0.59, 0.98, 1.0);
                elseif is_running then
                    imgui.PushStyleColor(ImGuiCol_Button, 0.15, 0.45, 0.15, 1.0);
                else
                    imgui.PushStyleColor(ImGuiCol_Button, 0.19, 0.22, 0.20, 1.0);
                end
                if imgui.Button(name .. '##' .. category, 96, 0) then
                    on_select(name);
                end
                imgui.PopStyleColor();
            end
        else
            imgui.TextDisabled('no ' .. category .. ' configs loaded');
        end
end

local function render_config_info(ctx)
    local running = ctx.running
    -- ── Active / Selected Config Info ──
    -- Always reserves space; rows display placeholders when nothing is
    -- selected or running so the rest of the column doesn't reflow.
    --
    -- Label + body selection priority:
    --   1) Nothing selected → show the running partyConfig (or placeholders),
    --      labeled "Active Config Info" — preserves the legacy idle view.
    --   2) Selected matches the running config → same partyConfig, labeled
    --      "Active Config Info" — user picked the one already in flight.
    --   3) Selected ≠ running → show the cached selectedAllianceBody,
    --      labeled "Selected Config Info".
    do
        local body, header, headerLabel;
        if selectedAllianceConfig == nil then
            body        = (running and partyConfig) or nil;
            headerLabel = (running and (configName or '--')) or '--';
            header      = 'Active Config Info';
        elseif running and selectedAllianceConfig == configName then
            body        = partyConfig;
            headerLabel = configName or '--';
            header      = 'Active Config Info';
        else
            body        = selectedAllianceBody;
            headerLabel = selectedAllianceConfig;
            header      = 'Selected Config Info';
        end

        imgui.Text(header);
        imgui.Dummy(0, 6);

        local tank, healStr, nukeStr, rdmStr, soloStr = '--', '--', '--', '--', '--';
        local scRows = {};   -- list of { label = 'SC1', text = 'opener > closer' }
        if body then
            tank    = join_names(body['tank']);
            healStr = join_names(body['heal']);
            nukeStr = join_names(body['nuke']);
            rdmStr  = join_names(body['rdm']);

            -- Skillchain pairs: render one row per sc%d+ key in the body
            -- rather than the hardcoded SC1/SC2 pair the schema used to
            -- emit. Configs may now have N pairs; collect_sc_pairs sorts
            -- by numeric suffix so the display order is stable across
            -- frame ticks regardless of pairs() iteration order.
            for _, sc in ipairs(collect_sc_pairs(body)) do
                local oN = sc.body.openName  or '';
                local cN = sc.body.closeName or '';
                local text;
                if oN == '' then
                    text = '--';
                elseif cN == '' then
                    text = oN;
                else
                    text = oN .. ' > ' .. cN;
                end
                table.insert(scRows, { label = string.format('SC%d', sc.idx), text = text });
            end

            -- Solo: name -> WS map of melees doing their own WS instead of
            -- participating in any SC pair. Sorted alphabetically for stable output.
            if type(body['solo']) == 'table' then
                local names = {};
                for nm, _ in pairs(body['solo']) do
                    if type(nm) == 'string' and nm ~= '' then
                        table.insert(names, nm);
                    end
                end
                table.sort(names);
                if #names > 0 then soloStr = table.concat(names, ', '); end
            end
        end
        imgui.Text('Config: ' .. headerLabel);
        imgui.TextDisabled('Tank:  ' .. tank);
        imgui.TextDisabled('Heal:  ' .. healStr);
        imgui.TextDisabled('Nuke:  ' .. nukeStr);
        imgui.TextDisabled('RDM:   ' .. rdmStr);
        if #scRows == 0 then
            imgui.TextDisabled('SC:    --');
        else
            for _, row in ipairs(scRows) do
                imgui.TextDisabled(string.format('%-6s %s', row.label .. ':', row.text));
            end
        end
        -- Solo row: long name lists would force the entire right column wider
        -- than the rest of the rows. Wrap to the column's current width so the
        -- row can spill onto multiple lines instead of pushing the column.
        local col_w = imgui.GetContentRegionAvailWidth();
        imgui.PushTextWrapPos(imgui.GetCursorPosX() + col_w);
        imgui.TextDisabled('Solo:  ' .. soloStr);
        imgui.PopTextWrapPos();

        -- Skill: bots in autoskill mode (sourced from autoutil.autoskill_state
        -- which is populated by the 0x192 push). Empty cache → '--' placeholder.
        local skillParts = {};
        if type(autoutil.autoskill_state) == 'table' then
            local sorted = {};
            for name, mode in pairs(autoutil.autoskill_state) do
                table.insert(sorted, { name = name, mode = mode });
            end
            table.sort(sorted, function(a, b) return a.name < b.name; end);
            for _, e in ipairs(sorted) do
                local label = (e.mode == 1) and 'RA' or (e.mode == 2) and 'Magic' or '?';
                table.insert(skillParts, e.name .. ' (' .. label .. ')');
            end
        end
        local skillStr = (#skillParts > 0) and table.concat(skillParts, ', ') or '--';
        imgui.TextDisabled('Skill: ' .. skillStr);

        -- Food: shows the currently-selected food config name (mirrors the
        -- food picker below). '--' when nothing is picked. Lives at the
        -- bottom of the config display so a glance at this panel covers
        -- both the running alliance and the food the user has staged.
        imgui.TextDisabled('Food:  ' .. (selectedFoodConfig or '--'));
    end

    sep();
end

local function render_config_pickers(ctx)
    -- ── Alliance Config ──
    render_picker_section('Alliance Config', 'alliance', allianceConfigNames,
                          selectedAllianceConfig,
                          function(name)
                              -- Re-clicking the active selection deselects it
                              -- (matches the toggle convention every other
                              -- picker uses in this addon set).
                              if selectedAllianceConfig == name then
                                  selectedAllianceConfig = nil;
                                  selectedAllianceBody   = nil;
                                  return;
                              end
                              selectedAllianceConfig = name;
                              -- Async GET — body lands on a later frame.
                              -- Right-column shows a loading placeholder
                              -- until selectedAllianceBody is non-nil.
                              selectedAllianceBody = nil;
                              local http = require('http_client');
                              http.get('/configs/alliance/' .. name, function(code, body)
                                  -- User may have changed selection by the
                                  -- time the response arrives — discard if so.
                                  if selectedAllianceConfig ~= name then return; end
                                  if code == 200 and body and body ~= '' then
                                      local ok, parsed = pcall(json.decode, json, body);
                                      if ok and type(parsed) == 'table' then
                                          if type(parsed.roles) == 'table' then
                                              for k, v in pairs(parsed.roles) do
                                                  if parsed[k] == nil then parsed[k] = v; end
                                              end
                                          end
                                          selectedAllianceBody = parsed;
                                      end
                                  end
                              end);
                          end);

    sep();

    -- ── Food Config ──
    render_picker_section('Food Config', 'food', foodConfigNames,
                          selectedFoodConfig,
                          function(name)
                              if selectedFoodConfig == name then
                                  selectedFoodConfig = nil;
                                  return;
                              end
                              selectedFoodConfig = name;
                          end);
end

local function render_configinfo_right(ctx)
    render_config_info(ctx)
    render_config_pickers(ctx)
end

local function render_right_column(ctx)
    imgui.BeginGroup()
    if active_tab == 'ai' then
        render_ai_right(ctx)
    else
        render_configinfo_right(ctx)
    end
    imgui.EndGroup()
end

ashita.register_event('render', function()
    -- Advance pending HTTP coroutines once per frame. http_client doesn't
    -- auto-register a 'render' hook because multiple register_event for
    -- the same event collide in Ashita v3 - we drive its scheduler from
    -- this addon's existing render instead.
    require('http_client').tick();
    if ui_open == nil or not imgui.GetVarValue(ui_open) then
        return;
    end

    -- Status tab packs more horizontally (per-bot icon rows in 2 cols) — it
    -- needs more width than the other tabs or the right column truncates
    -- icons. Force a wider window on the Status tab; other tabs keep the
    -- standard 660 first-use width (still resizable). Always-condition on
    -- Status overrides any saved user size.
    -- Window sizing. AlwaysAutoResize is restored — the window snaps to its
    -- content size and is NOT user-resizable. Status tab seeds wider now
    -- that it's a 4×4 card grid (4 × CARD_W=210 plus gaps + window padding);
    -- other tabs get 660. SetNextWindowSize values only matter as ceilings
    -- since AlwaysAutoResize shrinks to actual content.
    -- Per-tab width seed: Status packs more horizontally (per-bot card grid),
    -- others are narrower. height=0 because AlwaysAutoResize below fits the
    -- vertical axis to content anyway. FirstUseEver = only on first open;
    -- subsequent frames let resize_on_tab_change govern.
    local tab_w = (active_tab == 'status') and 920 or 660;
    imgui.SetNextWindowSize(tab_w, 0, ImGuiSetCond_FirstUseEver);
    -- Force the window to re-fit its content when the tab changes - otherwise
    -- it stays sized to whichever tab grew it widest. Same per-tab width,
    -- height=0 = no constraint (AlwaysAutoResize fits vertically).
    autoutil.resize_on_tab_change('AutoBots', active_tab, tab_w, 0);
    autoutil.push_solid_window_bg();
    if not imgui.Begin('AutoBots', ui_open, ImGuiWindowFlags_AlwaysAutoResize) then
        imgui.End();
        autoutil.pop_solid_window_bg();
        return;
    end

    refresh_pickers();

    -- ── Tab strip (Ashita v3 imgui has no native TabBar). Matches automog's
    --    convention: inactive tabs render with the default Button color, the
    --    active tab gets the standard imgui-blue background highlight.
    local function tab_button(label, key)
        local active = (active_tab == key);
        if active then imgui.PushStyleColor(ImGuiCol_Button, 0.26, 0.59, 0.98, 1.0); end
        if imgui.Button(label) then active_tab = key; end
        if active then imgui.PopStyleColor(); end
    end
    tab_button('Quick Menu', 'quick');     imgui.SameLine();
    tab_button('Controls', 'controls');    imgui.SameLine();
    tab_button('Skill Ups', 'skill');      imgui.SameLine();
    tab_button('Alliance AI', 'ai');       imgui.SameLine();
    tab_button('Item AI', 'roleai');       imgui.SameLine();
    tab_button('Status', 'status');
    sep();

    -- Migration: legacy 'setup' tab maps to Controls; legacy 'instance' tab
    -- maps to Controls (the Instance section was folded into Controls as
    -- another labelled section group). Anything else unrecognized lands
    -- in Controls so the UI never renders blank.
    if active_tab == 'setup'    then active_tab = 'controls'; end
    if active_tab == 'instance' then active_tab = 'controls'; end
    if active_tab ~= 'quick' and active_tab ~= 'controls' and active_tab ~= 'ai'
       and active_tab ~= 'roleai' and active_tab ~= 'status' and active_tab ~= 'skill' then
        active_tab = 'controls';
    end

    if active_tab == 'status' then
        status_tab.render();
        imgui.End();
        autoutil.pop_solid_window_bg();
        return;
    end

    if active_tab == 'roleai' then
        role_ai_tab.render();
        imgui.End();
        autoutil.pop_solid_window_bg();
        return;
    end

    -- 'skill' falls through to the standard two-column layout below — the
    -- AutoSkill roster renders inside the LEFT column block (see the
    -- `if active_tab == 'skill'` clause down there), and the RIGHT column's
    -- Active / Selected Config Info shows the same partyConfig / selected-
    -- config readout as Controls and AI Settings. Layout match means users
    -- get the same anchor across all three tabs.

    -- "Is the alliance live." partyConfig is only populated once the user has
    -- started/re-picked a config THIS session; after a login or /addon reload
    -- it's nil even while the alliance is running server-side (the /bot-state
    -- snapshot re-seeds the config NAME, not the body — see apply_server_snapshot).
    -- OR in the authoritative server_running flag so every button that only
    -- needs "is it running" (Attack/Finish, Despawn, Heal, Sync, Summon Trusts,
    -- etc.) works immediately after a reload. Buttons that dereference the config
    -- BODY (has_any_sc(partyConfig), the puller roster) stay correctly dimmed
    -- until the body rehydrates — both helpers are nil-safe.
    local running          = alliance_is_running();
    local can_start        = selectedAllianceConfig ~= nil;
    -- Server-authoritative dim on Use Food: only dim when there's a food
    -- config selected AND the server has confirmed every configured member
    -- already has a FOOD status. nil (no active food config server-side, or
    -- first-snapshot delay) leaves the button live.
    local can_food         = selectedFoodConfig ~= nil
                             and (qm_needed.food == nil or qm_needed.food > 0);

    -- Summon Trusts: alliance running (running now folds in server_running, so
    -- this is reload-safe) AND server sees at least one trust still missing.
    -- Server does the comparison (normalized name match across all alliance
    -- members) since client-side slot-name matching previously proved fragile.
    -- nil => snapshot hasn't landed, keep live.
    -- Summon Trusts: LIVE-detect trusts missing from the config vs the actual
    -- alliance roster, so the button re-lights the instant a trust dies. Fall
    -- back to the server snapshot's trustsNeeded only when we don't have the
    -- config body yet (e.g. right after a reload before it re-fetches).
    local trusts_missing = trusts_missing_count();
    local can_summon_trusts;
    if trusts_missing ~= nil then
        can_summon_trusts = running and (trusts_missing > 0);
    else
        can_summon_trusts = running and (qm_needed.trusts == nil or qm_needed.trusts > 0);
    end

    -- has_groupmate: any non-self member in slots 1..17 of the party manager.
    -- True when bots are spawned (they're in the party), OR when the user
    -- joined a real PC party. Used to gate Spawn Alliance: you can't start
    -- a fresh alliance while you already have one (or any group).
    local has_groupmate = false;
    -- has_dead_member: any alliance slot (0..17, including primary) currently
    -- at 0 HP. Drives the Spawn Dead button — no point clicking it when
    -- everyone's alive. Slot 0 is the primary; primary can self-resurrect via
    -- the same flow (homepoint /welcome) so include them.
    local has_dead_member = false;
    do
        local party = AshitaCore:GetDataManager():GetParty();
        if party ~= nil then
            for slot = 1, 17 do
                local nm = party:GetMemberName(slot);
                if nm ~= nil and nm ~= '' then has_groupmate = true; break; end
            end
            for slot = 0, 17 do
                local nm = party:GetMemberName(slot);
                if nm ~= nil and nm ~= '' and party:GetMemberCurrentHP(slot) <= 0 then
                    has_dead_member = true;
                    break;
                end
            end
        end
    end
    local can_spawn_fresh = can_start and not has_groupmate;
    local ctx = {
        running           = running,
        can_start         = can_start,
        can_food          = can_food,
        can_summon_trusts = can_summon_trusts,
        has_groupmate     = has_groupmate,
        has_dead_member   = has_dead_member,
        can_spawn_fresh   = can_spawn_fresh,
    }

    if active_tab == 'quick' then
        render_quick_tab(ctx)
        imgui.End()
        autoutil.pop_solid_window_bg()
        return
    end

    render_left_column(ctx)
    imgui.SameLine(0, 6);
    imgui.PushStyleColor(ImGuiCol_ChildWindowBg, _uc(imgui.GetColorU32(ImGuiCol_Button)));
    imgui.BeginChild('##col_divider', 1, 0, false);
    imgui.EndChild();
    imgui.PopStyleColor();
    imgui.SameLine(0, 6);
    render_right_column(ctx)

    -- Form-editor modals stay alive across frames. Each tab manages its own
    -- popup-open state; render() is a no-op when closed.
    food_tab.render();
    alliance_tab.render();

    imgui.End();
    autoutil.pop_solid_window_bg();
end);

function autobots_ui.on_party_status(partyNumber, members)
    status_tab.on_party_status(partyNumber, members);
end

return autobots_ui;
