-- AutoMog Transfer tab.
--
-- Two-column bag-to-bag / cross-char item transfer UI. Left column is a
-- source char + bag picker with a multi-select item list; the middle arrow
-- drives the transfer; the right column is a destination char + bag picker
-- with a read-only list.
--
-- (Extracted VERBATIM from the former monolithic automog.lua when the tabs
-- were split into sibling *_tab.lua files. transfer_status /
-- transfer_left_char / transfer_right_char now live in automog_state.)

local M = {}

local C              = require('automog_common');
local state          = require('automog_state');
local autoutil       = require('autoutil');
local inv_cache_lib  = require('inv_cache');

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
local transfer_left_bag  = 0;
local transfer_right_bag = 1;
local transfer_selected  = {};

local function draw_transfer_row()
    -- The old "Transfer Items" header + Transfer button + Clear button strip
    -- that lived at the top of this row was removed: the middle arrow
    -- (->##xfr_arrow) between the two columns already drives transfers, so
    -- the top Transfer button was redundant. The Clear button moved to the
    -- left column's slot-count row (right-aligned next to "N / M slots").
    local col_w     = 260;
    local clear_btn_w = 60;
    local sel_count = 0;
    for _ in pairs(transfer_selected) do sel_count = sel_count + 1; end

    -- task #110: cross-char Transfer. Both sides can be retargeted to any
    -- sessioned alliance member via their own picker button. nil overrides
    -- fall back to state.selected_char (the original behavior when both sides
    -- followed the automog top-level char). With both overrides set, the
    -- transfer happens between two arbitrary alliance chars regardless of
    -- who's selected at the top of the window.
    local left_char  = state.transfer_left_char  or state.selected_char or '';
    local right_char = state.transfer_right_char or state.selected_char or '';

    local can_xfr = sel_count > 0;

    -- Pre-fetch items so we can compute col_h before drawing columns.
    local left_items  = C.get_bag_items(transfer_left_bag, left_char);
    local right_items = C.get_bag_items(transfer_right_bag, right_char);

    local _, avail_h = imgui.GetContentRegionAvail();
    local col_h = math.max(avail_h or 60, 60);

    -- Left column: source char picker + bag selector + selectable item list
    imgui.BeginChild('##xfr_left', col_w, 0, true);
    do
        local party        = AshitaCore:GetDataManager():GetParty();
        local primary_name = (party and party:GetMemberName(0)) or '';
        local label        = 'From: ' .. ((left_char ~= '' and left_char) or '(no char)');
        local btn_w  = math.min(col_w - 16, 200);
        local pad_x  = math.max(0, math.floor((col_w - btn_w) / 2) - 6);
        imgui.SetCursorPosX(imgui.GetCursorPosX() + pad_x);
        if imgui.Button(label .. '##xfr_left_char', btn_w, 0) then
            autoutil.send_list_alliance_pcs();
            imgui.OpenPopup('##xfr_left_char_popup');
        end
        if imgui.BeginPopup('##xfr_left_char_popup') then
            local function pick(name)
                -- Same convention as the right picker: nil whenever the
                -- pick equals the top-level selected char (so the override
                -- only persists when it actually differs). Switching the
                -- source clears the selection set since slot ids are bag-
                -- and char-local and would point at the wrong inventory.
                if name == state.selected_char then
                    state.transfer_left_char = nil;
                else
                    state.transfer_left_char = name;
                    inv_cache_lib.ensure_inventory(name);
                end
                transfer_selected = {};
                imgui.CloseCurrentPopup();
            end
            if primary_name ~= '' and imgui.Selectable(primary_name .. ' (you)') then pick(primary_name) end
            imgui.Separator();
            local roster = autoutil.alliance_pcs or {};
            local listed = 0;
            for _, m in ipairs(roster) do
                if m.name ~= primary_name then
                    if imgui.Selectable(m.name) then pick(m.name); end
                    listed = listed + 1;
                end
            end
            if listed == 0 then imgui.TextDisabled('(no other sessioned chars)') end
            imgui.EndPopup();
        end
    end
    imgui.Separator();
    local new_left = C.draw_bag_selector('tl', transfer_left_bag, left_char);
    if new_left ~= transfer_left_bag then
        transfer_left_bag = new_left;
        transfer_selected = {};
    end
    imgui.Separator();
    imgui.Dummy(0, 10);
    -- Slot count on the left + Clear (right-aligned) on the same row.
    -- The Clear button used to live in a separate top strip; folding it
    -- in here gives the slot-count row a second use and reclaims the
    -- vertical real estate the strip was eating. Right-aligned by
    -- SetCursorPosX'ing to (column-right-edge - button-width).
    -- AlignTextToFramePadding is not exposed by all Ashita v3 imgui
    -- binding revisions — guard the call so the addon doesn't error out
    -- on builds that lack it. Visually we lose a tiny baseline nudge if
    -- it's missing, the slot count still reads correctly.
    if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end
    imgui.TextDisabled(string.format('%d / %d slots', #left_items, C.get_container_max(transfer_left_bag, left_char)));
    imgui.SameLine();
    local clear_row_x = imgui.GetCursorPosX();
    local clear_target_x = math.max(clear_row_x, col_w - clear_btn_w - 12);
    imgui.SetCursorPosX(clear_target_x);
    if not can_xfr then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    if imgui.Button('Clear##xfr', clear_btn_w, 0) and can_xfr then
        transfer_selected = {};
    end
    if not can_xfr then imgui.PopStyleVar(); end
    imgui.Dummy(0, 10);
    local dst_is_wardrobe = C.is_wardrobe_bag(transfer_right_bag);
    imgui.BeginChild('##xfr_llist', 0, 0, false);
    for _, item in ipairs(left_items) do
        local blocked = dst_is_wardrobe and not item.equippable;
        local is_sel  = transfer_selected[item.slot] == true;
        if blocked then
            if is_sel then transfer_selected[item.slot] = nil; end
            imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35);
        end
        if imgui.Selectable(item.name .. '##tli' .. item.slot, is_sel) and not blocked then
            if is_sel then transfer_selected[item.slot] = nil;
            else transfer_selected[item.slot] = true; end
        end
        if blocked then imgui.PopStyleVar(); end
        if item.stack_size > 1 then
            imgui.SameLine();
            imgui.TextDisabled('(' .. item.count .. ')');
        end
    end
    if #left_items == 0 then imgui.TextDisabled('(empty)'); end
    imgui.EndChild();
    imgui.EndChild();

    imgui.SameLine();
    local col_top_y = imgui.GetCursorPosY();
    imgui.SetCursorPosY(col_top_y);
    if not can_xfr then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
    if imgui.Button('->##xfr_arrow', 0, col_h) and can_xfr then
        local slots = {};
        for slot, _ in pairs(transfer_selected) do table.insert(slots, slot); end
        C.send_bulk_transfer(left_char, right_char, transfer_left_bag, transfer_right_bag, slots);
        transfer_selected = {};
        state.transfer_status   = 'Sending...';
    end
    if not can_xfr then imgui.PopStyleVar(); end
    imgui.SameLine();
    imgui.SetCursorPosY(col_top_y);

    -- Right column: destination char dropdown + bag selector + read-only list.
    -- Dropdown lists every sessioned alliance member (autoutil.alliance_pcs)
    -- plus the primary; selecting a different name from the left switches
    -- the right column to that char and dst routes to their bags.
    imgui.BeginChild('##xfr_right', col_w, 0, true);
    do
        local party        = AshitaCore:GetDataManager():GetParty();
        local primary_name = (party and party:GetMemberName(0)) or '';
        local label        = 'To: ' .. ((right_char ~= '' and right_char) or '(no char)');
        -- Center the dropdown button above the column for visual balance.
        local btn_w  = math.min(col_w - 16, 200);
        local pad_x  = math.max(0, math.floor((col_w - btn_w) / 2) - 6);
        imgui.SetCursorPosX(imgui.GetCursorPosX() + pad_x);
        if imgui.Button(label .. '##xfr_right_char', btn_w, 0) then
            autoutil.send_list_alliance_pcs();
            imgui.OpenPopup('##xfr_right_char_popup');
        end
        if imgui.BeginPopup('##xfr_right_char_popup') then
            local function pick(name)
                -- nil if pick mirrors left (i.e. primary clears the override
                -- AND it equals state.selected_char); else store explicit override.
                if name == state.selected_char then
                    state.transfer_right_char = nil;
                else
                    state.transfer_right_char = name;
                    -- Lazy: only fetch if cache is cold. Picking a char
                    -- you've already viewed before reuses the cache.
                    inv_cache_lib.ensure_inventory(name);
                end
                imgui.CloseCurrentPopup();
            end
            if primary_name ~= '' and imgui.Selectable(primary_name .. ' (you)') then pick(primary_name) end
            imgui.Separator();
            local roster = autoutil.alliance_pcs or {};
            local listed = 0;
            for _, m in ipairs(roster) do
                if m.name ~= primary_name then
                    if imgui.Selectable(m.name) then pick(m.name); end
                    listed = listed + 1;
                end
            end
            if listed == 0 then imgui.TextDisabled('(no other sessioned chars)') end
            imgui.EndPopup();
        end
    end
    imgui.Separator();
    transfer_right_bag = C.draw_bag_selector('tr', transfer_right_bag, right_char);
    imgui.Separator();
    imgui.Dummy(0, 10);
    imgui.TextDisabled(string.format('%d / %d slots', #right_items, C.get_container_max(transfer_right_bag, right_char)));
    imgui.Dummy(0, 10);
    imgui.BeginChild('##xfr_rlist', 0, 0, false);
    for _, item in ipairs(right_items) do
        imgui.Text(item.name);
        if item.stack_size > 1 then
            imgui.SameLine();
            imgui.TextDisabled('(' .. item.count .. ')');
        end
    end
    if #right_items == 0 then imgui.TextDisabled('(empty)'); end
    imgui.EndChild();
    imgui.EndChild();
end

local function draw_transfer_tab()
    draw_transfer_row();
end

M.draw = draw_transfer_tab

return M
