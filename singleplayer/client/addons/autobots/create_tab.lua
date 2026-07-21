-- create_tab.lua : autobots "Create Char" tab.
--
-- Creates a brand-new character (its own account, password "password") entirely
-- server-side via POST /chars/create — no client login/char-create screens. This
-- is char-AGNOSTIC (you're making a new char, not operating on a selected one),
-- which is why it lives in autobots and not automog/autoequip.
--
-- Layout (two columns, house style):
--   LEFT  — Name (validated) + face portrait + Race / Gender / Face / Size / Nation
--   RIGHT — Main Job (the 6 starting jobs) + starting stats / equipment preview
--
-- Race + Gender are shown as two controls but folded into the single encoded
-- 1-8 char_look.race the server wants (see libs/appearance_picker.lua). Mithra
-- and Galka are single-gender.

require 'imguidef';

local autoutil        = require('autoutil');
local json            = require('json');
local http_client     = require('http_client');
local loading_overlay = require('loading_overlay');
local icon_cache      = require('icon_cache');
local ap              = require('appearance_picker');

local create_tab = {};

local LOCK     = 'autobots:create';
local LEFT_W   = 300;
local COL_PAD  = 8;    -- left indent per column so text doesn't hug the edge
local TOP_PAD  = 6;    -- top padding at the head of each column
local PORTRAIT = 144;  -- portrait square size (px); 96 * 1.5
local COL_H    = 460;  -- fixed column height: keeps the tab as tall as the
                       -- Controls tab instead of collapsing to its short content

-- picker_row geometry, shared so the portrait can be aligned over the Race
-- row's value button (label + gap + '<' + gap + value button).
local PICK_ARROW_W   = 22;         -- '<' / '>' button width
local PICK_LABEL_GAP = 6;          -- gap between the label text and the '<' button
local PICK_BTN_GAP   = 2;          -- gap between adjacent buttons
local PICK_VALUE_W   = 96;         -- middle value button width
local RACE_LABEL     = 'Race:  ';  -- shared by the Race picker_row and the portrait

-- The 6 starting jobs (server clamps mjob to [1,6]). Indexed by job id.
local START_JOB_ABBR = { [1] = 'WAR', [2] = 'MNK', [3] = 'WHM', [4] = 'BLM', [5] = 'RDM', [6] = 'THF' };
local JOB_LO, JOB_HI = 1, 6;

-- Staged form state. A fresh char has no "current" values, so these are plain
-- defaults (unlike status_tab's editors, which stage against an existing char).
local form = {
    name_var   = nil,               -- CDSTRING buffer, created on first draw
    race_group = 1,                 -- Hume
    gender     = ap.GENDER_MALE,
    face       = 0,
    size       = 0,                 -- Small
    nation     = 0,                 -- San d'Oria
    job        = 1,                 -- WAR
};

-- Portrait assets live in the shared libs/portraits/ dir (moved out of this
-- addon so automog can share them). Files are named <encodedRace*100 + face>.png.
local portraits = nil;

-- Existing character names, for the client-side uniqueness check. Fetched lazily
-- from GET /chars; the server stays the authority, this just spares round-trips.
local existing_names = nil;         -- { [lowername] = true } once fetched
local names_fetched  = false;

local last_error = nil;             -- last create failure message

-- Unpack a packed U32 color into the 4 floats imgui.PushStyleColor expects
-- (mirrors autobots_ui.lua's _uc). imgui.GetColorU32 returns a packed value.
local function _uc(u)
    return bit.band(u, 0xFF) / 255, bit.band(bit.rshift(u, 8), 0xFF) / 255,
           bit.band(bit.rshift(u, 16), 0xFF) / 255, bit.band(bit.rshift(u, 24), 0xFF) / 255;
end

-- Text width with fallbacks. Ashita's imgui.CalcTextSize return shape varies
-- (number, ImVec2 table, or nil), so mirror automog_common.calc_text_w rather
-- than doing arithmetic on the raw result.
local function text_w(text)
    local a = imgui.CalcTextSize(text);
    if type(a) == 'number' then return a; end
    if type(a) == 'table'  then return a.x or a[1] or 0; end
    return #text * 7;
end

-- Resolve an item id to its name via Ashita's resource manager (Name[0] is the
-- English name; strip embedded nulls). Falls back to the raw id.
local function item_name(id)
    local res = AshitaCore:GetResourceManager():GetItemById(id);
    if res ~= nil and res.Name ~= nil then
        local n = tostring(res.Name[0]):gsub('%z', '');
        if n ~= '' then return n; end
    end
    return 'id=' .. tostring(id);
end

-- Starting stats/equipment preview, fetched per (encodedRace, job) and cached.
-- The server computes it from the same tables charCreate uses, so it stays in
-- sync. Fetch is debounced by the cache + in-flight guards.
local preview_cache   = {};   -- key -> { stats, equipped = {ids}, inventory = {ids} }
local preview_pending = {};   -- key -> true while a fetch is in flight

local function preview_key(encoded_race, job) return encoded_race .. '_' .. job; end

local function ensure_preview(encoded_race, job)
    local key = preview_key(encoded_race, job);
    if preview_cache[key] ~= nil or preview_pending[key] then return key; end
    preview_pending[key] = true;
    http_client.await_op('/chars/create-preview', { race = encoded_race, job = job }, nil,
        function(result, err)
            preview_pending[key] = nil;
            if err ~= nil then return; end -- leave uncached; UI keeps showing "loading"
            local ok, data = pcall(function() return json:decode(result.message or '{}'); end);
            if ok and type(data) == 'table' then preview_cache[key] = data; end
        end);
    return key;
end

-- ---------------------------------------------------------------------------

local function ensure_portraits()
    if portraits == nil then
        local base = (_addon and _addon.path or '') .. '../libs/portraits/';
        portraits = icon_cache.new(base);
    end
    return portraits;
end

local function ensure_names()
    if names_fetched then return; end
    names_fetched = true;
    http_client.get('/chars', function(code, body, _, err)
        if err ~= nil or code ~= 200 then
            names_fetched = false; -- allow a retry next frame
            return;
        end
        local ok, arr = pcall(function() return json:decode(body); end);
        if not ok or type(arr) ~= 'table' then
            names_fetched = false;
            return;
        end
        local set = {};
        for _, e in ipairs(arr) do
            if e.name ~= nil then set[tostring(e.name):lower()] = true; end
        end
        existing_names = set;
    end);
end

-- Returns (ok, reason). Mirrors the server's mandatory checks so the BE rarely
-- rejects: alpha-only, 3-15, not already taken.
local function validate_name(name)
    if name == nil or #name < 3 then return false, '3-15 letters'; end
    if #name > 15 then return false, '3-15 letters'; end
    if name:match('[^%a]') ~= nil then return false, 'letters only'; end
    if existing_names ~= nil and existing_names[name:lower()] then return false, 'name taken'; end
    return true, nil;
end

-- Generic "< [value] >" cycle row with a click-to-open popup of all values.
-- Returns the (possibly changed) value. Mirrors status_tab's Change Look row.
local function picker_row(label, id, value, lo, hi, label_fn)
    imgui.Text(label);
    imgui.SameLine(0, PICK_LABEL_GAP);
    if imgui.Button('<##' .. id .. '_l', PICK_ARROW_W, 0) then value = ap.cycle(lo, hi, value, -1); end
    imgui.SameLine(0, PICK_BTN_GAP);
    if imgui.Button(label_fn(value) .. '##' .. id .. '_c', PICK_VALUE_W, 0) then
        imgui.OpenPopup('##' .. id .. '_pop');
    end
    if imgui.BeginPopup('##' .. id .. '_pop') then
        for v = lo, hi do
            if imgui.Selectable(label_fn(v) .. '##' .. id .. '_o' .. v) then value = v; end
        end
        imgui.EndPopup();
    end
    imgui.SameLine(0, PICK_BTN_GAP);
    if imgui.Button('>##' .. id .. '_r', PICK_ARROW_W, 0) then value = ap.cycle(lo, hi, value, 1); end
    return value;
end

local function draw_left_column()
    -- Left padding so nothing hugs the column edge (mirrors automog status).
    -- Centered rows use absolute SetCursorPosX and are unaffected by Indent.
    imgui.Indent(COL_PAD);
    imgui.Dummy(0, TOP_PAD);

    -- Name --------------------------------------------------------------
    if form.name_var == nil then form.name_var = imgui.CreateVar(ImGuiVar_CDSTRING, 16); end
    autoutil.section_head('Name');
    imgui.InputText('##cr_name', form.name_var, 16);
    local name = imgui.GetVarValue(form.name_var) or '';
    local name_ok, name_reason = validate_name(name);
    if not name_ok and name ~= '' then
        imgui.TextColored(0.95, 0.6, 0.4, 1.0, '(' .. name_reason .. ')');
    else
        -- Reserve the error line's height so the portrait and the rest of the
        -- column below don't shift down when a validation message toggles.
        imgui.Text(' ');
    end

    -- Portrait, centered over the Race row's value button. The Race row is
    -- "label + gap + '<' + gap + [value button]"; that value button's left edge
    -- is line-start + label width + gaps + arrow. Center the portrait over it
    -- (works even if the two widths differ, though they're both 96 today).
    imgui.Dummy(0, 4);
    local encoded_race = ap.encode_race(form.race_group, form.gender);
    local tex = ensure_portraits():get(encoded_race * 100 + form.face);
    local race_label_w = text_w(RACE_LABEL);
    local value_btn_x  = imgui.GetCursorPosX() + race_label_w + PICK_LABEL_GAP + PICK_ARROW_W + PICK_BTN_GAP;
    imgui.SetCursorPosX(value_btn_x + (PICK_VALUE_W - PORTRAIT) / 2);
    if tex ~= nil then
        imgui.Image(tex, PORTRAIT, PORTRAIT);
    else
        -- Placeholder until art exists: a labelled box so the slot reads as
        -- "portrait here", not broken.
        imgui.BeginChild('##cr_portrait_ph', PORTRAIT, PORTRAIT, true);
        imgui.Dummy(0, 34);
        imgui.TextDisabled('  (portrait)');
        imgui.EndChild();
    end

    -- Appearance / nation ----------------------------------------------
    imgui.Dummy(0, 4);
    autoutil.section_head('Appearance');

    form.race_group = picker_row(RACE_LABEL, 'cr_race', form.race_group, ap.GROUP_LO, ap.GROUP_HI, ap.race_group_label);
    -- Snap gender if the newly-chosen race can't be that gender (Mithra->F, Galka->M).
    if not ap.group_allows_gender(form.race_group, form.gender) then
        form.gender = ap.first_gender_for_group(form.race_group);
    end

    -- Gender: a real toggle for dual-gender races; a fixed label for single-gender ones.
    local genders = ap.GROUP_GENDERS[form.race_group] or {};
    if #genders <= 1 then
        form.gender = genders[1] or ap.GENDER_MALE;
        imgui.Text('Gender:');
        imgui.SameLine(0, 6);
        imgui.TextDisabled(ap.gender_label(form.gender));
    else
        form.gender = picker_row('Gender:', 'cr_gender', form.gender, 0, 1, ap.gender_label);
    end

    form.face   = picker_row('Face:  ', 'cr_face', form.face, ap.FACE_LO, ap.FACE_HI, ap.face_label);
    form.size   = picker_row('Size:  ', 'cr_size', form.size, ap.SIZE_LO, ap.SIZE_HI, ap.size_label);
    form.nation = picker_row('Nation:', 'cr_nation', form.nation, ap.NATION_LO, ap.NATION_HI, ap.nation_label);

    imgui.Unindent(COL_PAD);
    return name, name_ok;
end

local function draw_right_column()
    imgui.Indent(COL_PAD);
    imgui.Dummy(0, TOP_PAD);

    autoutil.section_head('Main Job');
    form.job = picker_row('Job:', 'cr_job', form.job, JOB_LO, JOB_HI,
        function(v) return START_JOB_ABBR[v] or ('?' .. tostring(v)); end);

    imgui.Dummy(0, 6);
    autoutil.section_head('Starting Stats & Equipment');

    -- Stats depend on race+job only (gender/face/size don't affect them). Fetch
    -- lazily; cached per (encodedRace, job).
    local encoded_race = ap.encode_race(form.race_group, form.gender);
    local pv = preview_cache[ensure_preview(encoded_race, form.job)];
    if pv == nil then
        imgui.TextDisabled('(loading...)');
        imgui.Unindent(COL_PAD);
        return;
    end

    -- Stats, each on its own row (mirrors automog status_tab). HP/MP first in
    -- the dimmer read color, then the seven primary stats aligned in a column.
    local s = pv.stats or {};
    imgui.TextColored(0.85, 0.85, 0.85, 1.0, string.format('HP  %d', s.hp or 0));
    imgui.TextColored(0.85, 0.85, 0.85, 1.0, string.format('MP  %d', s.mp or 0));
    imgui.Dummy(0, 4);
    local stat_rows = {
        { 'STR', s.str }, { 'DEX', s.dex }, { 'VIT', s.vit },
        { 'AGI', s.agi }, { 'INT', s['int'] }, { 'MND', s.mnd }, { 'CHR', s.chr },
    };
    for _, r in ipairs(stat_rows) do
        imgui.Text(string.format('%-4s %3d', r[1], r[2] or 0));
    end

    imgui.Dummy(0, 4);
    imgui.TextDisabled('Equipped:');
    for _, id in ipairs(pv.equipped or {}) do imgui.BulletText(item_name(id)); end
    if #(pv.inventory or {}) > 0 then
        imgui.TextDisabled('Inventory:');
        for _, id in ipairs(pv.inventory or {}) do imgui.BulletText(item_name(id)); end
    end

    imgui.Unindent(COL_PAD);
end

-- ---------------------------------------------------------------------------

function create_tab.render()
    ensure_names();

    if loading_overlay.is_locked(LOCK) then
        loading_overlay.render(LOCK);
        return;
    end

    imgui.BeginChild('##cr_left', LEFT_W, COL_H, false);
    local name, name_ok = draw_left_column();
    imgui.EndChild();

    imgui.SameLine(0, 6);
    imgui.PushStyleColor(ImGuiCol_ChildWindowBg, _uc(imgui.GetColorU32(ImGuiCol_Button)));
    imgui.BeginChild('##cr_divider', 1, COL_H, false);
    imgui.EndChild();
    imgui.PopStyleColor();
    imgui.SameLine(0, 6);

    imgui.BeginChild('##cr_right', 0, COL_H, false);
    draw_right_column();
    imgui.EndChild();

    -- Create button + result. Below the fixed-height columns. Safe here now
    -- that the columns are a fixed height rather than height-0 fill: a fixed
    -- child can't feed its height back into the AlwaysAutoResize window the
    -- way a fill child did (which is what grew the tab without bound before).
    -- Create button, horizontally centered on the column divider so it
    -- straddles both columns, with a matching gap above and below. The line
    -- starts at the left content edge, so left col spans [x, x+LEFT_W] and the
    -- divider sits at x+LEFT_W+6; centering the button there splits it evenly.
    imgui.Dummy(0, 6);
    local can = name_ok;
    if not can then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    local btn_w = 200;
    imgui.SetCursorPosX(math.max(0, imgui.GetCursorPosX() + LEFT_W + 6 - btn_w / 2));
    if imgui.Button('Create Character##cr_go', btn_w, 0) and can then
        last_error = nil;
        local body = {
            name   = name,
            race   = ap.encode_race(form.race_group, form.gender),
            face   = form.face,
            size   = form.size,
            nation = form.nation,
            job    = form.job,
        };
        loading_overlay.begin(LOCK, 'Creating ' .. name .. '...');
        http_client.await_op('/chars/create', body, nil, function(result, err)
            loading_overlay.done(LOCK);
            if err ~= nil then
                last_error = err;
                autoutil.log('CreateChar', 'create failed: ' .. tostring(err));
            else
                last_error = nil;
                imgui.SetVarValue(form.name_var, '');  -- clear for the next one
                names_fetched = false;                 -- refetch so it shows as taken
            end
        end);
    end
    if not can then imgui.PopStyleVar(); end

    if last_error ~= nil then
        imgui.TextColored(0.95, 0.6, 0.4, 1.0, '(' .. tostring(last_error) .. ')');
    end
    imgui.Dummy(0, 6);  -- bottom padding, matching the gap above the button
end

return create_tab;
