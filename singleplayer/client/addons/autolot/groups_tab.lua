-- AutoLot Groups editor — Phase A of #72.
--
-- All persistence is server-side: groups live as JSON files at
-- singleplayer/config/lot/<name>.json. The addon never touches local
-- disk — listing, fetching, saving, and creating all happen via packets
-- (0x17A / 0x17E / 0x180 / 0x182). Server is the source of truth.
--
-- Schema: { "ids": [4096, ...] } — IDs only. Names are a display concern,
-- resolved at render time via the ResourceManager. The earlier "names" list
-- (name-match drop matching) was removed once the search-by-name picker (#81)
-- let users add by name without storing a separate name list.

local M = {}

local autoutil
local json = require('json')

-- ============================================================
-- State
-- ============================================================

local groups_list      = {}    -- array of group names from 0x17A
local active_group     = ''    -- selected group name
local group_bodies     = {}    -- name → parsed { ids } once fetched
local dirty_groups     = {}    -- name → true if has unsaved changes
local pending_change   = nil   -- group user clicked but was blocked from
local pending_fetch    = {}    -- name → true while we wait for 0x17F to land

-- Local mirror of per-char group assignments. Pure UI state — server is the
-- authority (assignments only apply to currently-spawned chars). When the
-- user toggles a checkbox we update this mirror AND fire 0x178; the next
-- frame's render reflects from the mirror immediately.
-- Shape: assignments[charName][groupName] = true
local assignments = {}

-- Per-(char, group) BOOLCPP imgui var cache. Reused across frames so we
-- don't churn allocations every render. on_unload clears the lot.
local assign_vars = {}
local function assign_var_for(charName, groupName)
    local k = charName .. '|' .. groupName
    if assign_vars[k] == nil then
        assign_vars[k] = imgui.CreateVar(ImGuiVar_BOOLCPP)
    end
    return assign_vars[k]
end

local function is_assigned(charName, groupName)
    return assignments[charName] ~= nil and assignments[charName][groupName] == true
end

local function set_assigned(charName, groupName, on)
    if on then
        assignments[charName] = assignments[charName] or {}
        assignments[charName][groupName] = true
    elseif assignments[charName] ~= nil then
        assignments[charName][groupName] = nil
    end
end

-- Roster source: the local Ashita party manager. Slots 0..17 cover the full
-- alliance (primary at 0, party 1 at 0-5, party 2 at 6-11, party 3 at 12-17).
-- Trusts surface here too but can never lot, so we filter them out by
-- intersecting with the server `chars` roster (primary + headless bots only;
-- trusts are transient entities, never DB chars). The fetch is kicked lazily;
-- until it resolves we show everyone so the list isn't empty during load.
local function get_alliance_members()
    local out = {}
    local party = AshitaCore:GetDataManager():GetParty()
    if party == nil then return out end
    if autoutil.fetch_chars and not autoutil.char_names_final then
        autoutil.fetch_chars()
    end
    local real = nil
    if autoutil.char_names_final and type(autoutil.char_names) == 'table' then
        real = {}
        for _, cn in ipairs(autoutil.char_names) do real[cn] = true end
    end
    for slot = 0, 17 do
        local nm = party:GetMemberName(slot)
        if nm ~= nil and nm ~= '' and (real == nil or real[nm]) then
            table.insert(out, nm)
        end
    end
    return out
end

-- "+ New Group" popup input
local new_group_input  = nil

-- Search-by-name item index (#81). Built lazily on first use, cached for the
-- session. We scan a bounded id range via ResourceManager and keep
-- { id, name, lname } entries; the input box substring-filters lname.
local item_index           = nil    -- nil until built; array of {id, name, lname}
local item_index_lo        = 1
local item_index_hi        = 32768  -- generous upper bound; gaps are skipped at build time
local search_input         = nil    -- CDSTRING
local search_last          = ''     -- last filter string we computed for
local search_results       = {}     -- cached top-N matches for search_last
local SEARCH_RESULT_LIMIT  = 80     -- how many matches to render at once

-- ============================================================
-- Init + lifecycle
-- ============================================================

function M.init(deps)
    autoutil = deps.autoutil
end

function M.on_load()
    new_group_input  = imgui.CreateVar(ImGuiVar_CDSTRING, 64)
    search_input     = imgui.CreateVar(ImGuiVar_CDSTRING, 64)
end

function M.on_unload()
    if new_group_input ~= nil then imgui.DeleteVar(new_group_input); new_group_input = nil end
    if search_input    ~= nil then imgui.DeleteVar(search_input);    search_input    = nil end
    for k, v in pairs(assign_vars) do imgui.DeleteVar(v); assign_vars[k] = nil end
end

-- Build the id → (name, lname) index by walking GetItemById across the bounded
-- range. Items with no Name field (id gaps) are skipped. This is a one-time
-- cost; subsequent searches just filter the cached array.
local function ensure_item_index()
    if item_index ~= nil then return end
    local res_mgr = AshitaCore:GetResourceManager()
    local idx     = {}
    for id = item_index_lo, item_index_hi do
        local res = res_mgr:GetItemById(id)
        if res and res.Name then
            local nm = tostring(res.Name[0]):gsub('%z', '')
            if nm ~= '' then
                table.insert(idx, { id = id, name = nm, lname = nm:lower() })
            end
        end
    end
    item_index = idx
    autoutil.log('AutoLot', string.format('item index built: %d entries', #idx))
end

local function refresh_search_results()
    local cur = ((search_input ~= nil) and imgui.GetVarValue(search_input) or ''):gsub('%z', '')
    cur = cur:match('^%s*(.-)%s*$'):lower()
    if cur == search_last then return end
    search_last    = cur
    search_results = {}
    if cur == '' then return end
    -- Auto-build the index on first non-empty search. One-shot ~32k lookup
    -- costs a single noticeable hitch, then subsequent keystrokes are cheap.
    if item_index == nil then ensure_item_index() end
    if item_index == nil then return end
    -- Plain substring match. Ranking: exact > prefix > substring.
    local exact, prefix, sub = nil, {}, {}
    for _, e in ipairs(item_index) do
        if e.lname == cur then
            exact = e
        elseif e.lname:sub(1, #cur) == cur then
            table.insert(prefix, e)
        elseif e.lname:find(cur, 1, true) ~= nil then
            table.insert(sub, e)
        end
        if #prefix + #sub > SEARCH_RESULT_LIMIT * 2 then break end
    end
    if exact then table.insert(search_results, exact) end
    for _, e in ipairs(prefix) do
        if #search_results >= SEARCH_RESULT_LIMIT then break end
        table.insert(search_results, e)
    end
    for _, e in ipairs(sub) do
        if #search_results >= SEARCH_RESULT_LIMIT then break end
        table.insert(search_results, e)
    end
end

-- ============================================================
-- Server I/O
-- ============================================================

local function refresh_group_list()
    local http = require('http_client')
    http.get('/configs/lot', function(code, body, _, err)
        if code == nil then
            autoutil.log('AutoLot', string.format(
                'refresh_group_list: %s', tostring(err)))
            groups_list = {}
            return
        end
        if code ~= 200 then
            autoutil.log('AutoLot', string.format(
                'refresh_group_list: GET /configs/lot -> HTTP %s', tostring(code)))
            groups_list = {}
            return
        end
        local ok, parsed = pcall(json.decode, json, body)
        local names = (ok and parsed and parsed.names) or {}
        groups_list = {}
        for _, n in ipairs(names) do table.insert(groups_list, n) end
        table.sort(groups_list)
    end)
end

local function fetch_group(name, after)
    -- pending_fetch still serves as a "request in flight" guard so concurrent
    -- callers don't dispatch multiple fetches for the same group.
    if pending_fetch[name] then return end
    pending_fetch[name] = true
    local http = require('http_client')
    http.get('/configs/lot/' .. name, function(code, body, _, err)
        pending_fetch[name] = nil
        if code == nil then
            autoutil.log('AutoLot', string.format('fetch_group[%s]: %s', name, tostring(err)))
            return
        end
        if code ~= 200 or body == nil or body == '' then
            if code ~= 200 then
                autoutil.log('AutoLot', string.format('fetch_group[%s]: GET returned %s', name, tostring(code)))
            end
            return
        end
        local ok, data = pcall(json.decode, json, body)
        if not ok or type(data) ~= 'table' then
            autoutil.log('AutoLot', 'parse failed for ' .. name)
            return
        end
        group_bodies[name] = { ids = data.ids or {} }
        dirty_groups[name] = nil
        if after then after(name) end
    end)
end

function M.reload()
    -- Preserve which group the user was looking at across the wipe so we can
    -- re-fetch its body once the name listing settles. Otherwise the active
    -- pane reads group_bodies[name] = nil and shows the "No data" placeholder
    -- until the user picks the group again, which felt like a regression.
    local prev_active = active_group
    group_bodies   = {}
    dirty_groups   = {}
    pending_change = nil
    refresh_group_list()
    if prev_active ~= '' then
        fetch_group(prev_active)
    end
end

-- Serialize a group body to the JSON shape autolot expects (one id per line
-- so diffs stay readable when groups grow).
local function serialize_group(body)
    local parts = { '{\n  "ids": [' }
    if #body.ids > 0 then
        table.insert(parts, '\n')
        for i, id in ipairs(body.ids) do
            table.insert(parts, '    ' .. tostring(id))
            if i < #body.ids then table.insert(parts, ',') end
            table.insert(parts, '\n')
        end
        table.insert(parts, '  ')
    end
    table.insert(parts, ']\n}\n')
    return table.concat(parts)
end

local function save_group(name)
    local body = group_bodies[name]
    if body == nil then return end
    local payload = serialize_group(body)
    local http    = require('http_client')
    http.put('/configs/lot/' .. name, payload, 'application/json', function(code, _, _, err)
        if code == 200 or code == 201 then
            dirty_groups[name] = nil
            if pending_change ~= nil then
                active_group   = pending_change
                pending_change = nil
                if group_bodies[active_group] == nil then fetch_group(active_group) end
            end
        elseif code == nil then
            autoutil.log('AutoLot', string.format('save_group[%s]: %s', name, tostring(err)))
        else
            autoutil.log('AutoLot', string.format('save_group[%s]: PUT returned %s', name, tostring(code)))
        end
    end)
end

local function discard_group(name)
    dirty_groups[name] = nil
    group_bodies[name] = nil
    fetch_group(name)
end

-- ============================================================
-- Cross-tab API: called by pool_tab + recent_tab to add an item id to an
-- existing group with implicit save (no need for the user to switch tabs).
-- Fetches the group body if not already cached, then appends + saves.
-- ============================================================

function M.get_group_names()
    return groups_list
end

function M.add_id_to_group_and_save(group_name, item_id)
    if group_name == nil or group_name == '' or item_id == nil or item_id <= 0 then return end

    local function append_and_save()
        local body = group_bodies[group_name]
        if body == nil then return end
        for _, id in ipairs(body.ids) do
            if id == item_id then
                autoutil.log('AutoLot', string.format('%s already contains item %d', group_name, item_id))
                return
            end
        end
        table.insert(body.ids, item_id)
        table.sort(body.ids)
        save_group(group_name)
        autoutil.log('AutoLot', string.format('Added item %d to %s', item_id, group_name))
    end

    if group_bodies[group_name] ~= nil then
        append_and_save()
    else
        -- Schedule the fetch and chain append_and_save via the `after`
        -- callback. The append runs on whichever frame the response lands.
        fetch_group(group_name, function() append_and_save() end)
    end
end

local function create_group(name)
    if name == nil or name == '' then return false end
    for _, existing in ipairs(groups_list) do
        if existing == name then return false end  -- duplicate
    end
    -- Chained GET-probe + PUT-template via http.go(). Returns true to
    -- mean "create was scheduled" — the actual creation completes
    -- a few frames later inside the coroutine.
    local http = require('http_client')
    http.go(function()
        local existsCode = http.get_sync('/configs/lot/' .. name)
        if existsCode == 200 then
            autoutil.log('AutoLot', string.format('create_group: %s already exists', name))
            return
        end
        if existsCode ~= 404 and existsCode ~= nil then
            autoutil.log('AutoLot', string.format('create_group[%s]: probe returned %s', name, tostring(existsCode)))
            return
        end
        local code = http.put_sync('/configs/lot/' .. name, '{}\n', 'application/json')
        if code == 200 or code == 201 then
            group_bodies[name] = { ids = {} }
            table.insert(groups_list, name)
            table.sort(groups_list)
            active_group = name
        else
            autoutil.log('AutoLot', string.format('create_group[%s]: PUT returned %s', name, tostring(code)))
        end
    end)
    return true
end

-- ============================================================
-- Mutations on the active group's body (mark dirty for explicit Save)
-- ============================================================

local function add_id(itemId)
    if active_group == '' or group_bodies[active_group] == nil then return end
    if itemId == nil or itemId <= 0 then return end
    for _, id in ipairs(group_bodies[active_group].ids) do
        if id == itemId then return end  -- dedupe
    end
    table.insert(group_bodies[active_group].ids, itemId)
    table.sort(group_bodies[active_group].ids)
    dirty_groups[active_group] = true
end

local function remove_id(itemId)
    if active_group == '' or group_bodies[active_group] == nil then return end
    for i, id in ipairs(group_bodies[active_group].ids) do
        if id == itemId then
            table.remove(group_bodies[active_group].ids, i)
            dirty_groups[active_group] = true
            return
        end
    end
end

-- ============================================================
-- draw
-- ============================================================

local function draw_new_group_popup()
    if imgui.BeginPopup('##autolot_new_group') then
        imgui.Text('New Group Name')
        imgui.PushItemWidth(220)
        imgui.InputText('##new_group_name', new_group_input, 64)
        imgui.PopItemWidth()
        imgui.Spacing()
        if imgui.Button('Create##new_group_create', 90, 0) then
            local name = (imgui.GetVarValue(new_group_input) or ''):gsub('%z', ''):match('^%s*(.-)%s*$')
            if create_group(name) then
                imgui.SetVarValue(new_group_input, '')
                imgui.CloseCurrentPopup()
            end
        end
        imgui.SameLine(0, 8)
        if imgui.Button('Cancel##new_group_cancel', 90, 0) then
            imgui.SetVarValue(new_group_input, '')
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end
end

local function draw_active_group_pane()
    local body = group_bodies[active_group]
    if body == nil then
        if pending_fetch[active_group] then
            imgui.TextDisabled('Loading...')
        else
            imgui.TextDisabled('No data - try Reload.')
        end
        return
    end

    -- Save / Discard banner when dirty.
    if dirty_groups[active_group] then
        if imgui.Button('Save##save_active') then save_group(active_group) end
        imgui.SameLine(0, 6)
        if imgui.Button('Discard##discard_active') then
            discard_group(active_group)
            if pending_change ~= nil then
                active_group   = pending_change
                pending_change = nil
                if group_bodies[active_group] == nil then fetch_group(active_group) end
            end
        end
        imgui.SameLine(0, 12)
        imgui.TextDisabled('unsaved changes')
        if pending_change ~= nil then
            imgui.SameLine(0, 12)
            imgui.TextColored(1.0, 0.7, 0.2, 1.0, string.format('-> switch to %s', pending_change))
            imgui.SameLine(0, 8)
            if imgui.Button('Cancel##cancel_nav') then pending_change = nil end
        end
        imgui.Separator()
        imgui.Dummy(0, 4)
    end

    imgui.Text(active_group)
    imgui.Dummy(0, 6)
    imgui.Separator()
    imgui.Dummy(0, 6)

    -- Item IDs section
    imgui.Text(string.format('Item IDs (%d)', #body.ids))

    -- Search box (primary affordance). Builds the index on first use; results
    -- list lets the user click an entry to add it directly.
    imgui.Text('Search items')
    imgui.SameLine(0, 8)
    imgui.PushItemWidth(240)
    imgui.InputText('##search_items', search_input, 64)
    imgui.PopItemWidth()
    imgui.SameLine(0, 4)
    if imgui.Button('X##search_clr') then
        imgui.SetVarValue(search_input, '')
    end
    refresh_search_results()
    if #search_results > 0 then
        imgui.BeginChild('##search_results', 0, 120, true)
        for _, e in ipairs(search_results) do
            if imgui.Selectable(string.format('%5d  %s##sr_%d', e.id, e.name, e.id)) then
                add_id(e.id)
            end
        end
        imgui.EndChild()
    end

    -- Assigned-to section. One checkbox per alliance member (primary +
    -- party + trusts). Toggling fires 0x178 SET_LOT_ASSIGNMENT immediately
    -- and updates the local mirror so the box reflects on the next frame.
    -- Server is spawned-only — toggling a row for a char that isn't a live
    -- PC is a no-op at receive. State is NOT persisted across addon reloads
    -- or bot despawns; the user re-applies as needed.
    imgui.Dummy(0, 6)
    imgui.Text('Assigned to')
    imgui.Separator()
    imgui.Dummy(0, 2)
    local members = get_alliance_members()
    if #members == 0 then
        imgui.TextDisabled('(no alliance members visible)')
    else
        for i, nm in ipairs(members) do
            local col = (i - 1) % 3
            if col > 0 then imgui.SameLine(col * 155) end -- 3 columns, aligned
            local on  = is_assigned(nm, active_group)
            local var = assign_var_for(nm, active_group)
            imgui.SetVarValue(var, on)
            imgui.Checkbox('##lot_assign_' .. nm, var)
            imgui.SameLine()
            imgui.Text(nm)
            local nv = imgui.GetVarValue(var)
            if nv ~= on then
                set_assigned(nm, active_group, nv)
                autoutil.send_set_lot_assignment(nm, active_group, nv)
            end
        end
    end

    imgui.Dummy(0, 6)
    imgui.Text('Item IDs')
    imgui.Separator()
    imgui.Dummy(0, 2)
    imgui.BeginChild('##ids_list', 0, 0, true)
    local res_mgr = AshitaCore:GetResourceManager()
    for _, id in ipairs(body.ids) do
        local res = res_mgr:GetItemById(id)
        local nm  = (res and res.Name) and tostring(res.Name[0]):gsub('%z', '') or ('item#' .. id)
        if imgui.Button('x##rmid_' .. id) then remove_id(id) end
        imgui.SameLine(0, 8)
        imgui.Text(string.format('%5d  %s', id, nm))
    end
    imgui.EndChild()
end

function M.draw()
    -- Top row: + New Group + Reload
    if imgui.Button('+ New Group##new_group_btn') then
        imgui.SetVarValue(new_group_input, '')
        imgui.OpenPopup('##autolot_new_group')
    end
    draw_new_group_popup()
    imgui.SameLine(0, 8)
    if imgui.Button('Reload##reload_groups') then M.reload() end
    imgui.Spacing()

    -- Left rail: group list
    imgui.BeginChild('##groups_rail', 180, 0, true)
    if #groups_list == 0 then
        imgui.TextDisabled('(no groups defined)')
    else
        for _, name in ipairs(groups_list) do
            local label = dirty_groups[name] and ('* ' .. name) or name
            if imgui.Selectable(label, name == active_group) then
                if name ~= active_group then
                    if dirty_groups[active_group] then
                        pending_change = name
                    else
                        active_group = name
                        if group_bodies[active_group] == nil then fetch_group(active_group) end
                    end
                end
            end
        end
    end
    imgui.EndChild()
    imgui.SameLine(0, 12)

    -- Right pane: active group editor
    imgui.BeginChild('##group_pane', 0, 0, false)
    if active_group == '' then
        imgui.TextDisabled('Select a group on the left, or click "+ New Group" to create one.')
    else
        draw_active_group_pane()
    end
    imgui.EndChild()
end

return M
