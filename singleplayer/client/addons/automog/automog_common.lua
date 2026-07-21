-- AutoMog shared helpers.
--
-- Small stateless-ish helper functions extracted from the former monolithic
-- automog.lua so the sibling *_tab.lua files and the main file can share one
-- copy instead of each re-implementing them. Other files require this module
-- (conventionally as `C`) and call each helper as C.<name>.
--
-- imgui-free? No — several helpers draw (they use the Ashita imgui global).
-- These functions call ONLY each other + libs (inv_cache) + state
-- (automog_state) + Ashita globals (imgui, AshitaCore, struct,
-- AddOutgoingPacket, io, os, string, table, math, ...). None of them reach
-- back into automog.lua.
--
-- NOTE on the mirrored constants below: a handful of module-level constants
-- (layout numbers, TRANSFER_BAGS, WARDROBE_BAG_IDS, the two custom opcodes)
-- still also live in automog.lua because functions that stay there reference
-- them. They are immutable, so duplicating them here is safe. The MUTABLE
-- AH-browse state is NOT duplicated: send_ah_cat_query reads/writes
-- state.ah_cat_cache / state.ah_browse_requesting so it shares one source of
-- truth with automog.lua's AH-browse readers (incoming-packet handler + AH
-- tab render).

local M = {}

local inv_cache_lib = require('inv_cache');
local state         = require('automog_state');

-- ---------------------------------------------------------------------------
-- Mirrored module constants / state (see header note).
-- ---------------------------------------------------------------------------

local AH_CAT_QUERY_OPCODE  = 0x16F;
local AUTOMOG_TRANSFER_OPCODE = 0x194;

local RADIO_PAD = 23;  -- per-RadioButton width overhead (circle + inner spacing)

local FAV_BTN_H    = 21;
local FAV_GAP      = 4;
local FAV_PER_ROW  = 2;
local FAV_MAX_ROWS = 5;  -- 5 fav rows × 2 per row = 10 max favs

local TRANSFER_BAGS = {
    { id=0,  name='Inventory'  },
    { id=1,  name='Mog Safe'   },
    { id=9,  name='Mog Safe 2' },
    { id=2,  name='Storage',    nl=true },
    { id=5,  name='Satchel'    },
    { id=7,  name='Case'       },
    { id=6,  name='Sack',       nl=true },
    { id=8,  name='Wardrobe'   },
    { id=10, name='Wardrobe 2' },
    { id=11, name='Wardrobe 3', nl=true },
    { id=12, name='Wardrobe 4' },
    { id=13, name='Wardrobe 5' },
    { id=14, name='Wardrobe 6', nl=true },
    { id=15, name='Wardrobe 7' },
    { id=16, name='Wardrobe 8' },
};

local WARDROBE_BAG_IDS = { [8]=true, [10]=true, [11]=true, [12]=true, [13]=true, [14]=true, [15]=true, [16]=true };

local item_name_cache = {};

-- ---------------------------------------------------------------------------
-- Favorites file IO.
-- ---------------------------------------------------------------------------

local function load_favorites(file)
    local result = {};
    local f = io.open(file, 'r');
    if not f then return result; end
    for line in f:lines() do
        line = line:match('^%s*(.-)%s*$');
        if line ~= '' then result[#result+1] = line; end
    end
    f:close();
    return result;
end

local function save_favorites(file, list)
    local f = io.open(file, 'w');
    if not f then return; end
    for _, k in ipairs(list) do f:write(k .. '\n'); end
    f:close();
end

-- ---------------------------------------------------------------------------
-- Packet senders.
-- ---------------------------------------------------------------------------

-- Inventory request / debounce / loading flag now live in libs/inv_cache.lua.
local function send_inv_request() inv_cache_lib.send_inv_request(state.selected_char); end

-- Cross-char transfer (task #110). Uses custom 0x194 AUTOMOG_TRANSFER which
-- carries src/dst char names so the server can move items between any two
-- sessioned chars owned by the primary. When src_char == dst_char this is
-- equivalent to the old 0x16B BULKXFER intra-char move.
local function pack_name_into(args, name)
    local s = (name or ''):sub(1, 15);
    for i = 1, 16 do
        args[#args + 1] = (i <= #s) and string.byte(s, i) or 0;
    end
end

local function send_bulk_transfer(src_char, dst_char, src_bag, dst_bag, slots)
    if #slots == 0 then return; end
    local count = math.min(#slots, 32);
    -- 0x194 payload: header(4) | SrcBag DstBag Count pad(4) | SrcCharName[16] DstCharName[16] | Slots[32]
    local fmt   = 'HHBBBB' .. string.rep('B', 16) .. string.rep('B', 16) .. string.rep('B', 32);
    local args  = { AUTOMOG_TRANSFER_OPCODE, 0, src_bag, dst_bag, count, 0 };
    pack_name_into(args, src_char);
    pack_name_into(args, dst_char);
    for i = 1, 32 do
        args[#args + 1] = slots[i] or 0;
    end
    AddOutgoingPacket(AUTOMOG_TRANSFER_OPCODE, struct.pack(fmt, unpack(args)):totable());
end

local function send_ah_cat_query(cat_id)
    state.ah_cat_cache[cat_id] = { items={}, complete=false };
    state.ah_browse_requesting = true;
    AddOutgoingPacket(AH_CAT_QUERY_OPCODE,
        struct.pack('HHBBBB', AH_CAT_QUERY_OPCODE, 0, cat_id, 0, 0, 0):totable());
end

-- items = { {bag=n, slot=n}, ... } up to 32 entries — all must share the same
-- src bag (UI guarantees this since the picker iterates a single inv_tab_bag).
-- Routes through 0x194 AUTOMOG_TRANSFER: src_char = sender's selected char,
-- dst_char = target_name, dst bag is always LOC_INVENTORY (0). Replaces the
-- old 0x171 ITEM_TRADE path (retired 2026-06-17 #233).
local function send_item_trade(src_char, target_name, items)
    if #items == 0 then return; end
    local src_bag = items[1].bag;
    local slots = {};
    for _, entry in ipairs(items) do
        if entry.bag == src_bag then
            slots[#slots + 1] = entry.slot;
        end
    end
    send_bulk_transfer(src_char, target_name, src_bag, 0, slots);
end

-- ---------------------------------------------------------------------------
-- Gil / container helpers.
-- ---------------------------------------------------------------------------

local function get_container_max(bag_id, char_name)
    return inv_cache_lib.get_container_max(char_name or state.selected_char, bag_id);
end

local function format_gil(n)
    n = math.floor(n or 0);
    local s = tostring(n);
    local result = '';
    local len = #s;
    for i = 1, len do
        result = result .. s:sub(i, i);
        local rem = len - i;
        if rem > 0 and rem % 3 == 0 then result = result .. ','; end
    end
    return result;
end

local function get_inv_gil(char_name)
    -- Pass BOTH args so get_bag doesn't fall into its one-arg compat branch
    -- (which defaults to the local player) -- otherwise every char shows the
    -- primary's gil. Defaults to the selected char, like get_container_max.
    local entry = inv_cache_lib.get_bag(char_name or state.selected_char, 0)[0];
    if not entry or entry.id == 0 then return 0; end
    local res = AshitaCore:GetResourceManager():GetItemById(entry.id);
    if not res or not res.Name then return 0; end
    local name = tostring(res.Name[0]):gsub('%z', '');
    return name == 'Gil' and entry.count or 0;
end

-- ---------------------------------------------------------------------------
-- imgui layout helpers.
-- ---------------------------------------------------------------------------

local function calc_text_w(text)
    local a, b = imgui.CalcTextSize(text);
    if type(a) == 'number' then return a; end
    if type(a) == 'table'  then return a.x or a[1] or 0; end
    return #text * 7;
end

local function stepper(id, var, min_val)
    local val = imgui.GetVarValue(var);
    if imgui.Button('-##' .. id, 22, 0) then
        imgui.SetVarValue(var, math.max(min_val or 1, val - 1));
    end
    imgui.SameLine();
    imgui.Button(tostring(imgui.GetVarValue(var)) .. '##' .. id .. 'n', 22, 0);
    imgui.SameLine();
    if imgui.Button('+##' .. id, 22, 0) then
        imgui.SetVarValue(var, val + 1);
    end
end

local function title_case(s)
    return (s:gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end));
end

-- Returns the SetCursorPosX value to horizontally center a row of RadioButtons
-- plus an optional trailing widget (e.g. stepper).  labels = display strings only.
local function radio_center_x(labels, extra_w)
    local w = 0;
    for i, lbl in ipairs(labels) do
        w = w + RADIO_PAD + calc_text_w(lbl);
        if i < #labels then w = w + 8; end  -- default SameLine spacing between radios
    end
    if extra_w and extra_w > 0 then w = w + 8 + extra_w; end
    return math.max(0, math.floor((imgui.GetContentRegionAvailWidth() - w) / 2));
end

local function stop_button(label, active, action, w)
    w = w or 0;
    if not active then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    if imgui.Button(label, w, 0) and active then action(); end
    if not active then imgui.PopStyleVar(); end
end

-- ---------------------------------------------------------------------------
-- Favorites UI.
-- ---------------------------------------------------------------------------

local function is_favorite(list, key)
    for _, k in ipairs(list) do if k == key then return true; end end
    return false;
end

local function truncate_fav_label(text, btn_w)
    local inner_w = btn_w - 8;  -- ~4px frame padding each side
    if calc_text_w(text) <= inner_w then return text; end
    local dots_w   = calc_text_w('...');
    local target_w = inner_w - dots_w;
    if target_w <= 0 then return '...'; end
    local result = '';
    for i = 1, #text do
        if calc_text_w(text:sub(1, i)) > target_w then break; end
        result = text:sub(1, i);
    end
    return result .. '...';
end

local function draw_fav_section(favorites, save_fn, selected, set_sel, prefix)
    imgui.Dummy(0, 6);
    imgui.TextDisabled('Favorites');
    local avail_w  = imgui.GetContentRegionAvailWidth();
    local btn_w    = math.floor((avail_w - (FAV_PER_ROW - 1) * FAV_GAP) / FAV_PER_ROW);
    local fav_rows = math.min(FAV_MAX_ROWS, math.ceil(#favorites / FAV_PER_ROW));
    local vis_rows = math.max(2, 1 + fav_rows);  -- 1 control row + fav rows, min 2 total
    local child_h  = vis_rows * FAV_BTN_H + (vis_rows - 1) * FAV_GAP + 2;
    imgui.BeginChild('##fav_' .. prefix, 0, child_h, false);
    local row_start_x = imgui.GetCursorPosX();

    -- Control row: [Add Fav] [Remove Fav]
    local already    = is_favorite(favorites, selected);
    local can_add    = selected ~= '' and not already
                       and math.ceil((#favorites + 1) / FAV_PER_ROW) <= FAV_MAX_ROWS;
    local can_remove = selected ~= '' and already;

    if not can_add then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    if imgui.Button('Add Fav##' .. prefix .. '_add', btn_w, 0) and can_add then
        favorites[#favorites + 1] = selected;
        save_fn();
    end
    if not can_add then imgui.PopStyleVar(); end

    imgui.SameLine(0, FAV_GAP);
    if not can_remove then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    if imgui.Button('Remove Fav##' .. prefix .. '_rem', btn_w, 0) and can_remove then
        for i, k in ipairs(favorites) do
            if k == selected then table.remove(favorites, i); break; end
        end
        save_fn();
    end
    if not can_remove then imgui.PopStyleVar(); end

    -- Fav buttons: FAV_PER_ROW per row, fixed width, text truncated if needed
    for i, key in ipairs(favorites) do
        local col = (i - 1) % FAV_PER_ROW;
        if col > 0 then imgui.SameLine(0, FAV_GAP); end
        local lbl    = truncate_fav_label(title_case(key), btn_w);
        local is_sel = (key == selected);
        if is_sel then imgui.PushStyleColor(ImGuiCol_Button, 0.26, 0.59, 0.98, 1.0); end
        if imgui.Button(lbl .. '##' .. prefix .. '_fb_' .. key, btn_w, 0) then set_sel(key); end
        if is_sel then imgui.PopStyleColor(); end
    end

    imgui.EndChild();
    imgui.Dummy(0, 6);
end

-- ---------------------------------------------------------------------------
-- Inventory read helpers.
-- ---------------------------------------------------------------------------

local function find_inv_slots_by_name(name)
    local res_mgr = AshitaCore:GetResourceManager();
    local lname   = name:lower();
    local results = {};
    for slot, entry in pairs(inv_cache_lib.get_bag(0)) do
        if entry.id ~= 0 and entry.count > 0 then
            local res = res_mgr:GetItemById(entry.id);
            if res and res.Name then
                local n = tostring(res.Name[0]):gsub('%z', ''):lower();
                if n == lname then
                    local display    = tostring(res.Name[0]):gsub('%z', '');
                    local stack_size = res.StackSize or 1;
                    table.insert(results, { index = slot, item_id = entry.id, count = entry.count, name = display, stack_size = stack_size });
                end
            end
        end
    end
    return results;
end

local function get_inv_items()
    local res_mgr = AshitaCore:GetResourceManager();
    local by_name = {};
    local order   = {};
    local bag = inv_cache_lib.get_bag(0);
    for _, entry in pairs(bag) do
        if entry.id ~= 0 and entry.count > 0 then
            local res = res_mgr:GetItemById(entry.id);
            if res and res.Name then
                local name = tostring(res.Name[0]):gsub('%z', '');
                if name ~= '' and name ~= 'Gil' then
                    if not by_name[name] then
                        by_name[name] = { name=name, count=0, stack_size=res.StackSize or 1 };
                        table.insert(order, name);
                    end
                    by_name[name].count = by_name[name].count + entry.count;
                end
            end
        end
    end
    table.sort(order);
    local result = {};
    for _, name in ipairs(order) do table.insert(result, by_name[name]); end
    return result;
end

local function get_inv_item_names()
    local names = {};
    for _, item in ipairs(get_inv_items()) do table.insert(names, item.name); end
    return names;
end

local function is_wardrobe_bag(bag_id)
    return WARDROBE_BAG_IDS[bag_id] == true;
end

local function get_bag_items(bag_id, char_name)
    local res_mgr = AshitaCore:GetResourceManager();
    local items   = {};
    local bag = inv_cache_lib.get_bag(char_name or state.selected_char, bag_id);
    for slot, entry in pairs(bag) do
        if entry.id ~= 0 and entry.count > 0 then
            local res        = res_mgr:GetItemById(entry.id);
            local name       = (res and res.Name) and tostring(res.Name[0]):gsub('%z','') or '???';
            local stack_size = (res and res.StackSize) or 1;
            local equippable = res and (res.Slots or 0) > 0;
            if #name >= 2 and name ~= 'Gil' then
                table.insert(items, { slot=slot, name=name, count=entry.count, stack_size=stack_size, equippable=equippable });
            end
        end
    end
    table.sort(items, function(a, b) return a.name < b.name; end);
    return items;
end

-- ---------------------------------------------------------------------------
-- Bag selector + small separators.
-- ---------------------------------------------------------------------------

local function draw_bag_selector(prefix, current_bag, char_name)
    local result  = current_bag;
    local btn_w   = math.floor((imgui.GetContentRegionAvailWidth() - 2 * FAV_GAP) / 3);
    local row_pos = 0;
    for i, bag in ipairs(TRANSFER_BAGS) do
        if bag.nl then row_pos = 0; end
        if row_pos > 0 then imgui.SameLine(0, FAV_GAP); end
        row_pos = row_pos + 1;
        local avail  = get_container_max(bag.id, char_name) >= 0;
        local active = (bag.id == current_bag);
        if active then imgui.PushStyleColor(ImGuiCol_Button, 0.26, 0.59, 0.98, 1.0); end
        if not avail then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
        if imgui.Button(bag.name .. '##' .. prefix .. i, btn_w, 0) and avail then result = bag.id; end
        if not avail then imgui.PopStyleVar(); end
        if active then imgui.PopStyleColor(); end
    end
    return result;
end

local function sep() imgui.Spacing(); imgui.Separator(); imgui.Spacing(); end

local function inv_sep()
    imgui.Dummy(0, 8);
    imgui.Separator();
    imgui.Dummy(0, 8);
end

-- ---------------------------------------------------------------------------
-- Item name lookup (cached).
-- ---------------------------------------------------------------------------

-- Look up an item name via Ashita's resource manager. Falls back to
-- "#<id>" when the resource isn't available so the layout never goes
-- blank on an unknown item.
local function item_name_for(itemId)
    if itemId == nil or itemId == 0 then return ''; end
    local cached = item_name_cache[itemId];
    if cached ~= nil then return cached; end
    local resmgr = AshitaCore:GetResourceManager();
    local name = string.format('#%d', itemId);
    if resmgr ~= nil then
        local ok, item = pcall(function() return resmgr:GetItemById(itemId); end);
        if ok and item ~= nil and item.Name then
            -- Ashita resource Name is a 0-indexed string array; element 0
            -- carries the English name. The underlying char[] is a fixed
            -- buffer whose bytes after the terminating NUL are uninitialized
            -- garbage, so truncate at the FIRST NUL (%Z* = leading run of
            -- non-NUL chars). Stripping NUL bytes instead would splice the
            -- trailing garbage onto the name.
            local n = tostring(item.Name[0]):match('^%Z*') or '';
            if n ~= '' then name = n; end
        end
    end
    item_name_cache[itemId] = name;
    return name;
end

-- ---------------------------------------------------------------------------
-- Exports.
-- ---------------------------------------------------------------------------

M.load_favorites        = load_favorites;
M.save_favorites        = save_favorites;
M.pack_name_into        = pack_name_into;
M.send_inv_request      = send_inv_request;
M.send_bulk_transfer    = send_bulk_transfer;
M.send_ah_cat_query     = send_ah_cat_query;
M.send_item_trade       = send_item_trade;
M.get_container_max     = get_container_max;
M.format_gil            = format_gil;
M.get_inv_gil           = get_inv_gil;
M.calc_text_w           = calc_text_w;
M.stepper               = stepper;
M.title_case            = title_case;
M.radio_center_x        = radio_center_x;
M.stop_button           = stop_button;
M.is_favorite           = is_favorite;
M.truncate_fav_label    = truncate_fav_label;
M.draw_fav_section      = draw_fav_section;
M.find_inv_slots_by_name = find_inv_slots_by_name;
M.get_inv_items         = get_inv_items;
M.get_inv_item_names    = get_inv_item_names;
M.is_wardrobe_bag       = is_wardrobe_bag;
M.get_bag_items         = get_bag_items;
M.draw_bag_selector     = draw_bag_selector;
M.sep                   = sep;
M.inv_sep               = inv_sep;
M.item_name_for         = item_name_for;

return M
