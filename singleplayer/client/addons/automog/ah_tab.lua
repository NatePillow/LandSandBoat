-- ah_tab.lua — Auction House tab (browse + buy + sell + my-listings),
-- extracted verbatim from automog.lua. Shared code is reached via C.<name>
-- (automog_common) and shared state via state.<x> (automog_state).

local M = {};

local C               = require('automog_common');
local state           = require('automog_state');
local autoutil        = require('autoutil');
local autobuy         = require('autobuy');
local autosell        = require('autosell');
local http_client     = require('http_client');
local json            = require('json');
local loading_overlay = require('loading_overlay');

-- Fav-file path, self-contained (Ashita v3: debug.getinfo on THIS file).
local _src        = ((debug.getinfo(1, 'S').source or ''):match('^@(.+)$') or ''):gsub('[\\/][\\/]+', '\\');
local _addon_dir  = _src:match('^(.*[/\\])[^/\\]+$') or '';
local _ashita_root = _addon_dir:match('^(.*[/\\])[Aa]ddons[/\\]') or '';
local BUY_FAV_FILE   = _ashita_root .. 'config\\automog\\buy_favorites.txt';

-- Layout constants (copies of the main file's shared locals).
local STEPPER_W = 82;  -- stepper: 3×22px buttons + 2×8px default SameLine gaps
local FAV_GAP      = 4;

--------------------------------------------------------------------------------
-- State locals (sliced verbatim from automog.lua)
--------------------------------------------------------------------------------
local sell_filter   = nil;
local sell_selected = '';
local sell_qty      = nil;
local sell_mode     = 'single';
local buy_filter    = nil;
local buy_selected  = '';
local buy_variant   = nil;
local buy_qty       = nil;
local buy_mode      = 'single';
local buy_subcmd    = 'item';
local buy_partial_var = nil;
local buy_favorites    = {};
local ah_filter        = nil;
local ah_filter_job    = nil;
local ah_filter_lv     = nil;
local ah_stat_vars     = {};

-- AH browse state
local ah_nav_level     = 0;   -- 0=top cats, 1=sub-cats, 2=items
local ah_nav_top_idx   = nil; -- index into AH_CATS
local ah_nav_cat_id    = nil; -- aH ID currently browsing
local ah_nav_cat_label = '';  -- breadcrumb string (e.g. "Weapons > Sword")
local ah_item_selected = nil; -- {id, name, single_count, stack_count, min_single_price, min_stack_price, stack_size, ...}

-- MY_LISTINGS state. Populated by GET /ah/listings on tab open and after
-- each mutation. Nil = never fetched; empty = fetched, no listings.
local my_listings         = nil;
local my_listings_char    = nil;   -- char the current cache is for
local my_listings_loading = false;

-- Cancel in-flight tracking. Each listingId gets stamped when we fire the
-- cancel op so the row can render "Cancelling..." until refresh.
local cancel_in_flight = {};

--------------------------------------------------------------------------------
-- Data tables (sliced verbatim from automog.lua)
--------------------------------------------------------------------------------
local PRIMARY_STATS = { 'STR', 'DEX', 'VIT', 'AGI', 'INT', 'MND', 'CHR' };
local DERIVED_STATS = { 'ATK', 'ACC', 'DEF', 'EVA', 'RACC', 'RATK', 'MACC', 'MEVA', 'MAB', 'MDB', 'Haste', 'STP', 'Enmity', 'SB', 'DA', 'TA', 'Crit' };

-- AH category hierarchy. Mirrors the nine top-level groups the FFXI vanilla
-- client uses (Weapons / Armor / Scrolls / Medicines / Furnishings /
-- Materials / Food / Crystals / Others). IDs are the engine's item_basic.aH
-- enum — see sql/item_basic.sql `SET @<name> = <id>;` declarations for the
-- authoritative source. Don't rename labels to match retail without checking
-- which SQL id they actually map to (we got bitten earlier with Geomancy
-- showing up under Crafting because id 45 is a scroll, not a material).
local AH_CATS = {
    { label = 'Weapons', equip = true, subs = {
        { label = 'Hand-to-Hand', id = 1  },
        { label = 'Dagger',       id = 2  },
        { label = 'Sword',        id = 3  },
        { label = 'Great Sword',  id = 4  },
        { label = 'Axe',          id = 5  },
        { label = 'Great Axe',    id = 6  },
        { label = 'Scythe',       id = 7  },
        { label = 'Polearm',      id = 8  },
        { label = 'Katana',       id = 9  },
        { label = 'Great Katana', id = 10 },
        { label = 'Club',         id = 11 },
        { label = 'Staff',        id = 12 },
        { label = 'Ranged',       id = 13 }, -- bows, crossbows, guns — Weapons->Bow
        { label = 'Instruments',  id = 14 },
        { label = 'Ammunition',   id = 15 },
        { label = 'Fishing Gear', id = 47 }, -- Weapons->Ammo&Misc
        { label = 'Pet Items',    id = 48 }, -- Weapons->Ammo&Misc
        { label = 'Grips',        id = 62 }, -- Weapons->Ammo&Misc
    }},
    { label = 'Armor', equip = true, subs = {
        { label = 'Shield',   id = 16 },
        { label = 'Head',     id = 17 },
        { label = 'Body',     id = 18 },
        { label = 'Hands',    id = 19 },
        { label = 'Legs',     id = 20 },
        { label = 'Feet',     id = 21 },
        { label = 'Neck',     id = 22 },
        { label = 'Waist',    id = 23 },
        { label = 'Earrings', id = 24 },
        { label = 'Rings',    id = 25 },
        { label = 'Back',     id = 26 },
    }},
    { label = 'Scrolls', subs = {
        { label = 'White Magic', id = 28 },
        { label = 'Black Magic', id = 29 },
        { label = 'Summoning',   id = 30 },
        { label = 'Ninjutsu',    id = 31 },
        { label = 'Songs',       id = 32 },
        { label = 'Geomancy',    id = 45 },
        { label = 'Dice',        id = 60 },
    }},
    { label = 'Medicines',   id = 33 },
    { label = 'Furnishings', id = 34 },
    { label = 'Materials', subs = {
        { label = 'Smithing',      id = 38 },
        { label = 'Goldsmithing',  id = 39 },
        { label = 'Clothcraft',    id = 40 },
        { label = 'Leathercraft',  id = 41 },
        { label = 'Bonecraft',     id = 42 },
        { label = 'Woodworking',   id = 43 },
        { label = 'Alchemy',       id = 44 },
        { label = 'Alchemy 2',     id = 63 },
    }},
    { label = 'Food', subs = {
        { label = 'Fish',          id = 51 },
        { label = 'Meat & Eggs',   id = 52 },
        { label = 'Seafood',       id = 53 },
        { label = 'Vegetables',    id = 54 },
        { label = 'Soups',         id = 55 },
        { label = 'Breads & Rice', id = 56 },
        { label = 'Sweets',        id = 57 },
        { label = 'Drinks',        id = 58 },
        { label = 'Ingredients',   id = 59 },
    }},
    { label = 'Crystals', id = 35 },
    { label = 'Others', subs = {
        { label = 'Cards',        id = 36 },
        { label = 'Cursed Items', id = 37 },
        { label = 'Misc',         id = 46 },
        { label = 'Ninja Tools',  id = 49 },
        { label = 'Beast Made',   id = 50 },
        { label = 'Automaton',    id = 61 },
        { label = 'Misc 2',       id = 64 },
        { label = 'Misc 3',       id = 65 },
    }},
};

--------------------------------------------------------------------------------
-- Functions (sliced verbatim from automog.lua)
--------------------------------------------------------------------------------
-- AH browse: navigate categories and request item stock data
local function draw_ah_browser()
    -- Back button + breadcrumb
    if ah_nav_level > 0 then
        if imgui.Button('< Back##ahbk') then
            if ah_nav_level == 2 and ah_nav_cat_id then
                state.ah_cat_cache[ah_nav_cat_id] = nil;
            end
            ah_nav_level = ah_nav_level - 1;
            if ah_nav_level == 0 then
                ah_nav_top_idx = nil; ah_nav_cat_id = nil; ah_nav_cat_label = '';
            else
                ah_nav_cat_id = nil;
            end
            ah_item_selected = nil;
            imgui.SetVarValue(ah_filter, '');
        end
        imgui.SameLine();
        imgui.TextDisabled(ah_nav_cat_label);
    else
        imgui.TextDisabled('Browse Categories');
    end
    imgui.Separator();

    if ah_nav_level == 0 then
        -- Top-level category list
        imgui.BeginChild('##ah_cats', 0, 0, false);
        local avail_w = imgui.GetContentRegionAvailWidth();
        for _, cat in ipairs(AH_CATS) do
            if imgui.Button(cat.label .. '##ahcat', avail_w, 0) then
                for i, c in ipairs(AH_CATS) do
                    if c == cat then ah_nav_top_idx = i; break; end
                end
                if cat.subs then
                    ah_nav_level     = 1;
                    ah_nav_cat_label = cat.label;
                else
                    -- leaf: go straight to items
                    ah_nav_level     = 2;
                    ah_nav_cat_id    = cat.id;
                    ah_nav_cat_label = cat.label;
                    if not (state.ah_cat_cache[cat.id] and state.ah_cat_cache[cat.id].complete) then
                        C.send_ah_cat_query(cat.id);
                    end
                end
            end
        end
        imgui.EndChild();

    elseif ah_nav_level == 1 then
        -- Sub-category list
        local top = AH_CATS[ah_nav_top_idx];
        if not top or not top.subs then ah_nav_level = 0; return; end
        imgui.BeginChild('##ah_subs', 0, 0, false);
        local avail_w = imgui.GetContentRegionAvailWidth();
        for _, sub in ipairs(top.subs) do
            if imgui.Button(sub.label .. '##ahsub', avail_w, 0) then
                ah_nav_level     = 2;
                ah_nav_cat_id    = sub.id;
                ah_nav_cat_label = top.label .. ' > ' .. sub.label;
                if not (state.ah_cat_cache[sub.id] and state.ah_cat_cache[sub.id].complete) then
                    C.send_ah_cat_query(sub.id);
                end
            end
        end
        imgui.EndChild();

    else
        -- Item list for selected category
        local cat_id = ah_nav_cat_id;
        if not cat_id then ah_nav_level = 0; return; end
        local cat_entry = state.ah_cat_cache[cat_id];

        -- Filter panel
        imgui.PushItemWidth(imgui.GetContentRegionAvailWidth() - 28);
        imgui.InputText('##ahflt', ah_filter, 64);
        imgui.PopItemWidth();
        imgui.SameLine(0, 4);
        if imgui.Button('X##ahfx') then imgui.SetVarValue(ah_filter, ''); end

        local is_equip = ah_nav_top_idx and AH_CATS[ah_nav_top_idx] and AH_CATS[ah_nav_top_idx].equip;
        if is_equip then
            imgui.Checkbox('Job##ahj', ah_filter_job);
            imgui.SameLine();
            imgui.Checkbox('Level##ahl', ah_filter_lv);

            if imgui.CollapsingHeader('Primary Stats##ahp') then
                for i, stat in ipairs(PRIMARY_STATS) do
                    if i > 1 and (i - 1) % 4 ~= 0 then imgui.SameLine(); end
                    imgui.Checkbox(stat .. '##ahps', ah_stat_vars[stat]);
                end
            end
            if imgui.CollapsingHeader('Derived Stats##ahd') then
                for i, stat in ipairs(DERIVED_STATS) do
                    if i > 1 and (i - 1) % 4 ~= 0 then imgui.SameLine(); end
                    imgui.Checkbox(stat .. '##ahds', ah_stat_vars[stat]);
                end
            end
        end
        imgui.Separator();

        if not cat_entry or not cat_entry.complete then
            imgui.TextDisabled('Loading...');
            return;
        end

        -- Build filter state
        local filter_lower = (imgui.GetVarValue(ah_filter) or ''):lower();
        local is_equip = ah_nav_top_idx and AH_CATS[ah_nav_top_idx] and AH_CATS[ah_nav_top_idx].equip;
        local do_job   = is_equip and imgui.GetVarValue(ah_filter_job);
        local do_level = is_equip and imgui.GetVarValue(ah_filter_lv);
        local stat_filters = {};
        if is_equip then
            for _, stat in ipairs(PRIMARY_STATS) do
                if ah_stat_vars[stat] and imgui.GetVarValue(ah_stat_vars[stat]) then
                    table.insert(stat_filters, stat);
                end
            end
            for _, stat in ipairs(DERIVED_STATS) do
                if ah_stat_vars[stat] and imgui.GetVarValue(ah_stat_vars[stat]) then
                    table.insert(stat_filters, stat);
                end
            end
        end

        local job_mask_val = 0;
        local job_lv = 0;
        do
            local player = AshitaCore:GetDataManager():GetPlayer();
            local job_idx = player:GetMainJob();
            job_mask_val = job_idx > 0 and bit.lshift(1, job_idx) or 0;
            job_lv = player:GetMainJobLevel();
        end

        local filtered = {};
        for _, item in ipairs(cat_entry.items) do
            local ok = true;
            if ok and filter_lower ~= '' and not item.name:lower():find(filter_lower, 1, true) then ok = false; end
            if ok and do_job and job_mask_val ~= 0 and item.jobs ~= 0
               and bit.band(item.jobs, job_mask_val) == 0 then ok = false; end
            if ok and do_level and job_lv > 0 and item.level > job_lv then ok = false; end
            if ok and #stat_filters > 0 then
                for _, stat in ipairs(stat_filters) do
                    if not item.stats[stat] then ok = false; break; end
                end
            end
            if ok then table.insert(filtered, item); end
        end

        imgui.TextDisabled(string.format('%d item(s)', #filtered));
        imgui.BeginChild('##ah_items', 0, 0, false);
        local list_w = imgui.GetContentRegionAvailWidth();
        if #filtered == 0 then
            imgui.TextDisabled('(no items match filters)');
        else
            for _, item in ipairs(filtered) do
                local display_count = buy_mode == 'stack' and item.stack_count or item.single_count;
                local name_lbl = item.level and item.level > 0
                    and string.format('[%2d] %s', item.level, item.name)
                    or item.name;
                -- Show the price for the currently selected buy mode — keeps the
                -- list-row gil figure consistent with what the buy will quote.
                local display_price = buy_mode == 'stack' and item.min_stack_price or item.min_single_price;
                local right_str = string.format('x%d  %d g', display_count, display_price or 0);
                local right_w   = C.calc_text_w(right_str);
                local sel = ah_item_selected and ah_item_selected.id == item.id;
                local cy = imgui.GetCursorPosY();
                if imgui.Selectable(name_lbl .. '##ahitem' .. item.id, sel) then
                    if sel then
                        ah_item_selected = nil;
                    else
                        ah_item_selected = item;
                        local max_c = buy_mode == 'stack' and item.stack_count or item.single_count;
                        local cur_qty = imgui.GetVarValue(buy_qty);
                        if cur_qty > max_c then
                            imgui.SetVarValue(buy_qty, math.max(1, max_c));
                        end
                    end
                end
                imgui.SetCursorPosX(list_w - right_w);
                imgui.SetCursorPosY(cy);
                imgui.TextDisabled(right_str);
            end
        end
        imgui.EndChild();
    end
end

local function draw_buy_row()
    local buy = autobuy.state;
    autoutil.section_head('Buy from Auction House');
    imgui.Dummy(0, 6);

    -- Row 1: Start (left 1/3) / Stop (right 1/3)
    local avail_w = imgui.GetContentRegionAvailWidth();
    local btn_w   = math.floor((avail_w - 2 * FAV_GAP) / 3);
    local sx      = imgui.GetCursorPosX();
    local is_partial = buy_partial_var ~= nil and imgui.GetVarValue(buy_partial_var) or false;
    if imgui.Button('Buy##buy', btn_w, 0) then
        if buy_subcmd == 'item' then
            if ah_item_selected then
                local is_stack = buy_mode == 'stack';
                local qty = imgui.GetVarValue(buy_qty);
                local max_c = is_stack and ah_item_selected.stack_count or ah_item_selected.single_count;
                qty = math.max(1, math.min(qty, max_c));
                local bid_price = is_stack and ah_item_selected.min_stack_price or ah_item_selected.min_single_price;
                autobuy.buy_item_direct(ah_item_selected.id, is_stack, qty, bid_price);
            end
        elseif buy_subcmd == 'group' then
            local name = imgui.GetVarValue(buy_filter):gsub('%z', '');
            if name ~= '' then
                local args = {'group', name};
                if is_partial then table.insert(args, 'partial'); end
                autobuy.on_command(args);
            end
        else
            local name = imgui.GetVarValue(buy_filter):gsub('%z', '');
            if name ~= '' then
                local qty     = imgui.GetVarValue(buy_qty);
                local variant = imgui.GetVarValue(buy_variant);
                local subcmd  = is_partial and 'partial' or 'recipe';
                local args    = { subcmd, name };
                local vcount  = 1;
                local lname   = name:lower();
                for _, r in ipairs(autobuy.recipe_list) do
                    if r.key == lname then vcount = r.variants; break; end
                end
                if vcount > 1 then
                    table.insert(args, 'v' .. tostring(variant));
                end
                table.insert(args, buy_mode);
                table.insert(args, tostring(qty));
                autobuy.on_command(args);
            end
        end
    end
    imgui.SameLine(0, 0);
    local cb_x = sx + btn_w + FAV_GAP + math.floor((btn_w - C.calc_text_w('Partial') - 20) / 2);
    imgui.SetCursorPosX(cb_x);
    if buy_partial_var ~= nil then imgui.Checkbox('Partial##buy', buy_partial_var); end
    imgui.SameLine(0, 0);
    imgui.SetCursorPosX(sx + 2 * (btn_w + FAV_GAP));
    C.stop_button('Stop##buy', buy.active, function() autobuy.stop(); end, btn_w);
    imgui.Dummy(0, 6);

    -- Row 2: sub-command radios (centered)
    imgui.SetCursorPosX(C.radio_center_x({'Item', 'Recipe', 'Group'}, 0));
    if imgui.RadioButton('Item##buy', buy_subcmd == 'item') then
        buy_subcmd = 'item'; imgui.SetVarValue(buy_filter, '');
    end
    imgui.SameLine();
    if imgui.RadioButton('Recipe##buy', buy_subcmd == 'recipe') then
        buy_subcmd = 'recipe'; imgui.SetVarValue(buy_filter, ''); buy_selected = '';
    end
    imgui.SameLine();
    if imgui.RadioButton('Group##buy', buy_subcmd == 'group') then
        buy_subcmd = 'group'; imgui.SetVarValue(buy_filter, ''); buy_selected = '';
    end

    if buy_subcmd == 'item' then
        -- Item mode: show selected item info + Single/Stack + qty
        imgui.Spacing();
        local max_qty    = ah_item_selected and (buy_mode == 'stack' and ah_item_selected.stack_count or ah_item_selected.single_count) or 99;
        local can_stack  = ah_item_selected and (ah_item_selected.stack_size or 1) > 1;
        if not can_stack and buy_mode == 'stack' then buy_mode = 'single'; end
        imgui.SetCursorPosX(C.radio_center_x({'Single', 'Stack'}, STEPPER_W));
        if imgui.RadioButton('Single##buy', buy_mode == 'single') then buy_mode = 'single'; end
        imgui.SameLine();
        if not can_stack then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
        if imgui.RadioButton('Stack##buy', buy_mode == 'stack') and can_stack then buy_mode = 'stack'; end
        if not can_stack then imgui.PopStyleVar(); end
        imgui.SameLine();
        do
            local cur = imgui.GetVarValue(buy_qty);
            if cur > max_qty then imgui.SetVarValue(buy_qty, math.max(1, max_qty)); end
        end
        C.stepper('buy_qty', buy_qty, 1);
        -- cap on + press
        do
            local cur = imgui.GetVarValue(buy_qty);
            if cur > max_qty then imgui.SetVarValue(buy_qty, math.max(1, max_qty)); end
        end
        imgui.Spacing();
        local cx = imgui.GetCursorPosX(); local avail_c = imgui.GetContentRegionAvailWidth();
        if ah_item_selected then
            local nw = C.calc_text_w(ah_item_selected.name);
            imgui.SetCursorPosX(cx + math.max(0, math.floor((avail_c - nw) / 2)));
            imgui.TextDisabled(ah_item_selected.name);
            local avail_c_display = buy_mode == 'stack' and ah_item_selected.stack_count or ah_item_selected.single_count;
            local detail_price    = buy_mode == 'stack' and ah_item_selected.min_stack_price or ah_item_selected.min_single_price;
            local detail = string.format('x%d available  |  %d gil min', avail_c_display, detail_price or 0);
            local dw = C.calc_text_w(detail);
            imgui.SetCursorPosX(cx + math.max(0, math.floor((avail_c - dw) / 2)));
            imgui.Text(detail);
        else
            local hw = C.calc_text_w('(select an item from browser)');
            imgui.SetCursorPosX(cx + math.max(0, math.floor((avail_c - hw) / 2)));
            imgui.TextDisabled('(select an item from browser)');
        end
        imgui.Spacing();
        imgui.BeginChild('##bim_browser', 0, 0, false);
        draw_ah_browser();
        imgui.EndChild();
        return;
    end

    -- Row 3: single/stack + qty centered (recipe/partial)
    imgui.Spacing();
    if buy_subcmd ~= 'group' then
        imgui.SetCursorPosX(C.radio_center_x({'Single', 'Stack'}, STEPPER_W));
        if imgui.RadioButton('Single##buy', buy_mode == 'single') then buy_mode = 'single'; end
        imgui.SameLine();
        if imgui.RadioButton('Stack##buy', buy_mode == 'stack') then buy_mode = 'stack'; end
        imgui.SameLine();
        C.stepper('buy_qty', buy_qty, 1);
        local lname  = (imgui.GetVarValue(buy_filter) or ''):lower();
        local vcount = 1;
        for _, r in ipairs(autobuy.recipe_list) do
            if r.key == lname then vcount = r.variants; break; end
        end
        if vcount > 1 then
            imgui.SameLine();
            imgui.Text('v');
            imgui.SameLine();
            C.stepper('buy_variant', buy_variant, 1);
        end
    end

    C.draw_fav_section(buy_favorites,
        function() C.save_favorites(BUY_FAV_FILE, buy_favorites); end,
        buy_selected,
        function(k) buy_selected = k; imgui.SetVarValue(buy_filter, k); end,
        'buy');

    -- Row 4: filter input + clear
    imgui.Spacing();
    local clear_w = C.calc_text_w('Clear') + 8;
    imgui.PushItemWidth(-(clear_w + FAV_GAP));
    if imgui.InputText('##buy_filter', buy_filter, 64) then
        buy_selected = imgui.GetVarValue(buy_filter);
    end
    imgui.PopItemWidth();
    imgui.SameLine(0, FAV_GAP);
    if imgui.Button('Clear##buy') then
        imgui.SetVarValue(buy_filter, ''); buy_selected = '';
    end
    imgui.Spacing();

    -- Filtered list
    local filter_lower = (imgui.GetVarValue(buy_filter) or ''):lower();
    local filtered = {};
    if buy_subcmd == 'group' then
        local source = autobuy.group_list or {};
        for _, name in ipairs(source) do
            if filter_lower == '' or name:lower():find(filter_lower, 1, true) then
                table.insert(filtered, name);
            end
        end
    else
        for _, r in ipairs(autobuy.recipe_list) do
            if filter_lower == '' or r.key:find(filter_lower, 1, true) then
                local display = C.title_case(r.key);
                local label   = r.variants > 1 and (display .. ' (v' .. r.variants .. ')') or display;
                table.insert(filtered, { key = r.key, label = label });
            end
        end
    end

    if #filtered > 0 then
        imgui.BeginChild('##buy_list', 0, 0, false);
        if buy_subcmd == 'group' then
            for _, name in ipairs(filtered) do
                if imgui.Selectable(C.title_case(name), name == buy_selected) then
                    buy_selected = name;
                    imgui.SetVarValue(buy_filter, C.title_case(name));
                end
            end
        else
            for _, entry in ipairs(filtered) do
                if imgui.Selectable(entry.label, entry.key == buy_selected) then
                    buy_selected = entry.key;
                    imgui.SetVarValue(buy_filter, C.title_case(entry.key));
                end
            end
        end
        imgui.EndChild();
    end
end

local function draw_sell_row()
    local sell = autosell.state;
    autoutil.section_head('Sell to Auction House');
    imgui.Dummy(0, 6);
    -- Row 1: Start (left 1/3) / Stop (right 1/3)
    local avail_w = imgui.GetContentRegionAvailWidth();
    local btn_w   = math.floor((avail_w - 2 * FAV_GAP) / 3);
    local sx      = imgui.GetCursorPosX();
    if imgui.Button('Sell##sell', btn_w, 0) then
        local name = imgui.GetVarValue(sell_filter):gsub('%z', '');
        local qty  = imgui.GetVarValue(sell_qty);
        if name ~= '' and qty and qty > 0 then
            local slots = C.find_inv_slots_by_name(name);
            if #slots == 0 then
                autoutil.log('AutoSell', 'No items found matching: ' .. name);
            else
                autosell.queue_sells(slots, sell_mode == 'stack', qty);
            end
        end
    end
    imgui.SameLine(0, 0);
    imgui.SetCursorPosX(sx + 2 * (btn_w + FAV_GAP));
    C.stop_button('Stop##sell', sell.active, function() autosell.on_command({'stop'}); end, btn_w);
    imgui.Dummy(0, 6);

    -- Row 2: single/stack + qty (centered)
    imgui.SetCursorPosX(C.radio_center_x({'Single', 'Stack'}, STEPPER_W));
    if imgui.RadioButton('Single##sell', sell_mode == 'single') then sell_mode = 'single'; end
    imgui.SameLine();
    if imgui.RadioButton('Stack##sell', sell_mode == 'stack') then sell_mode = 'stack'; end
    imgui.SameLine();
    C.stepper('sell_qty', sell_qty, 1);

    -- Row 3: filter input + clear
    imgui.Spacing();
    local clear_w = C.calc_text_w('Clear') + 8;
    imgui.PushItemWidth(-(clear_w + FAV_GAP));
    if imgui.InputText('##sell_filter', sell_filter, 64) then
        sell_selected = imgui.GetVarValue(sell_filter);
    end
    imgui.PopItemWidth();
    imgui.SameLine(0, FAV_GAP);
    if imgui.Button('Clear##sell') then
        imgui.SetVarValue(sell_filter, ''); sell_selected = '';
    end
    imgui.Spacing();

    local filter_lower = (imgui.GetVarValue(sell_filter) or ''):lower();
    local filtered     = {};
    for _, item in ipairs(C.get_inv_items()) do
        if filter_lower == '' or item.name:lower():find(filter_lower, 1, true) then
            table.insert(filtered, item);
        end
    end
    if #filtered > 0 then
        imgui.BeginChild('##sell_list', 0, 0, false);
        for _, item in ipairs(filtered) do
            -- Show count whenever there's more than one — including unstackable
            -- gear (Scorpion Harness, etc.) where stack_size=1 but the player
            -- may have several copies across slots/bags. The earlier gate
            -- (stack_size > 1) hid the count for those entirely. count is the
            -- aggregated total from C.get_inv_items().
            local lbl = item.count > 1
                and (item.name .. ' (' .. item.count .. ')##sell_' .. item.name)
                or  (item.name .. '##sell_' .. item.name);
            if imgui.Selectable(lbl, item.name == sell_selected) then
                sell_selected = item.name;
                imgui.SetVarValue(sell_filter, item.name);
            end
        end
        imgui.EndChild();
    end
end

local function refresh_my_listings(char_name)
    if char_name == nil or char_name == '' then return; end
    my_listings_loading = true;
    my_listings_char    = char_name;
    http_client.get('/ah/listings?for=' .. char_name, function(code, body, _, err)
        my_listings_loading = false;
        if err or code ~= 200 then
            my_listings = {};
            return;
        end
        local ok, arr = pcall(function() return json:decode(body); end);
        my_listings = (ok and type(arr) == 'table') and arr or {};
    end);
end

-- Cancel one listing. Server responds async (post_tick applier); we don't
-- await here — a poller-free "fire and refresh" is fine because the row
-- disappears in the next fetch. Row stays "Cancelling..." until then.
local function fire_cancel(listing_id, char_name)
    if listing_id == nil or listing_id == 0 then return; end
    cancel_in_flight[listing_id] = true;
    local party        = AshitaCore:GetDataManager():GetParty();
    local primary_name = (party and party:GetMemberName(0)) or '';
    local body = {
        by        = primary_name,
        ['for']   = char_name,
        listingId = listing_id,
    };
    http_client.await_op('/ah/cancel', body, nil, function(result, err)
        cancel_in_flight[listing_id] = nil;
        if err then
            autoutil.log('AutoMog', 'Cancel: ' .. err);
        end
        refresh_my_listings(char_name);
    end);
end

local function draw_my_listings_row(target_name)
    autoutil.section_head('My Listings');
    imgui.SameLine();
    if imgui.Button('Refresh##myl', 80, 0) then
        refresh_my_listings(target_name);
    end
    imgui.Dummy(0, 4);

    if my_listings_loading then
        imgui.TextDisabled('Loading...');
        return;
    end
    if my_listings == nil then
        imgui.TextDisabled('(click Refresh to load)');
        return;
    end
    if #my_listings == 0 then
        imgui.TextDisabled('No active listings.');
        return;
    end

    -- Fill remaining child height; server already filters to sale = 0
    -- so every row here is cancelable.
    imgui.BeginChild('##myl_scroll', 0, 0, true);
    for _, row in ipairs(my_listings) do
        local item_name   = C.item_name_for(row.itemId);
        local stack_label = (row.stack ~= 0) and 'stack' or 'single';
        imgui.Text(string.format('%s (%s) - %d gil',
            item_name, stack_label, row.price));
        imgui.SameLine();
        if cancel_in_flight[row.id] then
            imgui.TextDisabled('  Cancelling...');
        else
            if imgui.Button('Cancel##cancel_' .. tostring(row.id), 80, 0) then
                fire_cancel(row.id, target_name);
            end
        end
        imgui.Spacing();
    end
    imgui.EndChild();
end

local function draw_ah_tab()
    -- Loading-overlay short-circuit: while an HTTP AH op (sell/buy/cancel)
    -- is in flight the tab renders the overlay instead of its normal
    -- content. Full-tab replacement, not a modal — matches the "block the
    -- UI until the op completes" UX call.
    if loading_overlay.is_locked('automog:ah') then
        loading_overlay.render('automog:ah');
        return;
    end

    autobuy.target_name  = state.selected_char;
    autosell.target_name = state.selected_char;

    -- My Listings section intentionally disabled — user asked to hide it
    -- for now but keep the code (draw_my_listings_row / refresh_my_listings
    -- / fire_cancel / item_name_for and the server /ah/listings endpoint)
    -- in place in case we want to bring it back. Re-enable by uncommenting
    -- the refresh-on-char-change guard and the ##ah_listings_pane child
    -- below, and restoring the 2/3 sell split.

    -- Left = Buy, Right = Sell. Both fill to the panel's remaining height
    -- via height=0 (safe because the automog window is fixed-size, not
    -- AlwaysAutoResize).
    imgui.BeginChild('##ah_left', 260, 0, false);
    draw_buy_row();
    imgui.EndChild();
    imgui.SameLine(0, 30);
    imgui.BeginChild('##ah_right', 260, 0, false);
    draw_sell_row();
    imgui.EndChild();
end

--------------------------------------------------------------------------------
-- ImGuiVar lifecycle
--------------------------------------------------------------------------------
M.on_load = function()
    sell_filter = imgui.CreateVar(ImGuiVar_CDSTRING, 64);
    sell_qty    = imgui.CreateVar(ImGuiVar_INT32);
    imgui.SetVarValue(sell_qty, 1);
    buy_filter      = imgui.CreateVar(ImGuiVar_CDSTRING, 64);
    buy_partial_var = imgui.CreateVar(ImGuiVar_BOOLCPP);
    buy_variant     = imgui.CreateVar(ImGuiVar_INT32);
    imgui.SetVarValue(buy_variant, 1);
    buy_qty     = imgui.CreateVar(ImGuiVar_INT32);
    imgui.SetVarValue(buy_qty, 1);
    ah_filter     = imgui.CreateVar(ImGuiVar_CDSTRING, 64);
    ah_filter_job = imgui.CreateVar(ImGuiVar_BOOLCPP);
    ah_filter_lv  = imgui.CreateVar(ImGuiVar_BOOLCPP);
    imgui.SetVarValue(ah_filter_job, true);
    imgui.SetVarValue(ah_filter_lv, false);
    for _, stat in ipairs(PRIMARY_STATS) do
        ah_stat_vars[stat] = imgui.CreateVar(ImGuiVar_BOOLCPP);
    end
    for _, stat in ipairs(DERIVED_STATS) do
        ah_stat_vars[stat] = imgui.CreateVar(ImGuiVar_BOOLCPP);
    end
    buy_favorites = C.load_favorites(BUY_FAV_FILE);
end

M.on_unload = function()
    if sell_filter ~= nil then
        imgui.DeleteVar(sell_filter);
        sell_filter = nil;
    end
    if sell_qty ~= nil then
        imgui.DeleteVar(sell_qty);
        sell_qty = nil;
    end
    if buy_partial_var ~= nil then imgui.DeleteVar(buy_partial_var); buy_partial_var = nil; end
    if buy_filter ~= nil then
        imgui.DeleteVar(buy_filter);
        buy_filter = nil;
    end
    if buy_variant ~= nil then
        imgui.DeleteVar(buy_variant);
        buy_variant = nil;
    end
    if buy_qty ~= nil then
        imgui.DeleteVar(buy_qty);
        buy_qty = nil;
    end
    if ah_filter     ~= nil then imgui.DeleteVar(ah_filter);     ah_filter     = nil; end
    if ah_filter_job ~= nil then imgui.DeleteVar(ah_filter_job); ah_filter_job = nil; end
    if ah_filter_lv  ~= nil then imgui.DeleteVar(ah_filter_lv);  ah_filter_lv  = nil; end
    for _, v in pairs(ah_stat_vars) do
        if v ~= nil then imgui.DeleteVar(v); end
    end
    ah_stat_vars = {};
end

M.draw = draw_ah_tab;

return M;
