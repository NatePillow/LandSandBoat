-- AutoMog NM Hunter tab.
--
-- Server-side query against mob_spawn_points filtered by mobType &
-- MOBTYPE_NOTORIOUS. The lo/hi inputs are RELATIVE level offsets from the
-- selected char's level, so the mental model is "what NMs can I hunt?" rather
-- than an absolute range. The server clamps the absolute bounds to [1,99].
--
-- (Extracted from the former monolithic automog.lua when the tabs were split
-- into sibling *_tab.lua files.)

local M = {}

local autoutil           = require('autoutil');
local http_client        = require('http_client');
local json               = require('json');
local char_profile_cache = require('char_profile_cache');
local state              = require('automog_state');
local C                  = require('automog_common');

-- Per-tab UI + query state (was 16 file-scope nm_* locals in the monolith,
-- bundled into one table). Field names have the old "nm_" prefix dropped.
local nm = {
    lo_var       = nil,  -- created on first draw
    hi_var       = nil,
    filter_var   = nil,
    lo_last      = '-5',
    hi_last      = '10',
    filter_last  = '',
    lo           = -5,
    hi           = 10,
    filter       = '',
    results      = nil,
    loading      = false,
    last_query   = nil,
    inflight_tok = 0,
    -- Per-mobid expand state + drops cache for the expandable inline rows.
    -- expanded[mobid] = true / nil. drops[mobid] = { {itemId, rate}, ... } once
    -- /nms/<id>/drops responds; nil while in-flight or never-fetched.
    -- drops_loading[mobid] = true while fetch is in flight (prevents duplicate
    -- requests on rapid re-clicks). Cleared on tab leave to bound memory.
    expanded      = {},
    drops         = {},
    drops_loading = {},
};

-- ============================================================
-- NM Hunter tab — server-side query against mob_spawn_points
-- filtered by mobType & MOBTYPE_NOTORIOUS. The lo/hi inputs are
-- RELATIVE level offsets from the selected char's level so the
-- mental model is "what NMs can I hunt?" rather than "absolute
-- level range." Server clamps the absolute bounds to [1,99].
-- ============================================================

local function nm_fetch()
    -- Need the selected char's level to translate the relative offsets to
    -- an absolute range. Falls back to the profile cache (Status tab fetches
    -- the same data) and ensures the cache so opening NM Hunter first works.
    if state.selected_char == nil or state.selected_char == '' then return; end
    char_profile_cache.ensure(state.selected_char);
    local prof = char_profile_cache.get(state.selected_char);
    if prof == nil then return; end  -- wait for profile load; we'll re-poll next draw

    local level    = prof.ml or 1;
    local abs_lo   = math.max(1,  level + nm.lo);
    local abs_hi   = math.min(99, level + nm.hi);
    local qkey     = string.format('%d:%d:%d', level, abs_lo, abs_hi);
    if qkey == nm.last_query then return; end  -- same as last fetch
    if nm.loading then return; end             -- in-flight already

    nm.loading    = true;
    nm.last_query = qkey;
    nm.inflight_tok = nm.inflight_tok + 1;
    local tok = nm.inflight_tok;
    -- limit=500 (server max): the default 200, ordered by zone, truncated
    -- high-zone in-band NMs (e.g. Serket in Kuftal). See the server ORDER BY fix.
    local path = string.format('/nms?lo=%d&hi=%d&limit=500', abs_lo, abs_hi);
    http_client.get(path, function(code, body, _, err)
        if tok ~= nm.inflight_tok then return; end  -- stale response, ignore
        nm.loading = false;
        if code ~= 200 or type(body) ~= 'string' or body == '' then
            nm.results = {};
            return;
        end
        local ok, parsed = pcall(json.decode, json, body);
        if not ok or type(parsed) ~= 'table' then
            nm.results = {};
            return;
        end
        nm.results = parsed;
    end);
end

-- Force a refetch (clears the dedup key, kicks fetch on next draw).
local function nm_invalidate()
    nm.last_query = nil;
end

local function draw_nm_hunter_tab()
    -- Lazy-init the ImGuiVars on first draw. Doing this at file load risks
    -- racing the addon's bootstrap ordering (CreateVar is only valid once
    -- imgui is fully wired up), and it's free to defer.
    if nm.lo_var == nil then
        nm.lo_var     = imgui.CreateVar(ImGuiVar_CDSTRING, 8);
        nm.hi_var     = imgui.CreateVar(ImGuiVar_CDSTRING, 8);
        nm.filter_var = imgui.CreateVar(ImGuiVar_CDSTRING, 64);
        imgui.SetVarValue(nm.lo_var,     nm.lo_last);
        imgui.SetVarValue(nm.hi_var,     nm.hi_last);
        imgui.SetVarValue(nm.filter_var, nm.filter_last);
    end

    local prof = char_profile_cache.get(state.selected_char);
    local level = prof and prof.ml or nil;

    -- Header row: Min / Max relative-level inputs + Refresh button + filter.
    -- Mirrors the AI Settings "label-then-control" pattern at fixed widths
    -- so first-line-baseline alignment is predictable.
    autoutil.section_head('NMs within levels');
    imgui.Dummy(0, 4);

    local INPUT_W = 60;
    if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end
    imgui.Text('Min');
    imgui.SameLine(0, 6);
    imgui.PushItemWidth(INPUT_W);
    imgui.InputText('##nm.lo', nm.lo_var, 4);
    imgui.PopItemWidth();

    imgui.SameLine(0, 14);
    if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end
    imgui.Text('Max');
    imgui.SameLine(0, 6);
    imgui.PushItemWidth(INPUT_W);
    imgui.InputText('##nm.hi', nm.hi_var, 4);
    imgui.PopItemWidth();

    if level ~= nil then
        local abs_lo = math.max(1,  level + nm.lo);
        local abs_hi = math.min(99, level + nm.hi);
        imgui.SameLine(0, 14);
        if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end
        imgui.TextDisabled(string.format('(your Lv.%d -> Lv.%d-%d)', level, abs_lo, abs_hi));
    end

    imgui.Dummy(0, 4);

    -- Free-text name filter (case-insensitive substring). Pure UI filter —
    -- typed locally against the result set, doesn't refire a fetch.
    if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end
    imgui.Text('Filter');
    imgui.SameLine(0, 6);
    imgui.PushItemWidth(220);
    imgui.InputText('##nm.filter', nm.filter_var, 64);
    imgui.PopItemWidth();

    -- Read inputs back from the vars and parse. tonumber returns nil on
    -- bad input; we keep the last-known good value in that case so a
    -- mid-edit "-" doesn't flap zero results.
    local lo_str = imgui.GetVarValue(nm.lo_var)     or '';
    local hi_str = imgui.GetVarValue(nm.hi_var)     or '';
    nm.filter    = imgui.GetVarValue(nm.filter_var) or '';

    if lo_str ~= nm.lo_last then
        nm.lo_last = lo_str;
        local n = tonumber(lo_str);
        if n then
            n = math.max(-99, math.min(99, math.floor(n)));
            nm.lo = n;
            if nm.lo > nm.hi then nm.hi = nm.lo; imgui.SetVarValue(nm.hi_var, tostring(nm.hi)); end
            nm_invalidate();
        end
    end
    if hi_str ~= nm.hi_last then
        nm.hi_last = hi_str;
        local n = tonumber(hi_str);
        if n then
            n = math.max(-99, math.min(99, math.floor(n)));
            nm.hi = n;
            if nm.hi < nm.lo then nm.lo = nm.hi; imgui.SetVarValue(nm.lo_var, tostring(nm.lo)); end
            nm_invalidate();
        end
    end

    imgui.Dummy(0, 4);
    imgui.Separator();
    imgui.Dummy(0, 4);

    -- Kick / re-kick the fetch each draw — nm_fetch dedups via nm.last_query.
    nm_fetch();

    if state.selected_char == nil or state.selected_char == '' then
        imgui.TextDisabled('Select a character at the top of the window.');
        return;
    end
    if prof == nil then
        imgui.TextDisabled('Loading character profile...');
        return;
    end
    if nm.loading and nm.results == nil then
        imgui.TextDisabled('Loading NMs...');
        return;
    end
    if nm.results == nil then
        imgui.TextDisabled('No data yet.');
        return;
    end

    -- Filter + dedupe (one row per NM name) + sort by level. The server
    -- returns one row per spawn point, so a single NM that lives in two
    -- zones comes back twice; dedupe by name so each NM gets a single
    -- entry. When dedup'd rows differ in level/zone we keep the lowest
    -- level (the "starter" tier) which is the more useful target for
    -- hunters scanning the table.
    local needle = (nm.filter or ''):lower();
    local NM_SERVER_LIMIT = 200;
    if #nm.results >= NM_SERVER_LIMIT then
        imgui.TextDisabled(string.format('Showing first %d NMs - narrow Min/Max or use Filter to see more.', NM_SERVER_LIMIT));
        imgui.Dummy(0, 4);
    end

    local seen, rows = {}, {};
    for _, e in ipairs(nm.results) do
        local match = needle == '' or ((e.name or ''):lower():find(needle, 1, true) ~= nil);
        if match then
            local key = e.name or '';
            if seen[key] == nil then
                seen[key] = #rows + 1;
                table.insert(rows, e);
            elseif (e.lo or 999) < (rows[seen[key]].lo or 999) then
                rows[seen[key]] = e;
            end
        end
    end
    table.sort(rows, function(a, b)
        if (a.lo or 0) ~= (b.lo or 0) then return (a.lo or 0) < (b.lo or 0); end
        return (a.name or '') < (b.name or '');
    end);

    -- Three columns: Level | Name | Zone. Header row labels each column;
    -- Separator below acts as the table rule. SameLine X is child-relative
    -- (this all renders inside the BeginChild below), so the column
    -- offsets line up across rows.
    local LVL_X  = 0;
    local NAME_X = 80;
    local ZONE_X = 260;

    imgui.BeginChild('##nm_list', 0, 0, false);
    imgui.TextDisabled('Level');
    imgui.SameLine(NAME_X);
    imgui.TextDisabled('Name');
    imgui.SameLine(ZONE_X);
    imgui.TextDisabled('Zone');
    imgui.Separator();

    for _, e in ipairs(rows) do
        local lvl;
        if e.lo == e.hi then lvl = string.format('Lv.%d', e.lo);
        else                 lvl = string.format('Lv.%d-%d', e.lo, e.hi); end
        local mobid = e.id;
        local prefix = nm.expanded[mobid] and 'v ' or '> ';
        -- Whole row is a Selectable so clicking anywhere toggles expand.
        -- TextDisabled / TextColored layered via SameLine after the
        -- Selectable's bounding box is committed — works because the
        -- Selectable's own label is hidden (## prefix) and its hit region
        -- spans the row from x=0 to right edge.
        local clicked = imgui.Selectable('##nmrow_' .. tostring(mobid));
        imgui.SameLine(LVL_X);
        imgui.TextDisabled(prefix .. lvl);
        imgui.SameLine(NAME_X);
        imgui.Text(tostring(e.name or '?'));
        imgui.SameLine(ZONE_X);
        imgui.TextColored(0.7, 0.85, 1.0, 1.0, tostring(e.zone or '?'));

        if clicked then
            if nm.expanded[mobid] then
                nm.expanded[mobid] = nil;
            else
                nm.expanded[mobid] = true;
                -- Lazy-fetch drops on first expand. Cached forever (until
                -- tab leave / addon reload) since drop tables are static.
                if nm.drops[mobid] == nil and not nm.drops_loading[mobid] then
                    nm.drops_loading[mobid] = true;
                    http_client.get('/nms/' .. tostring(mobid) .. '/drops', function(code, body)
                        nm.drops_loading[mobid] = nil;
                        if code ~= 200 or type(body) ~= 'string' or body == '' then
                            nm.drops[mobid] = {};
                            return;
                        end
                        local ok, parsed = pcall(json.decode, json, body);
                        nm.drops[mobid] = (ok and type(parsed) == 'table') and parsed or {};
                    end);
                end
            end
        end

        -- Drops sub-list (when expanded). Loading placeholder if the
        -- fetch hasn't landed; "No drops." if the response was empty.
        if nm.expanded[mobid] then
            if nm.drops[mobid] == nil then
                imgui.SameLine(NAME_X);
                imgui.Dummy(0, 0);
                imgui.TextDisabled('   Loading drops...');
            elseif #nm.drops[mobid] == 0 then
                imgui.TextDisabled('   No drops.');
            else
                for _, d in ipairs(nm.drops[mobid]) do
                    -- Shared resolver handles the NUL-truncation + missing-item
                    -- fallback ('#<id>'); the inline version here used to splice
                    -- post-NUL buffer garbage onto names.
                    local item_name = C.item_name_for(d.itemId);
                    -- Server sends the effective drop chance in per-1000; /10 = percent.
                    local percent   = (d.rate or 0) / 10.0;
                    local pct_str;
                    if percent > 0 and percent < 0.1 then
                        pct_str = ' <0.1%';
                    else
                        pct_str = string.format('%5.1f%%', percent);
                    end
                    imgui.TextDisabled(string.format('   %s  %s', pct_str, item_name));
                end
            end
        end
    end
    if #rows == 0 then
        imgui.TextDisabled('No NMs match.');
    end
    imgui.EndChild();
end

M.draw = draw_nm_hunter_tab;

return M
