_addon.author  = 'Nate';
_addon.name    = 'AutoLot';
_addon.version = '1.0';

require 'common';
require 'imguidef';

local autoutil = require('autoutil');

-- Tab modules live in this addon's folder.
local groups_tab = require('groups_tab');
local pool_tab   = require('pool_tab');     -- live treasure pool slots
local recent_tab = require('recent_tab');   -- last 100 unique items seen

-- Shared pool-watcher state lives in pool_tab and is consumed by both Live
-- Pool and Recent. Recent reads pool_tab's cache; pool_tab maintains it from
-- a per-frame scan of GetInventory():GetTreasureItem(0..9).
groups_tab.init({ autoutil = autoutil });
pool_tab.init({ autoutil = autoutil, groups_tab = groups_tab });
recent_tab.init({ autoutil = autoutil, groups_tab = groups_tab, pool_tab = pool_tab });

-- ============================================================
-- UI state — button-row tab pattern matching automog / autoequip.
-- ============================================================
local ui_open    = nil;
local TABS       = { 'Pool & History', 'Groups' };
local active_tab = 'Pool & History';

-- ============================================================
-- Event wiring
-- ============================================================
ashita.register_event('load', function()
    autoutil.tag = 'AutoLot';
    ui_open = imgui.CreateVar(ImGuiVar_BOOLCPP);
    groups_tab.on_load();
    pool_tab.on_load();
    recent_tab.on_load();
    autoutil.send_request_server_ident();
end);

ashita.register_event('unload', function()
    if ui_open ~= nil then
        imgui.DeleteVar(ui_open);
        ui_open = nil;
    end
    groups_tab.on_unload();
    pool_tab.on_unload();
    recent_tab.on_unload();
end);

ashita.register_event('incoming_packet', function(id, size, data)
    if id == 0x150 then
        autoutil.check_for_server_ident(id, size, data);
        -- Config subscribe deferred to first window open — see render below.
        -- Was: subscribe-at-unlock pushed lot configs at login even for
        -- users who never opened autolot.
        return false;
    end
    if not autoutil.unlocked then return false; end
    -- Config CRUD packet dispatchers (0x17b/0x17f/0x181/0x183) removed.
    -- The addon now reads & writes configs over loopback HTTP via
    -- libs/http_client.lua; the server-side packet handlers are gone.
    return false;
end);

ashita.register_event('command', function(cmd, nType)
    local args = cmd:args();
    if args[1] ~= '/autolot' then return false; end
    if not autoutil.unlocked then
        autoutil.log('AutoLot', 'Not unlocked (waiting for server ident).');
        return true;
    end

    if args[2] == 'show' or args[2] == nil then
        if ui_open ~= nil then
            imgui.SetVarValue(ui_open, not imgui.GetVarValue(ui_open));
        end
        return true;
    end
    if args[2] == 'reload' then
        groups_tab.reload();
        return true;
    end
    autoutil.log('AutoLot', 'Usage: /autolot [show|reload]');
    return true;
end);

local first_render = true;
ashita.register_event('render', function()
    -- Advance pending HTTP coroutines once per frame. http_client doesn't
    -- auto-register a 'render' hook because multiple register_event for
    -- the same event collide in Ashita v3 - we drive its scheduler from
    -- this addon's existing render instead.
    require('http_client').tick();
    if first_render then
        local party = AshitaCore:GetDataManager():GetParty();
        if party and party:GetMemberName(0) and party:GetMemberName(0) ~= '' then
            groups_tab.reload();
            first_render = false;
        end
    end

    if ui_open == nil or not imgui.GetVarValue(ui_open) then return; end

    -- Pool & History splits the same width as Groups into two half-columns.
    local tw = 640;
    imgui.SetNextWindowSize(tw, 520, ImGuiSetCond_FirstUseEver);
    -- Re-fit on tab change (the two-column Pool & History vs the narrow Groups
    -- tab). Without this the window stays sized to the widest tab ever opened.
    autoutil.resize_on_tab_change('AutoLot', active_tab, tw, 520);
    autoutil.push_solid_window_bg();
    if not imgui.Begin('AutoLot', ui_open) then
        imgui.End();
        autoutil.pop_solid_window_bg();
        return;
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

    -- pool_tab.tick() must run regardless of which tab is active so the cache
    -- continues to accumulate while the user is in Groups or Drop History.
    pool_tab.tick();

    if active_tab == 'Pool & History' then
        -- Two columns: live Treasure Pool on the left, Drop History on the
        -- right. Both panes are narrow, so they share one wide tab. Each pane's
        -- own header + scrolling list live inside its column child.
        local avail = imgui.GetContentRegionAvailWidth();
        local colw  = math.floor((avail - 8) / 2);
        imgui.BeginChild('##pool_col', colw, 0, false);
        pool_tab.draw();
        imgui.EndChild();
        imgui.SameLine(0, 8);
        imgui.BeginChild('##hist_col', colw, 0, false);
        recent_tab.draw();
        imgui.EndChild();
    elseif active_tab == 'Groups' then
        groups_tab.draw();
    end

    imgui.End();
    autoutil.pop_solid_window_bg();
end);
