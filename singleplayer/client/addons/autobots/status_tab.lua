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
local icons = icon_cache.new(_addon and (_addon.path .. 'icons/') or 'icons/');

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
-- 200 (was 170) so the tallest card — RDM, which stacks Heal Scope + Nuke
-- Rotation + MB Spells (3 combos) below the divider — fits without an in-card
-- scrollbar. The Status window auto-fits height (SetNextWindowSize height 0),
-- so the taller grid just grows the window. Empty-slot placeholders share this
-- constant, keeping the 4x4 grid aligned.
local CARD_H        = 200;
local ICON_SIZE     = 18;
local ICON_GAP      = 2;
local ICONS_PER_ROW = 8;
local MAX_ICON_ROWS = 2;
local ICON_BLOCK_H  = MAX_ICON_ROWS * (ICON_SIZE + ICON_GAP);

-----------------------------------
-- Ashita party lookup. Returns mj, ml, sj, sl, or nil if the name isn't
-- in any alliance slot from this client's perspective.
-----------------------------------
local function lookup_jobs(name)
    local party = AshitaCore:GetDataManager():GetParty();
    if party == nil then return nil; end
    for slot = 0, 17 do
        if party:GetMemberName(slot) == name then
            return party:GetMemberMainJob(slot),
                   party:GetMemberMainJobLevel(slot),
                   party:GetMemberSubJob(slot),
                   party:GetMemberSubJobLvl(slot);
        end
    end
    return nil;
end

-- THF main-job ID. SATA eligibility still gated on job (needs both SA + TA),
-- not on role config - matches the prior implementation.
local JOB_THF = 6;
local function is_sata_eligible(name)
    local mj, ml, sj, sl = lookup_jobs(name);
    if mj == nil then return false; end
    if mj == JOB_THF and (ml or 0) >= 30 then return true; end
    if sj == JOB_THF and (sl or 0) >= 30 then return true; end
    return false;
end

-- PLD main-job ID. Add-control dropdown is PLD-only because Flash is a
-- PLD-unique spell (level 25). We accept main-PLD/lv25+ here; sub-PLD also
-- learns Flash at sub-25 (so main >= 50) but that's a rarer config and we
-- keep V1 simple - sub-PLD path can be added later by extending this check.
local JOB_PLD = 7;
local function is_pld_flash_eligible(name)
    local mj, ml = lookup_jobs(name);
    if mj == nil then return false; end
    if mj == JOB_PLD and (ml or 0) >= 25 then return true; end
    return false;
end

-- SMN main-job check. Avatar dropdown only appears for main-SMN; sub-SMN
-- has very limited summon access and the role_smn server-side dispatch
-- keys on main-job SMN anyway.
local JOB_SMN = 15;
local function is_smn_main(name)
    local mj = lookup_jobs(name);
    return mj == JOB_SMN;
end

-- THF main-job check. The RA cadence combo only appears for main-job THF
-- because the role_melee should_ra branch keys on is_job(bot, 'THF')
-- which is main-job. Sub THF doesn't drive the utility-RA logic.
-- (JOB_THF = 6 already declared above for is_sata_eligible.)
local function is_thf_main(name)
    local mj = lookup_jobs(name);
    if mj == nil then return false; end
    return mj == JOB_THF;
end

-----------------------------------
-- Per-bot ImGui combobox state. ComboBox needs a backing ImVar to store the
-- selected 0-based index. Vars are created lazily and cached by (bot name,
-- combo tag) so adding/removing bots between renders doesn't churn vars.
-----------------------------------
local combo_vars       = {};   -- ['<name>_<tag>'] = ImVar
local sata_modes       = {};   -- ['<name>'] = 'combined' / 'split' / 'saonly'
-- Per-bot THF utility-RA cadence (seconds). 0 = Off. Default 15 matches
-- the server-side bots.lua initializer; user changes are mirrored here
-- and re-sent over the wire.
local thf_ra_delays    = {};
local heal_scopes      = {};   -- ['<name>'] = 'party' / 'allianceAssist' / 'allianceMain'
local add_control_modes = {};  -- ['<name>'] = 'provoke' / 'flash' / 'both'  (PLD add-control)
local smn_avatars       = {};  -- ['<name>'] = current avatar spell ID (296 default)
local smn_known_summons = {};  -- ['<name>'] = { spellId, ... } filtered to learned
local casual_nuke_rotations = {}; -- ['<name>'] = 1..6 spells, 0 = All (role_nuke/rdm)
local casual_nuke_mb_modes  = {}; -- ['<name>'] = 'include' / 'exclude'

-- SMN avatar dropdown labels — keyed by summon spell ID. Plain ASCII per
-- ASCII-only-in-chat rule (the dropdown is local UI so the rule is
-- belt-and-braces here, but the labels never need anything special).
local SUMMON_LABEL = {
    [288] = 'Fire Spirit',
    [289] = 'Ice Spirit',
    [290] = 'Air Spirit',
    [291] = 'Earth Spirit',
    [292] = 'Thunder Spirit',
    [293] = 'Water Spirit',
    [294] = 'Light Spirit',
    [295] = 'Dark Spirit',
    [296] = 'Carbuncle',
    [297] = 'Fenrir',
    [298] = 'Ifrit',
    [299] = 'Titan',
    [300] = 'Leviathan',
    [301] = 'Garuda',
    [302] = 'Shiva',
    [303] = 'Ramuh',
    [304] = 'Diabolos',
};

-- Seed the per-bot mirrors from the HTTP bot-state snapshot. Called by
-- autobots_ui.apply_server_snapshot with the bots[] array (each row has
-- name + role + sataMode + healScope + addControlMode + thfRaDelay).
-- Defensive type-checks so a malformed entry can't corrupt the UI.
function status_tab.apply_bot_state(bots_arr)
    if type(bots_arr) ~= 'table' then return; end
    for _, row in ipairs(bots_arr) do
        local name = (type(row.name) == 'string') and row.name or nil;
        if name and name ~= '' then
            if type(row.sataMode)       == 'string' then sata_modes[name]        = row.sataMode;       end
            if type(row.healScope)      == 'string' then heal_scopes[name]       = row.healScope;      end
            if type(row.addControlMode) == 'string' then add_control_modes[name] = row.addControlMode; end
            if type(row.thfRaDelay)     == 'number' then thf_ra_delays[name]     = row.thfRaDelay;     end
            if type(row.smnAvatarSpellId) == 'number' then smn_avatars[name]     = row.smnAvatarSpellId; end
            if type(row.knownSummons)   == 'table'  then smn_known_summons[name] = row.knownSummons;   end
            if type(row.casualNukeRotation) == 'number' then casual_nuke_rotations[name] = row.casualNukeRotation; end
            if type(row.casualNukeMbMode)   == 'string' then casual_nuke_mb_modes[name]  = row.casualNukeMbMode;   end
        end
    end
end

local function get_combo_var(name, tag)
    local key = name .. '_' .. tag;
    local v   = combo_vars[key];
    if v == nil then
        v = imgui.CreateVar(ImGuiVar_INT32);
        combo_vars[key] = v;
    end
    return v;
end

local SATA_OPTIONS = { 'combined', 'split',     'saonly' };
local SATA_LABELS  = { 'Combined', 'Split',     'SA Only' };
local HEAL_OPTIONS = { 'party',    'allianceAssist', 'allianceMain' };
local HEAL_LABELS  = { 'Party',    'Alliance Assist', 'Alliance Main' };
-- PLD add-control. Wire-byte = (index - 1). Labels are the dropdown display
-- strings (title-cased + ampersand spelled out for the "both" case).
local ADD_CTRL_OPTIONS = { 'provoke', 'flash', 'both'          };
local ADD_CTRL_LABELS  = { 'Provoke', 'Flash', 'Provoke & Flash' };
-- THF utility-RA cadence in seconds. 0 = Off (sentinel — server skips RA
-- entirely when delay <= 0). Values match the discrete picker mentioned
-- in the conversation; tune by editing this table on both sides if more
-- granularity is wanted later.
local THF_RA_OPTIONS = { 0,     5,    10,    15,    20,    30    };
local THF_RA_LABELS  = { 'Off', '5s', '10s', '15s', '20s', '30s' };
-- Casual-nuke rotation: how many spells cycle before repeating. 0 = All (cycle
-- through everything castable). role_nuke / role_rdm cards.
local NUKE_ROT_OPTIONS = { 1,   2,   3,   4,   5,   6,   0     };
local NUKE_ROT_LABELS  = { '1', '2', '3', '4', '5', '6', 'All' };
-- Casual-nuke MB-spell mode. Include = SC-MB elements usable in casual rotation;
-- Exclude = reserve them for magic bursts.
local NUKE_MB_OPTIONS = { 'include', 'exclude' };
local NUKE_MB_LABELS  = { 'Include', 'Exclude' };

local function index_of(tbl, val)
    for i, v in ipairs(tbl) do
        if v == val then return i; end
    end
    return 1;
end

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

-----------------------------------
-- Centered role toggles. Each renders a single horizontal "Label  [Combo]"
-- or "Label  [< >]" group, centered in the card's content region.
-- ROW_H is the approximate vertical footprint used by the parent to vertical-
-- center the block.
-----------------------------------
local TOGGLE_ROW_H = 22;
local COMBO_W      = 120;
local LABEL_GAP    = 6;

-- Frame padding for combos (matches imgui dark-theme default). Used to
-- offset the label Y so it visually centers against the combo's frame
-- baseline. AlignTextToFramePadding turned out to be unreliable on the
-- first item of a fresh line in Ashita's binding - we got the "label
-- sits high" effect on every combo's first frame. Explicit Y offset is
-- binding-independent and works for all three combos.
local LABEL_Y_OFFSET = 3;

local function render_sata_combo_centered(name)
    local current = sata_modes[name] or 'combined';
    local var     = get_combo_var(name, 'sata');
    imgui.SetVarValue(var, index_of(SATA_OPTIONS, current) - 1);

    local label_w = calc_text_w('SATA');
    center_cursor_x(label_w + LABEL_GAP + COMBO_W);
    local row_y = imgui.GetCursorPosY();
    imgui.SetCursorPosY(row_y + LABEL_Y_OFFSET);
    imgui.Text('SATA');
    imgui.SameLine(0, LABEL_GAP);
    imgui.SetCursorPosY(row_y);
    imgui.PushItemWidth(COMBO_W);
    imgui.Combo('##sata_' .. name, var, table.concat(SATA_LABELS, '\0') .. '\0');
    imgui.PopItemWidth();

    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = SATA_OPTIONS[newIdx];
    if newVal ~= nil and newVal ~= current then
        sata_modes[name] = newVal;
        autoutil.send_bot_set_sata_mode(name, newIdx - 1);
    end
end

local function render_casual_nuke_rotation_centered(name)
    local current = casual_nuke_rotations[name] or 3;
    local var     = get_combo_var(name, 'nukerot');
    imgui.SetVarValue(var, index_of(NUKE_ROT_OPTIONS, current) - 1);

    local label_w = calc_text_w('Nuke Rotation');
    center_cursor_x(label_w + LABEL_GAP + COMBO_W);
    local row_y = imgui.GetCursorPosY();
    imgui.SetCursorPosY(row_y + LABEL_Y_OFFSET);
    imgui.Text('Nuke Rotation');
    imgui.SameLine(0, LABEL_GAP);
    imgui.SetCursorPosY(row_y);
    imgui.PushItemWidth(COMBO_W);
    imgui.Combo('##nukerot_' .. name, var, table.concat(NUKE_ROT_LABELS, '\0') .. '\0');
    imgui.PopItemWidth();

    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = NUKE_ROT_OPTIONS[newIdx];
    if newVal ~= nil and newVal ~= current then
        casual_nuke_rotations[name] = newVal;
        -- Wire byte = the number; 0 = All.
        autoutil.send_bot_set_casual_nuke_rotation(name, newVal);
    end
end

local function render_casual_nuke_mb_centered(name)
    local current = casual_nuke_mb_modes[name] or 'include';
    local var     = get_combo_var(name, 'nukemb');
    imgui.SetVarValue(var, index_of(NUKE_MB_OPTIONS, current) - 1);

    local label_w = calc_text_w('MB Spells');
    center_cursor_x(label_w + LABEL_GAP + COMBO_W);
    local row_y = imgui.GetCursorPosY();
    imgui.SetCursorPosY(row_y + LABEL_Y_OFFSET);
    imgui.Text('MB Spells');
    imgui.SameLine(0, LABEL_GAP);
    imgui.SetCursorPosY(row_y);
    imgui.PushItemWidth(COMBO_W);
    imgui.Combo('##nukemb_' .. name, var, table.concat(NUKE_MB_LABELS, '\0') .. '\0');
    imgui.PopItemWidth();

    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = NUKE_MB_OPTIONS[newIdx];
    if newVal ~= nil and newVal ~= current then
        casual_nuke_mb_modes[name] = newVal;
        -- Wire byte: 0 = exclude, 1 = include.
        autoutil.send_bot_set_casual_nuke_mb_mode(name, (newVal == 'include') and 1 or 0);
    end
end

local function render_heal_combo_centered(name)
    local current = heal_scopes[name] or 'party';
    local var     = get_combo_var(name, 'heal');
    imgui.SetVarValue(var, index_of(HEAL_OPTIONS, current) - 1);

    local label_w = calc_text_w('Heal');
    center_cursor_x(label_w + LABEL_GAP + COMBO_W);
    local row_y = imgui.GetCursorPosY();
    imgui.SetCursorPosY(row_y + LABEL_Y_OFFSET);
    imgui.Text('Heal');
    imgui.SameLine(0, LABEL_GAP);
    imgui.SetCursorPosY(row_y);
    imgui.PushItemWidth(COMBO_W);
    imgui.Combo('##heal_' .. name, var, table.concat(HEAL_LABELS, '\0') .. '\0');
    imgui.PopItemWidth();

    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = HEAL_OPTIONS[newIdx];
    if newVal ~= nil and newVal ~= current then
        heal_scopes[name] = newVal;
        autoutil.send_bot_set_heal_scope(name, newIdx - 1);
    end
end

local function render_add_control_combo_centered(name)
    local current = add_control_modes[name] or 'provoke';
    local var     = get_combo_var(name, 'addctl');
    imgui.SetVarValue(var, index_of(ADD_CTRL_OPTIONS, current) - 1);

    -- Label was previously "Add Control"; renamed to just "Adds" - the
    -- column header for this dropdown is short enough that the combo body
    -- (Provoke / Flash / Provoke & Flash) already conveys the semantics.
    -- "Provoke & Flash" is still the longest option so combo stays at 130.
    local label   = 'Adds';
    local combo_w = 130;
    local label_w = calc_text_w(label);
    center_cursor_x(label_w + LABEL_GAP + combo_w);
    local row_y = imgui.GetCursorPosY();
    imgui.SetCursorPosY(row_y + LABEL_Y_OFFSET);
    imgui.Text(label);
    imgui.SameLine(0, LABEL_GAP);
    imgui.SetCursorPosY(row_y);
    imgui.PushItemWidth(combo_w);
    imgui.Combo('##addctl_' .. name, var, table.concat(ADD_CTRL_LABELS, '\0') .. '\0');
    imgui.PopItemWidth();

    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = ADD_CTRL_OPTIONS[newIdx];
    if newVal ~= nil and newVal ~= current then
        add_control_modes[name] = newVal;
        autoutil.send_bot_set_add_control(name, newIdx - 1);
    end
end

-- THF utility-RA cadence combo. Renders under SATA on main-job THF cards.
-- Picker values come from THF_RA_OPTIONS (seconds); the index 0 entry is
-- the "Off" sentinel that maps to 0 on the wire and makes role_melee's
-- should_ra return false unconditionally.
local function render_thf_ra_combo_centered(name)
    local current = thf_ra_delays[name] or 15;
    local var     = get_combo_var(name, 'thfra');
    local idx     = index_of(THF_RA_OPTIONS, current);
    imgui.SetVarValue(var, idx - 1);

    local label   = 'RA';
    local combo_w = 80;
    local label_w = calc_text_w(label);
    center_cursor_x(label_w + LABEL_GAP + combo_w);
    local row_y = imgui.GetCursorPosY();
    imgui.SetCursorPosY(row_y + LABEL_Y_OFFSET);
    imgui.Text(label);
    imgui.SameLine(0, LABEL_GAP);
    imgui.SetCursorPosY(row_y);
    imgui.PushItemWidth(combo_w);
    imgui.Combo('##thfra_' .. name, var, table.concat(THF_RA_LABELS, '\0') .. '\0');
    imgui.PopItemWidth();

    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = THF_RA_OPTIONS[newIdx];
    if newVal ~= nil and newVal ~= current then
        thf_ra_delays[name] = newVal;
        autoutil.send_bot_set_thf_ra_delay(name, newVal);
    end
end

-- SMN avatar dropdown (#220). Options derived from the bot's known
-- summon spells in the snapshot (knownSummons). Carbuncle is the
-- default — surfaced as the first list entry if learned. Sends
-- SET_SMN_AVATAR (0x24) on change.
local function render_smn_avatar_combo_centered(name)
    local known = smn_known_summons[name] or {};
    if #known == 0 then return; end
    local current = smn_avatars[name] or 296;  -- Carbuncle fallback
    local var     = get_combo_var(name, 'smnavatar');
    local labels  = {};
    for _, spellId in ipairs(known) do
        table.insert(labels, SUMMON_LABEL[spellId] or ('Summon ' .. tostring(spellId)));
    end
    -- Find current index in known list
    local idx = 1;
    for i, spellId in ipairs(known) do
        if spellId == current then idx = i; break; end
    end
    imgui.SetVarValue(var, idx - 1);

    local label   = 'Avatar';
    local combo_w = 110;
    local label_w = calc_text_w(label);
    center_cursor_x(label_w + LABEL_GAP + combo_w);
    local row_y = imgui.GetCursorPosY();
    imgui.SetCursorPosY(row_y + LABEL_Y_OFFSET);
    imgui.Text(label);
    imgui.SameLine(0, LABEL_GAP);
    imgui.SetCursorPosY(row_y);
    imgui.PushItemWidth(combo_w);
    imgui.Combo('##smnavatar_' .. name, var, table.concat(labels, '\0') .. '\0');
    imgui.PopItemWidth();

    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = known[newIdx];
    if newVal ~= nil and newVal ~= current then
        smn_avatars[name] = newVal;
        autoutil.send_smn_avatar(name, newVal);
    end
end

local function render_tank_nudge_centered(name)
    -- Three fixed-width buttons on one row: Fwd / Back / To Me. Short labels
    -- so all three fit comfortably in the card's 210px interior. The card
    -- itself identifies the bot so abbreviated verbs are unambiguous.
    -- Fwd/Back: ai_move.tank_nudge (0=forward toward target, 1=backward away).
    -- To Me:    ai_move.tank_walk_to_me (snap bot to primary's current xyz).
    local BTN_W = 60;
    local GAP   = 4;
    center_cursor_x(BTN_W * 3 + GAP * 2);
    if imgui.Button('Fwd##tnudge_fwd_' .. name, BTN_W, 0) then
        autoutil.send_bot_tank_nudge(name, 0);
    end
    imgui.SameLine(0, GAP);
    if imgui.Button('Back##tnudge_back_' .. name, BTN_W, 0) then
        autoutil.send_bot_tank_nudge(name, 1);
    end
    imgui.SameLine(0, GAP);
    if imgui.Button('To Me##twalk_' .. name, BTN_W, 0) then
        autoutil.send_bot_tank_walk_to_me(name);
    end
end

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
    imgui.Dummy(0, 2);
    local display_name = (name ~= '') and name or '(loading)';
    center_cursor_x(calc_text_w(display_name));
    if is_primary then
        -- Primary gets a faint gold-ish tint so it visually anchors the grid.
        imgui.TextColored(1.0, 0.95, 0.6, 1.0, display_name);
    else
        imgui.TextColored(1.0, 1.0, 1.0, 1.0, display_name);
    end

    -- 2) Centered EXP row. Show denominator as "MAX" at level cap (req=0).
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

    imgui.Dummy(0, 4);

    -- 3) Status icon strip (reserves 2 rows of vertical space).
    render_icons(row and row.effects);

    imgui.Dummy(0, 4);

    -- 4) Mild divider. ImGui's default Separator is a single 1px line - "mild"
    --    enough for the card's interior.
    imgui.Separator();

    -- 5) Centered role toggles. Vertically center the block in the remaining
    --    space below the divider. Primary is INCLUDED - they get the same
    --    role-gated toggles as any headless because the AI runs the same
    --    role tick on them and the server-side setters accept the primary
    --    by name (set_bot_sata_mode / set_bot_heal_scope /
    --    set_add_control_mode / tank_nudge all special-case `m == primary`).
    --    For bots whose role config has no relevant toggle the block is
    --    empty and we skip the centering math entirely.
    local toggle_renderers = {};
    -- Heal-scope dropdown applies to anyone whose role tick reads
    -- state.healScope: role_heal (alliance Cure / -na fallback) and
    -- role_rdm (alliance Cure_P1 + status fallback, see role_rdm.tick).
    -- A future role_smn that picks up the toggle would just add 'smn'
    -- here. Each bot is in exactly one role bucket, so the OR-of-roles
    -- can't double-render the combo for a single card.
    if autoutil.bot_has_role and (autoutil.bot_has_role(name, 'heal')
                               or autoutil.bot_has_role(name, 'rdm')) then
        table.insert(toggle_renderers, render_heal_combo_centered);
    end
    if is_sata_eligible(name) then
        table.insert(toggle_renderers, render_sata_combo_centered);
    end
    -- Casual-nuke controls. role_nuke and role_rdm both run the casual-nuke
    -- path, so both cards get the rotation-size + MB-spell dropdowns.
    if autoutil.bot_has_role and (autoutil.bot_has_role(name, 'nuke')
                               or autoutil.bot_has_role(name, 'rdm')) then
        table.insert(toggle_renderers, render_casual_nuke_rotation_centered);
        table.insert(toggle_renderers, render_casual_nuke_mb_centered);
    end
    -- THF utility-RA cadence. Main-job THF only — the role_melee branch
    -- that uses thfRaDelay keys on is_job(bot, 'THF') which checks main
    -- job, so surfacing it for sub-THF would be a no-op control.
    if is_thf_main(name) then
        table.insert(toggle_renderers, render_thf_ra_combo_centered);
    end
    if is_smn_main(name) then
        table.insert(toggle_renderers, render_smn_avatar_combo_centered);
    end
    if autoutil.bot_has_role and autoutil.bot_has_role(name, 'tank') then
        table.insert(toggle_renderers, render_tank_nudge_centered);
        -- Add Control dropdown is tank-role + PLD-job gated. The PLD
        -- check covers Flash eligibility; a WAR/NIN/RUN tank gets the
        -- nudge buttons but not the Provoke/Flash toggle since they
        -- can't cast Flash.
        if is_pld_flash_eligible(name) then
            table.insert(toggle_renderers, render_add_control_combo_centered);
        end
    end

    if #toggle_renderers > 0 then
        local TOGGLE_SPACING = 4;
        local block_h = #toggle_renderers * TOGGLE_ROW_H
                      + math.max(0, #toggle_renderers - 1) * TOGGLE_SPACING;
        local cur_y     = imgui.GetCursorPosY();
        -- BeginChild's reported inner height isn't directly available here;
        -- approximate "remaining" as CARD_H minus current cursor Y minus a
        -- small bottom padding allowance for the child frame's border.
        local remaining = CARD_H - cur_y - 8;
        local top_pad   = math.max(0, (remaining - block_h) / 2);
        if top_pad > 0 then imgui.Dummy(0, top_pad); end
        for i, fn in ipairs(toggle_renderers) do
            -- Each combo renderer pushes ItemWidth and (less obviously) is
            -- the user-interaction source for the Status tab — opening /
            -- closing a Combo here was traced to global style-stack leaks
            -- (whole UI went dim across all addons). pcall the call so any
            -- error inside one renderer can't strand a half-rendered card
            -- or a leaked push. The outer pcall at the for-loop level
            -- catches the same class of errors, but having it here too
            -- means the rest of the toggle stack still renders for the
            -- current card.
            local ok, err = pcall(fn, name);
            if not ok then
                autoutil.log('AutoBots', 'status_tab toggle error: ' .. tostring(err));
            end
            if i < #toggle_renderers then imgui.Dummy(0, TOGGLE_SPACING); end
        end
    end

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

    -- Stale-data dim: if every row with a packet origin is older than STALE_MS
    -- dim the whole panel. The synthetic primary placeholder uses ms_now() at
    -- collect time and would otherwise read as always-fresh; only consider
    -- rows that came from a 0x191 push for the freshness test.
    local now      = ms_now();
    local anyFresh = false;
    for _, r in ipairs(rows) do
        if r and r.updatedMs and (now - r.updatedMs <= STALE_MS) then
            anyFresh = true; break;
        end
    end

    -- Wrap the body in pcall so a runtime error inside render_card() can't
    -- strand a PushStyleVar without its matching Pop. ImGui's style stack
    -- doesn't unwind on Lua error, and a leaked Alpha push contaminates
    -- every downstream addon's render in the same frame.
    if not anyFresh then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.5); end
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
    if not anyFresh then imgui.PopStyleVar(); end
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
