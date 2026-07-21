-- ============================================================
-- automog Status tab (extracted from automog.lua, verbatim).
-- Per-char profile view + the shared inventory right column
-- (gil / sort / delivery / scrolls / change-job / change-look).
-- ============================================================

local M = {};

local C                  = require('automog_common');
local state              = require('automog_state');
local autoutil           = require('autoutil');
local char_profile_cache = require('char_profile_cache');
local icon_cache         = require('icon_cache');
local autobox            = require('autobox');
local autoscroll         = require('autoscroll');
local autobuy            = require('autobuy');

local function draw_delivery_row()
    local box = autobox.state;
    local w = imgui.GetWindowWidth();
    local btn_w = 80;
    imgui.SetCursorPosX((w - 84) / 2);
    autoutil.section_head('Delivery Box');
    imgui.Spacing();
    imgui.SetCursorPosX((w - btn_w * 2 - 4) / 2);
    if imgui.Button('Retrieve##box', btn_w, 0) then autobox.retrieve(state.selected_char); end
    imgui.SameLine(0, 4);
    if not box.active then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    if imgui.Button('Stop##box', btn_w, 0) and box.active then
        autobox.state.active = false;
        autobox.state.status = 'Idle';
    end
    if not box.active then imgui.PopStyleVar(); end
end

-- task #124: AutoMog Change-Job section state. Staged values stash the
-- user's in-flight cycle picks per char so flipping between bots in the
-- selector doesn't lose what was about to be applied.
local inv_job_staged_mj = {};  -- [char] = jobId user cycled to
local inv_job_staged_sj = {};  -- [char] = jobId user cycled to
local inv_job_last_char = nil; -- detect state.selected_char edges to reset staging

local inv_look_staged_race = {};  -- [char] = race (1-8) user cycled to
local inv_look_staged_face = {};  -- [char] = face (0-15) user cycled to
local inv_look_staged_size = {};  -- [char] = size (0-2) user cycled to

-- Cycle ordered list of (jobId, levelLabel) tuples for the given mask + levels.
-- Jobs with bit set in mask AND level >= 1 are eligible.
local function available_jobs_list(info)
    local out = {};
    if info == nil then return out; end
    for jobId = 1, 22 do
        local bit_set = math.floor(info.unlocked_mask / (2 ^ jobId)) % 2 == 1;
        local lvl     = info.levels[jobId] or 0;
        if bit_set and lvl >= 1 then
            table.insert(out, { id = jobId, lvl = lvl });
        end
    end
    return out;
end

local function find_index(list, jobId)
    for i, entry in ipairs(list) do
        if entry.id == jobId then return i; end
    end
    return nil;
end

local function job_abbrev(jobId)
    return autoutil.jobs[jobId] or '?';
end

local function draw_change_job_row()
    local char = state.selected_char;
    if char == nil or char == '' then return; end

    -- Reset staging on char change.
    if inv_job_last_char ~= char then
        inv_job_last_char    = char;
    end

    -- Center the section header inside the available content region.
    local function header_centered()
        local w = imgui.GetContentRegionAvailWidth();
        imgui.SetCursorPosX(math.max(0, (w - C.calc_text_w('Change Job')) / 2));
        autoutil.section_head('Change Job');
    end

    local info = autoutil.char_job_info[char];
    if info == nil then
        header_centered();
        imgui.Dummy(0, 4);
        imgui.TextDisabled('(fetching jobs...)');
        return;
    end

    local available = available_jobs_list(info);
    if #available == 0 then
        header_centered();
        imgui.Dummy(0, 4);
        imgui.TextDisabled('(no unlocked jobs)');
        return;
    end

    local staged_mj = inv_job_staged_mj[char] or info.current_mj;
    local staged_sj = inv_job_staged_sj[char] or info.current_sj;

    -- Cycle helper: step the staged value to prev/next in the available list,
    -- wrapping around. If the current staged isn't in the list (rare —
    -- something got unlocked then re-locked?) start at index 1.
    local function cycle(staged, dir)
        local idx = find_index(available, staged) or 1;
        idx       = ((idx - 1 + dir) % #available) + 1;
        return available[idx].id;
    end

    local w           = imgui.GetContentRegionAvailWidth();
    local arrow_w     = 24;
    local center_w    = 80;
    -- Use the wider of the two row labels so MJ + SJ rows share a left edge.
    local mj_lbl      = 'Main Job:';
    local sj_lbl      = 'Sub Job:';
    local label_w     = math.max(C.calc_text_w(mj_lbl), C.calc_text_w(sj_lbl));
    local item_gap    = 4;
    local row_w       = label_w + item_gap + arrow_w + item_gap + center_w + item_gap + arrow_w;
    local label_x_off = math.max(0, (w - row_w) / 2);

    local function picker_popup(name, staged_var_field, current_val)
        if imgui.BeginPopup(name) then
            for _, entry in ipairs(available) do
                local lbl = string.format('%s  (Lv %d)', job_abbrev(entry.id), entry.lvl);
                local is_current = entry.id == current_val;
                if is_current then imgui.PushStyleColor(ImGuiCol_Text, 0.6, 0.85, 1.0, 1.0); end
                if imgui.Selectable(lbl) then
                    inv_job_staged_mj[char] = (staged_var_field == 'mj') and entry.id or inv_job_staged_mj[char];
                    inv_job_staged_sj[char] = (staged_var_field == 'sj') and entry.id or inv_job_staged_sj[char];
                end
                if is_current then imgui.PopStyleColor(); end
            end
            imgui.EndPopup();
        end
    end

    header_centered();
    imgui.Dummy(0, 4);

    -- Snap the first arrow button to a fixed X regardless of which label was
    -- rendered (Main Job: and Sub Job: are different widths, so SameLine after
    -- the Text would shift the arrows between rows). Both rows share the
    -- post-label X position, giving stacked-and-aligned cycle controls.
    local arrow1_x = label_x_off + label_w + item_gap;

    -- MJ row
    imgui.SetCursorPosX(label_x_off);
    imgui.Text(mj_lbl);
    imgui.SameLine();
    imgui.SetCursorPosX(arrow1_x);
    if imgui.Button('<##cj_mj_l', arrow_w, 0) then
        inv_job_staged_mj[char] = cycle(staged_mj, -1);
    end
    imgui.SameLine();
    local mj_label = job_abbrev(staged_mj);
    if staged_mj ~= info.current_mj then
        mj_label = mj_label .. ' *';
    end
    if imgui.Button(mj_label .. '##cj_mj_c', center_w, 0) then
        imgui.OpenPopup('##cj_mj_pick');
    end
    picker_popup('##cj_mj_pick', 'mj', info.current_mj);
    imgui.SameLine();
    if imgui.Button('>##cj_mj_r', arrow_w, 0) then
        inv_job_staged_mj[char] = cycle(staged_mj, 1);
    end

    imgui.Dummy(0, 2);

    -- SJ row
    imgui.SetCursorPosX(label_x_off);
    imgui.Text(sj_lbl);
    imgui.SameLine();
    imgui.SetCursorPosX(arrow1_x);
    if imgui.Button('<##cj_sj_l', arrow_w, 0) then
        inv_job_staged_sj[char] = cycle(staged_sj, -1);
    end
    imgui.SameLine();
    local sj_label = job_abbrev(staged_sj);
    if staged_sj ~= info.current_sj then
        sj_label = sj_label .. ' *';
    end
    if imgui.Button(sj_label .. '##cj_sj_c', center_w, 0) then
        imgui.OpenPopup('##cj_sj_pick');
    end
    picker_popup('##cj_sj_pick', 'sj', info.current_sj);
    imgui.SameLine();
    if imgui.Button('>##cj_sj_r', arrow_w, 0) then
        inv_job_staged_sj[char] = cycle(staged_sj, 1);
    end

    imgui.Dummy(0, 4);

    -- Apply row
    local mj_changed = staged_mj ~= info.current_mj;
    local sj_changed = staged_sj ~= info.current_sj;
    local can_apply  = mj_changed or sj_changed;

    local apply_w = 160;
    imgui.SetCursorPosX((w - apply_w) / 2);
    if not can_apply then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    if imgui.Button('Apply Change##cj_apply', apply_w, 0) and can_apply then
        local flags = 0;
        if mj_changed then flags = flags + 1; end
        if sj_changed then flags = flags + 2; end
        autoutil.send_change_job(char, staged_mj, staged_sj, flags);
        autoutil.last_change_job_status = nil;
        -- Re-fetch shortly so the cache reflects the new state. The 0x19D
        -- arrives first, then we kick off 0x19E. On ok, the staged values
        -- match the new current and the stars disappear.
        autoutil.send_get_job_info(char);
    end
    if not can_apply then imgui.PopStyleVar(); end

    -- Error surface from last attempt.
    if autoutil.last_change_job_status ~= nil and autoutil.last_change_job_status ~= 0 then
        local msg = ({
            [1] = 'no target',
            [2] = 'not owned',
            [3] = 'engaged in combat',
            [4] = 'job locked',
            [5] = 'level 0',
            [6] = 'no change',
        })[autoutil.last_change_job_status] or 'failed';
        imgui.TextColored(0.95, 0.6, 0.4, 1.0, '(' .. msg .. ')');
    end
end

-- Appearance value <-> label helpers (see reference_char_appearance memory).
local RACE_NAMES = {
    [1] = 'Hume M', [2] = 'Hume F', [3] = 'Elvaan M', [4] = 'Elvaan F',
    [5] = 'Taru M', [6] = 'Taru F', [7] = 'Mithra',   [8] = 'Galka',
};
local SIZE_NAMES = { [0] = 'Small', [1] = 'Medium', [2] = 'Large' };

local function appearance_race_label(v) return RACE_NAMES[v] or ('?' .. tostring(v)); end
local function size_label(v) return SIZE_NAMES[v] or ('?' .. tostring(v)); end
local function face_label(v)
    -- Interleaved: face = (num-1)*2 + variant, even = A, odd = B.
    local num     = math.floor(v / 2) + 1;
    local variant = (v % 2 == 0) and 'A' or 'B';
    return string.format('%d%s', num, variant);
end

local function draw_change_appearance_row()
    local char = state.selected_char;
    if char == nil or char == '' then return; end

    local function header_centered()
        local w = imgui.GetContentRegionAvailWidth();
        imgui.SetCursorPosX(math.max(0, (w - C.calc_text_w('Change Look')) / 2));
        autoutil.section_head('Change Look');
    end

    local info = autoutil.char_job_info[char];
    if info == nil or info.current_race == nil then
        header_centered();
        imgui.Dummy(0, 4);
        imgui.TextDisabled('(fetching appearance...)');
        return;
    end

    -- Attribute descriptors: staging table, current value, [lo,hi] range,
    -- label fn, and an id prefix for imgui widget ids.
    local attrs = {
        { key = 'race', staged = inv_look_staged_race, cur = info.current_race, lo = 1, hi = 8,  label = appearance_race_label, id = 'cl_race', name = 'Race:', flag = 1 },
        { key = 'face', staged = inv_look_staged_face, cur = info.current_face, lo = 0, hi = 15, label = face_label, id = 'cl_face', name = 'Face:', flag = 2 },
        { key = 'size', staged = inv_look_staged_size, cur = info.current_size, lo = 0, hi = 2,  label = size_label, id = 'cl_size', name = 'Size:', flag = 4 },
    };

    local w        = imgui.GetContentRegionAvailWidth();
    local arrow_w  = 24;
    local center_w = 90;
    local item_gap = 4;
    local label_w  = 0;
    for _, a in ipairs(attrs) do label_w = math.max(label_w, C.calc_text_w(a.name)); end
    local row_w       = label_w + item_gap + arrow_w + item_gap + center_w + item_gap + arrow_w;
    local label_x_off = math.max(0, (w - row_w) / 2);
    local arrow1_x    = label_x_off + label_w + item_gap;

    local function cycle(a, val, dir)
        local span = a.hi - a.lo + 1;
        return ((val - a.lo + dir) % span) + a.lo;
    end

    header_centered();
    imgui.Dummy(0, 4);

    local any_changed = false;

    for _, a in ipairs(attrs) do
        local staged = a.staged[char] or a.cur;

        imgui.SetCursorPosX(label_x_off);
        imgui.Text(a.name);
        imgui.SameLine();
        imgui.SetCursorPosX(arrow1_x);
        if imgui.Button('<##' .. a.id .. '_l', arrow_w, 0) then
            a.staged[char] = cycle(a, staged, -1);
            staged = a.staged[char];
        end
        imgui.SameLine();
        local center_label = a.label(staged);
        if staged ~= a.cur then center_label = center_label .. ' *'; end
        if imgui.Button(center_label .. '##' .. a.id .. '_c', center_w, 0) then
            imgui.OpenPopup('##' .. a.id .. '_pick');
        end
        if imgui.BeginPopup('##' .. a.id .. '_pick') then
            for v = a.lo, a.hi do
                local is_cur = (v == a.cur);
                if is_cur then imgui.PushStyleColor(ImGuiCol_Text, 0.6, 0.85, 1.0, 1.0); end
                if imgui.Selectable(a.label(v) .. '##' .. a.id .. '_opt_' .. v) then
                    a.staged[char] = v;
                end
                if is_cur then imgui.PopStyleColor(); end
            end
            imgui.EndPopup();
        end
        imgui.SameLine();
        if imgui.Button('>##' .. a.id .. '_r', arrow_w, 0) then
            a.staged[char] = cycle(a, staged, 1);
            staged = a.staged[char];
        end

        if staged ~= a.cur then any_changed = true; end
        imgui.Dummy(0, 2);
    end

    imgui.Dummy(0, 2);

    local apply_w = 160;
    imgui.SetCursorPosX((w - apply_w) / 2);
    if not any_changed then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    if imgui.Button('Apply Change##cl_apply', apply_w, 0) and any_changed then
        local flags = 0;
        for _, a in ipairs(attrs) do
            if (a.staged[char] or a.cur) ~= a.cur then flags = flags + a.flag; end
        end
        autoutil.send_change_look(char,
            inv_look_staged_race[char] or info.current_race,
            inv_look_staged_face[char] or info.current_face,
            inv_look_staged_size[char] or info.current_size,
            flags);
        autoutil.last_change_look_status = nil;
        -- Re-fetch so the cache (which now carries race/face/size) reflects the
        -- new state; on ok the staged values match current and stars clear.
        autoutil.send_get_job_info(char);
    end
    if not any_changed then imgui.PopStyleVar(); end

    if autoutil.last_change_look_status ~= nil and autoutil.last_change_look_status ~= 0 then
        local msg = ({
            [1] = 'no target',
            [2] = 'not owned',
            [3] = 'engaged in combat',
            [4] = 'out of range',
            [6] = 'no change',
        })[autoutil.last_change_look_status] or 'failed';
        imgui.TextColored(0.95, 0.6, 0.4, 1.0, '(' .. msg .. ')');
    end
end

local function draw_scrolls_row()
    local scroll = autoscroll.state;
    local w = imgui.GetWindowWidth();
    local btn_w = 90;
    imgui.SetCursorPosX((w - 80) / 2);
    autoutil.section_head('Learn Spells');
    imgui.Spacing();
    imgui.SetCursorPosX((w - btn_w * 2 - 4) / 2);
    if imgui.Button('Buy Scrolls##scroll', btn_w, 0) then autobuy.buy_scrolls(); end
    imgui.SameLine(0, 4);
    if imgui.Button('Use Scrolls##scroll', btn_w, 0) then autoscroll.learn(); end
end

local function draw_inv_right_static(col_w)
    local gil_text = C.format_gil(C.get_inv_gil()) .. ' Gil';
    imgui.Dummy(0, 4);
    imgui.SetCursorPosX((col_w - C.calc_text_w(gil_text)) / 2);
    imgui.Text(gil_text);

    -- (Manual "Sort Inventory" button removed: headless bots now auto-sort on
    -- their tick via ai_lot, and primaries sort with the in-game /sortinv. The
    -- server sort endpoint + inv_cache.send_sort_inventory remain available if
    -- an on-demand sort is ever wanted again.)

    C.inv_sep();
    draw_delivery_row();
    C.inv_sep();
    draw_scrolls_row();
    C.inv_sep();
    draw_change_job_row();
    C.inv_sep();
    draw_change_appearance_row();
end

-- ============================================================
-- Status tab — per-char profile view. Left column shows name +
-- portrait + jobs/levels + race/gender + exp + stats grid +
-- equipment list. Right column is the shared inventory right
-- column (gil / sort / delivery / scrolls / change-job).
--
-- Stats and equipment land via S2C 0x1A8 CHAR_PROFILE, requested
-- via 0x1A7 GET_CHAR_PROFILE on first paint of this tab for the
-- selected char. The cache survives across char switches so
-- flipping back to a previously-viewed char is instant.
-- ============================================================

-- Portrait cache - shared PNGs at singleplayer/client/addons/libs/portraits/
-- <race*100+face>.png (the same set the autobots Create Char tab shows). Both
-- addons point icon_cache at this shared dir; this is the one path to update
-- if the assets move again.
local status_portraits = nil;
local function get_portrait_cache()
    if status_portraits == nil then
        local path = _addon and (_addon.path .. '../libs/portraits/') or '../libs/portraits/';
        status_portraits = icon_cache.new(path);
    end
    return status_portraits;
end

-- FFXI race byte is 1-indexed per scripts/enum/race.lua:
-- 1=HumeM, 2=HumeF, 3=ElvaanM, 4=ElvaanF, 5=TaruM, 6=TaruF,
-- 7=Mithra (always F), 8=Galka (always M). The 0x1A8 CHAR_PROFILE
-- packet ships PChar->look.race directly, which is this 1-indexed
-- value, so the table has to match — earlier 0-indexed version was
-- shifting every race down by one (Mithra→Galka, Galka off the end).
local RACE_INFO = {
    [1] = { name = 'Hume',     gender = 'Male'   },
    [2] = { name = 'Hume',     gender = 'Female' },
    [3] = { name = 'Elvaan',   gender = 'Male'   },
    [4] = { name = 'Elvaan',   gender = 'Female' },
    [5] = { name = 'Tarutaru', gender = 'Male'   },
    [6] = { name = 'Tarutaru', gender = 'Female' },
    [7] = { name = 'Mithra',   gender = 'Female' },
    [8] = { name = 'Galka',    gender = 'Male'   },
};

local function race_label(race) return (RACE_INFO[race or -1] or { name = '?' }).name; end
local function gender_label(race) return (RACE_INFO[race or -1] or { gender = '?' }).gender; end

-- Resolve a job byte -> short code via autoutil's table. autoutil.jobs is
-- 1-indexed so we offset.
local function job_short(jobId)
    if jobId == nil or jobId == 0 then return '---'; end
    return (autoutil.jobs and autoutil.jobs[jobId]) or string.format('J%d', jobId);
end

local EQUIP_SLOT_NAMES = {
    'Main',  'Sub',   'Range', 'Ammo',
    'Head',  'Body',  'Hands', 'Legs',  'Feet',
    'Neck',  'Waist', 'Ear1',  'Ear2',
    'Ring1', 'Ring2', 'Back',
};

local STAT_KEYS = { 'STR', 'DEX', 'VIT', 'AGI', 'INT', 'MND', 'CHR' };

-- Skill display lists: { skillId, label }. Combat first, then magic (matches
-- SKILLTYPE ids in the 0x1A8 packet). prof.skills[id] = { value, capped }.
local COMBAT_SKILLS = {
    { 1, 'H2H' },    { 2, 'Dagger' }, { 3, 'Sword' },   { 4, 'GSword' },
    { 5, 'Axe' },    { 6, 'GAxe' },   { 7, 'Scythe' },  { 8, 'Polearm' },
    { 9, 'Katana' }, { 10, 'GKatana' }, { 11, 'Club' }, { 12, 'Staff' },
    { 25, 'Archery' }, { 26, 'Marksman' }, { 27, 'Throwing' }, { 28, 'Guard' },
    { 29, 'Evasion' }, { 30, 'Shield' },   { 31, 'Parry' },
};
local MAGIC_SKILLS = {
    { 32, 'Divine' },  { 33, 'Healing' },  { 34, 'Enhancing' }, { 35, 'Enfeebling' },
    { 36, 'Elemental' }, { 37, 'Dark' },   { 38, 'Summoning' }, { 39, 'Ninjutsu' },
    { 40, 'Singing' }, { 41, 'Strings' },  { 42, 'Wind' },      { 43, 'BlueMagic' },
    { 44, 'Geomancy' }, { 45, 'Handbell' },
};


local STATUS_LEFT_PAD = 8;    -- left indent so text doesn't hug the column edge
local STATUS_PORTRAIT = 144;  -- portrait square size (px)

local function draw_status_profile(col_w, prof)
    -- Indent the whole left column a few px so nothing hugs the left edge.
    -- Centered rows use absolute SetCursorPosX(col_w-based) and are unaffected.
    imgui.Indent(STATUS_LEFT_PAD);

    -- Centered name.
    imgui.Dummy(0, 4);
    imgui.SetCursorPosX(math.max(0, (col_w - C.calc_text_w(prof.name)) / 2));
    imgui.TextColored(1.0, 1.0, 1.0, 1.0, prof.name);

    -- Portrait, centered, between the name and the identity rows.
    imgui.Dummy(0, 4);
    local ptex = get_portrait_cache():get((prof.race or 0) * 100 + (prof.face or 0));
    if ptex ~= nil then
        imgui.SetCursorPosX(math.max(0, (col_w - STATUS_PORTRAIT) / 2));
        imgui.Image(ptex, STATUS_PORTRAIT, STATUS_PORTRAIT);
    end

    -- Identity row: "Male Hume   13 WAR / 6 THF"
    imgui.Dummy(0, 6);
    imgui.Text(string.format('%s %s', gender_label(prof.race), race_label(prof.race)));
    imgui.Text(string.format('%d %s / %d %s', prof.ml or 0, job_short(prof.mj),
                                              prof.sl or 0, job_short(prof.sj)));

    -- Exp.
    if (prof.exp_to or 0) > 0 then
        imgui.Text(string.format('Exp: %d / %d', prof.exp_cur or 0, prof.exp_to));
    else
        imgui.Text('Exp: MAX');
    end

    C.inv_sep();

    -- Stats grid. Format mirrors the client UI: "STR  12  +4".
    autoutil.section_head('Stats');
    imgui.Dummy(0, 2);
    -- HP / MP first, each on its own row, above the primary stats.
    imgui.TextColored(0.85, 0.85, 0.85, 1.0,
        string.format('HP  %d / %d', prof.hp_cur or 0, prof.hp_max or 0));
    imgui.TextColored(0.85, 0.85, 0.85, 1.0,
        string.format('MP  %d / %d', prof.mp_cur or 0, prof.mp_max or 0));
    imgui.Dummy(0, 4);
    -- Two sub-columns within the left column: primary attributes on the left,
    -- combat stats (Atk/Def/Acc/Eva) to their right, top-aligned.
    imgui.BeginGroup();
    for _, k in ipairs(STAT_KEYS) do
        local base  = (prof.stat_base or {})[k]  or 0;
        local bonus = (prof.stat_bonus or {})[k] or 0;
        local sign  = (bonus >= 0) and '+' or '';
        imgui.Text(string.format('%-4s %3d  %s%d', k, base, sign, bonus));
    end
    imgui.EndGroup();
    -- Combat column starts at the horizontal middle of the left column, for a
    -- clear gap between the two stat groups.
    imgui.SameLine(0, 0);
    imgui.SetCursorPosX(math.floor(col_w / 2));
    imgui.BeginGroup();
    -- Labels are all 3 chars, so '%-4s' left-aligns them and the values line up.
    local combat_rows = {
        { 'Atk', prof.atk }, { 'Def', prof.def },
        { 'Acc', prof.acc }, { 'Eva', prof.eva },
    };
    for _, r in ipairs(combat_rows) do
        imgui.TextColored(0.85, 0.85, 0.85, 1.0,
            string.format('%-4s %d', r[1], r[2] or 0));
    end
    imgui.EndGroup();

    C.inv_sep();

    -- Equipment list. Each row: small [x] Button on the LEFT for unequip
    -- (only when the slot has an item; empty rows pad with a 22-px Dummy
    -- so the slot text stays aligned), then a Selectable that focuses
    -- the slot and switches the right column to an item picker. Mirrors
    -- the autoequip Gear-tab slot layout. Server-side 0x171 with
    -- ItemId=0 = unequip (charutils::UnequipItem on the named slot).
    -- Skills — combat first, then magic. Shows exactly what vanilla's Skills
    -- window would: every skill the current job combination can use, including
    -- those still at 0. The visibility signal is already in WorkingSkills:
    -- BuildingCharSkillsTable writes a skill the job CAN'T use as value 0 with
    -- the capped bit set (the 0x8000-only case), whereas a usable-but-unraised
    -- skill is value 0 with the capped bit CLEAR. So: show when value>0 or the
    -- capped bit is clear; hide the value-0-and-capped pairs. Colour: capped =
    -- blue (matches vanilla), unraised (0) = grey, in-progress = normal.
    -- (The equipped-items list moved to the autoequip "Current" tab.)
    local skills = prof.skills or {};
    local skill_col_w = math.floor((col_w - STATUS_LEFT_PAD) / 2);  -- two entries per row
    local function skill_col(title, list)
        autoutil.section_head(title);
        imgui.Dummy(0, 2);
        local any = false;
        local col, rowX = 0, 0;
        for _, sk in ipairs(list) do
            local s = skills[sk[1]];
            if s and (s.value > 0 or not s.capped) then
                any = true;
                -- Two per row: first entry sets the row's left x, the second is
                -- placed a half-column to its right on the same line.
                if col == 0 then
                    rowX = imgui.GetCursorPosX();
                else
                    imgui.SameLine(0, 0);
                    imgui.SetCursorPosX(rowX + skill_col_w);
                end
                local row = string.format('%-10s %d', sk[2] .. ':', s.value);
                if s.value == 0 then
                    imgui.TextDisabled(row);                     -- unraised = grey
                elseif s.capped then
                    imgui.TextColored(0.4, 0.7, 1.0, 1.0, row);  -- capped = blue
                else
                    imgui.Text(row);
                end
                col = (col + 1) % 2;
            end
        end
        if not any then imgui.TextDisabled('  (none)'); end
    end
    skill_col('Combat Skills', COMBAT_SKILLS);
    imgui.Dummy(0, 4);
    skill_col('Magic Skills', MAGIC_SKILLS);

    imgui.Unindent(STATUS_LEFT_PAD);
end

-- Send EQUIP_BOT_ITEM (0x171). Wire body: 4-byte header + 16 CharName +
-- 2 ItemId + 1 SlotId + 1 padding = 24 bytes total. Server validates the
-- target char is the requester themselves OR a headless owned by them,
-- finds the item across all equip-bearing containers, calls
-- charutils::EquipItem, then pushes a fresh 0x1A8 CHAR_PROFILE so the
-- addon's char_profile_cache picks up the new equipment.
--
-- Same packet for primary AND headless — the server-side handler treats
-- both uniformly. This replaces the vanilla 0x173 EQUIP_BY_ID path for
-- the Status tab picker because 0x173 has no target-char field so it
-- couldn't be reused for cross-char headless equip.
-- Assigns to the forward-declared local above draw_status_profile.
-- Using `function name(...)` syntax (without `local`) would create a
-- global; plain assignment binds to the existing local instead.
local function draw_status_tab()
    -- Same width as the inventory tab for parity / no jumpiness on swap.
    local col_w = 260;

    if state.selected_char == nil or state.selected_char == '' then
        imgui.TextDisabled('No character selected.');
        return;
    end

    -- Kick a fetch the first time this tab paints for the current char.
    -- ensure() is a no-op if the cache already has a profile.
    char_profile_cache.ensure(state.selected_char);
    local prof = char_profile_cache.get(state.selected_char);

    imgui.BeginChild('##status_left', col_w, 0, false);
    if prof == nil then
        imgui.Dummy(0, 8);
        imgui.TextDisabled('Loading profile...');
    else
        draw_status_profile(col_w, prof);
    end
    imgui.EndChild();

    imgui.SameLine(0, 30);

    imgui.BeginChild('##status_right', col_w, 0, false);
    -- Equipment editing moved to the autoequip "Current" tab; the right column
    -- now always shows the gil / delivery / scrolls / change-job block.
    draw_inv_right_static(col_w);
    imgui.EndChild();
end

M.draw = draw_status_tab;

return M;
