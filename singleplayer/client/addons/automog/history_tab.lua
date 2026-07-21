-- AutoMog History tab.
--
-- Scrollable feed of recent status lines (Box / Buy / Sell / Drop / Craft /
-- Scrolls / Transfer operations), filterable by character. Reads the shared
-- status history maintained in automog_state.
--
-- (Extracted from the former monolithic automog.lua when the tabs were split
-- into sibling *_tab.lua files.)

local M = {}

local autoutil = require('autoutil');
local state    = require('automog_state');

-- Char filter for the feed; defaults (on first draw) to the selected char.
local history_filter = nil;

local function draw_history_tab()
    -- Plant a minimum-width marker so the History tab renders at the same
    -- window width as the wider tabs (Inventory / AH / Craft). Without
    -- this, AlwaysAutoResize on the parent window shrinks to History's
    -- own (narrower) content, making the window jump narrower whenever
    -- the user switches to this tab. The other tabs naturally render
    -- at ~620px; a zero-height Dummy of that width pins the floor
    -- without leaving a visible gap.
    imgui.Dummy(620, 0);

    -- Filter dropdown: defaults to the automog selected char so the History
    -- view tracks the Inventory/Transfer/etc. lens by default.
    local party        = AshitaCore:GetDataManager():GetParty();
    local primary_name = (party and party:GetMemberName(0)) or '';
    if history_filter == nil then history_filter = state.selected_char or primary_name; end

    do
        local label = 'Filter: ' .. (history_filter or 'All chars');
        if imgui.Button(label .. '##hist_filter', 200, 0) then
            imgui.OpenPopup('##hist_filter_popup');
        end
        if imgui.BeginPopup('##hist_filter_popup') then
            local function pick(v) history_filter = v; imgui.CloseCurrentPopup(); end
            if imgui.Selectable('All chars') then pick(nil); end
            imgui.Separator();
            if primary_name ~= '' and imgui.Selectable(primary_name .. ' (you)') then pick(primary_name); end
            local roster = autoutil.alliance_pcs or {};
            for _, m in ipairs(roster) do
                if m.name ~= primary_name then
                    if imgui.Selectable(m.name) then pick(m.name); end
                end
            end
            imgui.EndPopup();
        end
    end
    imgui.Separator();
    imgui.Dummy(0, 4);

    if #state.status_history == 0 then
        imgui.TextDisabled('No status history yet.');
        return;
    end

    local shown = 0;
    imgui.BeginChild('##status_hist', 0, 0, false);
    for i = #state.status_history, 1, -1 do
        local entry = state.status_history[i];
        local pass  = (history_filter == nil)
                   or (entry.char ~= nil and entry.char == history_filter)
                   or (entry.char == nil and history_filter == primary_name);
        if pass then
            local char_tag = (entry.char and entry.char ~= primary_name) and (' <' .. entry.char .. '>') or '';
            imgui.TextDisabled(string.format('[%s] [%s]%s %s', entry.time, entry.source, char_tag, entry.text));
            imgui.Spacing();
            shown = shown + 1;
        end
    end
    if shown == 0 then imgui.TextDisabled('(no entries match the current filter)'); end
    imgui.EndChild();
end

M.draw = draw_history_tab;

return M
