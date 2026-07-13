-- Role AI tab: per-role item-usage policy.
--
-- Two-column layout to match other autobots tabs:
--   LEFT  — Tank, Melee, Heal, RDM
--   RIGHT — Nuke, BRD, SMN
--
-- Each section has HP / MP / Status combos (Off / NM Only / Always; Status
-- adds a fourth "Poison" mode that only fires on rest-blocking afflictions)
-- plus per-status checkboxes inside the Status block (3 per row).
--
-- Wire format owns the canonical role/type/mode/status indices — see
-- autoutil.RoleAiRole / .RoleAiType / .RoleAiMode / .RoleAiStatusList,
-- mirrored on the server in ai_item.lua.

require 'imguidef';

local autoutil = require('autoutil');

local role_ai_tab = {};

-- Section ordering. Two columns: Tank/Melee/Heal/RDM on the left, Nuke/BRD/SMN
-- on the right. SECTIONS (the union, declaration order) stays around for the
-- snapshot/policy init loop so the wire-format role indices stay 1:1 — so the
-- UNION order below must remain tank,melee,heal,rdm,nuke,brd,smn regardless of
-- which column a section renders in. RDM sits last on the left (under Heal) and
-- nuke first on the right, which keeps that union order unchanged.
local SECTIONS_LEFT  = {
    { key = 'tank',  label = 'Tank'  },
    { key = 'melee', label = 'Melee' },
    { key = 'heal',  label = 'Heal'  },
    { key = 'rdm',   label = 'RDM'   },
};
local SECTIONS_RIGHT = {
    { key = 'nuke', label = 'Nuke' },
    { key = 'brd',  label = 'BRD'  },
    { key = 'smn',  label = 'SMN'  },
};
local SECTIONS = {};
for _, s in ipairs(SECTIONS_LEFT)  do table.insert(SECTIONS, s); end
for _, s in ipairs(SECTIONS_RIGHT) do table.insert(SECTIONS, s); end

-- Combo labels: Off / NM Only / Always. Used for HP, MP, and Status.
-- (Status previously had a fourth "Poison" mode for the rest-blocker
-- subset; removed because untick-everything-but-Poison on the checkboxes
-- + Status=Always covers the same case without a redundant control.)
local MODE_LABELS = { 'Off', 'NM Only', 'Always' };
local MODE_JOINED = table.concat(MODE_LABELS, '\0') .. '\0';

-- Default-ticked statuses match the server defaults: Poison / Silence /
-- Blind / Paralyze. Curse and Disease start unchecked.
local DEFAULT_STATUS_ON = { [0] = true, [1] = true, [2] = true, [3] = true };

-- Local policy mirror. UI reads this; UI writes also fire the wire packet.
local policy = nil;

local function ensure_policy()
    if policy ~= nil then return policy end
    policy = {};
    for _, sec in ipairs(SECTIONS) do
        local flags = {};
        for _, status in ipairs(autoutil.RoleAiStatusList) do
            flags[status.key] = DEFAULT_STATUS_ON[status.key] == true;
        end
        policy[sec.key] = {
            hp = 0, mp = 0, status = 0,  -- all Off by default
            flags = flags,
        };
    end
    return policy;
end

-- Snapshot ingest. Called from autobots_ui.apply_server_snapshot when the
-- HTTP /bot-state response contains a rolePolicy block (integer-keyed by
-- role index, mode values as ints, statusFlags as key→bool map — flattened
-- server-side by ai_item.role_ai_snapshot).
function role_ai_tab.apply_snapshot(snap)
    if type(snap) ~= 'table' then return end
    ensure_policy();
    for roleKey, _ in pairs(policy) do
        local roleIdx = autoutil.RoleAiRole[roleKey];
        if roleIdx ~= nil then
            local body = snap[tostring(roleIdx)] or snap[roleIdx];
            if type(body) == 'table' then
                policy[roleKey].hp     = tonumber(body.hp)     or policy[roleKey].hp;
                policy[roleKey].mp     = tonumber(body.mp)     or policy[roleKey].mp;
                policy[roleKey].status = tonumber(body.status) or policy[roleKey].status;
                if type(body.statusFlags) == 'table' then
                    for k, v in pairs(body.statusFlags) do
                        local kn = tonumber(k);
                        if kn ~= nil then policy[roleKey].flags[kn] = (v == true); end
                    end
                end
            end
        end
    end
end

-- Per-(role, type) imgui var storage. Combos and checkboxes need an
-- ImGuiVar to hold their value across frames; we cache per key.
local combo_vars = {};
local function combo_var_for(roleKey, typeKey)
    local k = roleKey .. ':' .. typeKey;
    if combo_vars[k] == nil then
        combo_vars[k] = imgui.CreateVar(ImGuiVar_INT32);
    end
    return combo_vars[k];
end

local check_vars = {};
local function check_var_for(roleKey, statusKey)
    local k = roleKey .. ':' .. statusKey;
    if check_vars[k] == nil then
        check_vars[k] = imgui.CreateVar(ImGuiVar_BOOLCPP);
    end
    return check_vars[k];
end

-- Layout constants. COL_W matches the established 304px column width used
-- by other tabs (Controls, Alliance AI). COMBO_W matches the Status tab's
-- THF RA combo (80). STATUS_INDENT is small so the checkbox row sits
-- visually under the Status combo without floating off the left edge.
local COL_W         = 304;
local LABEL_W       = 60;
local COMBO_W       = 80;
local STATUS_INDENT = 20;
local ROW_GAP_Y     = 2;
local CHECKS_PER_ROW = 3;

-- Column stride used by the row-of-labels + row-of-combos layout in
-- render_section. Combo is COMBO_W (80) wide; INTER_CELL_GAP places the
-- next cell's start relative to the previous cell's end. Cell stride
-- (label-to-label / combo-to-combo) is COMBO_W + INTER_CELL_GAP.
local INTER_CELL_GAP = 20;

-- Render just the combo for one (role,type) cell. Called from
-- render_section's combos row after the label row above it.
local function render_mode_combo(roleKey, typeKey)
    local body = policy[roleKey];
    local current = body[typeKey] or 0;
    local var = combo_var_for(roleKey, typeKey);
    imgui.SetVarValue(var, current);

    imgui.PushItemWidth(COMBO_W);
    imgui.Combo('##roleai_' .. roleKey .. '_' .. typeKey, var, MODE_JOINED);
    imgui.PopItemWidth();

    local newIdx = imgui.GetVarValue(var);
    if newIdx ~= current then
        body[typeKey] = newIdx;
        local roleIdx = autoutil.RoleAiRole[roleKey];
        local typeIdx = autoutil.RoleAiType[typeKey];
        autoutil.send_role_ai_set_mode(roleIdx, typeIdx, newIdx);
    end
end

-- Per-status checkbox grid. 3 per row keeps each row narrow enough to fit
-- a 304-wide column comfortably. Indent is small (20px) so the row reads
-- as "indented under the Status combo" without burning column width.
local function render_status_flags(roleKey)
    local body = policy[roleKey];
    local roleIdx = autoutil.RoleAiRole[roleKey];

    imgui.Indent(STATUS_INDENT);
    for i, status in ipairs(autoutil.RoleAiStatusList) do
        if i > 1 and ((i - 1) % CHECKS_PER_ROW) ~= 0 then
            imgui.SameLine();
        end
        local current = body.flags[status.key] == true;
        local var = check_var_for(roleKey, status.key);
        imgui.SetVarValue(var, current);
        imgui.Checkbox('##roleai_' .. roleKey .. '_st_' .. tostring(status.key) .. ' ', var);
        imgui.SameLine();
        imgui.Text(status.label);

        local newVal = imgui.GetVarValue(var);
        if newVal ~= current then
            body.flags[status.key] = newVal;
            autoutil.send_role_ai_set_status_flag(roleIdx, status.key, newVal);
        end
    end
    imgui.Unindent(STATUS_INDENT);
end

local function render_section(sec)
    autoutil.section_head(sec.label);
    -- Labels row + Combos row aligned to shared column X-positions.
    -- Cell stride = COMBO_W + INTER_CELL_GAP; each cell starts at
    -- startX + i*stride. Explicit SetCursorPosX per widget so labels sit
    -- flush with the left edge of their combo below (independent of
    -- Health/Mana/Status width differences).
    local stride = COMBO_W + INTER_CELL_GAP;
    local startX = imgui.GetCursorPosX();
    -- Row 1: labels.
    imgui.SetCursorPosX(startX);
    imgui.Text('Health');
    imgui.SameLine();
    imgui.SetCursorPosX(startX + stride);
    imgui.Text('Mana');
    imgui.SameLine();
    imgui.SetCursorPosX(startX + stride * 2);
    imgui.Text('Status');
    -- Row 2: combos. Aligned to same X positions as labels above.
    imgui.SetCursorPosX(startX);
    render_mode_combo(sec.key, 'hp');
    imgui.SameLine();
    imgui.SetCursorPosX(startX + stride);
    render_mode_combo(sec.key, 'mp');
    imgui.SameLine();
    imgui.SetCursorPosX(startX + stride * 2);
    render_mode_combo(sec.key, 'status');
    imgui.Dummy(0, ROW_GAP_Y);
    render_status_flags(sec.key);
    imgui.Dummy(0, 8);
end

-----------------------------------
-- BRD per-bot song-roster mirror (#252)
--
-- Per-bot data, NOT per-role — so it doesn't fit the column layout above.
-- Renders below the columns as one row per BRD bot in the alliance.
-- Each row: bot name + 4 dropdowns (Minuet / Madrigal / Ballad A / Ballad B).
-- "Auto" sentinel (spell ID 0) is always available; remaining options come
-- from the bot's knownSongs list in the snapshot.
-----------------------------------

-- Per-bot mirrors, populated by apply_bot_state from /bot-state snapshot.
--   brd_roster[name] = { slot0, slot1, slot2, slot3 }  -- spell IDs, 0 = Auto
--   brd_known[name]  = { spellId, spellId, ... }       -- what BRD has learned
local brd_roster = {};
local brd_known  = {};

-- Spell-id → display name. Hardcoded since the autobots addon doesn't need
-- to drag in the full Ashita ResourceManager dependency for ~20 spells.
-- Extend this table as you add more song families to the BRD catalogue
-- (server-side bots.lua BRD_SONG_CATALOGUE). Spell IDs match scripts/enum/magic.lua.
local SONG_LABEL = {
    [394] = 'Valor Minuet',
    [395] = 'Valor Minuet II',
    [396] = 'Valor Minuet III',
    [397] = 'Valor Minuet IV',
    [398] = 'Valor Minuet V',
    [399] = 'Sword Madrigal',
    [400] = 'Blade Madrigal',
    [419] = 'Advancing March',
    [420] = 'Victory March',
    [417] = 'Honor March',
    [386] = 'Mage\'s Ballad',
    [387] = 'Mage\'s Ballad II',
    [388] = 'Mage\'s Ballad III',
    [389] = 'Knight\'s Minne',
    [390] = 'Knight\'s Minne II',
    [391] = 'Knight\'s Minne III',
    [392] = 'Knight\'s Minne IV',
    [393] = 'Knight\'s Minne V',
};
local function song_label(spellId)
    if spellId == 0 then return 'Auto'; end
    return SONG_LABEL[spellId] or string.format('#%d', spellId);
end

-- Per-(bot, slot) imgui var cache.
local roster_combo_vars = {};
local function roster_combo_var(botName, slotIdx)
    local k = botName .. ':' .. tostring(slotIdx);
    if roster_combo_vars[k] == nil then
        roster_combo_vars[k] = imgui.CreateVar(ImGuiVar_INT32);
    end
    return roster_combo_vars[k];
end

-- Snapshot ingest from autobots_ui.apply_server_snapshot. Called with the
-- bots[] array; we filter to BRD rows and stash roster + knownSongs.
function role_ai_tab.apply_bot_state(bots_arr)
    if type(bots_arr) ~= 'table' then return; end
    brd_roster = {};
    brd_known  = {};
    for _, row in ipairs(bots_arr) do
        if row.role == 'brd' and type(row.name) == 'string' and row.name ~= '' then
            local r = row.songRoster or { 0, 0, 0, 0 };
            brd_roster[row.name] = {
                tonumber(r[1]) or 0,
                tonumber(r[2]) or 0,
                tonumber(r[3]) or 0,
                tonumber(r[4]) or 0,
            };
            local k = row.knownSongs or {};
            brd_known[row.name] = {};
            for _, spellId in ipairs(k) do
                if type(spellId) == 'number' then
                    table.insert(brd_known[row.name], spellId);
                end
            end
        end
    end
end

local SLOT_LABELS = { 'Minuet', 'Madrigal', 'Ballad A', 'Ballad B' };
local SLOT_COMBO_W = 110;

local function render_roster_row(botName)
    local roster = brd_roster[botName] or { 0, 0, 0, 0 };
    local known  = brd_known[botName]  or {};

    -- Build the per-slot options list: "Auto" sentinel + every learned song.
    -- We rebuild this every frame because the snapshot can mutate (rare —
    -- spells learned mid-session); cost is small (≤20 entries).
    local options    = { 0 };  -- "Auto" sentinel
    for _, sid in ipairs(known) do table.insert(options, sid); end

    -- Joined null-delim string for imgui.Combo.
    local labels = {};
    for _, sid in ipairs(options) do table.insert(labels, song_label(sid)); end
    local joined = table.concat(labels, '\0') .. '\0';

    imgui.Text(botName);
    imgui.SameLine();
    -- Per-slot dropdowns laid out horizontally on the same line as the name.
    for slotIdx = 1, 4 do
        local currentSpell = roster[slotIdx] or 0;
        -- Resolve current spell to its index in `options` (0-based for combo).
        local currentIdx = 0;
        for i, sid in ipairs(options) do
            if sid == currentSpell then currentIdx = i - 1; break; end
        end
        local var = roster_combo_var(botName, slotIdx);
        imgui.SetVarValue(var, currentIdx);
        imgui.PushItemWidth(SLOT_COMBO_W);
        imgui.Combo(string.format('##brdslot_%s_%d', botName, slotIdx), var, joined);
        imgui.PopItemWidth();

        local newIdx = imgui.GetVarValue(var);
        if newIdx ~= currentIdx then
            local newSpell = options[newIdx + 1] or 0;
            roster[slotIdx] = newSpell;
            brd_roster[botName] = roster;
            -- Send the WHOLE roster (server overwrites all 4 slots on each
            -- packet) so the user gets atomic updates.
            autoutil.send_brd_song_roster(botName,
                roster[1], roster[2], roster[3], roster[4]);
        end

        if slotIdx < 4 then imgui.SameLine(); end
    end
end

local function render_brd_roster_block()
    -- Skip the whole block when there are no BRD bots — keeps the tab clean
    -- for compositions without a Bard.
    local hasAny = false;
    for _ in pairs(brd_roster) do hasAny = true; break; end
    if not hasAny then return; end

    imgui.Dummy(0, 8);
    autoutil.section_head('BRD Song Roster (per bot)');
    imgui.TextDisabled('Auto = use highest tier learned. Slot order: Minuet / Madrigal / Ballad A / Ballad B.');
    imgui.Dummy(0, 4);

    -- Stable iteration order by name.
    local names = {};
    for n in pairs(brd_roster) do table.insert(names, n); end
    table.sort(names);
    for _, name in ipairs(names) do
        render_roster_row(name);
        imgui.Dummy(0, 4);
    end
end

-- Extract RGBA components from a packed uint32 color (mirrors autobots_ui's
-- _uc helper; lifted here to keep this file standalone).
local function unpack_color(u)
    return bit.band(u, 0xFF) / 255,
           bit.band(bit.rshift(u, 8),  0xFF) / 255,
           bit.band(bit.rshift(u, 16), 0xFF) / 255,
           bit.band(bit.rshift(u, 24), 0xFF) / 255;
end

local function render_col_divider()
    imgui.PushStyleColor(ImGuiCol_ChildWindowBg, unpack_color(imgui.GetColorU32(ImGuiCol_Button)));
    imgui.BeginChild('##roleai_col_divider', 1, 0, false);
    imgui.EndChild();
    imgui.PopStyleColor();
end

function role_ai_tab.render()
    ensure_policy();

    -- Wrap the body in pcall so an error inside any render_section (e.g. a
    -- broken send_role_ai_set_mode dispatch after a Combo commit) can't
    -- strand an unmatched PushItemWidth / PushStyleColor / PushStyleVar.
    -- ImGui's style + item stacks don't unwind on Lua error, and a leaked
    -- push contaminates every downstream addon's render (autobots is
    -- early-alphabetical so later addons render dimmed until the frame
    -- ends). Matches the same pcall guard used by status_tab.render.
    local ok, err = pcall(function()
        imgui.Text('Per-role item-usage policy. HP/MP thresholds fixed at 20%%.');
        imgui.Text('Status items prefer specific items; Remedy for multi-status.');
        imgui.Dummy(0, 6);

        -- Left column: Tank / Melee / Heal / RDM.
        imgui.BeginGroup();
        imgui.Dummy(COL_W, 0);
        for i, sec in ipairs(SECTIONS_LEFT) do
            if i > 1 then imgui.Separator(); imgui.Dummy(0, 4); end
            render_section(sec);
        end
        imgui.EndGroup();

        imgui.SameLine(0, 6);
        render_col_divider();
        imgui.SameLine(0, 6);

        -- Right column: Nuke / BRD / SMN.
        imgui.BeginGroup();
        imgui.Dummy(COL_W, 0);
        for i, sec in ipairs(SECTIONS_RIGHT) do
            if i > 1 then imgui.Separator(); imgui.Dummy(0, 4); end
            render_section(sec);
        end
        imgui.EndGroup();

        -- BRD per-bot song-roster section spans the full tab width below the
        -- two policy columns. Only renders if there's at least one BRD bot.
        render_brd_roster_block();
    end);
    if not ok then
        autoutil.log('AutoBots', 'role_ai_tab error: ' .. tostring(err));
    end
end

return role_ai_tab;
