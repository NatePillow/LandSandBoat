-- AutoMog Craft tab.
--
-- Recipe browser + synth driver: filter/sort the recipe catalog, inspect a
-- recipe's skills/crystal/ingredients/HQ results with live inventory counts,
-- and fire FAST_SYNTH runs (all / count / HQ) or buy missing ingredients.
--
-- (Extracted from the former monolithic automog.lua when the tabs were split
-- into sibling *_tab.lua files. Code moved verbatim; shared helpers are still
-- referenced through C.* / state.*.)

local M = {}

local autoutil      = require('autoutil');
local autocraft     = require('autocraft');
local autobuy       = require('autobuy');
local inv_cache_lib = require('inv_cache');
local state         = require('automog_state');
local C             = require('automog_common');

-- Self-contained fav-file path derivation (Ashita v3 pattern, off THIS file's
-- own dir - same addon dir as the monolith, so the path resolves identically).
local _src        = ((debug.getinfo(1, 'S').source or ''):match('^@(.+)$') or ''):gsub('[\\/][\\/]+', '\\');
local _addon_dir  = _src:match('^(.*[/\\])[^/\\]+$') or '';
local _ashita_root = _addon_dir:match('^(.*[/\\])[Aa]ddons[/\\]') or '';
local CRAFT_FAV_FILE = _ashita_root .. 'config\\automog\\craft_favorites.txt';

local craft_filter  = nil;
local craft_selected = '';
local craft_variant  = nil;
local craft_limit_n  = nil;
local craft_limit_mode = 'all';
local craft_ing_mode   = 'single';
local craft_ing_qty    = nil;
local craft_sort_mode   = 'name';
local craft_skill_vars  = {};
local craft_slot_vars   = {};
local craft_slot_filter = nil;
local craft_favorites  = {};

-- SLOT_LABEL / SLOT_MASK are used by both the craft tab (kept here) and the
-- gear tab (lifted into autoequip). The craft tab references a subset of slots
-- via CRAFT_SLOT_ORDER, so we keep just the labels/masks the craft tab needs.
local SLOT_LABEL = {
    main='Main',  sub='Sub',    range='Range', ammo='Ammo',
    head='Head',  body='Body',  hands='Hands', legs='Legs',  feet='Feet',
    neck='Neck',  waist='Waist',  back='Back',
    ear='Ear',    ring='Ring',
};

local SLOT_MASK = {
    main=0x0001,  sub=0x0002,   range=0x0004,  ammo=0x0008,
    head=0x0010,  body=0x0020,  hands=0x0040,  legs=0x0080,  feet=0x0100,
    neck=0x0200,  waist=0x0400,
    lear=0x0800,  rear=0x1000,  lring=0x2000,  rring=0x4000, back=0x8000,
    ear=0x1800,   ring=0x6000,
};

local CRAFT_SLOT_ORDER = {
    'main', 'sub', 'range', 'ammo',
    'head', 'neck', 'ear',
    'body', 'hands', 'ring',
    'back', 'waist', 'legs', 'feet',
};

local CRAFT_SKILL_NAMES = {
    wood='Woodworking', smith='Smithing', gold='Goldsmithing',
    cloth='Clothcraft', leather='Leathercraft', bone='Bonecraft',
    alchemy='Alchemy', cook='Cooking', fish='Fishing',
};
local CRAFT_SKILL_KEYS = { 'wood', 'smith', 'gold', 'cloth', 'leather', 'bone', 'alchemy', 'cook' };

-- Shared layout constants (copied from the monolith - same values).
local STEPPER_W = 82;  -- stepper: 3×22px buttons + 2×8px default SameLine gaps
local FAV_GAP   = 4;

local function draw_craft_row()
    local craft = autocraft.state;
    autoutil.section_head('Craft');
    imgui.Dummy(0, 6);

    -- Row 1: Start (left 1/3) / Stop (right 1/3)
    local avail_w = imgui.GetContentRegionAvailWidth();
    local btn_w   = math.floor((avail_w - 2 * FAV_GAP) / 3);
    local sx      = imgui.GetCursorPosX();
    if imgui.Button('Start##craft', btn_w, 0) then
        local name = imgui.GetVarValue(craft_filter);
        if name and name ~= '' then
            local args = { 'recipe', name };
            local lname  = name:lower();
            local vcount = 1;
            for _, r in ipairs(autocraft.recipe_list) do
                if r.key == lname then vcount = r.variants; break; end
            end
            if vcount > 1 then
                table.insert(args, 'v' .. tostring(imgui.GetVarValue(craft_variant)));
            end
            if craft_limit_mode == 'all' then
                table.insert(args, 'all');
            elseif craft_limit_mode == 'hq' then
                table.insert(args, 'hq' .. tostring(imgui.GetVarValue(craft_limit_n)));
            else
                table.insert(args, tostring(imgui.GetVarValue(craft_limit_n)));
            end
            autocraft.on_command(args);
        end
    end
    imgui.SameLine(0, 0);
    imgui.SetCursorPosX(sx + 2 * (btn_w + FAV_GAP));
    C.stop_button('Stop##craft', craft.active, function()
        autocraft.on_command({'stop'});
    end, btn_w);
    imgui.Dummy(0, 6);

    -- Row 2: mode radios + qty stepper (centered)
    local is_all = craft_limit_mode == 'all';
    imgui.SetCursorPosX(C.radio_center_x({'All', 'Count', 'HQ'}, STEPPER_W));
    if imgui.RadioButton('All##craft', is_all) then craft_limit_mode = 'all'; end
    imgui.SameLine();
    if imgui.RadioButton('Count##craft', craft_limit_mode == 'count') then craft_limit_mode = 'count'; end
    imgui.SameLine();
    if imgui.RadioButton('HQ##craft', craft_limit_mode == 'hq') then craft_limit_mode = 'hq'; end
    imgui.SameLine();
    if is_all then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    C.stepper('craft_limit', craft_limit_n, 1);
    if is_all then imgui.PopStyleVar(); end
    local lname  = (imgui.GetVarValue(craft_filter) or ''):lower();
    local vcount = 1;
    for _, r in ipairs(autocraft.recipe_list) do
        if r.key == lname then vcount = r.variants; break; end
    end
    if vcount > 1 then
        imgui.SameLine();
        imgui.Text('v');
        imgui.SameLine();
        C.stepper('craft_variant', craft_variant, 1);
    end

    -- Sort radios
    imgui.Dummy(0, 8);
    imgui.Text('Sort');
    if imgui.RadioButton('Name##csort', craft_sort_mode == 'name') then craft_sort_mode = 'name'; end
    imgui.SameLine();
    if imgui.RadioButton('Skill Level##csort', craft_sort_mode == 'level') then craft_sort_mode = 'level'; end

    -- Skills filter (collapsing multi-select)
    imgui.Spacing();
    local function _uc(u)
        return bit.band(u,0xFF)/255, bit.band(bit.rshift(u,8),0xFF)/255,
               bit.band(bit.rshift(u,16),0xFF)/255, bit.band(bit.rshift(u,24),0xFF)/255;
    end
    local function push_header_btn()
        imgui.PushStyleColor(ImGuiCol_Header,        _uc(imgui.GetColorU32(ImGuiCol_Button)));
        imgui.PushStyleColor(ImGuiCol_HeaderHovered, _uc(imgui.GetColorU32(ImGuiCol_ButtonHovered)));
        imgui.PushStyleColor(ImGuiCol_HeaderActive,  _uc(imgui.GetColorU32(ImGuiCol_ButtonActive)));
    end
    push_header_btn();
    local skills_open = imgui.CollapsingHeader('Skills##cskflt');
    imgui.PopStyleColor(3);
    if skills_open then
        local sk_start_x = imgui.GetCursorPosX();
        local sk_avail_w = imgui.GetContentRegionAvailWidth();
        for i, sk in ipairs(CRAFT_SKILL_KEYS) do
            if (i - 1) % 2 == 1 then imgui.SameLine(sk_start_x + math.floor(sk_avail_w / 2)); end
            if craft_skill_vars[sk] then
                imgui.Checkbox(CRAFT_SKILL_NAMES[sk] .. '##csk', craft_skill_vars[sk]);
            end
        end
    end

    -- Equipment slot filter
    imgui.Spacing();
    push_header_btn();
    local equip_open = imgui.CollapsingHeader('Equipment##cekflt');
    imgui.PopStyleColor(3);
    if equip_open then
        local eq_start_x = imgui.GetCursorPosX();
        local eq_avail_w = imgui.GetContentRegionAvailWidth();
        for i, slot in ipairs(CRAFT_SLOT_ORDER) do
            local col = (i - 1) % 3;
            if col == 1 then imgui.SameLine(eq_start_x + math.floor(eq_avail_w / 3)); end
            if col == 2 then imgui.SameLine(eq_start_x + math.floor(2 * eq_avail_w / 3)); end
            if craft_slot_vars[slot] then
                imgui.SetVarValue(craft_slot_vars[slot], craft_slot_filter == slot);
                if imgui.Checkbox(SLOT_LABEL[slot] .. '##ceq', craft_slot_vars[slot]) then
                    craft_slot_filter = imgui.GetVarValue(craft_slot_vars[slot]) and slot or nil;
                end
            end
        end
    end

    C.draw_fav_section(craft_favorites,
        function() C.save_favorites(CRAFT_FAV_FILE, craft_favorites); end,
        craft_selected,
        function(k) craft_selected = k; imgui.SetVarValue(craft_filter, k); end,
        'craft');

    -- Row 3: filter input + clear
    imgui.Spacing();
    local clear_w = C.calc_text_w('Clear') + 8;
    imgui.PushItemWidth(-(clear_w + FAV_GAP));
    if imgui.InputText('##craft_filter', craft_filter, 64) then
        craft_selected = imgui.GetVarValue(craft_filter);
    end
    imgui.PopItemWidth();
    imgui.SameLine(0, FAV_GAP);
    if imgui.Button('Clear##craft') then
        imgui.SetVarValue(craft_filter, ''); craft_selected = '';
    end
    imgui.Spacing();

    -- Build active skill filter set
    local active_skills = {};
    for _, sk in ipairs(CRAFT_SKILL_KEYS) do
        if craft_skill_vars[sk] and imgui.GetVarValue(craft_skill_vars[sk]) then
            active_skills[sk] = true;
        end
    end
    local has_skill_filter = next(active_skills) ~= nil;

    -- Filtered + sorted recipe list
    local filter_lower = (imgui.GetVarValue(craft_filter) or ''):lower();
    local filtered = {};
    for _, r in ipairs(autocraft.recipe_list) do
        if filter_lower ~= '' and not r.key:find(filter_lower, 1, true) then
            -- skip: text filter mismatch
        else
            local skill_ok = not has_skill_filter;
            local slot_ok  = (craft_slot_filter == nil);
            local max_level = 0;
            if has_skill_filter or craft_sort_mode == 'level' or craft_slot_filter ~= nil then
                -- Filter/level against THIS variant (r.vidx) only — each row is
                -- one recipe now, so it stands or falls on its own skills/slot.
                local v = (autocraft.get_recipe(r.key) or {})[r.vidx];
                if v then
                    for sk, lv in pairs(v.skills or {}) do
                        if not skill_ok and active_skills[sk] then skill_ok = true; end
                        if lv > max_level then max_level = lv; end
                    end
                    if not slot_ok and v.result then
                        local res = AshitaCore:GetResourceManager():GetItemById(v.result);
                        local slot_bits = (res and res.Slots) or 0;
                        if bit.band(slot_bits, SLOT_MASK[craft_slot_filter] or 0) ~= 0 then slot_ok = true; end
                    end
                end
            end
            if skill_ok and slot_ok then
                local display = C.title_case(r.key);
                local label   = (r.variants > 1) and (display .. ' (v' .. r.vidx .. ')') or display;
                table.insert(filtered, { key = r.key, vidx = r.vidx, label = label, max_level = max_level });
            end
        end
    end
    if craft_sort_mode == 'level' then
        table.sort(filtered, function(a, b)
            if a.max_level ~= b.max_level then return a.max_level > b.max_level; end
            if a.key ~= b.key then return a.key < b.key; end
            return a.vidx < b.vidx;
        end);
    end
    if #filtered > 0 then
        local cur_vidx = imgui.GetVarValue(craft_variant);
        imgui.BeginChild('##craft_list', 0, 0, false);
        for i, entry in ipairs(filtered) do
            local sel = (entry.key == craft_selected) and (entry.vidx == cur_vidx);
            if imgui.Selectable(entry.label .. '##cr_' .. i, sel) then
                craft_selected = entry.key;
                imgui.SetVarValue(craft_variant, entry.vidx);
                imgui.SetVarValue(craft_filter, C.title_case(entry.key));
            end
        end
        imgui.EndChild();
    end
end

local function draw_recipe_detail(key, variant_idx)
    local variants = autocraft.get_recipe(key);
    if not variants then
        imgui.TextDisabled('No recipe data.');
        return;
    end
    local v = variants[variant_idx] or variants[1];
    if not v then return; end

    local res_mgr = AshitaCore:GetResourceManager();
    local function iname(id)
        local r = res_mgr:GetItemById(id);
        return (r and r.Name and r.Name[0]) and tostring(r.Name[0]):gsub('%z','') or ('item#'..id);
    end

    -- Skills
    local skill_parts = {};
    for k, lv in pairs(v.skills or {}) do
        local sname = CRAFT_SKILL_NAMES[k] or k;
        skill_parts[#skill_parts+1] = sname .. ' ' .. lv;
    end
    if #skill_parts > 0 then
        table.sort(skill_parts);
        imgui.TextDisabled('Skills');
        imgui.Text(table.concat(skill_parts, ' / '));
        imgui.Spacing();
    end

    -- Crystal
    imgui.TextDisabled('Crystal');
    imgui.Text(iname(v.crystal));
    imgui.Dummy(0, 8);

    -- Ingredients: deduplicate and count
    local ing_counts = {};
    local ing_order  = {};
    for _, id in ipairs(v.ingredients or {}) do
        if not ing_counts[id] then
            ing_counts[id] = 0;
            ing_order[#ing_order+1] = id;
        end
        ing_counts[id] = ing_counts[id] + 1;
    end

    -- Inventory counts from cache (check all bags)
    local function inv_count(item_id)
        local total = 0;
        for _, bag in pairs(inv_cache_lib.get_all()) do
            for _, entry in pairs(bag) do
                if entry.id == item_id then total = total + entry.count; end
            end
        end
        return total;
    end

    -- Possible synths (limiting ingredient)
    local crystal_have = inv_count(v.crystal);
    local min_synths   = crystal_have;  -- crystal counts as ×1
    for _, id in ipairs(ing_order) do
        local need  = ing_counts[id];
        local have  = inv_count(id);
        local possible = math.floor(have / need);
        if possible < min_synths then min_synths = possible; end
    end

    imgui.TextDisabled('Ingredients');
    for _, id in ipairs(ing_order) do
        local need  = ing_counts[id];
        local have  = inv_count(id);
        local possible = math.floor(have / need);
        local label = string.format('%s ×%d', iname(id), need);
        imgui.Text(label);
        imgui.SameLine();
        if have >= need then
            imgui.PushStyleColor(ImGuiCol_Text, 0.40, 0.90, 0.40, 1.0);
        else
            imgui.PushStyleColor(ImGuiCol_Text, 0.90, 0.35, 0.35, 1.0);
        end
        imgui.Text(string.format('(%d)', have));
        imgui.PopStyleColor();
    end
    -- Crystal row
    do
        local have = crystal_have;
        imgui.Text(iname(v.crystal) .. ' ×1');
        imgui.SameLine();
        if have >= 1 then
            imgui.PushStyleColor(ImGuiCol_Text, 0.40, 0.90, 0.40, 1.0);
        else
            imgui.PushStyleColor(ImGuiCol_Text, 0.90, 0.35, 0.35, 1.0);
        end
        imgui.Text(string.format('(%d)', have));
        imgui.PopStyleColor();
    end
    imgui.Dummy(0, 8);

    -- Possible synths
    imgui.TextDisabled('Possible synths');
    imgui.Text(tostring(min_synths));
    imgui.Dummy(0, 8);

    -- NQ result
    imgui.TextDisabled('Result');
    imgui.Text(string.format('%s ×%d', iname(v.result), v.qty));
    imgui.Dummy(0, 8);

    -- HQ results (show if any differ from NQ)
    if v.hq and #v.hq > 0 then
        local hq_lines = {};
        for i, hqid in ipairs(v.hq) do
            local qty  = (v.hqqty and v.hqqty[i]) or 1;
            local line = string.format('HQ%d  %s ×%d', i, iname(hqid), qty);
            local dup  = false;
            for _, prev in ipairs(hq_lines) do if prev == line then dup = true; break; end end
            if not dup then hq_lines[#hq_lines+1] = line; end
        end
        if #hq_lines > 0 then
            imgui.TextDisabled('HQ Results');
            for _, line in ipairs(hq_lines) do imgui.Text(line); end
        end
    end
end

local function draw_craft_tab()
    -- task #116: thread state.selected_char into autocraft so FAST_SYNTH is wrapped
    -- in 0x19A and dispatched as the target char (doInstantSynth runs server-
    -- side, no animation gating needed; COMBINE_ANS is mirrored back).
    autocraft.target_name = state.selected_char;
    imgui.BeginChild('##craft_left', 260, 0, false);
    draw_craft_row();
    imgui.EndChild();
    imgui.SameLine(0, 30);
    imgui.BeginChild('##craft_right', 260, 0, false);
    if craft_selected ~= '' then
        local vcount = 1;
        for _, r in ipairs(autocraft.recipe_list) do
            if r.key == craft_selected:lower() then vcount = r.variants; break; end
        end
        local vidx = (vcount > 1 and craft_variant) and imgui.GetVarValue(craft_variant) or 1;
        imgui.Spacing();
        imgui.Text(C.title_case(craft_selected));
        if vcount > 1 then
            imgui.SameLine(0, 8);
            imgui.TextDisabled('v' .. tostring(vidx) .. ' / ' .. tostring(vcount));
        end
        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();
        draw_recipe_detail(craft_selected, vidx);

        -- Buy Ingredients section
        imgui.Dummy(0, 8);
        imgui.Separator();
        imgui.Dummy(0, 8);
        local buy_avail_w = imgui.GetContentRegionAvailWidth();
        imgui.SetCursorPosX(math.floor((buy_avail_w - C.calc_text_w('Buy Ingredients')) / 2));
        autoutil.section_head('Buy Ingredients');
        imgui.Dummy(0, 8);
        imgui.SetCursorPosX(C.radio_center_x({'Single', 'Stack'}, STEPPER_W));
        if imgui.RadioButton('Single##ing', craft_ing_mode == 'single') then craft_ing_mode = 'single'; end
        imgui.SameLine();
        if imgui.RadioButton('Stack##ing', craft_ing_mode == 'stack') then craft_ing_mode = 'stack'; end
        imgui.SameLine();
        if craft_ing_qty then C.stepper('craft_ing_qty', craft_ing_qty, 1); end
        imgui.Dummy(0, 8);
        local buy_btn_w = 100;
        imgui.SetCursorPosX(math.floor((buy_avail_w - buy_btn_w) / 2));
        if imgui.Button('Buy##craftbuy', buy_btn_w, 0) then
            local qty  = craft_ing_qty and math.max(1, imgui.GetVarValue(craft_ing_qty)) or 1;
            local args = { 'recipe', craft_selected, 'v' .. tostring(vidx), craft_ing_mode, tostring(qty) };
            autobuy.on_command(args);
        end
    else
        imgui.TextDisabled('Select a recipe to see details.');
    end
    imgui.EndChild();
end

function M.on_load()
    craft_filter  = imgui.CreateVar(ImGuiVar_CDSTRING, 64);
    craft_variant = imgui.CreateVar(ImGuiVar_INT32);
    imgui.SetVarValue(craft_variant, 1);
    craft_limit_n = imgui.CreateVar(ImGuiVar_INT32);
    imgui.SetVarValue(craft_limit_n, 1);
    craft_ing_qty = imgui.CreateVar(ImGuiVar_INT32);
    imgui.SetVarValue(craft_ing_qty, 1);
    for _, sk in ipairs(CRAFT_SKILL_KEYS) do
        craft_skill_vars[sk] = imgui.CreateVar(ImGuiVar_BOOLCPP);
    end
    for _, slot in ipairs(CRAFT_SLOT_ORDER) do
        craft_slot_vars[slot] = imgui.CreateVar(ImGuiVar_BOOLCPP);
    end
    craft_favorites = C.load_favorites(CRAFT_FAV_FILE);
end

function M.on_unload()
    if craft_filter ~= nil then
        imgui.DeleteVar(craft_filter);
        craft_filter = nil;
    end
    if craft_variant ~= nil then
        imgui.DeleteVar(craft_variant);
        craft_variant = nil;
    end
    if craft_limit_n ~= nil then
        imgui.DeleteVar(craft_limit_n);
        craft_limit_n = nil;
    end
    if craft_ing_qty ~= nil then
        imgui.DeleteVar(craft_ing_qty);
        craft_ing_qty = nil;
    end
    for _, sk in ipairs(CRAFT_SKILL_KEYS) do
        if craft_skill_vars[sk] ~= nil then
            imgui.DeleteVar(craft_skill_vars[sk]);
            craft_skill_vars[sk] = nil;
        end
    end
    for _, slot in ipairs(CRAFT_SLOT_ORDER) do
        if craft_slot_vars[slot] ~= nil then
            imgui.DeleteVar(craft_slot_vars[slot]);
            craft_slot_vars[slot] = nil;
        end
    end
end

M.draw = draw_craft_tab;

return M
