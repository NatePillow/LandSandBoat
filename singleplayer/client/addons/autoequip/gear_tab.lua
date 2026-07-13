-- Full gear-set editor: set list, slot picker (with filters + stat diff), and
-- per-stat optimizer. Lifted from automog as part of the addon split.
--
-- This module owns its own state, imgui vars, and draw routines. The hosting
-- addon needs to:
--   - call M.init(deps) at load time with { autoequip, autoutil, inv_cache }
--   - call M.on_load() / M.on_unload() inside register_event('load'/'unload')
--     so imgui vars are created/destroyed
--   - call M.draw() inside the tab body
--   - call M.reload_config() when the user requests it

local M = {}

local autoequip
local autoutil
local inv_cache
local open_copy_from -- callback from autoequip.lua; opens the Copy-From popup

-- Shared item-description parser + colored stat-diff renderer. Used by both
-- this tab's Confirm panel and automog's Status-tab equipment swap. The
-- previous in-file copies of parse_item_stats / get_item_desc were lifted
-- into addons/libs/item_stat_diff.lua so both addons render identically.
local item_stat_diff = require('item_stat_diff')

-- ============================================================
-- Gear slot taxonomy (only used by this tab — kept local)
-- ============================================================

local SLOT_ORDER = {
    'main', 'sub', 'range', 'ammo',
    'head', 'neck', 'lear', 'rear',
    'body', 'hands', 'lring', 'rring',
    'back', 'waist', 'legs', 'feet',
}

local SLOT_LABEL = {
    main='Main',  sub='Sub',    range='Range', ammo='Ammo',
    head='Head',  body='Body',  hands='Hands', legs='Legs',  feet='Feet',
    neck='Neck',  waist='Waist',
    lear='L.Ear', rear='R.Ear', lring='L.Ring', rring='R.Ring', back='Back',
    ear='Ear',    ring='Ring',
}

local SLOT_MASK = {
    main=0x0001,  sub=0x0002,   range=0x0004,  ammo=0x0008,
    head=0x0010,  body=0x0020,  hands=0x0040,  legs=0x0080,  feet=0x0100,
    neck=0x0200,  waist=0x0400,
    lear=0x0800,  rear=0x1000,  lring=0x2000,  rring=0x4000, back=0x8000,
    ear=0x1800,   ring=0x6000,
}

local PRIMARY_STATS = { 'STR', 'DEX', 'VIT', 'AGI', 'INT', 'MND', 'CHR' }
local DERIVED_STATS = { 'ATK', 'ACC', 'DEF', 'EVA', 'RACC', 'RATK', 'MACC', 'MEVA', 'MAB', 'MDB', 'Haste', 'STP', 'Enmity', 'SB', 'DA', 'TA', 'Crit' }

local OPTIMIZE_STATS = {}
for _, s in ipairs(PRIMARY_STATS) do table.insert(OPTIMIZE_STATS, s) end
for _, s in ipairs(DERIVED_STATS) do table.insert(OPTIMIZE_STATS, s) end

local STAT_MULTI = {
    { 'Accuracy', 'ACC' }, { 'Attack', 'ATK' }, { 'Evasion', 'EVA' },
    { 'Ranged Accuracy', 'RACC' }, { 'Ranged Attack', 'RATK' },
    { 'Magic Accuracy', 'MACC' }, { 'Magic Evasion', 'MEVA' },
    { 'Magic Attack Bonus', 'MAB' }, { 'Magic Defense Bonus', 'MDB' },
    { 'Store TP', 'STP' }, { 'Subtle Blow', 'SB' },
    { 'Double Attack', 'DA' }, { 'Triple Attack', 'TA' },
    { 'Crit hit rate', 'Crit' }, { 'Haste', 'Haste' }, { 'Enmity', 'Enmity' },
}

local PICKER_BAGS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 }

-- ============================================================
-- UI metrics
-- ============================================================

local RADIO_PAD = 23  -- per-RadioButton width overhead (unused here but parallels automog)
local STEPPER_W = 82  -- stepper: 3×22 + 2×8 spacing

local function calc_text_w(text)
    local a, b = imgui.CalcTextSize(text)
    if type(a) == 'number' then return a end
    if type(a) == 'table'  then return a.x or a[1] or 0 end
    return #text * 7
end

-- ============================================================
-- State
-- ============================================================

local sets_list         = {}
local ui_selected       = ''
local gear_xml_list     = {}
local gear_xml_selected = ''

local picker_active      = false
local picker_slot        = nil
local picker_pending     = nil
local picker_items_cache = nil
local picker_filter      = nil
local picker_filter_job  = nil
local picker_filter_lv   = nil
local picker_stat_vars   = {}

local optimize_stat_var  = nil
local optimize_level_var = nil
local optimize_preview   = nil

-- Dirty-state model (mirrors swap_logic_tab): each gear set is independently
-- dirty/clean. Slot picker / optimizer confirms set dirty_sets[ui_selected],
-- the Save button serializes that <set> node and ships subtree "sets/<name>"
-- via 0x180. Switching sets while dirty is blocked via pending_set_change.
local dirty_sets         = {}
local pending_set_change = nil

-- "+ New Set" and "+ New File" popup state. new_set_name_input is the imgui
-- text-input var for the New Set name prompt; both popups open via imgui's
-- own popup stack and don't need a global flag.
local new_set_name_input = nil

-- ============================================================
-- Init + lifecycle
-- ============================================================

function M.init(deps)
    autoequip      = deps.autoequip
    autoutil       = deps.autoutil
    inv_cache      = deps.inv_cache
    open_copy_from = deps.open_copy_from
end

function M.on_load()
    picker_filter      = imgui.CreateVar(ImGuiVar_CDSTRING, 64)
    picker_filter_job  = imgui.CreateVar(ImGuiVar_BOOLCPP)
    picker_filter_lv   = imgui.CreateVar(ImGuiVar_BOOLCPP)
    optimize_stat_var  = imgui.CreateVar(ImGuiVar_INT32)
    optimize_level_var = imgui.CreateVar(ImGuiVar_INT32)
    imgui.SetVarValue(picker_filter_job, true)
    imgui.SetVarValue(picker_filter_lv, false)
    for _, stat in ipairs(PRIMARY_STATS) do
        picker_stat_vars[stat] = imgui.CreateVar(ImGuiVar_BOOLCPP)
    end
    for _, stat in ipairs(DERIVED_STATS) do
        picker_stat_vars[stat] = imgui.CreateVar(ImGuiVar_BOOLCPP)
    end
    new_set_name_input = imgui.CreateVar(ImGuiVar_CDSTRING, 64)
end

function M.on_unload()
    if picker_filter     ~= nil then imgui.DeleteVar(picker_filter);     picker_filter     = nil end
    if picker_filter_job ~= nil then imgui.DeleteVar(picker_filter_job); picker_filter_job = nil end
    if picker_filter_lv  ~= nil then imgui.DeleteVar(picker_filter_lv);  picker_filter_lv  = nil end
    if optimize_stat_var  ~= nil then imgui.DeleteVar(optimize_stat_var);  optimize_stat_var  = nil end
    if optimize_level_var ~= nil then imgui.DeleteVar(optimize_level_var); optimize_level_var = nil end
    for _, v in pairs(picker_stat_vars) do
        if v ~= nil then imgui.DeleteVar(v) end
    end
    picker_stat_vars = {}
    if new_set_name_input ~= nil then imgui.DeleteVar(new_set_name_input); new_set_name_input = nil end
end

-- ============================================================
-- Item stat parsing
-- ============================================================

-- Thin shims so the existing call sites below keep reading. The actual
-- implementations now live in addons/libs/item_stat_diff.lua, shared
-- with automog's equipment-swap Confirm panel.
local parse_item_stats = item_stat_diff.parse_item_stats
local get_item_desc    = item_stat_diff.get_item_desc

-- ============================================================
-- Set / XML list rebuilds
-- ============================================================

function M.rebuild_sets()
    sets_list   = {}
    ui_selected = ''
    if autoequip.sets_node then
        for _, child in ipairs(autoequip.sets_node.children) do
            if child.tag == 'set' and child.attrs and child.attrs.name then
                table.insert(sets_list, child.attrs.name)
            end
        end
        table.sort(sets_list)
    end
end

-- Sync server-side fetch over loopback HTTP. Filters to entries starting with
-- the current character's name; populates gear_xml_list inline. UI redraws
-- naturally on the next frame.
function M.rebuild_xml_list()
    local charName = autoequip.get_edit_target()
    if not charName or charName == '' then
        gear_xml_list = {}
        return
    end
    local http = require('http_client')
    local json = require('json')
    http.get('/configs/equip', function(code, body, _, err)
        -- Re-check the target since the response arrives on a later frame
        -- and the user could have changed selection in the meantime.
        local cur = autoequip.get_edit_target()
        if cur ~= charName then return end
        if code == nil then
            autoutil.log('AutoEquip', string.format('rebuild_xml_list: %s', tostring(err)))
            gear_xml_list = {}
            return
        end
        if code ~= 200 then
            autoutil.log('AutoEquip', string.format('rebuild_xml_list: HTTP %s', tostring(code)))
            gear_xml_list = {}
            return
        end
        local ok, parsed = pcall(json.decode, json, body)
        local names = (ok and parsed and parsed.names) or {}
        local prefix = charName .. '_'
        gear_xml_list = {}
        local seen = {}
        for _, entry in ipairs(names) do
            local job = entry:match('^' .. prefix .. '(.+)$')
            if job and not seen[job] then
                seen[job] = true
                table.insert(gear_xml_list, { filename = entry, job = job })
            end
        end
        table.sort(gear_xml_list, function(a, b) return a.job < b.job end)
    end)
end

function M.reload_config()
    local charName, jobName = autoequip.get_edit_target()
    if not charName or charName == '' or not jobName or jobName == '' then
        autoutil.log('AutoEquip', 'Cannot load config: no char/job data yet.')
        return
    end
    autoequip.load_tried = false
    autoequip.xml_root   = nil
    -- Async — populates xml_root when server replies via 0x17F chunks.
    autoequip.load(charName, jobName, function(ok)
        if ok then M.rebuild_sets() end
    end)
    M.rebuild_xml_list()
    dirty_sets         = {}
    pending_set_change = nil
end

-- ============================================================
-- Per-set dirty / save helpers
-- ============================================================

local function file_basename()
    if autoequip.loaded_char == nil or autoequip.loaded_job == nil then return nil end
    return autoequip.loaded_char .. '_' .. autoequip.loaded_job
end

local function set_node_for(set_name)
    if autoequip.sets_node == nil then return nil end
    for _, child in ipairs(autoequip.sets_node.children) do
        if child.tag == 'set' and child.attrs and child.attrs.name == set_name then
            return child
        end
    end
    return nil
end

-- Set (base_name) or clear (base_name '') the `baseset` inheritance attr on a
-- set node. resolve_set (client + server, identical logic) overlays this set's
-- own slots on top of base_name's resolved gear. Pure authoring — persists on
-- Save via serialize_node's attr output.
local function set_baseset(set_name, base_name)
    local node = set_node_for(set_name)
    if node == nil then return end
    node.attrs = node.attrs or {}
    if base_name == nil or base_name == '' then
        node.attrs.baseset = nil
    else
        node.attrs.baseset = base_name
    end
    dirty_sets[set_name] = true
end

local function save_set(set_name)
    local file = file_basename()
    if file == nil then
        autoutil.log('AutoEquip', 'save_set: no XML loaded')
        return
    end
    -- Whole-file PUT. The in-memory autoequip.xml_root is the live document;
    -- any dirty edits across any sets have already been applied to it via
    -- autoequip.set_slot() and the gear-tab editors. Serializing and PUTting
    -- the whole thing captures every pending edit at once. (The legacy 0x180
    -- SET_XML_SUBTREE path saved per-set partial fragments; with HTTP the
    -- transport cost of the whole file is negligible (~10 ms loopback) and
    -- the server-side XML-splice handler can be deleted entirely.)
    local body = autoequip.serialize_full()
    if body == nil then
        autoutil.log('AutoEquip', 'save_set: serialize_full returned nil')
        return
    end
    local http = require('http_client')
    http.put('/configs/equip/' .. file, body, 'application/xml', function(code, _, _, err)
        if code == 200 or code == 201 then
            -- All sets are persisted in the single file now, so clear every
            -- dirty marker — not just the one the user clicked.
            dirty_sets = {}
            if pending_set_change ~= nil then
                ui_selected        = pending_set_change
                pending_set_change = nil
                optimize_preview   = nil
            end
        elseif code == nil then
            autoutil.log('AutoEquip', string.format('save_set[%s]: %s', set_name, tostring(err)))
        else
            autoutil.log('AutoEquip', string.format('save_set[%s]: PUT returned %s', set_name, tostring(code)))
        end
    end)
end

local function discard_set(set_name)
    dirty_sets[set_name] = nil
    -- Drop the in-memory edits by re-fetching the file from the server.
    if autoequip.loaded_char and autoequip.loaded_job then
        autoequip.load_tried = false
        autoequip.xml_root   = nil
        autoequip.load(autoequip.loaded_char, autoequip.loaded_job, function(ok)
            if ok then M.rebuild_sets() end
        end)
    end
end

-- ============================================================
-- Create-new helpers (new set within current XML, new XML file for a job)
-- ============================================================

-- Append a new <set name="X"/> in memory and mark it dirty so the user can
-- hit Save to push it. Refuses duplicates. Selects the new set on success.
local function create_new_set(name)
    if name == nil or name == '' then return false end
    if autoequip.sets_node == nil then return false end
    for _, child in ipairs(autoequip.sets_node.children) do
        if child.tag == 'set' and (child.attrs or {}).name == name then
            return false  -- duplicate
        end
    end
    table.insert(autoequip.sets_node.children, {
        tag = 'set', attrs = { name = name }, children = {}, text = '',
    })
    dirty_sets[name] = true
    M.rebuild_sets()
    ui_selected      = name
    optimize_preview = nil
    return true
end

-- Jobs that don't yet have an XML file for the current character. The
-- character's CURRENT job is placed first when missing — that's the user's
-- common case for hitting "+ New File".
local function missing_jobs_list()
    local _, curJob = autoequip.get_edit_target()

    local existing = {}
    for _, entry in ipairs(gear_xml_list) do existing[entry.job] = true end

    local missing = {}
    -- autoutil.jobs is a 1-indexed array of all job abbreviations.
    for i = 1, 22 do
        local j = autoutil.jobs[i]
        if j and not existing[j] and j ~= curJob then
            table.insert(missing, j)
        end
    end
    table.sort(missing)
    if curJob and not existing[curJob] then
        table.insert(missing, 1, curJob)
    end
    return missing
end

-- Create a new <char>_<job>.xml file server-side. GET to check existence
-- first (preserves the "refuse overwrite" semantic the legacy server-side
-- 0x182 handler enforced), then PUT the minimal AshitaCast template. On
-- success transitions the UI to the new file via load_gear_xml.
local EQUIP_TEMPLATE_XML =
    '<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n'
    .. '<ashitacast>\n\t<sets>\n\t</sets>\n</ashitacast>\n'

local function create_new_file(jobName)
    local charName = autoequip.get_edit_target()
    if not charName or charName == '' or not jobName or jobName == '' then
        autoutil.log('AutoEquip', 'create_new_file: missing char or job')
        return
    end
    local fname = charName .. '_' .. jobName
    local http  = require('http_client')
    -- Chained GET-probe + PUT-template — easier inside an http.go() coroutine
    -- with the _sync variants than tracking state through two nested callbacks.
    http.go(function()
        local existsCode = http.get_sync('/configs/equip/' .. fname)
        if existsCode == 200 then
            autoutil.log('AutoEquip', string.format('create_new_file: %s already exists', fname))
            return
        end
        if existsCode ~= 404 and existsCode ~= nil then
            autoutil.log('AutoEquip', string.format('create_new_file[%s]: probe returned %s', fname, tostring(existsCode)))
            return
        end
        local code = http.put_sync('/configs/equip/' .. fname, EQUIP_TEMPLATE_XML, 'application/xml')
        if code == 201 or code == 200 then
            load_gear_xml(charName, jobName)
            M.rebuild_xml_list()
        else
            autoutil.log('AutoEquip', string.format('create_new_file[%s]: PUT returned %s', fname, tostring(code)))
        end
    end)
end

local function draw_new_set_popup()
    if imgui.BeginPopup('##new_set_popup') then
        imgui.Text('New Set Name')
        imgui.PushItemWidth(220)
        imgui.InputText('##new_set_name', new_set_name_input, 64)
        imgui.PopItemWidth()
        imgui.Spacing()
        if imgui.Button('Create##new_set_create', 90, 0) then
            local name = (imgui.GetVarValue(new_set_name_input) or ''):gsub('%z', ''):match('^%s*(.-)%s*$')
            if create_new_set(name) then
                imgui.SetVarValue(new_set_name_input, '')
                imgui.CloseCurrentPopup()
            end
        end
        imgui.SameLine(0, 8)
        if imgui.Button('Cancel##new_set_cancel', 90, 0) then
            imgui.SetVarValue(new_set_name_input, '')
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end
end

local function draw_new_file_popup()
    if imgui.BeginPopup('##new_file_popup') then
        imgui.Text('Job for new XML')
        imgui.Spacing()
        local missing = missing_jobs_list()
        if #missing == 0 then
            imgui.TextDisabled('(all jobs already have files)')
        else
            for _, j in ipairs(missing) do
                if imgui.Selectable(j .. '##nf_' .. j) then
                    create_new_file(j)
                    imgui.CloseCurrentPopup()
                end
            end
        end
        imgui.Spacing()
        if imgui.Button('Cancel##new_file_cancel') then imgui.CloseCurrentPopup() end
        imgui.EndPopup()
    end
end

local function load_gear_xml(charName, job)
    autoequip.load_tried = false
    autoequip.xml_root   = nil
    gear_xml_selected  = job
    dirty_sets         = {}
    pending_set_change = nil
    autoequip.load(charName, job, function(ok)
        if ok then M.rebuild_sets() end
    end)
end

-- ============================================================
-- Equippable item inventory (cross-bag, dedup by item id)
-- ============================================================

local function get_equippable_items()
    local res_mgr = AshitaCore:GetResourceManager()
    local seen    = {}
    local items   = {}
    local editChar = autoequip.get_edit_target()
    for _, bag_id in ipairs(PICKER_BAGS) do
        local bag = inv_cache.get_bag(editChar, bag_id)
        for _, entry in pairs(bag) do
            if entry.id ~= 0 and entry.count > 0 and not seen[entry.id] then
                local res = res_mgr:GetItemById(entry.id)
                if res and res.Name then
                    local name  = tostring(res.Name[0]):gsub('%z', '')
                    local slots = res.Slots or 0
                    if name ~= '' and slots ~= 0 then
                        seen[entry.id] = true
                        local desc = (res.Description and res.Description[0])
                            and tostring(res.Description[0]):gsub('%z', '') or ''
                        table.insert(items, {
                            name  = name,
                            id    = entry.id,
                            slots = slots,
                            jobs  = res.Jobs  or 0,
                            level = res.Level or 0,
                            stats = parse_item_stats(desc),
                        })
                    end
                end
            end
        end
    end
    return items
end

-- ============================================================
-- Slot picker
-- ============================================================

local function open_picker(slot)
    if ui_selected == '' then return end
    picker_slot        = slot
    picker_active      = true
    picker_pending     = nil
    picker_items_cache = get_equippable_items()
    if picker_filter then imgui.SetVarValue(picker_filter, '') end
end

local function draw_confirm_panel()
    local item = picker_pending
    if imgui.Button('< Back##pkc') then
        picker_pending = nil
        return
    end
    imgui.SameLine()
    imgui.Text(SLOT_LABEL[picker_slot] or picker_slot or '?')
    imgui.Separator()

    imgui.Text(item.name)
    if item.level > 0 then
        imgui.SameLine(0, 8)
        imgui.TextDisabled('Lv.' .. item.level)
    end
    imgui.Dummy(0, 10)

    if item.jobs ~= 0 and item.jobs ~= 0xFFFFFFFF then
        local jnames = {}
        for i, jname in ipairs(autoutil.jobs) do
            if bit.band(item.jobs, bit.lshift(1, i)) ~= 0 then
                table.insert(jnames, jname)
            end
        end
        if #jnames > 0 then
            local row = {}
            for idx, jname in ipairs(jnames) do
                table.insert(row, jname)
                if #row == 6 or idx == #jnames then
                    imgui.TextDisabled(table.concat(row, ' '))
                    row = {}
                    if idx < #jnames then imgui.Dummy(0, 5) end
                end
            end
        end
    end

    imgui.Dummy(0, 10)
    imgui.Separator()
    local res = AshitaCore:GetResourceManager():GetItemById(item.id)
    if res and res.Description and res.Description[0] then
        local desc = tostring(res.Description[0]):gsub('%z', '')
        if desc ~= '' then
            imgui.TextWrapped(desc)
        end
    end

    -- Stat diff vs currently equipped item from the selected set. Render
    -- logic lives in libs/item_stat_diff.render_stat_diff so both autoequip
    -- and automog draw an identical strip.
    local xml_tag  = autoequip.SLOT_XML_TAG
    local cur_tag  = xml_tag and xml_tag[picker_slot] or picker_slot
    local gear     = autoequip.resolve_set(autoequip.sets_node, ui_selected, {})
    local cur_name = gear[picker_slot] or (cur_tag and gear[cur_tag]) or ''
    item_stat_diff.render_stat_diff(cur_name, item.name)

    imgui.Dummy(0, 10)
    if imgui.Button('Confirm##pkc', 90, 0) then
        autoequip.set_slot(ui_selected, picker_slot, item.name)
        dirty_sets[ui_selected] = true
        picker_active  = false
        picker_slot    = nil
        picker_pending = nil
    end
    imgui.SameLine()
    if imgui.Button('Cancel##pkc', 90, 0) then
        picker_active  = false
        picker_slot    = nil
        picker_pending = nil
    end
end

local function draw_picker_panel()
    if picker_pending ~= nil then
        draw_confirm_panel()
        return
    end

    if imgui.Button('< Back##pk') then
        picker_active  = false
        picker_slot    = nil
        picker_pending = nil
    end
    imgui.SameLine()
    imgui.Text(SLOT_LABEL[picker_slot] or picker_slot or '?')

    imgui.Separator()
    imgui.PushItemWidth(170)
    imgui.InputText('##pk_filter', picker_filter, 64)
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button('X##pk_clr') then imgui.SetVarValue(picker_filter, '') end

    imgui.Checkbox('Job##pk', picker_filter_job)
    imgui.SameLine()
    imgui.Checkbox('Level##pk', picker_filter_lv)

    if imgui.CollapsingHeader('Primary Stats##pk') then
        for i, stat in ipairs(PRIMARY_STATS) do
            if i > 1 and (i - 1) % 4 ~= 0 then imgui.SameLine() end
            imgui.Checkbox(stat .. '##pks', picker_stat_vars[stat])
        end
    end
    if imgui.CollapsingHeader('Derived Stats##pk') then
        for i, stat in ipairs(DERIVED_STATS) do
            if i > 1 and (i - 1) % 4 ~= 0 then imgui.SameLine() end
            imgui.Checkbox(stat .. '##pkd', picker_stat_vars[stat])
        end
    end
    imgui.Separator()

    local filter_lower = (imgui.GetVarValue(picker_filter) or ''):lower()
    local do_job   = imgui.GetVarValue(picker_filter_job)
    local do_level = imgui.GetVarValue(picker_filter_lv)
    local slot_mask = SLOT_MASK[picker_slot] or 0

    local stat_filters = {}
    for _, stat in ipairs(PRIMARY_STATS) do
        if picker_stat_vars[stat] and imgui.GetVarValue(picker_stat_vars[stat]) then
            table.insert(stat_filters, stat)
        end
    end
    for _, stat in ipairs(DERIVED_STATS) do
        if picker_stat_vars[stat] and imgui.GetVarValue(picker_stat_vars[stat]) then
            table.insert(stat_filters, stat)
        end
    end

    local job_idx = nil
    if autoequip.loaded_job then
        for i, name in ipairs(autoutil.jobs) do
            if name == autoequip.loaded_job then job_idx = i; break end
        end
    end
    local job_mask_val = job_idx and bit.lshift(1, job_idx) or 0
    local job_lv = (job_idx and autoequip.job_levels[job_idx]) or 0
    if job_lv == 0 and job_idx then
        local player = AshitaCore:GetDataManager():GetPlayer()
        if player:GetMainJob() == job_idx then
            job_lv = player:GetMainJobLevel()
        elseif player:GetSubJob() == job_idx then
            job_lv = player:GetSubJobLevel()
        end
    end

    local filtered = {}
    for _, item in ipairs(picker_items_cache or {}) do
        local ok = true
        if slot_mask ~= 0 and bit.band(item.slots, slot_mask) == 0 then ok = false end
        if ok and do_job and job_mask_val ~= 0 and item.jobs ~= 0
           and bit.band(item.jobs, job_mask_val) == 0 then ok = false end
        if ok and do_level and job_lv > 0 and item.level > job_lv then ok = false end
        if ok and filter_lower ~= '' and not item.name:lower():find(filter_lower, 1, true) then ok = false end
        if ok and #stat_filters > 0 then
            local item_stats = item.stats or {}
            for _, stat in ipairs(stat_filters) do
                if not item_stats[stat] then ok = false; break end
            end
        end
        if ok then table.insert(filtered, item) end
    end
    table.sort(filtered, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.name < b.name
    end)

    imgui.BeginChild('##pk_list', 0, 0, false)
    if #filtered == 0 then
        imgui.TextDisabled('(no items)')
    else
        for _, item in ipairs(filtered) do
            local lbl = item.level > 0
                and string.format('[%2d] %s##pk%d', item.level, item.name, item.id)
                or  (item.name .. '##pk' .. item.id)
            if imgui.Selectable(lbl, false) then
                picker_pending = item
            end
        end
    end
    imgui.EndChild()
end

-- ============================================================
-- Optimizer: for each slot, pick the equippable item that maximises stat_name
-- subject to job + level filters; returns a list of proposed changes.
-- ============================================================

local function run_optimize(stat_name, level_override)
    local job_idx = nil
    if autoequip.loaded_job then
        for i, name in ipairs(autoutil.jobs) do
            if name == autoequip.loaded_job then job_idx = i; break end
        end
    end
    local job_mask_val = job_idx and bit.lshift(1, job_idx) or 0
    local job_lv
    if level_override and level_override > 0 then
        job_lv = level_override
    else
        job_lv = (job_idx and autoequip.job_levels[job_idx]) or 0
        if job_lv == 0 and job_idx then
            local player = AshitaCore:GetDataManager():GetPlayer()
            if player:GetMainJob() == job_idx then
                job_lv = player:GetMainJobLevel()
            elseif player:GetSubJob() == job_idx then
                job_lv = player:GetSubJobLevel()
            end
        end
    end

    local all_items = get_equippable_items()
    local gear      = autoequip.resolve_set(autoequip.sets_node, ui_selected, {})
    local xml_tag   = autoequip.SLOT_XML_TAG
    local changes   = {}

    for _, slot in ipairs(SLOT_ORDER) do
        local slot_mask = SLOT_MASK[slot] or 0
        local best_item = nil
        local best_val  = 0
        for _, item in ipairs(all_items) do
            local passes = true
            if slot_mask ~= 0 and bit.band(item.slots, slot_mask) == 0 then passes = false end
            if passes and job_mask_val ~= 0 and item.jobs ~= 0
               and bit.band(item.jobs, job_mask_val) == 0 then passes = false end
            if passes and job_lv > 0 and item.level > job_lv then passes = false end
            if passes then
                local val = (item.stats and item.stats[stat_name]) or 0
                if val > best_val then best_val = val; best_item = item end
            end
        end
        if best_item then
            local old_name = gear[slot] or (xml_tag and gear[xml_tag[slot]]) or ''
            if best_item.name ~= old_name then
                table.insert(changes, { slot=slot, old_name=old_name, new_name=best_item.name, val=best_val })
            end
        end
    end
    return changes
end

-- ============================================================
-- draw
-- ============================================================

function M.draw()
    local charLabel = (autoequip.loaded_char and autoequip.loaded_job)
        and (autoequip.loaded_char .. ' / ' .. autoequip.loaded_job) or '--'
    imgui.Text('Config: ' .. charLabel)
    imgui.SameLine(0, 20)
    -- File actions share the Config row.
    if imgui.Button('New File##new_file_btn') then
        imgui.OpenPopup('##new_file_popup')
    end
    imgui.SameLine(0, 6)
    if imgui.Button('Copy From##copy_xml') and open_copy_from then
        open_copy_from()
    end
    draw_new_file_popup()

    imgui.Spacing()
    -- Per-job set files.
    for i, entry in ipairs(gear_xml_list) do
        if i > 1 and (i - 1) % 12 > 0 then imgui.SameLine() end
        local is_current = (entry.job == (autoequip.loaded_job or ''))
        if is_current then imgui.PushStyleColor(ImGuiCol_Button, 0.26, 0.59, 0.98, 1.0) end
        if imgui.Button(entry.job .. '##xml') then
            local charName = autoequip.get_edit_target()
            load_gear_xml(charName, entry.job)
        end
        if is_current then imgui.PopStyleColor() end
    end
    imgui.Spacing()

    imgui.Separator()

    -- Save / Discard for the active set when dirty + pending-change banner.
    if ui_selected ~= '' and dirty_sets[ui_selected] then
        if imgui.Button('Save##gset_save') then save_set(ui_selected) end
        imgui.SameLine(0, 6)
        if imgui.Button('Discard##gset_discard') then
            discard_set(ui_selected)
            if pending_set_change ~= nil then
                ui_selected        = pending_set_change
                pending_set_change = nil
                optimize_preview   = nil
            end
        end
        imgui.SameLine(0, 12)
        imgui.TextDisabled('unsaved changes')
        if pending_set_change ~= nil then
            imgui.SameLine(0, 12)
            imgui.TextColored(1.0, 0.7, 0.2, 1.0,
                string.format('→ Save/Discard to switch to %s', pending_set_change))
            imgui.SameLine(0, 8)
            if imgui.Button('Cancel##gset_cancel') then pending_set_change = nil end
        end
        imgui.Spacing()
    end

    -- "+ New Set" button above the set list. Disabled until an XML is loaded.
    if autoequip.sets_node ~= nil then
        if imgui.Button('+ New Set##new_set_btn') then
            imgui.SetVarValue(new_set_name_input, '')
            imgui.OpenPopup('##new_set_popup')
        end
    else
        imgui.TextDisabled('(load an XML to enable + New Set)')
    end
    draw_new_set_popup()
    imgui.Spacing()

    imgui.BeginChild('##sets', 260, 0, true)
    if #sets_list == 0 then
        imgui.TextDisabled('no sets loaded')
    else
        for _, name in ipairs(sets_list) do
            local label = dirty_sets[name] and ('* ' .. name) or name
            if imgui.Selectable(label, name == ui_selected) then
                if name ~= ui_selected then
                    if dirty_sets[ui_selected] then
                        pending_set_change = name
                    else
                        ui_selected      = name
                        optimize_preview = nil
                    end
                end
            end
        end
    end
    imgui.EndChild()
    imgui.SameLine(0, 30)

    if picker_active and picker_slot ~= nil then
        imgui.BeginChild('##pk_panel', 260, 0, true)
        draw_picker_panel()
        imgui.EndChild()
    else
        imgui.BeginChild('##slots', 260, 0, true)
        if optimize_preview ~= nil then
            if imgui.Button('< Cancel##opt') then optimize_preview = nil end
            imgui.Separator()
            if #optimize_preview == 0 then
                imgui.TextDisabled('No improvements found.')
            else
                imgui.Text(#optimize_preview .. ' change(s):')
                imgui.Dummy(0, 4)
                for _, ch in ipairs(optimize_preview) do
                    imgui.Text(SLOT_LABEL[ch.slot] or ch.slot)
                    imgui.TextDisabled('  ' .. (ch.old_name ~= '' and ch.old_name or '(empty)'))
                    imgui.TextDisabled('  -> ' .. ch.new_name .. '  +' .. ch.val)
                    imgui.Dummy(0, 3)
                end
                imgui.Dummy(0, 6)
                if imgui.Button('Confirm##opt', 90, 0) then
                    for _, ch in ipairs(optimize_preview) do
                        autoequip.set_slot(ui_selected, ch.slot, ch.new_name)
                    end
                    dirty_sets[ui_selected] = true
                    optimize_preview = nil
                end
                imgui.SameLine()
                if imgui.Button('Cancel##opt2', 90, 0) then optimize_preview = nil end
            end
        elseif ui_selected ~= '' and autoequip.sets_node then
            imgui.Dummy(0, 8)
            local opt_btn_w = 70
            local combo_w   = 140
            local avail_w   = imgui.GetContentRegionAvailWidth()
            local row1_w    = combo_w + 8 + opt_btn_w
            imgui.SetCursorPosX(imgui.GetCursorPosX() + math.floor((avail_w - row1_w) / 2))
            imgui.PushItemWidth(combo_w)
            imgui.Combo('##optstat', optimize_stat_var, table.concat(OPTIMIZE_STATS, '\0') .. '\0')
            imgui.PopItemWidth()
            imgui.SameLine(0, 8)
            if imgui.Button('Optimize##opt', opt_btn_w, 0) then
                local idx       = imgui.GetVarValue(optimize_stat_var) + 1
                local stat_name = OPTIMIZE_STATS[idx]
                local lv_override = imgui.GetVarValue(optimize_level_var)
                if stat_name then optimize_preview = run_optimize(stat_name, lv_override) end
            end
            imgui.Dummy(0, 4)
            local lv_val    = imgui.GetVarValue(optimize_level_var)
            local lv_text_w = calc_text_w('Lv')
            local row2_w    = lv_text_w + 8 + 26 + 8 + 22 + 8 + 40 + 8 + 22 + 8 + 26
            imgui.SetCursorPosX(imgui.GetCursorPosX() + math.floor((avail_w - row2_w) / 2))
            imgui.Text('Lv')
            imgui.SameLine()
            if imgui.Button('<<##optlv', 26, 0) then
                imgui.SetVarValue(optimize_level_var, math.max(0, lv_val - 10))
            end
            imgui.SameLine()
            if imgui.Button('-##optlv', 22, 0) then
                imgui.SetVarValue(optimize_level_var, math.max(0, lv_val - 1))
            end
            imgui.SameLine()
            imgui.Button(lv_val > 0 and tostring(lv_val) or 'auto', 40, 0)
            imgui.SameLine()
            if imgui.Button('+##optlv', 22, 0) then
                imgui.SetVarValue(optimize_level_var, math.min(75, lv_val + 1))
            end
            imgui.SameLine()
            if imgui.Button('>>##optlv', 26, 0) then
                imgui.SetVarValue(optimize_level_var, math.min(75, lv_val + 10))
            end
            imgui.Dummy(0, 6)
            imgui.Separator()
            imgui.Dummy(0, 4)

            -- Base set (inheritance) selector. This set overlays its own slots
            -- on top of the chosen base's resolved gear; client + server resolve
            -- `baseset` identically, so this is pure authoring.
            do
                local cur_node = set_node_for(ui_selected)
                local cur_base = (cur_node and cur_node.attrs and cur_node.attrs.baseset) or ''
                imgui.Text('Base set:')
                imgui.SameLine()
                if imgui.Button(((cur_base ~= '' and cur_base) or '(none)') .. '##baseset_btn', 150, 0) then
                    imgui.OpenPopup('##baseset_popup')
                end
                if imgui.BeginPopup('##baseset_popup') then
                    if imgui.Selectable('(none)##bs_none') then set_baseset(ui_selected, '') end
                    for _, sname in ipairs(sets_list) do
                        if sname ~= ui_selected then -- can't inherit from self
                            if imgui.Selectable(sname .. '##bs_' .. sname) then
                                set_baseset(ui_selected, sname)
                            end
                        end
                    end
                    imgui.EndPopup()
                end
            end

            imgui.Dummy(0, 4)
            imgui.Separator()
            imgui.Dummy(0, 4)

            local gear = autoequip.resolve_set(autoequip.sets_node, ui_selected, {})
            local xml_tag = autoequip.SLOT_XML_TAG
            -- Slots this set OWNS (a direct child with an item) vs slots merged
            -- in from the base set. Only owned slots get the remove [x]; base
            -- rows render dimmed with a (base) marker and no remove — you edit
            -- those in the base set itself.
            local owned_tag = {}
            local own_node  = set_node_for(ui_selected)
            if own_node then
                for _, sn in ipairs(own_node.children) do
                    if sn.text and sn.text ~= '' then owned_tag[sn.tag] = true end
                end
            end
            for _, slot in ipairs(SLOT_ORDER) do
                local item  = gear[slot] or (xml_tag and gear[xml_tag[slot]])
                local label = SLOT_LABEL[slot] or slot
                local has_item = item ~= nil and item ~= ''
                local tag       = (xml_tag and xml_tag[slot]) or slot
                local owned     = has_item and owned_tag[tag] == true
                local inherited = has_item and not owned
                local row   = string.format('%-6s  %s', label, has_item and item or '(empty)')
                if inherited then row = row .. '  (base)' end
                -- Remove [x] only for owned slots (X-on-left so it doesn't fight
                -- the Selectable for the click); inherited/empty rows pad with a
                -- Dummy to keep the row text aligned.
                if owned then
                    if imgui.Button('x##slrm_' .. slot, 22, 0) then
                        autoequip.remove_slot(ui_selected, slot)
                        dirty_sets[ui_selected] = true
                    end
                else
                    imgui.Dummy(22, 0)
                end
                imgui.SameLine(0, 6)
                if inherited then imgui.PushStyleColor(ImGuiCol_Text, 0.55, 0.55, 0.55, 1.0) end
                if imgui.Selectable(row .. '##sl_' .. slot) then
                    open_picker(slot)
                end
                if inherited then imgui.PopStyleColor() end
            end
        elseif ui_selected ~= '' then
            imgui.TextDisabled('config not loaded')
        else
            imgui.TextDisabled('select a set')
        end
        imgui.EndChild()
    end
end

return M
