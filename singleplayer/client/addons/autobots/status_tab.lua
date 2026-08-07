-- Status tab: 4x4 grid of per-character cards. Top-left slot is the primary
-- (sourced from the local Ashita party + the same 0x191 PARTY_STATUS feed as
-- the other 15 slots). Remaining 15 slots hold trusts, owned headless bots,
-- and any real alliance PCs that the periodic 0x191 push includes.
--
-- Card layout per row (top to bottom):
--   1. Character name           (centered, brighter text)
--   2. "Exp: cur / next" label  (centered)
--   3. Status-effect icon strip (fixed 2-row reserve, even when empty)
--   4. Mild horizontal divider
--   5. Role-specific toggles    (horizontally + vertically centered in
--                                the remaining space; hidden when not
--                                applicable to the row, leaving the
--                                space empty)
--
-- Portraits were removed from this revision; the planned re-add lives in
-- a future spike (see #232's followup). The portraits/ dir and PNGs are
-- still on disk; only the render path is gone.
--
-- Data source: the periodic 0x191 PARTY_STATUS push from bots_status.lua
-- server-side (~2s cadence, plus a force-push at spawn-time so the grid
-- populates within a tick instead of waiting for the gate).
--
-- Per-card data sources:
--   name / effects / expCurrent / expToNext
--      -> 0x191 PARTY_STATUS push (one packet per party)
--   main job / main job lvl / sub job / sub job lvl
--      -> AshitaCore:GetDataManager():GetParty():GetMember*() (free, fast)

require 'imguidef';
require 'd3d8';

local autoutil   = require('autoutil');
local icon_cache = require('icon_cache');

local status_tab = {};

-- Status-effect icons keyed by effectId (e.g. 142.png).
local icons = icon_cache.new(_addon and (_addon.path .. '../libs/icons/') or '../libs/icons/');

-- Per-party member lists keyed by partyNumber (1..3). Each entry:
--   { name, effects, race, face, expCurrent, expToNext, updatedMs }
-- race/face are still parsed off the wire (unused since the portrait drop)
-- so we don't have to change the 0x191 packet shape just to rewire the UI.
local party_data = { [1] = {}, [2] = {}, [3] = {} };

-- Stale-data threshold. If we haven't seen a fresh push for this many ms
-- the panel is dimmed so the user knows what they're looking at is old.
-- Set generously above the 2s push cadence to tolerate a missed beat.
local STALE_MS = 15000;

local function ms_now()
    return ashita.timer.get_time and ashita.timer.get_time() or os.clock() * 1000;
end

-- Effect-name fallback for when no PNG is bundled for that effect ID.
local name_cache = {};
local function effect_name_for(effectId)
    local cached = name_cache[effectId];
    if cached ~= nil then return cached; end
    local resmgr = AshitaCore:GetResourceManager();
    if resmgr == nil then return ('#%d'):format(effectId); end
    local ok, str = pcall(function() return resmgr:GetString('statusnames', effectId, 2); end);
    local out;
    if ok and type(str) == 'string' and #str > 0 then
        out = str;
    else
        out = ('#%d'):format(effectId);
    end
    name_cache[effectId] = out;
    return out;
end

-----------------------------------
-- Packet handler. Wired from autobots.lua on incoming 0x191. Layout matches
-- the new wire format documented in autoutil.check_for_party_status.
-----------------------------------
function status_tab.on_party_status(partyNumber, members)
    local now = ms_now();
    local out = {};
    for _, entry in ipairs(members or {}) do
        table.insert(out, {
            name       = entry.name,
            effects    = entry.effects    or {},
            race       = entry.race       or 0,
            face       = entry.face       or 0,
            expCurrent = entry.expCurrent or 0,
            expToNext  = entry.expToNext  or 0,
            updatedMs  = now,
        });
    end
    party_data[partyNumber] = out;
end

-----------------------------------
-- Resolve the primary character's name (Ashita party slot 0). Returns '' if
-- unavailable - the render path handles a nil/empty primary by drawing a
-- placeholder card so the grid stays aligned during early bootstrap.
-----------------------------------
local function primary_name_now()
    local party = AshitaCore:GetDataManager():GetParty();
    return (party and party:GetMemberName(0)) or '';
end

-----------------------------------
-- Build the slot list: primary first, then up to 15 other party members
-- pulled from the 0x191 cache in party-order (party 1, 2, 3). When the
-- primary's 0x191 entry hasn't arrived yet we still emit a slot 1 with at
-- least the name pulled from Ashita so the upper-left card isn't a hole.
-----------------------------------
local function collect_rows()
    local primary    = primary_name_now();
    local primary_row = nil;
    local others      = {};
    for p = 1, 3 do
        for _, member in ipairs(party_data[p] or {}) do
            if member.name == primary and primary_row == nil then
                primary_row = member;
            else
                table.insert(others, member);
            end
        end
    end
    -- Synthesize a name-only placeholder when 0x191 hasn't filled the
    -- primary's slot yet. Effects empty, exp 0/0 - the card still renders
    -- cleanly and the data arrives within ~2s when the push lands.
    if primary_row == nil and primary ~= '' then
        primary_row = {
            name       = primary,
            effects    = {},
            expCurrent = 0,
            expToNext  = 0,
            updatedMs  = ms_now(),
        };
    end

    local out = {};
    table.insert(out, primary_row);  -- may still be nil if even Ashita isn't ready
    for _, m in ipairs(others) do
        if #out >= 16 then break; end
        table.insert(out, m);
    end
    return out;
end

-- Grid shape.
local GRID_COLS = 4;
local GRID_ROWS = 4;

-----------------------------------
-- Card layout constants. Tuned for a 4-wide grid at the Status tab's
-- 920px first-use window width.
-----------------------------------
local CARD_W        = 210;
-- View-only card: name + exp + 2-row status-icon strip. The per-bot controls
-- moved to the Role AI tab, but the card keeps its original 200 height (a
-- rectangle, not a square) so the Status grid reads the same as before.
local CARD_H        = 200;
local ICON_SIZE     = 22;  -- larger than the old 18, tuned down from 27
local ICON_GAP      = 2;
-- Per-row count keeps a full row within the 210px card interior
-- (7 * 22 + 6 * 2 = 166, within the padded content width).
local ICONS_PER_ROW = 7;
local MAX_ICON_ROWS = 4;  -- ~7*4 = 28 icons before the "+N" overflow
local ICON_BLOCK_H  = MAX_ICON_ROWS * (ICON_SIZE + ICON_GAP);

-- (The per-bot control machinery that used to live here — job gates
--  lookup_jobs / is_sata_eligible / is_pld_flash_eligible / is_smn_main /
--  is_thf_main, the per-name state mirrors, apply_bot_state ingest, the
--  option constants, get_combo_var, index_of, and the eight
--  render_*_combo_centered helpers — all moved to role_ai_tab.lua when the
--  per-bot AI settings got their own tab. Status is now a view-only monitor
--  and consumes only the 0x191 PARTY_STATUS feed.)

-- Pull the width component out of imgui.CalcTextSize's variable return shape.
-- Different Ashita imgui versions hand back number, {x=..,y=..}, or {w,h}.
local function calc_text_w(text)
    local a, b = imgui.CalcTextSize(text);
    if type(a) == 'number' then return a; end
    if type(a) == 'table'  then return a.x or a[1] or 0; end
    return #text * 7;
end

-- Set the cursor X so the next pushed content of `width` lands horizontally
-- centered in the remaining content region.
local function center_cursor_x(width)
    local avail = imgui.GetContentRegionAvailWidth();
    local off   = math.max(0, (avail - width) / 2);
    imgui.SetCursorPosX(imgui.GetCursorPosX() + off);
end

-----------------------------------
-- Status-effect icon strip. Always reserves space for two rows even when the
-- bot has zero effects, so the divider below stays at the same Y across
-- cards (visual stability when bots come and go between renders).
-----------------------------------
local function render_icons(effects)
    local startY = imgui.GetCursorPosY();
    if effects ~= nil and #effects > 0 then
        local total    = #effects;
        local capacity = ICONS_PER_ROW * MAX_ICON_ROWS;
        local visible  = math.min(total, capacity);
        local overflow = total - visible;
        for i = 1, visible do
            local effectId = effects[i];
            local tex      = icons:get(effectId);
            if tex ~= nil then
                imgui.Image(tex, ICON_SIZE, ICON_SIZE);
            else
                imgui.PushStyleColor(ImGuiCol_Button, 0.35, 0.35, 0.35, 0.85);
                imgui.SmallButton(effect_name_for(effectId):sub(1, 3) .. '##e_' .. i);
                imgui.PopStyleColor();
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip(effect_name_for(effectId));
            end
            local positionInRow = (i - 1) % ICONS_PER_ROW;
            if i < visible and positionInRow < ICONS_PER_ROW - 1 then
                imgui.SameLine(0, ICON_GAP);
            end
        end
        if overflow > 0 then
            imgui.SameLine(0, ICON_GAP);
            imgui.TextDisabled(('+%d'):format(overflow));
            if imgui.IsItemHovered() then
                local lines = {};
                for j = visible + 1, total do
                    table.insert(lines, effect_name_for(effects[j]));
                end
                imgui.SetTooltip(table.concat(lines, '\n'));
            end
        end
    end
    -- Pad up to the full reserved icon-block height so the divider Y stays
    -- consistent whether the bot has 0, 4, or 16 effects.
    local consumed = imgui.GetCursorPosY() - startY;
    local pad      = ICON_BLOCK_H - consumed;
    if pad > 0 then imgui.Dummy(0, pad); end
end

-- Main/sub job + level string for the card, e.g. "WAR60/NIN30" (or "WAR60"
-- with no sub). Pulled from the live Ashita party (free, fast). Returns nil
-- when the char isn't in an alliance slot or has no resolved main job.
local function member_jobs_str(name)
    if name == nil or name == '' then return nil; end
    local party = AshitaCore:GetDataManager():GetParty();
    if party == nil then return nil; end
    for slot = 0, 17 do
        if party:GetMemberName(slot) == name then
            local mj = party:GetMemberMainJob(slot) or 0;
            if mj == 0 then return nil; end
            local ml = party:GetMemberMainJobLevel(slot) or 0;
            local sj = party:GetMemberSubJob(slot) or 0;
            local sl = party:GetMemberSubJobLvl(slot) or 0;
            local s = string.format('%s %d', autoutil.jobs[mj] or '?', ml);
            if sj > 0 then
                s = s .. string.format(' / %s %d', autoutil.jobs[sj] or '?', sl);
            end
            return s;
        end
    end
    return nil;
end

-- Horizontal padding on the status-icon strip so it doesn't hug the card edges.
local ICON_PAD_X = 12;

-----------------------------------
-- One card. Owns a fixed-size BeginChild frame so the grid stays aligned
-- regardless of which optional toggles are present.
-----------------------------------
local function render_card(row, idx)
    local name = row and row.name or '';
    local is_primary = (name ~= '' and name == primary_name_now());

    imgui.BeginChild('##card_' .. idx, CARD_W, CARD_H, true);

    -- 1) Centered name. Ashita v3 imgui doesn't expose font scaling, so the
    --    "slightly bigger" feel comes from a brighter foreground color plus
    --    the surrounding whitespace giving the line visual weight.
    -- Name + jobs render a little larger via SetWindowFontScale where the
    -- binding exposes it (guarded — ADKv3's imgui is ashita.gui and the func
    -- set is binary-provided; no-op if absent). Widths are measured at base
    -- scale then multiplied so the centering stays correct at the larger size.
    -- Kept modest: the bitmap font gets rough when scaled up much past this.
    local BIG       = 1.1;
    local can_scale = (imgui.SetWindowFontScale ~= nil);

    imgui.Dummy(0, 4);
    local display_name = (name ~= '') and name or '(loading)';
    local nw = calc_text_w(display_name);
    local js = member_jobs_str(name);
    local jw = (js ~= nil) and calc_text_w(js) or 0;

    if can_scale then imgui.SetWindowFontScale(BIG); end
    center_cursor_x(can_scale and nw * BIG or nw);
    if is_primary then
        -- Primary gets a faint gold-ish tint so it visually anchors the grid.
        imgui.TextColored(1.0, 0.95, 0.6, 1.0, display_name);
    else
        imgui.TextColored(1.0, 1.0, 1.0, 1.0, display_name);
    end

    imgui.Dummy(0, 4);

    -- 2) Centered jobs row: "WAR60/NIN30" (main + sub with levels), same size.
    if js ~= nil then
        center_cursor_x(can_scale and jw * BIG or jw);
        imgui.TextColored(0.80, 0.88, 1.0, 1.0, js);
    end
    if can_scale then imgui.SetWindowFontScale(1.0); end

    imgui.Dummy(0, 4);

    -- 3) Centered EXP row. Show denominator as "MAX" at level cap (req=0).
    -- Brightened from TextDisabled to a bright neutral so the EXP line
    -- reads as foreground content rather than washing into the card chrome.
    do
        local cur = (row and row.expCurrent) or 0;
        local req = (row and row.expToNext)  or 0;
        local s   = (req > 0) and string.format('Exp: %d / %d', cur, req)
                              or  'Exp: MAX';
        center_cursor_x(calc_text_w(s));
        imgui.TextColored(0.90, 0.90, 0.90, 1.0, s);
    end

    imgui.Dummy(0, 6);

    -- 4) Status icon strip (reserves 2 rows of vertical space). Indented on
    --    both sides so the icons don't hug the card edges.
    imgui.Indent(ICON_PAD_X);
    render_icons(row and row.effects);
    imgui.Unindent(ICON_PAD_X);

    -- View-only: the per-bot role toggles that used to render below a mild
    -- divider here moved to the Role AI tab. Status is now name + exp + status
    -- icons only, so the card ends after the icon strip.

    imgui.EndChild();
end

-----------------------------------
-- Empty-slot placeholder. Same frame footprint as render_card so the grid
-- stays aligned when the alliance has fewer than 16 entries.
-----------------------------------
local function render_empty_card(idx)
    imgui.BeginChild('##card_empty_' .. idx, CARD_W, CARD_H, false);
    imgui.EndChild();
end

-----------------------------------
-- Main render entry. Called from autobots_ui.lua when the Status tab is
-- active. Owns its own layout; caller controls the surrounding window.
-----------------------------------
function status_tab.render()
    local rows = collect_rows();
    if #rows == 0 then
        imgui.TextColored(0.85, 0.85, 0.85, 1.0, 'No party / alliance data yet.');
        return;
    end

    -- (Stale-data dim removed: the panel used to drop to 0.5 alpha whenever no
    -- row had a fresh 0x191 push within STALE_MS, then brighten on the next
    -- push — which read as an occasional dim/brighten flicker. User prefers it
    -- always at full brightness.)
    local ok, err = pcall(function()
        local totalSlots = GRID_COLS * GRID_ROWS;
        for slot = 1, totalSlots do
            local row = rows[slot];
            if row ~= nil then
                render_card(row, slot);
            else
                render_empty_card(slot);
            end
            if (slot % GRID_COLS) ~= 0 and slot < totalSlots then
                imgui.SameLine(0, 6);
            end
        end
    end);
    if not ok then
        autoutil.log('AutoBots', 'status_tab error: ' .. tostring(err));
    end
end

-----------------------------------
-- Wipe everything (e.g. on tab close or zone change). Combo vars are kept -
-- they're cheap and re-keyed by name so the next render aligns.
-----------------------------------
function status_tab.reset()
    party_data = { [1] = {}, [2] = {}, [3] = {} };
end

-- Subscribe to the autoutil dispatcher so the parser routes packets here.
if autoutil and autoutil.on_party_status then
    autoutil.on_party_status(function(partyNumber, members)
        status_tab.on_party_status(partyNumber, members);
    end);
end

return status_tab;
