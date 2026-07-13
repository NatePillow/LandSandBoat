-- Alliance Config form editor (#98).
-- Opens from the right-column Alliance Config "Edit" button. Edits the
-- combined alliance config JSON in a tabbed modal:
--   * Parties     — up to 3 parties with leader, members, trusts
--   * Roles       — Tank, Melee, Heal, Nuke, RDM (multi-select dropdowns)
--   * Skillchains — SC1 / SC2 opener+closer + Solo derived from Melee
--   * Rotations   — Provoke (Melee pool), Stun (Heal/Nuke/Rdm + any DRK)
--   * Flags       — Item multi-select + NM + Stationary
--
-- All dropdowns enforce "used elsewhere" exclusion so the same char can't be
-- double-booked. Trust dropdown options are fetched live from the server via
-- 0x18B/0x18C so it tracks whatever SPELLGROUP_TRUST spells the running map is
-- shipping. WS dropdowns iterate the Ashita resource manager.
--
-- Save serializes to JSON and ships through 0x189 (whole-file write).

require 'imguidef';

local autoutil = require('autoutil');
local json     = require('json');

local alliance_tab = {};

-- ============================================================
-- State
-- ============================================================

local state = {
    open         = false,
    needs_open   = false,
    needs_close  = false,
    config_name  = nil,
    tab          = 'parties',
    body         = nil,  -- parsed JSON edited in place
    error        = '',
    -- WS cache built on open.
    ws_cache     = nil,  -- list of WS names, scanned from ability resource
    ws_filter    = nil,  -- imgui CHARARRAY var for WS picker
    pc_filter    = nil,
    trust_filter = nil,
    -- Picker context (which row triggered the open).
    pc_picker    = nil,  -- { kind = 'leader'|'member'|... , path = ..., value_setter = fn }
    trust_picker = nil,
    ws_picker    = nil,
};

-- Standard ability ID range that covers WS. Iterating once on open is fast.
local WS_ID_LO = 1;
local WS_ID_HI = 256;

local FFXI_NAME_PATTERN = '^[A-Za-z][A-Za-z0-9%-\']*$';
local NAME_MAX_LEN      = 15;

-- ============================================================
-- Helpers
-- ============================================================

local function clean_str(s)
    if s == nil then return ''; end
    return tostring(s):gsub('%z+$', ''):gsub('^%s+', ''):gsub('%s+$', '');
end

local function deep_copy(t)
    if type(t) ~= 'table' then return t; end
    local out = {};
    for k, v in pairs(t) do out[k] = deep_copy(v); end
    return out;
end

local function default_body()
    return {
        alliance   = {
            { ptLeader = '', members = {}, trusts = {} },
        },
        roles      = {
            tank    = { '' },  -- single-element list; [1] = tank char
            melee   = {},
            heal    = {},
            nuke    = {},
            rdm     = {},
            brd     = {},
            smn     = {},
            stun    = {},
            provoke = {},
            item    = {},
        },
        -- SC pairs: server-canonical shape is this ARRAY of
        -- { priority, openName, openWS, closeName, closeWS } (see bots_spawn.lua
        -- apply_alliance, which ipairs over cfg.sc). Arbitrary count. The legacy
        -- sc1/sc2 KEYS the editor used to write were never read by the server;
        -- normalize_body migrates + drops them.
        sc         = {},
        solo       = {},
        nm         = false,
        stationary = false,
    };
end

-- Normalize a loaded body: backfill missing fields, derive melee role from
-- legacy configs where it wasn't an explicit list yet (union of solo keys and
-- SC opener/closer names).
local function normalize_body(b)
    local d = default_body();
    if type(b) ~= 'table' then return d; end
    for k, _ in pairs(d) do
        if b[k] == nil then b[k] = deep_copy(d[k]); end
    end
    if type(b.alliance) ~= 'table' or #b.alliance == 0 then
        b.alliance = { { ptLeader = '', members = {}, trusts = {} } };
    end
    for _, party in ipairs(b.alliance) do
        party.ptLeader = party.ptLeader or '';
        party.members  = party.members  or {};
        party.trusts   = party.trusts   or {};
    end
    -- Roles backfill.
    b.roles = b.roles or {};
    for _, k in ipairs({ 'melee', 'heal', 'nuke', 'rdm', 'brd', 'smn', 'stun', 'provoke', 'item' }) do
        b.roles[k] = b.roles[k] or {};
    end
    b.roles.tank = b.roles.tank or { '' };
    if type(b.roles.tank) ~= 'table' then b.roles.tank = { '' }; end

    -- SC array normalization. The editor authors b.sc (the server-canonical
    -- array). Migrate any legacy sc1/sc2 KEYS a prior editor version wrote
    -- (server never read them) into the array when the array is empty, then
    -- drop the dead keys so we never re-emit them.
    if type(b.sc) ~= 'table' then b.sc = {}; end
    if #b.sc == 0 then
        for _, key in ipairs({ 'sc1', 'sc2' }) do
            local p = b[key];
            if type(p) == 'table' and ((p.openName or '') ~= '' or (p.closeName or '') ~= '') then
                table.insert(b.sc, { openName = p.openName, openWS = p.openWS,
                                     closeName = p.closeName, closeWS = p.closeWS });
            end
        end
    end
    b.sc1 = nil;
    b.sc2 = nil;
    -- Backfill each pair's fields and give it a priority (editor order =
    -- priority); sort so display order matches the server's run order.
    for i, p in ipairs(b.sc) do
        p.openName  = p.openName  or '';
        p.openWS    = p.openWS    or '';
        p.closeName = p.closeName or '';
        p.closeWS   = p.closeWS   or '';
        if type(p.priority) ~= 'number' then p.priority = i; end
    end
    table.sort(b.sc, function(x, y) return x.priority < y.priority; end);

    -- Derive melee from legacy fields if empty (union of solo keys + SC names).
    if #b.roles.melee == 0 then
        local seen = {};
        local function maybe(name)
            if name and name ~= '' and not seen[name] then
                seen[name] = true;
                table.insert(b.roles.melee, name);
            end
        end
        if type(b.solo) == 'table' then
            for name, _ in pairs(b.solo) do maybe(name); end
        end
        for _, p in ipairs(b.sc) do
            maybe(p.openName);
            maybe(p.closeName);
        end
    end
    return b;
end

-- Authoritative PC pool: every charname in the server's `chars` table,
-- fetched via GET /chars (loopback HTTP). Single-player project — caller
-- controls the whole DB so this is the right source of truth. Already
-- sorted server-side. Falls back to the empty list while the HTTP fetch
-- is still in flight.
local function sorted_known_pcs()
    return autoutil.char_names or {};
end

-- Alliance-membership exclusion: a char can only be in one slot across all
-- parties (leader of one or member of one). Used by the Parties tab.
local function pcs_used_excluding(keep_value)
    local used = {};
    local function mark(name)
        if name and name ~= '' and name ~= keep_value then used[name] = true; end
    end
    if not state.body then return used; end
    for _, party in ipairs(state.body.alliance or {}) do
        mark(party.ptLeader);
        for _, m in ipairs(party.members or {}) do mark(m); end
    end
    return used;
end

-- Roster of every char currently in the alliance (leader or member of any
-- party). Sorted. Roles / Rotations / Flags dropdowns source from this rather
-- than the whole server, because role assignments only make sense for chars
-- who are actually in the alliance.
local function alliance_member_pool()
    if not state.body then return {}; end
    local seen = {};
    local out  = {};
    for _, party in ipairs(state.body.alliance or {}) do
        if party.ptLeader and party.ptLeader ~= '' and not seen[party.ptLeader] then
            seen[party.ptLeader] = true;
            table.insert(out, party.ptLeader);
        end
        for _, m in ipairs(party.members or {}) do
            if m and m ~= '' and not seen[m] then
                seen[m] = true;
                table.insert(out, m);
            end
        end
    end
    table.sort(out);
    return out;
end

-- Mutual-exclusion sets:
-- * roles_used: tank + melee + heal + nuke + rdm + brd + smn. A char can only
--   have one of these primary roles. Stun / Provoke / Item are separate
--   orthogonal selections (handled by their own picker pools, NOT exclusion).
local function roles_used(keep_value)
    local used = {};
    local function mark(name)
        if name and name ~= '' and name ~= keep_value then used[name] = true; end
    end
    if not state.body then return used; end
    if state.body.roles.tank and state.body.roles.tank[1] then
        mark(state.body.roles.tank[1]);
    end
    for _, k in ipairs({ 'melee', 'heal', 'nuke', 'rdm', 'brd', 'smn' }) do
        for _, n in ipairs(state.body.roles[k] or {}) do mark(n); end
    end
    return used;
end

-- Scan the ability resource manager once for WS names. Skip empties / non-WS.
local function ws_names()
    if state.ws_cache ~= nil then return state.ws_cache; end
    local res_mgr = AshitaCore:GetResourceManager();
    local out = {};
    local seen = {};
    for id = WS_ID_LO, WS_ID_HI do
        local ab = res_mgr:GetAbilityById(id);
        if ab and ab.Name and ab.Name[0] then
            local nm = clean_str(ab.Name[0]);
            -- 0x4 ability type is WS in classic FFXI ability table; some
            -- resource APIs expose Type instead. Filter loose — anything with
            -- a Recast0 of zero and non-empty name in this ID band is WS-ish.
            if nm ~= '' and not seen[nm] then
                seen[nm] = true;
                table.insert(out, nm);
            end
        end
    end
    table.sort(out);
    state.ws_cache = out;
    return out;
end

-- ============================================================
-- Generic picker popup (text filter + scrollable list)
-- ============================================================

-- Renders a popup for picking one value from a list. The popup ID is shared;
-- caller is expected to OpenPopup(popup_id) before calling this.
local function picker_popup(popup_id, title, options, used_set, filter_var, on_pick)
    if imgui.BeginPopup(popup_id) then
        imgui.Text(title);
        imgui.InputText('Filter##' .. popup_id, filter_var);
        local filter = imgui.GetVarValue(filter_var):lower();

        imgui.BeginChild('list##' .. popup_id, 260, 240, true);
        local count = 0;
        for _, nm in ipairs(options) do
            if not used_set[nm] and (filter == '' or nm:lower():find(filter, 1, true)) then
                if imgui.Selectable(nm) then
                    on_pick(nm);
                    imgui.CloseCurrentPopup();
                end
                count = count + 1;
                if count >= 200 then break; end
            end
        end
        if count == 0 then imgui.TextDisabled('(no matches)'); end
        imgui.EndChild();

        if imgui.Button('Cancel##' .. popup_id, 80, 0) then
            imgui.CloseCurrentPopup();
        end
        imgui.EndPopup();
    end
end

-- ============================================================
-- Common widgets
-- ============================================================

-- A "pick a PC name" button + popup. label is the imgui button text.
-- value: current selected name (string, empty for none). on_set(name): called
-- when user picks. keep_value: the current value (so picker doesn't exclude it).
local function pc_dropdown(id, current_value, on_set)
    local label = (current_value ~= nil and current_value ~= '') and current_value or '(none)';
    if imgui.Button(label .. '##' .. id, 160, 0) then
        state.pc_picker = { popup = 'pc_pick##pcp_' .. id, on_set = on_set, keep = current_value };
        if state.pc_filter then imgui.SetVarValue(state.pc_filter, ''); end
        imgui.OpenPopup(state.pc_picker.popup);
    end
    if state.pc_picker and state.pc_picker.popup == 'pc_pick##pcp_' .. id then
        local used = pcs_used_excluding(state.pc_picker.keep);
        picker_popup(state.pc_picker.popup, 'Pick a character', sorted_known_pcs(), used, state.pc_filter, function(name)
            state.pc_picker.on_set(name);
            state.pc_picker = nil;
        end);
    end
end

-- Trust dropdown — sourced from the spells the named party leader actually
-- has learned (server-side 0x18B with groupFilter=1). Per-party exclusion
-- only — the same trust can repeat across parties, just not within one.
-- leader_name="" disables the picker since trusts are leader-scoped.
local function trust_dropdown(id, leader_name, current_value, excluded_set, on_set)
    local label = (current_value ~= nil and current_value ~= '') and current_value or '(none)';
    local enabled = (leader_name ~= nil and leader_name ~= '');
    if not enabled then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    if imgui.Button(label .. '##' .. id, 200, 0) and enabled then
        -- Kick a fetch for this leader if we don't have one cached yet.
        local slot = autoutil.bot_spells[leader_name] and autoutil.bot_spells[leader_name][1];
        if slot == nil or not slot.final then
            autoutil.send_list_bot_spells(leader_name, 1);
        end
        state.trust_picker = {
            popup = 'trust_pick##trp_' .. id,
            on_set = on_set,
            excluded = excluded_set,
            leader = leader_name,
        };
        if state.trust_filter then imgui.SetVarValue(state.trust_filter, ''); end
        imgui.OpenPopup(state.trust_picker.popup);
    end
    if not enabled then imgui.PopStyleVar(); end
    if state.trust_picker and state.trust_picker.popup == 'trust_pick##trp_' .. id then
        local slot = autoutil.bot_spells[state.trust_picker.leader]
                 and autoutil.bot_spells[state.trust_picker.leader][1];
        local names = {};
        if slot and slot.entries then
            for _, e in ipairs(slot.entries) do table.insert(names, e.name); end
        end
        picker_popup(state.trust_picker.popup, 'Pick a trust', names,
            state.trust_picker.excluded, state.trust_filter, function(name)
                state.trust_picker.on_set(name);
                state.trust_picker = nil;
            end);
    end
end

-- WS dropdown — no exclusion.
local function ws_dropdown(id, current_value, on_set)
    local label = (current_value ~= nil and current_value ~= '') and current_value or '(none)';
    if imgui.Button(label .. '##ws_' .. id, 160, 0) then
        state.ws_picker = { popup = 'ws_pick##wsp_' .. id, on_set = on_set };
        if state.ws_filter then imgui.SetVarValue(state.ws_filter, ''); end
        imgui.OpenPopup(state.ws_picker.popup);
    end
    if state.ws_picker and state.ws_picker.popup == 'ws_pick##wsp_' .. id then
        picker_popup(state.ws_picker.popup, 'Pick a weapon skill', ws_names(), {}, state.ws_filter, function(name)
            state.ws_picker.on_set(name);
            state.ws_picker = nil;
        end);
    end
end

-- Multi-select PC dropdown list: renders existing values with [-] buttons and a
-- trailing empty dropdown for adding. exclusion_provider is a function called
-- per-row to get the "used elsewhere" set; pass-through to pc_dropdown.
local function pc_multi_select(id, value_list)
    for i, name in ipairs(value_list) do
        local row_id = id .. '_' .. i;
        pc_dropdown(row_id, name, function(picked) value_list[i] = picked; end);
        imgui.SameLine();
        if imgui.Button('-##rm_' .. row_id, 22, 0) then
            table.remove(value_list, i);
            return;  -- mutation invalidates index; redraw next frame
        end
    end
    -- Trailing empty row for adding more.
    pc_dropdown(id .. '_add', '', function(picked)
        table.insert(value_list, picked);
    end);
end

-- ============================================================
-- Tab: Parties
-- ============================================================

local function render_parties_tab()
    -- Two parties per row (BeginGroup + SameLine): Pt1|Pt2 on row 1, Pt3 on
    -- row 2. Each party is ~262 wide (indent + 200 dropdown + 22 rm); two fit
    -- inside the 600-wide editor child.
    local function render_one_party(i, party)
        imgui.BeginGroup();
        imgui.Text(string.format('Party %d', i));
        imgui.Spacing();

        -- Leader.
        imgui.Text('  Leader:');
        imgui.SameLine();
        pc_dropdown('p' .. i .. '_leader', party.ptLeader, function(picked)
            party.ptLeader = picked;
        end);
        if party.ptLeader and party.ptLeader ~= '' then
            imgui.SameLine();
            if imgui.Button('-##p' .. i .. '_leader_rm', 22, 0) then party.ptLeader = ''; end
        end

        -- Members (multi-select).
        imgui.Text('  Members:');
        imgui.Indent(40);
        pc_multi_select('p' .. i .. '_mem', party.members);
        imgui.Unindent(40);

        -- Trusts (multi-select with within-party exclusion).
        imgui.Text('  Trusts:');
        imgui.Indent(40);
        local within_party = {};
        for _, t in ipairs(party.trusts) do within_party[t] = true; end
        -- Deferred removal: never `return` mid-render here — we're inside a
        -- BeginGroup and skipping EndGroup would corrupt the imgui stack.
        local remove_ti = nil;
        for ti, t in ipairs(party.trusts) do
            local excl = {};
            for k, v in pairs(within_party) do
                if k ~= t then excl[k] = v; end
            end
            trust_dropdown('p' .. i .. '_t_' .. ti, party.ptLeader, t, excl, function(picked)
                party.trusts[ti] = picked;
            end);
            imgui.SameLine();
            if imgui.Button('-##p' .. i .. '_trm_' .. ti, 22, 0) then
                remove_ti = ti;
            end
        end
        -- Trailing add row.
        trust_dropdown('p' .. i .. '_t_add', party.ptLeader, '', within_party, function(picked)
            table.insert(party.trusts, picked);
        end);
        imgui.Unindent(40);
        imgui.EndGroup();

        if remove_ti then table.remove(party.trusts, remove_ti); end
    end

    for i, party in ipairs(state.body.alliance) do
        render_one_party(i, party);
        if i % 2 == 1 and i < #state.body.alliance then
            imgui.SameLine(0, 30); -- pair this party with the next on the same row
        else
            imgui.Dummy(0, 6);
            imgui.Separator();
            imgui.Dummy(0, 6);
        end
    end

    -- Add party button (max 3).
    if #state.body.alliance < 3 then
        if imgui.Button('+ Add party', 160, 0) then
            table.insert(state.body.alliance, { ptLeader = '', members = {}, trusts = {} });
        end
    end
    -- Remove last party.
    if #state.body.alliance > 1 then
        imgui.SameLine();
        if imgui.Button('Remove last party', 160, 0) then
            state.body.alliance[#state.body.alliance] = nil;
        end
    end
end

-- ============================================================
-- Tab: Roles
-- ============================================================

-- A multi-select dropdown that pulls from PCs only, with role-level exclusion.
local function role_multi_select(id, value_list)
    for i, name in ipairs(value_list) do
        local row_id = id .. '_' .. i;
        local current = name;
        if imgui.Button(((current ~= '' and current) or '(none)') .. '##' .. row_id, 200, 0) then
            state.pc_picker = {
                popup = 'pc_pick##rolep_' .. row_id,
                on_set = function(picked) value_list[i] = picked; end,
                keep   = current,
                role   = true,
            };
            if state.pc_filter then imgui.SetVarValue(state.pc_filter, ''); end
            imgui.OpenPopup(state.pc_picker.popup);
        end
        if state.pc_picker and state.pc_picker.popup == 'pc_pick##rolep_' .. row_id then
            local used = roles_used(state.pc_picker.keep);
            picker_popup(state.pc_picker.popup, 'Pick a character', alliance_member_pool(), used, state.pc_filter,
                function(picked)
                    state.pc_picker.on_set(picked);
                    state.pc_picker = nil;
                end);
        end
        imgui.SameLine();
        if imgui.Button('-##rrm_' .. row_id, 22, 0) then
            table.remove(value_list, i);
            return;
        end
    end
    -- Trailing add.
    local add_id = id .. '_add';
    if imgui.Button('(add)##' .. add_id, 200, 0) then
        state.pc_picker = {
            popup = 'pc_pick##rolep_' .. add_id,
            on_set = function(picked) table.insert(value_list, picked); end,
            keep   = '',
            role   = true,
        };
        if state.pc_filter then imgui.SetVarValue(state.pc_filter, ''); end
        imgui.OpenPopup(state.pc_picker.popup);
    end
    if state.pc_picker and state.pc_picker.popup == 'pc_pick##rolep_' .. add_id then
        local used = roles_used('');
        picker_popup(state.pc_picker.popup, 'Pick a character', alliance_member_pool(), used, state.pc_filter,
            function(picked)
                state.pc_picker.on_set(picked);
                state.pc_picker = nil;
            end);
    end
end

-- Single-pick role dropdown (Tank). Sources from the alliance roster, excludes
-- chars already used in another primary role.
local function tank_dropdown(id, current_value, on_set)
    local label = (current_value ~= nil and current_value ~= '') and current_value or '(none)';
    if imgui.Button(label .. '##trank_' .. id, 200, 0) then
        state.pc_picker = { popup = 'pc_pick##tankp_' .. id, on_set = on_set, keep = current_value };
        if state.pc_filter then imgui.SetVarValue(state.pc_filter, ''); end
        imgui.OpenPopup(state.pc_picker.popup);
    end
    if state.pc_picker and state.pc_picker.popup == 'pc_pick##tankp_' .. id then
        local used = roles_used(current_value);
        picker_popup(state.pc_picker.popup, 'Pick a character', alliance_member_pool(), used, state.pc_filter,
            function(picked)
                state.pc_picker.on_set(picked);
                state.pc_picker = nil;
            end);
    end
end

local function render_roles_tab()
    -- Two columns via BeginGroup/SameLine (imgui.Columns isn't used anywhere in
    -- this addon set; groups are the proven pattern). The editor child is 600
    -- wide, ~290 per column — comfortably fits the 200-wide role buttons.
    -- Left: Tank, Melee, Heal, Rdm.  Right: Nuke, Brd, Smn. Sections separate
    -- with a Dummy gap rather than Separator so the rule doesn't span across
    -- into the other column.
    local function role_section(label, key)
        imgui.Text(label);
        imgui.Spacing();
        imgui.Indent(20);
        role_multi_select(key, state.body.roles[key]);
        imgui.Unindent(20);
        imgui.Dummy(0, 8);
    end

    imgui.BeginGroup();
        -- Tank — the assist target; single-pick. WS goes via the Solo/SC tab.
        imgui.Text('Tank');
        imgui.Spacing();
        tank_dropdown('tank_char', state.body.roles.tank[1] or '', function(picked)
            state.body.roles.tank[1] = picked;
        end);
        if (state.body.roles.tank[1] or '') ~= '' then
            imgui.SameLine();
            if imgui.Button('-##tank_rm', 22, 0) then state.body.roles.tank[1] = ''; end
        end
        imgui.Dummy(0, 8);
        role_section('Melee', 'melee');
        role_section('Heal',  'heal');
        role_section('Rdm',   'rdm');
    imgui.EndGroup();

    imgui.SameLine(0, 24);

    imgui.BeginGroup();
        role_section('Nuke', 'nuke');
        role_section('Brd',  'brd');
        role_section('Smn',  'smn');
    imgui.EndGroup();
end

-- ============================================================
-- Tab: Skillchains
-- ============================================================

-- Names currently assigned to SC1 or SC2 (any of 4 slots).
local function sc_assigned_set()
    local s = {};
    for _, p in ipairs(state.body.sc or {}) do
        if (p.openName  or '') ~= '' then s[p.openName]  = true; end
        if (p.closeName or '') ~= '' then s[p.closeName] = true; end
    end
    return s;
end

-- A name dropdown sourced from Melee pool minus SC-assigned, keeping current.
local function sc_dropdown(id, current_value, on_set)
    local label = (current_value ~= nil and current_value ~= '') and current_value or '(none)';
    if imgui.Button(label .. '##scd_' .. id, 160, 0) then
        state.pc_picker = {
            popup = 'pc_pick##scdp_' .. id,
            on_set = on_set,
            keep   = current_value,
            sc     = true,
        };
        if state.pc_filter then imgui.SetVarValue(state.pc_filter, ''); end
        imgui.OpenPopup(state.pc_picker.popup);
    end
    if state.pc_picker and state.pc_picker.popup == 'pc_pick##scdp_' .. id then
        -- Source = Melee role list. Exclude already-assigned SC slots (other than this row's current).
        local options = {};
        for _, n in ipairs(state.body.roles.melee or {}) do
            if n and n ~= '' then table.insert(options, n); end
        end
        table.sort(options);
        local used = sc_assigned_set();
        if state.pc_picker.keep then used[state.pc_picker.keep] = nil; end
        picker_popup(state.pc_picker.popup, 'Pick from Melee', options, used, state.pc_filter,
            function(picked)
                state.pc_picker.on_set(picked);
                state.pc_picker = nil;
            end);
    end
end

local function render_skillchains_tab()
    state.body.sc = state.body.sc or {};

    -- One section per SC pair, in order (order = priority on save). An X to
    -- the LEFT of the "SCn" label removes that pair; a button below adds one.
    for i, pair in ipairs(state.body.sc) do
        if imgui.Button('X##sc_rm_' .. i, 22, 0) then
            table.remove(state.body.sc, i);
            return; -- list mutated mid-iteration; restart next frame
        end
        imgui.SameLine();
        imgui.Text(string.format('SC%d', i));
        imgui.Spacing();

        -- Opener on its own row. The trailing "-" clear button's SameLine is
        -- guarded inside the if so an empty pair doesn't drag the Closer row
        -- up onto this line.
        imgui.Text('  Opener:');
        imgui.SameLine();
        sc_dropdown('sc' .. i .. '_open_name', pair.openName, function(picked) pair.openName = picked; end);
        imgui.SameLine();
        ws_dropdown('sc' .. i .. '_open_ws', pair.openWS, function(picked) pair.openWS = picked; end);
        if pair.openName ~= '' or pair.openWS ~= '' then
            imgui.SameLine();
            if imgui.Button('-##sc' .. i .. '_open_rm', 22, 0) then
                pair.openName = ''; pair.openWS = '';
            end
        end

        -- Closer on its own row.
        imgui.Text('  Closer:');
        imgui.SameLine();
        sc_dropdown('sc' .. i .. '_close_name', pair.closeName, function(picked) pair.closeName = picked; end);
        imgui.SameLine();
        ws_dropdown('sc' .. i .. '_close_ws', pair.closeWS, function(picked) pair.closeWS = picked; end);
        if pair.closeName ~= '' or pair.closeWS ~= '' then
            imgui.SameLine();
            if imgui.Button('-##sc' .. i .. '_close_rm', 22, 0) then
                pair.closeName = ''; pair.closeWS = '';
            end
        end

        imgui.Spacing();
        imgui.Separator();
    end

    if imgui.Button('+ Add skillchain', 160, 0) then
        table.insert(state.body.sc, { openName = '', openWS = '', closeName = '', closeWS = '' });
    end

    imgui.Spacing();
    imgui.Separator();

    -- Solo derived from Melee minus SC-assigned. Each row gets a WS dropdown,
    -- mutating state.body.solo[name].
    imgui.Text('Solo');
    imgui.TextDisabled('(Melee chars not used in SC; pick a WS for each)');
    imgui.Spacing();

    local assigned = sc_assigned_set();
    local any = false;
    for _, name in ipairs(state.body.roles.melee or {}) do
        if name ~= '' and not assigned[name] then
            any = true;
            imgui.Text(' ' .. name);
            imgui.SameLine(140);
            local current_ws = (state.body.solo and state.body.solo[name]) or '';
            ws_dropdown('solo_ws_' .. name, current_ws, function(picked)
                state.body.solo = state.body.solo or {};
                state.body.solo[name] = picked;
            end);
            -- Guard the SameLine inside the if: when a solo char has no WS yet
            -- an unconditional SameLine would pull the NEXT name onto this row
            -- (the "names stacked to the right" bug).
            if current_ws ~= '' then
                imgui.SameLine();
                if imgui.Button('-##solo_rm_' .. name, 22, 0) then
                    state.body.solo[name] = nil;
                end
            end
        end
    end
    if not any then imgui.TextDisabled('  (no melee chars available - pick some in Roles tab)'); end

    -- Drop solo[k] entries whose name is no longer in melee or got assigned to
    -- SC; we re-compute on Save anyway, but this keeps the in-memory shape tidy.
    if state.body.solo then
        for name, _ in pairs(state.body.solo) do
            local stillMelee = false;
            for _, m in ipairs(state.body.roles.melee or {}) do
                if m == name then stillMelee = true; break; end
            end
            if (not stillMelee) or assigned[name] then state.body.solo[name] = nil; end
        end
    end
end

-- ============================================================
-- Public API
-- ============================================================

local function close_modal()
    state.open = false;
    if state.pc_filter    then imgui.DeleteVar(state.pc_filter);    state.pc_filter    = nil; end
    if state.trust_filter then imgui.DeleteVar(state.trust_filter); state.trust_filter = nil; end
    if state.ws_filter    then imgui.DeleteVar(state.ws_filter);    state.ws_filter    = nil; end
    state.ws_cache = nil;
end

function alliance_tab.open(configName)
    state.open        = true;
    state.needs_open  = true;
    state.needs_close = false;
    state.config_name = configName;
    state.tab         = 'parties';
    state.body        = nil;
    state.error       = '';
    -- Delete-before-create: if the modal was dismissed via ESC / click-away
    -- (which bypasses close_modal), these three CDSTRING vars are still live.
    -- CreateVar-ing over them orphans the old handles in the native ImGuiVar
    -- registry; repeated open cycles accumulate orphans and eventually crash
    -- the client (the registry corrupts). Mirror food_tab.open()'s guard so
    -- every reopen reclaims whatever the last session left behind.
    if state.pc_filter    then imgui.DeleteVar(state.pc_filter);    end
    if state.trust_filter then imgui.DeleteVar(state.trust_filter); end
    if state.ws_filter    then imgui.DeleteVar(state.ws_filter);    end
    state.pc_filter    = imgui.CreateVar(ImGuiVar_CDSTRING, 64);
    state.trust_filter = imgui.CreateVar(ImGuiVar_CDSTRING, 64);
    state.ws_filter    = imgui.CreateVar(ImGuiVar_CDSTRING, 64);
    imgui.SetVarValue(state.pc_filter, '');
    imgui.SetVarValue(state.trust_filter, '');
    imgui.SetVarValue(state.ws_filter, '');

    -- Seed with the default body so the editor renders immediately while
    -- the fetch is in flight; overwrite when the response lands.
    state.body = normalize_body(default_body());
    local http = require('http_client');
    http.get('/configs/alliance/' .. configName, function(code, body, _, err)
        -- User might have closed the modal or switched configs by the
        -- time the response arrives — drop the result if so.
        if state.config_name ~= configName then return; end
        if code == 200 and body and body ~= '' then
            local ok, parsed = pcall(json.decode, json, body);
            state.body = normalize_body(ok and parsed or default_body());
        elseif code == nil then
            autoutil.log('AutoBots', string.format('alliance fetch %s: %s', configName, tostring(err)));
        elseif code ~= 200 and code ~= 404 then
            autoutil.log('AutoBots', string.format('alliance fetch %s: HTTP %s', configName, tostring(code)));
        end
    end);

    -- Auth pools. Cached at autoutil — only fire requests if we don't have a
    -- final response yet for this session.
    if not autoutil.char_names_final  then autoutil.fetch_chars();      end
    -- Trust spell list is now per-leader; fetched lazily by trust_dropdown
    -- the first time the user opens a picker for a given ptLeader.
end

local function build_save_body()
    -- Strip empties from members/trusts arrays, drop empty parties, normalize
    -- solo to a clean { name = ws } map.
    local out = deep_copy(state.body);
    for _, party in ipairs(out.alliance) do
        local mem = {};
        for _, m in ipairs(party.members or {}) do if m and m ~= '' then table.insert(mem, m); end end
        party.members = mem;
        local tr = {};
        for _, t in ipairs(party.trusts or {}) do if t and t ~= '' then table.insert(tr, t); end end
        party.trusts = tr;
    end
    -- Roles cleanup.
    for _, k in ipairs({ 'melee', 'heal', 'nuke', 'rdm', 'brd', 'smn', 'stun', 'provoke', 'item' }) do
        local clean = {};
        for _, n in ipairs(out.roles[k] or {}) do if n and n ~= '' then table.insert(clean, n); end end
        out.roles[k] = clean;
    end
    -- SC array: drop fully-empty pairs and stamp priority = editor order, so
    -- the server (bots_spawn.lua ipairs over cfg.sc) runs them in that order.
    local sc_out = {};
    for _, p in ipairs(out.sc or {}) do
        if (p.openName or '') ~= '' or (p.closeName or '') ~= '' then
            table.insert(sc_out, {
                priority  = #sc_out + 1,
                openName  = p.openName  or '',
                openWS    = p.openWS    or '',
                closeName = p.closeName or '',
                closeWS   = p.closeWS   or '',
            });
        end
    end
    out.sc = sc_out;
    -- Solo recomputation: Melee minus SC slots, preserve existing WS choices.
    local assigned = {};
    for _, p in ipairs(out.sc) do
        if p.openName  ~= '' then assigned[p.openName]  = true; end
        if p.closeName ~= '' then assigned[p.closeName] = true; end
    end
    local solo_out = {};
    for _, m in ipairs(out.roles.melee) do
        if not assigned[m] and (out.solo or {})[m] then
            solo_out[m] = out.solo[m];
        end
    end
    out.solo = solo_out;
    return json:encode(out);
end

function alliance_tab.render()
    if not state.open then return; end
    local popup_id = 'alliance_editor##ae_popup';
    if state.needs_open then
        imgui.OpenPopup(popup_id);
        state.needs_open = false;
    end

    imgui.SetNextWindowSize(620, 540, ImGuiSetCond_FirstUseEver);
    if imgui.BeginPopupModal(popup_id, nil, ImGuiWindowFlags_AlwaysAutoResize) then
        if state.needs_close then
            state.needs_close = false;
            close_modal();
            imgui.CloseCurrentPopup();
            imgui.EndPopup();
            return;
        end

        imgui.Text('Edit Alliance Config: "' .. tostring(state.config_name) .. '"');
        imgui.Dummy(0, 6);

        -- Tab buttons.
        local function tab_button(label, key)
            local active = (state.tab == key);
            if active then imgui.PushStyleColor(ImGuiCol_Button, 0.26, 0.59, 0.98, 1.0); end
            if imgui.Button(label .. '##fe_tab_' .. key, 110, 0) then state.tab = key; end
            if active then imgui.PopStyleColor(); end
        end
        tab_button('Parties',     'parties');     imgui.SameLine();
        tab_button('Roles',       'roles');       imgui.SameLine();
        tab_button('Skillchains', 'skillchains');

        imgui.Separator();
        imgui.Dummy(0, 4);

        if state.error ~= '' then
            imgui.TextColored(1.0, 0.4, 0.4, 1.0, state.error);
            imgui.Dummy(0, 4);
        end

        -- Tab content. Body might still be in-flight from the 0x17F fetch.
        imgui.BeginChild('##ae_tab_body', 600, 380, true);
        if state.body == nil then
            imgui.TextDisabled('Loading config…');
        elseif state.tab == 'parties' then
            render_parties_tab();
        elseif state.tab == 'roles' then
            render_roles_tab();
        elseif state.tab == 'skillchains' then
            render_skillchains_tab();
        end
        imgui.EndChild();

        imgui.Dummy(0, 4);
        imgui.Separator();
        imgui.Dummy(0, 4);

        -- Persistent action bar.
        local save_disabled = (state.body == nil);
        if save_disabled then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
        if imgui.Button('Save##ae_save', 90, 0) and not save_disabled then
            local body    = build_save_body();
            local cfgName = state.config_name;
            local http    = require('http_client');
            http.put('/configs/alliance/' .. cfgName, body, 'application/json', function(code, _, _, err)
                if state.config_name ~= cfgName then return; end
                if code == 200 or code == 201 then
                    state.needs_close = true;
                elseif code == nil then
                    state.error = string.format('Save failed: %s', tostring(err));
                else
                    state.error = string.format('Save failed (HTTP %s)', tostring(code));
                end
            end);
        end
        if save_disabled then imgui.PopStyleVar(); end
        imgui.SameLine();
        if imgui.Button('Cancel##ae_cancel', 90, 0) then
            close_modal();
            imgui.CloseCurrentPopup();
        end

        imgui.EndPopup();
    end
end

return alliance_tab;
