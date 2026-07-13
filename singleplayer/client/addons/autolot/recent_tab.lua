-- AutoLot Drop History tab.
--
-- Renders the last 100 unique items observed in the treasure pool this
-- session (maintained by pool_tab.tick). Per-row actions mirror Treasure Pool:
--   + Group ▼   — add this item id to an existing group, auto-save (Phase A)
--   Lot List    — assign chars that should lot this item id when it next
--                  drops, until they own one. Shared membership mirror via
--                  autoutil.lot_list_* (same list the Live Pool tab edits).

local M = {}

local autoutil
local groups_tab
local pool_tab

local picker_target_id    = nil
local lot_picker_selected = {}

function M.init(deps)
    autoutil   = deps.autoutil
    groups_tab = deps.groups_tab
    pool_tab   = deps.pool_tab
end

function M.on_load()   end
function M.on_unload() end

local function draw_group_picker_popup()
    if imgui.BeginPopup('##autolot_recent_group_picker') then
        imgui.Text('Add to group')
        imgui.Separator()
        local names = groups_tab.get_group_names()
        if #names == 0 then
            imgui.TextDisabled('(no groups - create one in Groups tab)')
        else
            for _, gname in ipairs(names) do
                if imgui.Selectable(gname .. '##rgpick_' .. gname) then
                    if picker_target_id ~= nil then
                        groups_tab.add_id_to_group_and_save(gname, picker_target_id)
                    end
                    picker_target_id = nil
                    imgui.CloseCurrentPopup()
                end
            end
        end
        imgui.EndPopup()
    end
end

local function alliance_bots()
    local out   = {}
    local party = AshitaCore:GetDataManager():GetParty()
    if party == nil then return out end
    -- Filter trusts via the server `chars` roster (never contains trusts);
    -- show everyone until it resolves so the list isn't empty during load.
    if autoutil.fetch_chars and not autoutil.char_names_final then
        autoutil.fetch_chars()
    end
    local real = nil
    if autoutil.char_names_final and type(autoutil.char_names) == 'table' then
        real = {}
        for _, cn in ipairs(autoutil.char_names) do real[cn] = true end
    end
    for i = 1, 17 do
        local nm = party:GetMemberName(i)
        if nm ~= nil and nm ~= '' and (real == nil or real[nm]) then
            table.insert(out, nm)
        end
    end
    return out
end

local function draw_lot_list_popup()
    if imgui.BeginPopup('##autolot_recent_lot_list') then
        imgui.Text('Lot List - pick chars to receive one')
        imgui.Separator()
        imgui.TextDisabled('Checked chars lot this item until each owns one. Uncheck + Apply to remove.')
        imgui.Dummy(0, 6)

        local bots = alliance_bots()
        if #bots == 0 then
            imgui.TextDisabled('(no headless in alliance)')
        else
            for _, nm in ipairs(bots) do
                local v = imgui.CreateVar(ImGuiVar_BOOLCPP)
                imgui.SetVarValue(v, lot_picker_selected[nm] or false)
                imgui.Checkbox(nm .. '##rllpick_' .. nm, v)
                lot_picker_selected[nm] = imgui.GetVarValue(v)
                imgui.DeleteVar(v)
            end
        end

        imgui.Dummy(0, 8)
        imgui.Separator()
        imgui.Dummy(0, 4)
        if imgui.Button('Apply##rll_apply', 90, 0) then
            if picker_target_id ~= nil then
                autoutil.lot_list_apply(picker_target_id, lot_picker_selected)
            end
            picker_target_id    = nil
            lot_picker_selected = {}
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine(0, 6)
        if imgui.Button('Cancel##rll_cancel', 90, 0) then
            picker_target_id    = nil
            lot_picker_selected = {}
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end
end

local function fmt_time_ago(epoch)
    local delta = os.time() - (epoch or 0)
    if delta < 60      then return string.format('%ds ago', delta) end
    if delta < 3600    then return string.format('%dm ago', math.floor(delta / 60)) end
    return string.format('%dh ago', math.floor(delta / 3600))
end

local BTN_W, BTN_GAP = 70, 4

local function draw_row(e, idx)
    -- Layout mirrors the Live Pool row: item id + name, buttons flush right.
    -- Fit the name to the space before the buttons (pixel-based, via pool_tab's
    -- shared helper) so SE's already-short names render whole and only genuinely
    -- long ones get an ellipsis rather than colliding with the buttons.
    local id_str  = string.format('%-5d  ', e.id)
    local blockW  = BTN_W + BTN_GAP + BTN_W
    local name_px = imgui.GetContentRegionAvailWidth() - pool_tab.text_w(id_str) - blockW - 12
    local nm = (pool_tab.truncate_to_width and pool_tab.truncate_to_width(e.name, name_px)) or e.name
    imgui.Text(id_str .. nm)
    imgui.SameLine()
    local avail = imgui.GetContentRegionAvailWidth()
    imgui.SameLine(0, math.max(6, avail - blockW))
    if imgui.Button('+ Group##rcg_' .. idx, BTN_W, 0) then
        picker_target_id = e.id
        imgui.OpenPopup('##autolot_recent_group_picker')
    end
    imgui.SameLine(0, BTN_GAP)
    if imgui.Button('Lot List##rcll_' .. idx, BTN_W, 0) then
        picker_target_id    = e.id
        lot_picker_selected = autoutil.lot_list_get(e.id)
        imgui.OpenPopup('##autolot_recent_lot_list')
    end
end

function M.draw()
    autoutil.section_head('Drop History (last 100 unique items)')
    imgui.Spacing()
    imgui.TextDisabled('Items seen in the pool this session. Newest first. Cleared on /addon reload autolot.')
    imgui.Separator()
    imgui.Dummy(0, 6)

    local cache = pool_tab.get_cache()
    if #cache == 0 then
        imgui.TextDisabled('(nothing observed yet)')
    else
        imgui.BeginChild('##recent_rows', 0, 0, false)
        for i, e in ipairs(cache) do
            draw_row(e, i)
            imgui.Dummy(0, 1)
        end
        imgui.EndChild()
    end

    draw_group_picker_popup()
    draw_lot_list_popup()
end

return M
