-- Food Config form editor.
-- Modal opened from the right-column Food Config "Edit" button. The user
-- assigns a food item to each char in a roster. Roster source: either the
-- active alliance (via 0x186 alliance_pc_list) or any saved alliance config
-- (loaded via 0x17E config content fetch).
--
-- Food picker: items in the player's inventory float to the top with an
-- "[in bag]" marker; the rest of the list is filterable by name across the
-- FFXI item DB. Free-form text entry is intentionally not offered — users
-- must pick an actual resource-manager item to avoid stale / typo'd names
-- silently breaking server-side use_food_from_config.
--
-- Save flow: serialize the assignments table to JSON, ship via 0x189
-- SET_CONFIG_FILE (chunked), wait for 0x18A result.

require 'imguidef';

local autoutil = require('autoutil');
local json     = require('json');

local food_tab = {};

-- Modal state. Reset by open() each invocation.
local state = {
    open           = false,
    needs_open     = false,       -- set by open(), consumed by render() to OpenPopup
    needs_close    = false,       -- set when save succeeds; consumed inside Begin block
    config_name    = nil,
    roster_mode    = 'alliance',  -- 'alliance' or a saved alliance config name
    rows           = {},          -- list of { name, food }
    food_picker_for = nil,        -- name of the row whose picker is open, or nil
    food_filter    = nil,         -- imgui CHARARRAY var
    inventory_foods_cache = nil,  -- list of { id, name, count }
    error          = '',
};

local CONTAINER_INVENTORY = 0;   -- main bag (LOC_INVENTORY / bag 0)

-- Authoritative food item-id set, generated from item_basic (aH food band).
-- The client item resource exposes no food discriminator, so we key off this
-- list instead of the old (broken) cast_time>0 heuristic. See food_ids.lua.
local FOOD_IDS = require('food_ids');
local food_id_set = {};
for _, id in ipairs(FOOD_IDS) do food_id_set[id] = true; end

local function clean_str(s)
    if s == nil then return ''; end
    return tostring(s):gsub('%z+$', ''):gsub('^%s+', ''):gsub('%s+$', '');
end

local function item_name(res)
    if res == nil or res.Name == nil then return '?'; end
    return clean_str(res.Name[0]);
end

-- Fetch the TARGET character's inventory (headless or primary) over HTTP and
-- keep only food. AshitaCore:GetInventory() is the logged-in client's bag =
-- always the primary, so it can't show a headless's food; the server endpoint
-- resolves any char by name. Result lands in state.inventory_foods_cache. The
-- fetch is fired when the picker opens for a row (see the food button).
local function fetch_target_food_inventory(charName)
    state.inventory_foods_cache = {};
    if charName == nil or charName == '' then return; end
    local http    = require('http_client');
    local wanted  = charName;
    http.get('/chars/' .. charName .. '/inventory', function(code, body)
        -- Drop the result if the user moved on to a different row/target.
        if state.food_picker_for ~= wanted then return; end
        if code ~= 200 or body == nil or body == '' then return; end
        local ok, parsed = pcall(json.decode, json, body);
        if not ok or type(parsed) ~= 'table' or type(parsed.items) ~= 'table' then return; end
        local res_mgr = AshitaCore:GetResourceManager();
        local out, seen = {}, {};
        for _, it in ipairs(parsed.items) do
            local id = it.itemId;
            -- bag 0 = main inventory; only food ids, deduped.
            if it.bag == CONTAINER_INVENTORY and food_id_set[id] and not seen[id] then
                seen[id] = true;
                table.insert(out, { id = id, name = item_name(res_mgr:GetItemById(id)), count = it.count or 0 });
            end
        end
        table.sort(out, function(a, b) return a.name < b.name; end);
        state.inventory_foods_cache = out;
    end);
end

-- All food items, resolved from the authoritative id set (names via the client
-- resource manager). Cached for the modal's lifetime.
local _all_foods_cache = nil;
local function all_foods()
    if _all_foods_cache ~= nil then return _all_foods_cache; end
    local res_mgr = AshitaCore:GetResourceManager();
    local out     = {};
    for _, id in ipairs(FOOD_IDS) do
        local nm = item_name(res_mgr:GetItemById(id));
        if nm ~= '' and nm ~= '?' then
            table.insert(out, { id = id, name = nm });
        end
    end
    table.sort(out, function(a, b) return a.name < b.name; end);
    _all_foods_cache = out;
    return out;
end

-- Build roster rows from the active alliance — sourced from autoutil.alliance_pcs
-- which the BF section already populates via 0x185/0x186. If the cache is
-- empty (alliance not currently spawned), fire the request and we'll repopulate
-- on the next 0x186 arrival.
local function set_roster_from_alliance()
    local roster = autoutil.alliance_pcs or {};
    if #roster == 0 then
        autoutil.send_list_alliance_pcs();
    end
    state.rows = {};
    for _, m in ipairs(roster) do
        table.insert(state.rows, { name = m.name, food = '' });
    end
end

-- Fetch a saved alliance config from the server, derive roster from its
-- alliance[].ptLeader + alliance[].members lists. Existing assignments in
-- state.rows for the same name are preserved.
local function set_roster_from_config(cfgName)
    local http = require('http_client');
    http.get('/configs/alliance/' .. cfgName, function(code, body, _, err)
        if state.roster_mode ~= cfgName then return; end
        if code == nil then
            state.error = string.format("Couldn't read alliance config '%s': %s", cfgName, tostring(err));
            return;
        end
        if code ~= 200 or body == nil or body == '' then
            state.error = string.format("Couldn't read alliance config '%s' (HTTP %s)", cfgName, tostring(code));
            return;
        end
        local ok, parsed = pcall(json.decode, json, body);
        if not ok or type(parsed) ~= 'table' or type(parsed.alliance) ~= 'table' then
            state.error = string.format("Couldn't parse alliance config '%s'", cfgName);
            return;
        end
        local existing = {};
        for _, r in ipairs(state.rows) do existing[r.name] = r.food; end
        state.rows = {};
        for _, party in ipairs(parsed.alliance) do
            if party.ptLeader and party.ptLeader ~= '' then
                table.insert(state.rows, { name = party.ptLeader, food = existing[party.ptLeader] or '' });
            end
            if type(party.members) == 'table' then
                for _, m in ipairs(party.members) do
                    if m ~= '' then
                        table.insert(state.rows, { name = m, food = existing[m] or '' });
                    end
                end
            end
        end
        state.error = '';
    end);
end

-- Apply an existing food config's assignments onto state.rows (matched by name).
local function apply_existing_assignments(name_to_food)
    if type(name_to_food) ~= 'table' then return; end
    for _, r in ipairs(state.rows) do
        if name_to_food[r.name] then r.food = name_to_food[r.name]; end
    end
end

-- Open the modal for the named food config. Fetches existing body so we can
-- seed assignments. roster_mode defaults to 'alliance'.
function food_tab.open(configName)
    state.open                  = true;
    state.needs_open            = true;
    state.config_name           = configName;
    state.roster_mode           = 'alliance';
    state.rows                  = {};
    state.food_picker_for       = nil;
    -- Populated per-row over HTTP when the food picker opens (headless-aware).
    state.inventory_foods_cache = {};
    state.error                 = '';
    _all_foods_cache            = nil;  -- force re-scan
    if state.food_filter ~= nil then imgui.DeleteVar(state.food_filter); end
    -- CDSTRING + 2-arg paired calls match every other input across the addon
    -- set; the CHARARRAY/3-arg form was crashing the client.
    state.food_filter = imgui.CreateVar(ImGuiVar_CDSTRING, 64);
    imgui.SetVarValue(state.food_filter, '');

    set_roster_from_alliance();

    -- Async GET of the food config; missing file (404) is fine — that means
    -- this is a fresh config and there's no existing assignments to apply.
    local http = require('http_client');
    http.get('/configs/food/' .. configName, function(code, body, _, err)
        if state.config_name ~= configName then return; end
        if code == 200 and body and body ~= '' then
            local ok, parsed = pcall(json.decode, json, body);
            if ok and type(parsed) == 'table' then
                apply_existing_assignments(parsed);
            end
        elseif code == nil then
            autoutil.log('AutoBots', string.format('food fetch %s: %s', configName, tostring(err)));
        elseif code ~= 200 and code ~= 404 then
            autoutil.log('AutoBots', string.format('food fetch %s: HTTP %s', configName, tostring(code)));
        end
    end);
end

local function close_modal()
    state.open = false;
    if state.food_filter ~= nil then imgui.DeleteVar(state.food_filter); state.food_filter = nil; end
    _all_foods_cache = nil;
end

-- Build the JSON body { CharName = "FoodName", ... }. Skips empty assignments.
local function build_body()
    local out = {};
    for _, r in ipairs(state.rows) do
        if r.food ~= nil and r.food ~= '' then out[r.name] = r.food; end
    end
    return json:encode(out);
end

-- Render the food picker popup for the active row. Inventory first
-- (highlighted), then filtered all-foods list.
local function render_food_picker()
    if state.food_picker_for == nil then return; end
    local popup_id = 'food_pick##fp_popup';

    if imgui.BeginPopup(popup_id) then
        imgui.Text('Pick food for ' .. state.food_picker_for);
        imgui.InputText('Filter##fp_filter', state.food_filter);
        local filter = imgui.GetVarValue(state.food_filter):lower();

        imgui.Dummy(0, 4);
        imgui.TextDisabled('In inventory');
        imgui.BeginChild('##fp_inv', 280, 110, true);
        local any_inv = false;
        for _, it in ipairs(state.inventory_foods_cache or {}) do
            if filter == '' or it.name:lower():find(filter, 1, true) then
                any_inv = true;
                if imgui.Selectable(string.format('%s  [in bag x%d]', it.name, it.count)) then
                    for _, r in ipairs(state.rows) do
                        if r.name == state.food_picker_for then r.food = it.name; end
                    end
                    state.food_picker_for = nil;
                    imgui.CloseCurrentPopup();
                end
            end
        end
        if not any_inv then imgui.TextDisabled('(none)'); end
        imgui.EndChild();

        imgui.Dummy(0, 4);
        imgui.TextDisabled('All foods');
        imgui.BeginChild('##fp_all', 280, 200, true);
        local count = 0;
        for _, it in ipairs(all_foods()) do
            if (filter == '' or it.name:lower():find(filter, 1, true)) and count < 100 then
                if imgui.Selectable(it.name) then
                    for _, r in ipairs(state.rows) do
                        if r.name == state.food_picker_for then r.food = it.name; end
                    end
                    state.food_picker_for = nil;
                    imgui.CloseCurrentPopup();
                end
                count = count + 1;
            end
        end
        if count == 0 then imgui.TextDisabled('(no matches)'); end
        imgui.EndChild();

        imgui.Dummy(0, 4);
        if imgui.Button('Cancel##fp_cancel', 80, 0) then
            state.food_picker_for = nil;
            imgui.CloseCurrentPopup();
        end
        imgui.EndPopup();
    else
        state.food_picker_for = nil;
    end
end

-- Main render entry. Called every frame from autobots_ui.lua. The modal opens
-- itself via OpenPopup the first frame after open() is called.
function food_tab.render()
    if not state.open then return; end
    local popup_id = 'food_editor##fe_popup';
    if state.needs_open then
        imgui.OpenPopup(popup_id);
        state.needs_open = false;
    end

    imgui.SetNextWindowSize(420, 0, ImGuiSetCond_FirstUseEver);
    if imgui.BeginPopupModal(popup_id, nil, ImGuiWindowFlags_AlwaysAutoResize) then
        if state.needs_close then
            state.needs_close = false;
            close_modal();
            imgui.CloseCurrentPopup();
            imgui.EndPopup();
            return;
        end

        imgui.Text('Edit Food Config: "' .. tostring(state.config_name) .. '"');
        imgui.Dummy(0, 6);

        -- Roster source row.
        imgui.Text('Roster from:');
        imgui.SameLine();
        local mode_label = (state.roster_mode == 'alliance') and 'Active Alliance' or state.roster_mode;
        if imgui.Button(mode_label .. '##fe_mode', 200, 0) then
            -- Fire-and-forget refresh of the cached alliance config list
            -- when the dropdown opens. The popup renders from cache; the
            -- response replaces the cache when it arrives (later frame).
            local http = require('http_client');
            http.get('/configs/alliance', function(code, body)
                if code == 200 then
                    local ok, parsed = pcall(json.decode, json, body);
                    if ok and parsed and parsed.names then
                        state.alliance_cfgs_cache = parsed.names;
                    end
                end
            end);
            imgui.OpenPopup('mode_pick##fe_mode_popup');
        end
        if imgui.BeginPopup('mode_pick##fe_mode_popup') then
            if imgui.Selectable('Active Alliance') then
                state.roster_mode = 'alliance';
                set_roster_from_alliance();
            end
            imgui.Separator();
            local cfgs = state.alliance_cfgs_cache or {};
            if #cfgs == 0 then
                imgui.TextDisabled('(no alliance configs)');
            else
                for _, name in ipairs(cfgs) do
                    if imgui.Selectable(name) then
                        state.roster_mode = name;
                        set_roster_from_config(name);
                    end
                end
            end
            imgui.EndPopup();
        end

        if state.error ~= '' then
            imgui.TextColored(1.0, 0.4, 0.4, 1.0, state.error);
        end

        imgui.Dummy(0, 8);
        imgui.Separator();
        imgui.Dummy(0, 6);

        -- Rows.
        if #state.rows == 0 then
            imgui.TextDisabled('(no roster - pick a source above)');
        else
            for _, r in ipairs(state.rows) do
                imgui.Text(r.name);
                imgui.SameLine(140);
                local label = (r.food ~= '' and r.food or '(none)') .. '##fe_food_' .. r.name;
                if imgui.Button(label, 240, 0) then
                    state.food_picker_for = r.name;
                    if state.food_filter ~= nil then imgui.SetVarValue(state.food_filter, ''); end
                    fetch_target_food_inventory(r.name); -- headless-aware, over HTTP
                    imgui.OpenPopup('food_pick##fp_popup');
                end
            end
        end

        render_food_picker();

        imgui.Dummy(0, 8);
        imgui.Separator();
        imgui.Dummy(0, 4);

        if imgui.Button('Save##fe_save', 80, 0) then
            local body    = build_body();
            local cfgName = state.config_name;
            local http    = require('http_client');
            http.put('/configs/food/' .. cfgName, body, 'application/json', function(code, _, _, err)
                if state.config_name ~= cfgName then return; end
                if code == 200 or code == 201 then
                    state.needs_close = true;
                elseif code == nil then
                    state.error = string.format('Save failed: %s', tostring(err));
                else
                    state.error = string.format('Save failed (HTTP %s)', tostring(code));
                end
            end);
        end
        imgui.SameLine();
        if imgui.Button('Cancel##fe_cancel', 80, 0) then
            close_modal();
            imgui.CloseCurrentPopup();
        end

        imgui.EndPopup();
    end
end

return food_tab;
