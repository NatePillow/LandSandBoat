-- AutoSkill tab — folded in from the former standalone AutoSkill addon.
-- Drives the server-side autoskill override (0x191) per alliance member:
-- three-state mode (Off / RA / Magic), and when Magic, a multi-select
-- spell list fed by 0x18B/0x18C (groupFilter=0) showing only spells
-- that specific bot has actually learned.
--
-- Why this is a tab now: the slash-command-and-window pattern made sense
-- when the addon was new, but the overlap with autobots (same roster,
-- same packet path, same overall purpose: drive bot behaviour) wasn't
-- enough to justify a separate window. autobots already routes 0x192
-- through autoutil.check_for_autoskill_state, so we just register a
-- callback here for row mirroring.
--
-- Wire-side packet handling is unchanged: 0x191 sends, 0x192 receives,
-- 0x193 list-request, 0x18B/0x18C for the magic spell roster — all in
-- autoutil.

require 'imguidef';

local autoutil = require('autoutil');

local M = {};

local MODE = { OFF = 0, RA = 1, MAGIC = 2 };
local MODE_LABEL = { [0] = 'Off', [1] = 'RA', [2] = 'Magic' };
local MAX_SPELLS_PER_BOT = 16;

-- Per-char working state. rows[name] = { mode, spells = {ids...} }
local rows = {};

-- ImGuiVar for the spell-picker filter text. Lazy-created in on_load.
local spell_filter = nil;

-- Bot name whose magic spell picker is currently open (nil = none).
local picker_for = nil;

-- Set true on first M.render() so refresh_roster() fires once when the user
-- first opens the tab. Reset to true by on_load so /addon reload re-arms it.
local first_render = true;

-- ============================================================
-- Outgoing packet helpers
-- ============================================================

local function get_row(name)
    if rows[name] == nil then rows[name] = { mode = MODE.OFF, spells = {} } end
    return rows[name];
end

local function send_set_autoskill(name, mode, spellIds)
    -- 56-byte packet: 4 header + 16 BotName + 1 Mode + 1 SpellCount + 2 Pad
    --                 + 32 SpellIds(16xu16)
    local bytes = {};
    for i = 1, 56 do bytes[i] = 0; end
    bytes[1] = 0x91; bytes[2] = 0x01;  -- opcode 0x191 LE

    local nm = (name or ''):sub(1, 15);
    for i = 1, #nm do bytes[4 + i] = nm:byte(i); end

    bytes[21] = mode or 0;
    local count = math.min(spellIds and #spellIds or 0, MAX_SPELLS_PER_BOT);
    bytes[22] = count;
    for i = 1, count do
        local id = spellIds[i] or 0;
        local off = 24 + (i - 1) * 2;
        bytes[off + 1] = id % 256;
        bytes[off + 2] = math.floor(id / 256) % 256;
    end
    AddOutgoingPacket(0x191, bytes);
end

local function commit(name)
    local r = get_row(name);
    send_set_autoskill(name, r.mode, r.spells);
end

-- ============================================================
-- Roster — primary + every sessioned alliance PC
-- ============================================================

local function roster()
    local out = {};
    local seen = {};
    local party = AshitaCore:GetDataManager():GetParty();
    local primary_name = party and party:GetMemberName(0) or '';
    if primary_name ~= '' then
        local jobIdx = party:GetMemberMainJob(0) or 0;
        table.insert(out, { name = primary_name, job = autoutil.jobs[jobIdx] or '?' });
        seen[primary_name] = true;
    end
    for _, m in ipairs(autoutil.alliance_pcs or {}) do
        if not seen[m.name] then
            local mj = autoutil.char_jobs and autoutil.char_jobs[m.name] or 0;
            table.insert(out, { name = m.name, job = autoutil.jobs[mj] or '?' });
            seen[m.name] = true;
        end
    end
    return out;
end

function M.refresh_roster()
    autoutil.send_list_alliance_pcs();
    if not autoutil.char_names_final then autoutil.fetch_chars(); end
    autoutil.send_list_autoskill();
end

-- ============================================================
-- Spell picker
-- ============================================================

local function known_magic_spells_for(name)
    local slot = autoutil.bot_spells[name] and autoutil.bot_spells[name][0];
    if slot == nil then return nil; end
    return slot.entries or {};
end

local function ensure_spells_fetched(name)
    local slot = autoutil.bot_spells[name] and autoutil.bot_spells[name][0];
    if slot == nil or not slot.final then
        autoutil.send_list_bot_spells(name, 0);
    end
end

local function find_spell_name(name, id)
    local entries = known_magic_spells_for(name) or {};
    for _, e in ipairs(entries) do
        if e.id == id then return e.name; end
    end
    return string.format('spell #%d', id);
end

local function render_spell_row(name)
    local r = get_row(name);
    for i, id in ipairs(r.spells) do
        local label = find_spell_name(name, id) .. '##sk_' .. name .. '_' .. i;
        imgui.Button(label, 140, 0);
        imgui.SameLine();
        if imgui.Button('-##skrm_' .. name .. '_' .. i, 22, 0) then
            table.remove(r.spells, i);
            commit(name);
            return;
        end
        if (i % 3) == 0 and i < #r.spells then imgui.Dummy(0, 0); end
    end
    if #r.spells < MAX_SPELLS_PER_BOT then
        if imgui.Button('+ add##skadd_' .. name, 80, 0) then
            picker_for = name;
            ensure_spells_fetched(name);
            if spell_filter then imgui.SetVarValue(spell_filter, ''); end
            imgui.OpenPopup('spell_pick##sk_popup');
        end
    end
end

local function render_spell_picker()
    if picker_for == nil then return; end
    if imgui.BeginPopup('spell_pick##sk_popup') then
        imgui.Text('Pick a spell for ' .. picker_for);
        imgui.InputText('Filter##sk_filter', spell_filter);
        local f = imgui.GetVarValue(spell_filter):lower();
        local entries = known_magic_spells_for(picker_for);
        if entries == nil then
            imgui.TextDisabled('(loading spells...)');
        elseif #entries == 0 then
            imgui.TextDisabled('(no magic spells learned)');
        else
            local r = get_row(picker_for);
            local used = {};
            for _, id in ipairs(r.spells) do used[id] = true; end
            imgui.BeginChild('list##sk_list', 280, 240, true);
            local count = 0;
            for _, e in ipairs(entries) do
                if not used[e.id] and (f == '' or e.name:lower():find(f, 1, true)) then
                    if imgui.Selectable(e.name) then
                        table.insert(r.spells, e.id);
                        commit(picker_for);
                        picker_for = nil;
                        imgui.CloseCurrentPopup();
                    end
                    count = count + 1;
                end
            end
            if count == 0 then imgui.TextDisabled('(no matches)'); end
            imgui.EndChild();
        end
        if imgui.Button('Cancel##sk_cancel', 80, 0) then
            picker_for = nil;
            imgui.CloseCurrentPopup();
        end
        imgui.EndPopup();
    else
        picker_for = nil;
    end
end

-- ============================================================
-- Per-row mode radio
-- ============================================================

local function render_mode_radio(name)
    local r = get_row(name);
    for _, opt in ipairs({ MODE.OFF, MODE.RA, MODE.MAGIC }) do
        local label = MODE_LABEL[opt];
        local is_active = (r.mode == opt);
        if is_active then imgui.PushStyleColor(ImGuiCol_Button, 0.26, 0.59, 0.98, 1.0); end
        if imgui.Button(label .. '##sk_' .. name .. '_m' .. opt, 60, 0) then
            r.mode = opt;
            if opt == MODE.OFF then r.spells = {}; end
            commit(name);
            if opt == MODE.MAGIC then ensure_spells_fetched(name); end
        end
        if is_active then imgui.PopStyleColor(); end
        imgui.SameLine();
    end
    imgui.NewLine();
end

-- ============================================================
-- Public API
-- ============================================================

function M.on_load()
    spell_filter = imgui.CreateVar(ImGuiVar_CDSTRING, 64);
    imgui.SetVarValue(spell_filter, '');
    first_render = true;
    -- Mirror 0x192 receipts into the local row table so the radio stays
    -- consistent across despawn / server-side auto-clears. Off mode also
    -- clears the spells list since the server forgets them.
    autoutil.on_autoskill_state(function(name, mode)
        if name == nil or name == '' then return; end
        local r = rows[name] or { mode = 0, spells = {} };
        r.mode = mode;
        if mode == 0 then r.spells = {}; end
        rows[name] = r;
    end);
end

function M.on_unload()
    if spell_filter ~= nil then imgui.DeleteVar(spell_filter); spell_filter = nil; end
end

function M.render()
    if first_render and autoutil.unlocked then
        M.refresh_roster();
        first_render = false;
    end
    -- Bare imgui.Separator() spans the WHOLE window content region, which
    -- bleeds across the autobots tab's left/right column divider. Clip
    -- the rule to the left column's width (304px, matching the rest of
    -- the autobots tab's section_label / left_sep convention). left_x is
    -- captured once at render entry so the clip stays at the left
    -- column's x even after Indent / Unindent push the cursor around.
    local left_x = imgui.GetCursorScreenPos();
    local LEFT_COL_W = 304;
    local function clipped_sep()
        local wx, wy = imgui.GetWindowPos();
        local wh     = imgui.GetWindowHeight();
        imgui.PushClipRect(left_x, wy, left_x + LEFT_COL_W, wy + wh, true);
        imgui.Separator();
        imgui.PopClipRect();
    end
    if imgui.Button('Refresh roster##sk_refresh', 130, 0) then M.refresh_roster(); end
    imgui.SameLine();
    if imgui.Button('All Off##sk_all_off', 80, 0) then
        for _, m in ipairs(roster()) do
            local r = get_row(m.name);
            if r.mode ~= MODE.OFF then
                r.mode = MODE.OFF;
                r.spells = {};
                commit(m.name);
            end
        end
    end
    clipped_sep();
    imgui.Dummy(0, 4);

    local list = roster();
    if #list == 0 then
        imgui.TextDisabled('(no roster yet - try Refresh)');
    else
        for _, m in ipairs(list) do
            imgui.Text(string.format('%s (%s)', m.name, m.job));
            imgui.Indent(16);
            render_mode_radio(m.name);
            if get_row(m.name).mode == MODE.MAGIC then
                imgui.Text('Spells:');
                imgui.SameLine();
                render_spell_row(m.name);
            end
            imgui.Unindent(16);
            clipped_sep();
        end
    end

    render_spell_picker();
end

-- /autobots stop-equivalent for autoskill. Called when the user types
-- `/autobots autoskill off` or wants a global kill switch.
function M.all_off()
    for _, m in ipairs(roster()) do
        local r = get_row(m.name);
        if r.mode ~= MODE.OFF then
            r.mode = MODE.OFF;
            r.spells = {};
            commit(m.name);
        end
    end
end

return M;
