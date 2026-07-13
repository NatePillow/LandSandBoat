_addon.author  = 'Nate';
_addon.name    = 'AutoEquip';
_addon.version = '1.0';

require 'common';
require 'imguidef';

-- The lib (XML parser + gear-set cache) lives at addons/libs/autoequip.lua.
local autoequip     = require('autoequip');
local autoutil      = require('autoutil');
local inv_cache_lib = require('inv_cache');
local char_profile_cache = require('char_profile_cache'); -- for the Current tab's equipped-items list
local item_stat_diff     = require('item_stat_diff');     -- stat-diff strip in the Current tab's equip picker

-- Self-contained gear-tab module — owns its own state, helpers, and draw.
-- init() is deferred until after the Copy-From state + open_copy_from() are
-- defined below, so the callback can be wired into gear_tab.
local gear_tab = require('gear_tab');

-- Swap-logic editor (Phase C): Settings, Variables, swap-logic tree, etc.
local swap_logic_tab = require('swap_logic_tab');
swap_logic_tab.init({ autoequip = autoequip, autoutil = autoutil });

-- ============================================================
-- UI state
-- ============================================================
local ui_open    = nil;
local TABS       = { 'Current', 'Gear Sets', 'Swap Logic' };
local active_tab = 'Current';

-- Char selector dropdown state. The "edit target" is who autoequip is loading
-- / saving / picking for. Initial = primary; can flip to any headless bot
-- owned by the primary (fetched via 0x186 alliance_pc_list).
local selected_char = nil;
local selected_job  = nil;

-- ============================================================
-- Copy-XML modal state (task #125)
-- ============================================================
-- Cache of equip XML files that exist on the server, parsed from
-- list_configs('equip'). Shape: { ['CharName'] = { 'WAR', 'RDM', ... }, ... }
local copy_xml_index = {};
local copy_xml_index_refreshed = false;
-- Modal staging
local copy_src_char         = '';
local copy_src_job          = '';
local copy_dst_job          = '';    -- destination job (defaults to the loaded job; user-selectable)
local copy_confirm_active   = false;  -- once true, the Copy button does an overwrite-confirm step

-- Parse a filename like 'Cornelia_RDM' → ('Cornelia', 'RDM'). Returns nil on
-- bad shape (no underscore, or unknown job abbrev). Splits on the LAST '_'
-- so char names containing underscores still parse correctly.
local function parse_equip_filename(name)
    if not name or name == '' then return nil; end
    local us_idx = nil;
    for i = #name, 1, -1 do
        if name:sub(i, i) == '_' then us_idx = i; break; end
    end
    if not us_idx then return nil; end
    local char_part = name:sub(1, us_idx - 1);
    local job_part  = name:sub(us_idx + 1);
    if char_part == '' or job_part == '' then return nil; end
    -- Validate job abbrev. autoutil.jobs is 1-indexed list of abbrevs.
    local ok_job = false;
    for _, abbrev in ipairs(autoutil.jobs or {}) do
        if abbrev == job_part then ok_job = true; break; end
    end
    if not ok_job then return nil; end
    return char_part, job_part;
end

local function refresh_copy_xml_index()
    local http = require('http_client');
    local json = require('json');
    http.get('/configs/equip', function(code, body, _, err)
        if code == nil then
            autoutil.log('AutoEquip', string.format('refresh_copy_xml_index: %s', tostring(err)));
            copy_xml_index = {};
            copy_xml_index_refreshed = true;
            return;
        end
        if code ~= 200 then
            autoutil.log('AutoEquip', string.format('refresh_copy_xml_index: HTTP %s', tostring(code)));
            copy_xml_index = {};
            copy_xml_index_refreshed = true;
            return;
        end
        local ok, parsed = pcall(json.decode, json, body);
        local names = (ok and parsed and parsed.names) or {};
        local idx = {};
        for _, n in ipairs(names) do
            local c, j = parse_equip_filename(n);
            if c then
                idx[c] = idx[c] or {};
                table.insert(idx[c], j);
            end
        end
        for _, jobs in pairs(idx) do
            table.sort(jobs);
        end
        copy_xml_index = idx;
        copy_xml_index_refreshed = true;
    end);
end

-- (Subscribe set previously tracked here for inv push; removed when we
-- reverted to on-demand fetching.)

-- Called from gear_tab.lua's Copy-From button. Refreshes the source index,
-- clears the modal staging, then opens the popup whose body is defined
-- further down in this file (BeginPopup('##copy_xml_modal')).
local function open_copy_from()
    refresh_copy_xml_index();
    copy_src_char       = '';
    copy_src_job        = '';
    copy_dst_job        = selected_job or '';  -- default destination to the loaded job
    copy_confirm_active = false;
    autoutil.last_copy_xml_result = nil;
    imgui.OpenPopup('##copy_xml_modal');
end

gear_tab.init({
    autoequip      = autoequip,
    autoutil       = autoutil,
    inv_cache      = inv_cache_lib,
    open_copy_from = open_copy_from,
});

-- ============================================================
-- Event wiring
-- ============================================================
ashita.register_event('load', function()
    autoutil.tag = 'AutoEquip';
    ui_open = imgui.CreateVar(ImGuiVar_BOOLCPP);
    gear_tab.on_load();
    swap_logic_tab.on_load();
    autoutil.send_request_server_ident();
end);

-- One-shot kick to populate the char selector's data sources once the server
-- handshake has unlocked us. autoutil's check_for_server_ident sets unlocked=true
-- on 0x150 receive; we piggyback here so the chars/alliance fetches happen as
-- early as possible without spamming during the unauth window.
local _bootstrapped = false;
local function bootstrap_char_selector()
    if _bootstrapped or not autoutil.unlocked then return; end
    _bootstrapped = true;
    if not autoutil.char_names_final then autoutil.fetch_chars();        end
    autoutil.send_list_alliance_pcs();
    -- Equip config subscribe + initial inv_request moved to lazy-on-first-
    -- window-open. Both were dominating the login-time push for users who
    -- never opened autoequip; the inv pull in particular triggers a full
    -- inventory packet dump for the primary which can collide with heavy
    -- zone-in load (Dynamis etc.) and trip the inactivity watchdog. The
    -- fetch happens on first window-open instead — see render below.
end

ashita.register_event('unload', function()
    if ui_open ~= nil then
        imgui.DeleteVar(ui_open);
        ui_open = nil;
    end
    gear_tab.on_unload();
    swap_logic_tab.on_unload();
end);

ashita.register_event('incoming_packet', function(id, size, data)
    if id == 0x150 then
        autoutil.check_for_server_ident(id, size, data);
        return false;
    end
    if not autoutil.unlocked then return false; end
    -- Feed the shared inventory cache (0x020 / 0x01E). Cache claims the
    -- packet on a match; nothing else in this addon needs those IDs.
    if inv_cache_lib.on_incoming_packet(id, size, data) then return false; end
    if char_profile_cache.on_incoming_packet(id, size, data) then return false; end
    if id == 0x1B then
        -- GP_MYROOM_DANCER.job_lev[16] at PacketData+12 = raw byte 17; job IDs
        -- 1-16 at indices [1..15] then BLU.
        -- job_lev2[24] at PacketData+68 = raw byte 73; copies jobs.job[0..23],
        -- so job IDs 16-22 at byte 73+16..73+22.
        for i = 1, 15 do
            local lv = struct.unpack('b', data, 17 + i);
            autoequip.job_levels[i] = math.max(0, lv);
        end
        for i = 16, 22 do
            local lv = struct.unpack('B', data, 73 + i);
            autoequip.job_levels[i] = lv;
        end
        return false;
    end
    -- Config CRUD packet dispatchers (0x17b/0x17f/0x181/0x183) removed —
    -- the addon now talks to the server over loopback HTTP via
    -- libs/http_client.lua.
    if id == 0x186 then
        autoutil.check_for_alliance_pc_list(id, size, data);
    elseif id == 0x1A2 then
        autoutil.check_for_copy_xml_result(id, size, data);
    end
    -- 0x18E CHARS_LIST receive handler retired alongside the packet;
    -- char roster now flows through GET /chars (loopback HTTP) via
    -- autoutil.fetch_chars().
    return false;
end);

ashita.register_event('command', function(cmd, nType)
    local args = cmd:args();
    if args[1] ~= '/autoequip' then return false; end
    if not autoutil.unlocked then
        autoutil.log('AutoEquip', 'Not unlocked (waiting for server ident).');
        return true;
    end

    -- Delegate to the lib first (preserves any legacy /autoequip subcommands).
    if autoequip.handle_command and autoequip.handle_command(args) then
        return true;
    end

    if args[2] == 'show' or args[2] == nil then
        if ui_open ~= nil then
            imgui.SetVarValue(ui_open, not imgui.GetVarValue(ui_open));
        end
        return true;
    end
    if args[2] == 'reload' then
        gear_tab.reload_config();
        swap_logic_tab.on_xml_loaded();
        return true;
    end
    -- /autoequip gearlock - retained as a no-op informer since the
    -- visual lock is now server-driven via xi.player.onGameIn. To
    -- re-trigger after editing the XML, zone change (which re-fires
    -- onGameIn) or run /autoequip reload to invalidate the server-side
    -- XML cache, then zone.
    if args[2] == 'gearlock' then
        autoutil.log('AutoEquip', 'gearlock visual is applied server-side on login / zone-in. Edit the XML and zone to re-apply.');
        return true;
    end
    autoutil.log('AutoEquip', 'Usage: /autoequip [show|reload|gearlock]');
    return true;
end);

-- "Current" tab: the live equipped-items list for the selected char plus a
-- per-slot equip picker (add / remove / change). Sourced from char_profile_cache
-- (server 0x1A8, works for headless) + inv_cache for candidate items. Moved here
-- from automog's Status tab so all equipment editing lives in one place.
local CURRENT_SLOT_NAMES = {
    'Main',  'Sub',   'Range', 'Ammo',
    'Head',  'Body',  'Hands', 'Legs',  'Feet',
    'Neck',  'Waist', 'Ear1',  'Ear2',
    'Ring1', 'Ring2', 'Back',
};
local cur_focused_slot = nil;  -- 1..16, the slot whose picker is open
local cur_pending_pick = nil;  -- item id staged in the confirm panel

local function cur_calc_text_w(text)
    local a = imgui.CalcTextSize(text);
    if type(a) == 'number' then return a; end
    if type(a) == 'table'  then return a.x or a[1] or 0; end
    return #text * 7;
end

local function cur_item_name(itemId)
    if itemId == nil or itemId == 0 then return '--'; end
    local res = AshitaCore:GetResourceManager():GetItemById(itemId);
    return (res and res.Name and tostring(res.Name[0]):gsub('%z', '')) or ('item#' .. itemId);
end

-- 0x171 EQUIP: item_id 0 = unequip. slot_id is 0-based.
local function cur_send_equip(char_name, item_id, slot_id)
    local bytes = {};
    for i = 1, 24 do bytes[i] = 0; end
    bytes[1] = 0x71; bytes[2] = 0x01;                 -- opcode 0x171 LE
    local nm = (char_name or ''):sub(1, 15);
    for i = 1, #nm do bytes[4 + i] = nm:byte(i); end  -- name at byte 5..
    bytes[21] = item_id % 256;                        -- ItemId at byte 21 (after 4 hdr + 16 name)
    bytes[22] = math.floor(item_id / 256) % 256;
    bytes[23] = slot_id;
    AddOutgoingPacket(0x171, bytes);
end

-- Right-column picker for cur_focused_slot: current item, then either the
-- confirm panel (item detail + stat diff + Confirm/Cancel) or the inventory
-- candidate list. Adapted from automog's draw_status_eq_picker.
local function cur_draw_picker(col_w, prof, char)
    local slot_idx = cur_focused_slot;
    if slot_idx == nil then return; end
    local slot_id = slot_idx - 1;

    autoutil.section_head(CURRENT_SLOT_NAMES[slot_idx] or 'Slot');
    imgui.Dummy(0, 4);
    local cur_id = (prof.equipment or {})[slot_idx] or 0;
    imgui.TextDisabled('Current: ' .. ((cur_id > 0) and cur_item_name(cur_id) or '--'));
    imgui.SameLine();
    imgui.SetCursorPosX(math.max(imgui.GetCursorPosX(), col_w - 60));
    if imgui.Button('Close##cureqpk_close', 50, 0) then
        cur_focused_slot = nil; cur_pending_pick = nil; return;
    end
    imgui.Dummy(0, 6);

    -- Confirm panel: preview the staged item before committing the swap.
    if cur_pending_pick ~= nil then
        local pick_id = cur_pending_pick;
        local res     = AshitaCore:GetResourceManager():GetItemById(pick_id);
        local nm      = (res and res.Name and tostring(res.Name[0]):gsub('%z', '')) or ('item#' .. pick_id);
        local level   = (res and res.Level) or 0;
        local desc    = (res and res.Description and res.Description[0])
                        and tostring(res.Description[0]):gsub('%z', '') or '';
        imgui.SetCursorPosX(math.max(0, (col_w - cur_calc_text_w(nm)) / 2));
        imgui.TextColored(1.0, 1.0, 1.0, 1.0, nm);
        if level > 0 then
            local sub = 'Lv.' .. level;
            imgui.SetCursorPosX(math.max(0, (col_w - cur_calc_text_w(sub)) / 2));
            imgui.TextDisabled(sub);
        end
        imgui.Dummy(0, 4); imgui.Separator(); imgui.Dummy(0, 4);
        local cur_name = (cur_id > 0) and cur_item_name(cur_id) or '';
        imgui.Text('Current:  ' .. ((cur_id > 0) and cur_name or '--'));
        imgui.Text('Equip:    ' .. nm);
        if desc ~= '' then
            imgui.Dummy(0, 6); imgui.PushTextWrapPos(0); imgui.TextDisabled(desc); imgui.PopTextWrapPos();
        end
        item_stat_diff.render_stat_diff(cur_name, nm);
        imgui.Dummy(0, 8);
        local btn_w = 80;
        imgui.SetCursorPosX(math.max(0, (col_w - btn_w * 2 - 8) / 2));
        if imgui.Button('Confirm##cureqpk_confirm', btn_w, 0) then
            cur_send_equip(char, pick_id, slot_id);
            cur_focused_slot = nil; cur_pending_pick = nil;
        end
        imgui.SameLine(0, 8);
        if imgui.Button('Cancel##cureqpk_cancel', btn_w, 0) then cur_pending_pick = nil; end
        return;
    end

    -- Candidate list: inventory + wardrobes whose Slots mask covers this slot.
    -- Items the current main job/level can't equip are shown dimmed and are not
    -- clickable (the server would silently reject the 0x171 anyway).
    local res_mgr   = AshitaCore:GetResourceManager();
    local slot_mask = bit.lshift(1, slot_id);
    local job_mask  = bit.lshift(1, prof.mj or 0);
    local my_level  = prof.ml or 0;
    local candidates, seen = {}, {};
    for _, bag_id in ipairs({ 0, 8, 10, 11, 12, 13, 14, 15, 16 }) do
        local bag = inv_cache_lib.get_bag(char, bag_id);
        for _, entry in pairs(bag or {}) do
            if entry and entry.id and entry.id ~= 0 and not seen[entry.id] then
                local res = res_mgr:GetItemById(entry.id);
                if res and res.Slots and bit.band(res.Slots, slot_mask) ~= 0 then
                    seen[entry.id] = true;
                    local nm  = (res.Name and tostring(res.Name[0]):gsub('%z', '')) or ('item#' .. entry.id);
                    local lvl = (res.Level or 0);
                    local job_ok = (res.Jobs == nil) or (bit.band(res.Jobs, job_mask) ~= 0);
                    local equippable = job_ok and (my_level >= lvl);
                    table.insert(candidates, { id = entry.id, name = nm, level = lvl, equippable = equippable });
                end
            end
        end
    end
    if #candidates == 0 then
        imgui.TextDisabled('No equippable items found in inventory or wardrobes.');
        return;
    end
    -- Sort equippable-first, then by level (desc), then name.
    table.sort(candidates, function(a, b)
        if a.equippable ~= b.equippable then return a.equippable; end
        if a.level ~= b.level then return a.level > b.level; end
        return a.name < b.name;
    end);
    imgui.BeginChild('##cur_eq_picker_list', 0, 0, false);
    for _, c in ipairs(candidates) do
        local label = (c.level > 0) and string.format('Lv.%-3d  %s', c.level, c.name)
                                     or  ('       ' .. c.name);
        if c.equippable then
            if imgui.Selectable(label .. '##cureqpk_' .. c.id) then
                cur_pending_pick = c.id;
            end
        else
            -- Dimmed + non-clickable: current job/level can't equip this. Plain
            -- Text (not a Selectable) so it can't be picked. Ashita v3's ImGui has
            -- no ImGuiSelectableFlags_Disabled, so a disabled Selectable isn't an
            -- option here.
            imgui.TextColored(0.45, 0.45, 0.45, 1.0, label);
        end
    end
    imgui.EndChild();
end

local function render_current_tab()
    local char = selected_char;
    if char == nil or char == '' then
        imgui.Text('Currently Equipped');
        imgui.Separator();
        imgui.TextDisabled('(no character selected)');
        return;
    end
    char_profile_cache.ensure(char);           -- profile (equipped items)
    inv_cache_lib.ensure_inventory(char);       -- inventory (picker candidates)
    imgui.Text('Currently Equipped: ' .. char);
    imgui.Separator();
    imgui.Dummy(0, 4);
    local prof = char_profile_cache.get(char);
    if prof == nil then
        imgui.TextDisabled('(loading...)');
        return;
    end

    local col_w = 260;
    -- Left column: equipment list. X unequips; clicking a slot opens the picker.
    imgui.BeginChild('##cur_left', col_w, 0, false);
    -- Small header so the Main row isn't jammed against the top edge. Job/level
    -- is readily available from the profile, so show it rather than dead space.
    local mj_ab = (autoutil.jobs and autoutil.jobs[prof.mj]) or '--';
    local jl    = string.format('Lv.%d %s', prof.ml or 0, mj_ab);
    if prof.sj and prof.sj > 0 and autoutil.jobs and autoutil.jobs[prof.sj] then
        jl = jl .. string.format(' / Lv.%d %s', prof.sl or 0, autoutil.jobs[prof.sj]);
    end
    imgui.Dummy(0, 4);
    imgui.TextDisabled(jl);
    imgui.Dummy(0, 6);
    for i = 1, 16 do
        local itemId = (prof.equipment or {})[i] or 0;
        local row    = string.format('%-6s %s', CURRENT_SLOT_NAMES[i] .. ':',
                                      (itemId > 0) and cur_item_name(itemId) or '--');
        local sel    = (cur_focused_slot == i);
        if itemId > 0 then
            if imgui.Button('x##cureqrm_' .. i, 22, 0) then
                cur_send_equip(char, 0, i - 1);     -- unequip
                cur_focused_slot = nil; cur_pending_pick = nil;
            end
        else
            imgui.Dummy(22, 0);
        end
        imgui.SameLine(0, 6);
        if imgui.Selectable(row .. '##cureqrow_' .. i, sel) then
            cur_pending_pick = nil;
            if sel then cur_focused_slot = nil; else cur_focused_slot = i; end
        end
    end
    imgui.EndChild();

    imgui.SameLine(0, 30);

    -- Right column: per-slot picker when a slot is focused.
    imgui.BeginChild('##cur_right', col_w, 0, false);
    if cur_focused_slot ~= nil then
        cur_draw_picker(col_w, prof, char);
    else
        imgui.TextDisabled('Click a slot to add / change gear.');
    end
    imgui.EndChild();
end

local first_open_load = true;
local was_ui_open = false;
ashita.register_event('render', function()
    -- Advance pending HTTP coroutines once per frame. http_client doesn't
    -- auto-register a 'render' hook because multiple register_event for
    -- the same event collide in Ashita v3 - we drive its scheduler from
    -- this addon's existing render instead.
    require('http_client').tick();
    bootstrap_char_selector();

    if ui_open == nil or not imgui.GetVarValue(ui_open) then
        was_ui_open = false;
        return;
    end

    -- First-window-open: fetch the active char's gear XML + inventory
    -- snapshot. On-demand pattern — server-side configcache serves the
    -- XML from memory; rate-limited chunk drain keeps the wire honest.
    if first_open_load then
        local party = AshitaCore:GetDataManager():GetParty();
        local name  = party and party:GetMemberName(0) or '';
        local mjob  = party and party:GetMemberMainJob(0) or 0;
        if name ~= '' and mjob > 0 then
            gear_tab.reload_config();
            swap_logic_tab.on_xml_loaded();
            inv_cache_lib.send_inv_request(name);
            first_open_load = false;
        end
    end

    -- Rising-edge: the window just opened (closed-to-open this frame). Re-pull
    -- the gear XML so the panel shows current data without the user having to
    -- click Reload Sets. Gate on (unlocked AND party data settled) so we don't
    -- trip the "no char/job data yet" warning if the user types /autoequip
    -- the instant they're zoned in.
    if not was_ui_open then
        was_ui_open = true;
        local party = AshitaCore:GetDataManager():GetParty();
        local name  = party and party:GetMemberName(0) or '';
        local mjob  = party and party:GetMemberMainJob(0) or 0;
        if autoutil.unlocked and name ~= '' and mjob > 0 then
            gear_tab.reload_config();
            swap_logic_tab.on_xml_loaded();
        end
    end
    -- Seed size uniform across tabs (580×580). Gear is the reference
    -- layout — two 260-wide cols + 30 gap + ~26 chrome = 576 rounded to
    -- 580. Swap Logic used to seed larger (640×800) to give the XML
    -- editor room, but users can drag-resize whenever they need more
    -- and a stable default size avoids the window jumping on tab switch.
    local seed_w = 580;
    local seed_h = 580;
    imgui.SetNextWindowSize(seed_w, seed_h, ImGuiSetCond_FirstUseEver);
    -- Re-fit on tab change (Gear / Swap Logic differ in horizontal density).
    autoutil.resize_on_tab_change('AutoEquip', active_tab, seed_w, seed_h);
    autoutil.push_solid_window_bg();
    if not imgui.Begin('AutoEquip', ui_open) then
        imgui.End();
        autoutil.pop_solid_window_bg();
        return;
    end

    -- Char selector dropdown — far left of the tab row. The selected char's
    -- XML is loaded for editing in both Gear and Swap Logic tabs. Source:
    -- primary (slot 0) + every PC the server lists in our alliance.
    do
        local primary_name = autoequip.get_local_char();
        if selected_char == nil then
            selected_char = primary_name;
            selected_job  = autoequip.get_local_job();
            autoequip.set_edit_target(selected_char, selected_job);
        end

        local label = (selected_char ~= nil and selected_char ~= '')
                    and (selected_char .. ' (' .. (selected_job or '?') .. ')')
                    or  'Pick char';
        if imgui.Button(label .. '##char_pick', 200, 0) then
            -- Refresh the roster every time the menu opens.
            autoutil.send_list_alliance_pcs();
            imgui.OpenPopup('##char_pick_popup');
        end
        if imgui.BeginPopup('##char_pick_popup') then
            -- Always offer the primary as a row even if alliance_pcs hasn't
            -- arrived yet (or we're solo).
            local function pick(name)
                if name == primary_name then
                    selected_job = autoequip.get_local_job();
                else
                    local mj = autoutil.char_jobs and autoutil.char_jobs[name] or 0;
                    selected_job = autoutil.jobs[mj] or '?';
                end
                selected_char = name;
                autoequip.set_edit_target(selected_char, selected_job);
                gear_tab.reload_config();
                swap_logic_tab.on_xml_loaded();
                -- Trigger a server-side inventory snapshot for the picked char
                -- so the gear picker's "in bag" markers reflect that target.
                -- Debounced inside inv_cache, safe to fire on every click.
                inv_cache_lib.send_inv_request(name);
                imgui.CloseCurrentPopup();
            end

            if imgui.Selectable(primary_name .. ' (you)') then pick(primary_name) end
            imgui.Separator();
            local roster = autoutil.alliance_pcs or {};
            local listed = 0;
            for _, m in ipairs(roster) do
                if m.name ~= primary_name then
                    local mj = autoutil.char_jobs and autoutil.char_jobs[m.name] or 0;
                    local job_label = autoutil.jobs[mj] or '?';
                    if imgui.Selectable(m.name .. '  (' .. job_label .. ')') then
                        pick(m.name);
                    end
                    listed = listed + 1;
                end
            end
            if listed == 0 then imgui.TextDisabled('(no bots in alliance)') end
            imgui.EndPopup();
        end
        -- Char selector sits on its own row above the tabs — matches automog's
        -- updated layout. Tabs ('Gear Sets' | 'Swap Logic') don't share the row
        -- since other affordances (Copy From, Reload buttons) compete for width.
    end

    -- task #125: Copy-From button lives next to Reload Sets / Reload Addons in
    -- gear_tab.lua; it invokes open_copy_from() below, which opens the popup
    -- whose body is defined further down in this file.

    if imgui.BeginPopup('##copy_xml_modal') then
        imgui.Text('Copy XML from...');
        imgui.Separator();
        imgui.Dummy(0, 4);

        if not copy_xml_index_refreshed then
            imgui.TextDisabled('(loading...)');
        else
            -- Char dropdown — every char with at least one saved equip XML.
            local char_label = (copy_src_char ~= '' and copy_src_char) or 'Pick char';
            imgui.Text('Char: ');
            imgui.SameLine();
            if imgui.Button(char_label .. '##copy_src_char', 180, 0) then
                imgui.OpenPopup('##copy_src_char_popup');
            end
            if imgui.BeginPopup('##copy_src_char_popup') then
                local sorted = {};
                for c, _ in pairs(copy_xml_index) do table.insert(sorted, c); end
                table.sort(sorted);
                if #sorted == 0 then
                    imgui.TextDisabled('(no equip XMLs on server)');
                end
                for _, c in ipairs(sorted) do
                    if imgui.Selectable(c) then
                        copy_src_char = c;
                        copy_src_job  = '';
                    end
                end
                imgui.EndPopup();
            end

            -- Job dropdown — only jobs that have an XML for the picked char.
            local job_label = (copy_src_job ~= '' and copy_src_job) or 'Pick job';
            imgui.Text('Job:  ');
            imgui.SameLine();
            local job_disabled = copy_src_char == '';
            if job_disabled then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
            if imgui.Button(job_label .. '##copy_src_job', 180, 0) and not job_disabled then
                imgui.OpenPopup('##copy_src_job_popup');
            end
            if job_disabled then imgui.PopStyleVar(); end
            if imgui.BeginPopup('##copy_src_job_popup') then
                for _, j in ipairs(copy_xml_index[copy_src_char] or {}) do
                    if imgui.Selectable(j) then
                        copy_src_job = j;
                    end
                end
                imgui.EndPopup();
            end

            imgui.Dummy(0, 8);
            -- Destination: always the loaded char, but the JOB is selectable so
            -- you can copy one job's set into a different job of the same char.
            local dst_char = selected_char or '';
            imgui.TextDisabled(string.format('Target char: %s', dst_char ~= '' and dst_char or '?'));
            local dst_job_label = (copy_dst_job ~= '' and copy_dst_job) or 'Pick job';
            imgui.Text('To job:');
            imgui.SameLine();
            if imgui.Button(dst_job_label .. '##copy_dst_job', 180, 0) then
                imgui.OpenPopup('##copy_dst_job_popup');
            end
            if imgui.BeginPopup('##copy_dst_job_popup') then
                -- Every job (autoutil.jobs, 1-indexed abbreviations) so you can
                -- target a job that has no XML yet.
                for i = 1, #(autoutil.jobs or {}) do
                    local j = autoutil.jobs[i];
                    if j and j ~= '' then
                        if imgui.Selectable(j .. '##cdj_' .. j) then copy_dst_job = j; end
                    end
                end
                imgui.EndPopup();
            end

            -- Detect overwrite: does the target's filename already exist?
            local dst_job  = copy_dst_job or '';
            local target_exists = false;
            if copy_xml_index[dst_char] then
                for _, j in ipairs(copy_xml_index[dst_char]) do
                    if j == dst_job then target_exists = true; break; end
                end
            end

            if target_exists and not copy_confirm_active then
                imgui.TextColored(0.95, 0.75, 0.25, 1.0,
                    '[!] Existing XML will be overwritten.');
            end
            if copy_confirm_active then
                imgui.TextColored(0.95, 0.6, 0.4, 1.0,
                    'Click Copy again to confirm overwrite.');
            end

            imgui.Dummy(0, 6);

            local src_ok    = copy_src_char ~= '' and copy_src_job ~= '';
            local same_pair = src_ok and (copy_src_char == dst_char and copy_src_job == dst_job);
            local target_ok = dst_char ~= '' and dst_job ~= '';
            local can_copy  = src_ok and target_ok and not same_pair;

            if same_pair then
                imgui.TextDisabled('(source and target are the same)');
            end

            if not can_copy then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35); end
            if imgui.Button('Copy##copy_xml_go', 80, 0) and can_copy then
                if target_exists and not copy_confirm_active then
                    copy_confirm_active = true;
                else
                    local src_name = string.format('%s_%s', copy_src_char, copy_src_job);
                    local dst_name = string.format('%s_%s', dst_char,        dst_job);
                    autoutil.send_copy_xml(src_name, dst_name);
                    imgui.CloseCurrentPopup();
                end
            end
            if not can_copy then imgui.PopStyleVar(); end
            imgui.SameLine();
            if imgui.Button('Cancel##copy_xml_cancel', 80, 0) then
                imgui.CloseCurrentPopup();
            end
        end

        imgui.EndPopup();
    end

    -- Surface the latest copy result + reload the editor on success.
    if autoutil.last_copy_xml_result ~= nil then
        local r = autoutil.last_copy_xml_result;
        if r.status == 0 then
            autoutil.log('AutoEquip', string.format('Copied XML to %s', r.dest_name));
            -- Reload the editor's view from the freshly-written file.
            autoequip.load(selected_char, selected_job, function(ok)
                if ok then
                    gear_tab.reload_config();
                    swap_logic_tab.on_xml_loaded();
                end
            end);
        else
            local msg = ({ [1] = 'source not found', [2] = 'invalid name', [3] = 'filesystem error' })[r.status] or 'unknown error';
            autoutil.log('AutoEquip', 'Copy failed: ' .. msg);
        end
        autoutil.last_copy_xml_result = nil;
    end

    for i, tab in ipairs(TABS) do
        if i > 1 then imgui.SameLine(); end
        local is_active = (tab == active_tab);
        if is_active then imgui.PushStyleColor(ImGuiCol_Button, 0.26, 0.59, 0.98, 1.0); end
        if imgui.Button(tab) then
            active_tab = tab;
        end
        if is_active then imgui.PopStyleColor(); end
    end
    imgui.Separator();
    imgui.Dummy(0, 3);

    if active_tab == 'Current' then
        render_current_tab();
    elseif active_tab == 'Gear Sets' then
        gear_tab.draw();
    elseif active_tab == 'Swap Logic' then
        swap_logic_tab.draw();
    end

    imgui.End();
    autoutil.pop_solid_window_bg();
end);
