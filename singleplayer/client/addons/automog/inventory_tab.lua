local M = {};

local C              = require('automog_common');
local state          = require('automog_state');
local autoutil       = require('autoutil');
local inv_cache_lib  = require('inv_cache');
local autodrop       = require('autodrop');

-- Favorites-grid gap constant used for the inline action-button layout (kept
-- as a local copy; the monolith had it as a shared module constant).
local FAV_GAP = 4;

local inv_tab_bag      = 0;
local inv_tab_selected = {};
-- Last clicked slot (used to drive the right-column item detail panel —
-- autoequip-style name/level/jobs/description for whatever the user most
-- recently interacted with). Cleared on bag change.
local inv_tab_focused  = nil;

local function draw_inv_item_detail(col_w, bag_id, slot)
    if slot == nil then
        imgui.SetCursorPosX(math.max(0, (col_w - C.calc_text_w('Select an item to view details.')) / 2));
        imgui.TextDisabled('Select an item to view details.');
        return;
    end

    local bag   = inv_cache_lib.get_bag(state.selected_char, bag_id);
    local entry = bag and bag[slot];
    if not entry or entry.id == 0 or entry.count == 0 then
        imgui.SetCursorPosX(math.max(0, (col_w - C.calc_text_w('Select an item to view details.')) / 2));
        imgui.TextDisabled('Select an item to view details.');
        return;
    end

    local res_mgr = AshitaCore:GetResourceManager();
    local res     = res_mgr:GetItemById(entry.id);
    local name    = (res and res.Name) and tostring(res.Name[0]):gsub('%z', '') or ('item#' .. entry.id);
    local level   = (res and res.Level) or 0;
    local jobs    = (res and res.Jobs) or 0;
    local desc    = (res and res.Description and res.Description[0]) and tostring(res.Description[0]):gsub('%z', '') or '';
    local stack_sz = (res and res.StackSize) or 1;
    local count   = entry.count or 0;

    -- Top padding so the name isn't flush against the top of the panel.
    imgui.Dummy(0, 8);

    -- Name centered. White text (not the dim "section header" color) so it
    -- reads as the actual title of the panel.
    imgui.SetCursorPosX(math.max(0, (col_w - C.calc_text_w(name)) / 2));
    imgui.TextColored(1.0, 1.0, 1.0, 1.0, name);

    -- Subtitle: level + count (dim, centered)
    local subtitle = {};
    if level and level > 0 then table.insert(subtitle, 'Lv.' .. level); end
    if stack_sz > 1 then
        table.insert(subtitle, string.format('%d / %d', count, stack_sz));
    elseif count > 1 then
        table.insert(subtitle, 'x' .. count);
    end
    if #subtitle > 0 then
        local sub = table.concat(subtitle, '   ');
        imgui.SetCursorPosX(math.max(0, (col_w - C.calc_text_w(sub)) / 2));
        imgui.TextDisabled(sub);
    end

    -- Jobs that can equip. 0 == none (consumable / scroll). 0xFFFFFFFF == any.
    if jobs ~= 0 and jobs ~= 0xFFFFFFFF then
        local jnames = {};
        for i, jname in ipairs(autoutil.jobs) do
            if bit.band(jobs, bit.lshift(1, i)) ~= 0 then
                table.insert(jnames, jname);
            end
        end
        if #jnames > 0 then
            imgui.Dummy(0, 8);
            local row = {};
            for idx, jname in ipairs(jnames) do
                table.insert(row, jname);
                if #row == 6 or idx == #jnames then
                    local line = table.concat(row, ' ');
                    imgui.SetCursorPosX(math.max(0, (col_w - C.calc_text_w(line)) / 2));
                    imgui.TextDisabled(line);
                    row = {};
                    if idx < #jnames then imgui.Dummy(0, 2); end
                end
            end
        end
    end

    if desc ~= '' then
        imgui.Dummy(0, 8);
        imgui.Separator();
        imgui.Dummy(0, 6);
        -- Left padding so the description doesn't hug the column edge (the
        -- indent also shifts TextWrapped's wrap point in, keeping a left margin).
        imgui.Indent(8);
        imgui.TextWrapped(desc);
        imgui.Unindent(8);
    end
end

local function draw_inventory_tab()
    local col_w = 260;

    local bag_items = C.get_bag_items(inv_tab_bag);
    local sel_count = 0;
    for _ in pairs(inv_tab_selected) do sel_count = sel_count + 1; end
    local has_sel = sel_count > 0;
    local can_drop = has_sel and inv_tab_bag == 0;

    -- Drop a stale focused slot if the item is gone (sort, drop, transfer).
    if inv_tab_focused ~= nil then
        local still_present = false;
        for _, item in ipairs(bag_items) do
            if item.slot == inv_tab_focused then still_present = true; break; end
        end
        if not still_present then inv_tab_focused = nil; end
    end

    -- Left: bag selector + multi-select item list
    imgui.BeginChild('##inv_left', col_w, 0, false);
    local new_bag = C.draw_bag_selector('inv', inv_tab_bag);
    if new_bag ~= inv_tab_bag then
        inv_tab_bag      = new_bag;
        inv_tab_selected = {};
        inv_tab_focused  = nil;
    end
    imgui.Separator();
    imgui.Dummy(0, 6);
    imgui.TextDisabled(string.format('%d / %d slots', #bag_items, C.get_container_max(inv_tab_bag)));
    imgui.Dummy(0, 6);
    imgui.BeginChild('##inv_ilist', 0, 0, false);
    for _, item in ipairs(bag_items) do
        local is_sel = inv_tab_selected[item.slot] == true;
        if imgui.Selectable(item.name .. '##invi_' .. item.slot, is_sel) then
            -- A click both (a) toggles selection state (multi-select stays as-is)
            -- and (b) sets focus for the right-column detail panel so even
            -- deselecting still rests focus on what was just clicked.
            if is_sel then inv_tab_selected[item.slot] = nil;
            else inv_tab_selected[item.slot] = true; end
            inv_tab_focused = item.slot;
        end
        if item.stack_size > 1 then
            imgui.SameLine();
            imgui.TextDisabled('(' .. item.count .. ')');
        end
    end
    if #bag_items == 0 then imgui.TextDisabled('(empty)'); end
    imgui.EndChild();
    imgui.EndChild();

    imgui.SameLine(0, 30);

    -- Right: focused-item detail card, then Trade + Drop when items are selected.
    -- The static gil/sort/delivery/scrolls/change-job block was moved to the
    -- Status tab — that's a per-char "always visible" home and frees this
    -- column to be about the item the user is actually looking at.
    imgui.BeginChild('##inv_right', col_w, 0, false);
    draw_inv_item_detail(col_w, inv_tab_bag, inv_tab_focused);

    if has_sel then
        local avail_w = imgui.GetContentRegionAvailWidth();

        -- Trade section
        C.inv_sep();
        imgui.SetCursorPosX((avail_w - C.calc_text_w('Trade')) / 2);
        autoutil.section_head('Trade');
        imgui.Spacing();
        local trade_btn_w = math.floor((avail_w - 2 * FAV_GAP) / 3);
        local party     = AshitaCore:GetDataManager():GetParty();
        -- Exclude the currently-displayed char (you can't trade to yourself).
        -- Was using primary name regardless of char selection, so switching the
        -- char selector left the wrong row excluded.
        local self_name = state.selected_char or ((party and party:GetMemberName(0)) or '');
        -- party:GetMemberName(i) returns trusts alongside PCs and there's no
        -- v3 API to tell them apart. Use the server-authoritative PC roster
        -- (0x186 → autoutil.alliance_pcs) as the source of truth so trust
        -- buttons don't pollute the trade row.
        local pc_set = {};
        for _, m in ipairs(autoutil.alliance_pcs or {}) do
            if m.name and m.name ~= '' then pc_set[m.name] = true; end
        end
        if next(pc_set) == nil and self_name ~= '' then
            -- Roster hasn't synced yet — allow self at minimum so the trade
            -- block doesn't read as broken on a cold cache.
            pc_set[self_name] = true;
        end
        local col_idx = 0;
        for i = 0, 17 do
            local name = (party and party:GetMemberName(i)) or '';
            if name ~= '' and name ~= self_name and pc_set[name] then
                if col_idx % 3 ~= 0 then imgui.SameLine(0, FAV_GAP); end
                if imgui.Button(name .. '##trd_' .. i, trade_btn_w, 0) then
                    local trade_items = {};
                    for slot, _ in pairs(inv_tab_selected) do
                        table.insert(trade_items, { bag = inv_tab_bag, slot = slot });
                    end
                    if #trade_items > 0 then
                        C.send_item_trade(self_name, name, trade_items);
                        inv_tab_selected = {};
                    end
                end
                col_idx = col_idx + 1;
            end
        end
        if col_idx == 0 then
            imgui.SetCursorPosX((avail_w - C.calc_text_w('No other members.')) / 2);
            imgui.TextDisabled('No other members.');
        end

        -- Drop section
        C.inv_sep();
        local drop_w = imgui.GetWindowWidth();
        imgui.SetCursorPosX((drop_w - C.calc_text_w('Drop Items')) / 2);
        autoutil.section_head('Drop Items');
        imgui.Spacing();
        local ds_w   = C.calc_text_w('Drop Selected') + 16;
        local dat_w  = C.calc_text_w('Drop All Of Type') + 16;
        local row_w  = ds_w + 8 + dat_w;
        imgui.SetCursorPosX(math.floor((drop_w - row_w) / 2));
        if not can_drop then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
        if imgui.Button('Drop Selected##invds', ds_w, 0) and can_drop then
            local bag0    = inv_cache_lib.get_bag(0);
            local entries = {};
            for slot, _ in pairs(inv_tab_selected) do
                local e = bag0[slot];
                if e and e.id ~= 0 and e.count > 0 then
                    local res = AshitaCore:GetResourceManager():GetItemById(e.id);
                    local n   = res and res.Name and tostring(res.Name[0]):gsub('%z','') or ('item#'..e.id);
                    table.insert(entries, { index = slot, count = e.count, name = n });
                end
            end
            if #entries > 0 then autodrop.queue_drops(entries); end
        end
        imgui.SameLine(0, 8);
        if imgui.Button('Drop All Of Type##invdat', dat_w, 0) and can_drop then
            local bag0     = inv_cache_lib.get_bag(0);
            local seen_ids = {};
            local entries  = {};
            for slot, _ in pairs(inv_tab_selected) do
                local e = bag0[slot];
                if e and e.id ~= 0 and not seen_ids[e.id] then
                    seen_ids[e.id] = true;
                    for s, se in pairs(bag0) do
                        if se.id == e.id and se.count > 0 then
                            local res = AshitaCore:GetResourceManager():GetItemById(se.id);
                            local n   = res and res.Name and tostring(res.Name[0]):gsub('%z','') or ('item#'..se.id);
                            table.insert(entries, { index = s, count = se.count, name = n });
                        end
                    end
                end
            end
            if #entries > 0 then autodrop.queue_drops(entries); end
        end
        if not can_drop then imgui.PopStyleVar(); end
    end

    imgui.EndChild();
end

M.draw = draw_inventory_tab;

return M;
