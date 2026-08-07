-- Role AI tab: all per-bot AI settings, grouped by role section.
--
-- Sibling of the "Alliance AI" tab (which holds alliance-wide behavior).
-- This tab is the per-bot counterpart: role sections (Tank / Melee / Heal /
-- RDM / Nuke / BRD / SMN), each listing the specific characters currently in
-- that role, with their per-bot controls underneath.
--
-- The controls and their state mirrors moved here from status_tab.lua (Status
-- is now a view-only monitor). The BRD song-roster moved here from the old
-- role_ai_tab.lua (which was renamed to item_ai_tab.lua — it holds the
-- per-role item-usage policy).
--
-- Layout: two columns (COL_W each), sections packed whole — a role section is
-- never split across the column boundary. Section heights are estimated at
-- render time and the split index chosen to balance the two columns.
--
-- Roster source:
--   * headless bots  -> snap.bots[] rows (authoritative .role incl. brd/smn),
--                       fed via role_ai_tab.apply_bot_state.
--   * primary        -> Ashita party slot 0; role resolved from cfg.roles /
--                       main job (snap.bots never includes the primary).
-- The server-side setters accept the primary by name (they special-case
-- m == primary), so the primary gets the same role-gated controls as any
-- headless bot.

require 'imguidef';

local autoutil = require('autoutil');

local role_ai_tab = {};

-----------------------------------
-- Per-bot state mirrors (moved from status_tab). Seeded from the /bot-state
-- snapshot; UI writes update these AND fire the wire packet.
-----------------------------------
local combo_vars            = {};   -- ['<name>_<tag>'] = ImVar
local sata_modes            = {};   -- ['<name>'] = 'combined' / 'split' / 'saonly'
local thf_ra_delays         = {};   -- ['<name>'] = seconds, 0 = Off (default 15)
local heal_scopes           = {};   -- ['<name>'] = 'party' / 'allianceAssist' / 'allianceMain'
local add_control_modes     = {};   -- ['<name>'] = 'provoke' / 'flash' / 'both'
local smn_avatars           = {};   -- ['<name>'] = avatar spell ID (296 default)
local smn_known_summons     = {};   -- ['<name>'] = { spellId, ... } filtered to learned
local casual_nuke_rotations = {};   -- ['<name>'] = 1..6, 0 = All
local casual_nuke_mb_modes  = {};   -- ['<name>'] = 'include' / 'exclude'
-- BRD per-bot song roster (moved from old role_ai_tab, #252).
local brd_roster            = {};   -- ['<name>'] = { slot0, slot1, slot2, slot3 } spell IDs, 0 = Auto
local brd_known             = {};   -- ['<name>'] = { spellId, ... } learned songs
-- Roster for sectioning: array of { name, role } from snap.bots (headless
-- bots). The primary is injected separately at render time.
local bot_rows              = {};

-----------------------------------
-- Option constants (moved from status_tab).
-----------------------------------
local SATA_OPTIONS = { 'combined', 'split',     'saonly' };
local SATA_LABELS  = { 'Combined', 'Split',     'SA Only' };
local HEAL_OPTIONS = { 'party',    'allianceAssist',  'allianceMain' };
local HEAL_LABELS  = { 'Party',    'Alliance Assist', 'Alliance Main' };
local ADD_CTRL_OPTIONS = { 'provoke', 'flash', 'both'            };
local ADD_CTRL_LABELS  = { 'Provoke', 'Flash', 'Provoke & Flash' };
local THF_RA_OPTIONS = { 0,     5,    10,    15,    20,    30    };
local THF_RA_LABELS  = { 'Off', '5s', '10s', '15s', '20s', '30s' };
local NUKE_ROT_OPTIONS = { 1,   2,   3,   4,   5,   6,   0     };
local NUKE_ROT_LABELS  = { '1', '2', '3', '4', '5', '6', 'All' };
local NUKE_MB_OPTIONS = { 'include', 'exclude' };
local NUKE_MB_LABELS  = { 'Include', 'Exclude' };
local SLOT_LABELS     = { 'Melee 1', 'Melee 2', 'Mage 1', 'Mage 2' };

-- SMN avatar dropdown labels — keyed by summon spell ID.
local SUMMON_LABEL = {
    [288] = 'Fire Spirit',  [289] = 'Ice Spirit',   [290] = 'Air Spirit',
    [291] = 'Earth Spirit', [292] = 'Thunder Spirit', [293] = 'Water Spirit',
    [294] = 'Light Spirit', [295] = 'Dark Spirit',  [296] = 'Carbuncle',
    [297] = 'Fenrir',       [298] = 'Ifrit',        [299] = 'Titan',
    [300] = 'Leviathan',    [301] = 'Garuda',       [302] = 'Shiva',
    [303] = 'Ramuh',        [304] = 'Diabolos',
};

-- BRD song spell-id → display name. Hardcoded (see old role_ai_tab); extend
-- alongside the server-side BRD_SONG_CATALOGUE.
local SONG_LABEL = {
    [394] = 'Valor Minuet',    [395] = 'Valor Minuet II',  [396] = 'Valor Minuet III',
    [397] = 'Valor Minuet IV', [398] = 'Valor Minuet V',   [399] = 'Sword Madrigal',
    [400] = 'Blade Madrigal',  [419] = 'Advancing March',  [420] = 'Victory March',
    [417] = 'Honor March',     [386] = 'Mage\'s Ballad',   [387] = 'Mage\'s Ballad II',
    [388] = 'Mage\'s Ballad III', [389] = 'Knight\'s Minne', [390] = 'Knight\'s Minne II',
    [391] = 'Knight\'s Minne III', [392] = 'Knight\'s Minne IV', [393] = 'Knight\'s Minne V',
};
local function song_label(spellId)
    if spellId == 0 then return 'Auto'; end
    return SONG_LABEL[spellId] or string.format('#%d', spellId);
end

-----------------------------------
-- Snapshot ingest. Called from autobots_ui.apply_server_snapshot with the
-- bots[] array (each row has name + role + sataMode + healScope + ...).
-- Populates every per-bot mirror plus the sectioning roster.
-----------------------------------
function role_ai_tab.apply_bot_state(bots_arr)
    if type(bots_arr) ~= 'table' then return; end
    brd_roster = {};
    brd_known  = {};
    bot_rows   = {};
    for _, row in ipairs(bots_arr) do
        local name = (type(row.name) == 'string') and row.name or nil;
        if name and name ~= '' then
            if type(row.sataMode)         == 'string' then sata_modes[name]            = row.sataMode;         end
            if type(row.healScope)        == 'string' then heal_scopes[name]           = row.healScope;        end
            if type(row.addControlMode)   == 'string' then add_control_modes[name]     = row.addControlMode;   end
            if type(row.thfRaDelay)       == 'number' then thf_ra_delays[name]         = row.thfRaDelay;       end
            if type(row.smnAvatarSpellId) == 'number' then smn_avatars[name]           = row.smnAvatarSpellId; end
            if type(row.knownSummons)     == 'table'  then smn_known_summons[name]     = row.knownSummons;     end
            if type(row.casualNukeRotation) == 'number' then casual_nuke_rotations[name] = row.casualNukeRotation; end
            if type(row.casualNukeMbMode)   == 'string' then casual_nuke_mb_modes[name]  = row.casualNukeMbMode;   end

            -- BRD roster mirror (only meaningful for brd rows, but the
            -- songRoster field is always present for wire stability).
            if row.role == 'brd' then
                local r = row.songRoster or { 0, 0, 0, 0 };
                brd_roster[name] = {
                    tonumber(r[1]) or 0, tonumber(r[2]) or 0,
                    tonumber(r[3]) or 0, tonumber(r[4]) or 0,
                };
                brd_known[name] = {};
                for _, spellId in ipairs(row.knownSongs or {}) do
                    if type(spellId) == 'number' then
                        table.insert(brd_known[name], spellId);
                    end
                end
            end

            -- Keep EVERY named headless, even when the snapshot role is nil
            -- (st.role == Idle until the bot is assigned a combat role — e.g.
            -- standing around out of a fight). build_sections resolves the
            -- section from cfg.roles / job when this snapshot role is absent.
            table.insert(bot_rows, { name = name, role = (type(row.role) == 'string') and row.role or nil });
        end
    end
end

-----------------------------------
-- imgui var cache + small utilities (moved from status_tab).
-----------------------------------
local function get_combo_var(name, tag)
    local key = name .. '_' .. tag;
    local v   = combo_vars[key];
    if v == nil then
        v = imgui.CreateVar(ImGuiVar_INT32);
        combo_vars[key] = v;
    end
    return v;
end

local function index_of(tbl, val)
    for i, v in ipairs(tbl) do
        if v == val then return i; end
    end
    return 1;
end

-----------------------------------
-- Ashita party job lookup + job gates (moved from status_tab).
-----------------------------------
local JOB_THF = 6;
local JOB_PLD = 7;
local JOB_BRD = 10;
local JOB_SMN = 15;

local function primary_name_now()
    local party = AshitaCore:GetDataManager():GetParty();
    return (party and party:GetMemberName(0)) or '';
end

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

local function is_sata_eligible(name)
    local mj, ml, sj, sl = lookup_jobs(name);
    if mj == nil then return false; end
    if mj == JOB_THF and (ml or 0) >= 30 then return true; end
    if sj == JOB_THF and (sl or 0) >= 30 then return true; end
    return false;
end

local function is_pld_flash_eligible(name)
    local mj, ml = lookup_jobs(name);
    if mj == nil then return false; end
    return mj == JOB_PLD and (ml or 0) >= 25;
end

local function is_smn_main(name)
    return lookup_jobs(name) == JOB_SMN;
end

local function is_thf_main(name)
    return lookup_jobs(name) == JOB_THF;
end

-- Valid section keys (must match SECTION_ORDER below). Declared here so the
-- resolver can validate a snapshot role before SECTION_LABEL exists.
local SECTION_SET = {
    tank = true, melee = true, heal = true, rdm = true,
    nuke = true, brd = true, smn = true,
};

-- Main-job → section fallback when cfg.roles can't place a char (cfg has no
-- brd/smn bucket, and a brand-new alliance may not list everyone). BRD/SMN
-- are job-unique so they win over cfg; everything else defers to cfg first.
local JOB_SECTION = {
    [3] = 'heal', [20] = 'heal',                 -- WHM, SCH
    [4] = 'nuke', [21] = 'nuke',                 -- BLM, GEO
    [5] = 'rdm',                                 -- RDM
    [7] = 'tank', [13] = 'tank', [22] = 'tank',  -- PLD, NIN, RUN
    [10] = 'brd',                                -- BRD
    [15] = 'smn',                                -- SMN
    -- everything else falls through to 'melee'
};

-- Resolve a char's role section (works for headless bots AND the primary).
-- Priority:
--   1. the snapshot's combat role when present (authoritative in a fight),
--   2. job-unique BRD / SMN (cfg has no bucket for these),
--   3. alliance config role bucket (respects the user's tank-vs-melee choice
--      a PLD/NIN can't resolve by job alone),
--   4. job → section map, defaulting to melee.
-- The snapshot role is nil while a bot is Idle (out of combat), so steps 2-4
-- carry the section assignment the rest of the time.
local function resolve_role(name, snapRole)
    if snapRole and SECTION_SET[snapRole] then return snapRole; end
    local mj = lookup_jobs(name);
    if mj == JOB_BRD then return 'brd'; end
    if mj == JOB_SMN then return 'smn'; end
    for _, key in ipairs({ 'tank', 'heal', 'rdm', 'nuke', 'melee' }) do
        if autoutil.bot_has_role and autoutil.bot_has_role(name, key) then return key; end
    end
    return JOB_SECTION[mj or 0] or 'melee';
end

-----------------------------------
-- Row-layout constants. Controls render left-aligned under a member's name,
-- indented, with the combo at a fixed X so combos align down the column.
-----------------------------------
local COL_W          = 304;
local MEMBER_INDENT  = 14;
local CTRL_LABEL_W   = 96;
local CTRL_COMBO_W   = 150;
local LABEL_Y_OFFSET = 3;   -- nudge label down to center against combo frame

-- Approx pixel heights for the two-column packing estimate.
local H_HEADER   = 26;
local H_NAME     = 20;
local H_CTRL_ROW = 24;
local H_MEMBER_GAP  = 6;
local H_SECTION_GAP = 10;

-- One "Label  [combo]" row. combo_id must be unique (##tag + name).
local function combo_row(label, combo_id, var, joined, combo_w)
    combo_w = combo_w or CTRL_COMBO_W;
    local x0    = imgui.GetCursorPosX();
    local row_y = imgui.GetCursorPosY();
    imgui.SetCursorPosX(x0 + MEMBER_INDENT);
    imgui.SetCursorPosY(row_y + LABEL_Y_OFFSET);
    imgui.Text(label);
    imgui.SameLine(x0 + MEMBER_INDENT + CTRL_LABEL_W);
    imgui.SetCursorPosY(row_y);
    imgui.PushItemWidth(combo_w);
    imgui.Combo(combo_id, var, joined);
    imgui.PopItemWidth();
end

-----------------------------------
-- Per-control row renderers. Each renders its row(s) and fires the setter on
-- change, mirroring the proven status_tab logic (only the layout wrapper
-- changed from card-centered to row-under-name).
-----------------------------------
local function render_heal_row(name)
    local current = heal_scopes[name] or 'party';
    local var     = get_combo_var(name, 'heal');
    imgui.SetVarValue(var, index_of(HEAL_OPTIONS, current) - 1);
    combo_row('Heal Scope', '##heal_' .. name, var, table.concat(HEAL_LABELS, '\0') .. '\0');
    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = HEAL_OPTIONS[newIdx];
    if newVal ~= nil and newVal ~= current then
        heal_scopes[name] = newVal;
        autoutil.send_bot_set_heal_scope(name, newIdx - 1);
    end
end

local function render_sata_row(name)
    local current = sata_modes[name] or 'combined';
    local var     = get_combo_var(name, 'sata');
    imgui.SetVarValue(var, index_of(SATA_OPTIONS, current) - 1);
    combo_row('SATA', '##sata_' .. name, var, table.concat(SATA_LABELS, '\0') .. '\0');
    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = SATA_OPTIONS[newIdx];
    if newVal ~= nil and newVal ~= current then
        sata_modes[name] = newVal;
        autoutil.send_bot_set_sata_mode(name, newIdx - 1);
    end
end

local function render_thf_ra_row(name)
    local current = thf_ra_delays[name] or 15;
    local var     = get_combo_var(name, 'thfra');
    imgui.SetVarValue(var, index_of(THF_RA_OPTIONS, current) - 1);
    combo_row('RA Cadence', '##thfra_' .. name, var, table.concat(THF_RA_LABELS, '\0') .. '\0', 80);
    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = THF_RA_OPTIONS[newIdx];
    if newVal ~= nil and newVal ~= current then
        thf_ra_delays[name] = newVal;
        autoutil.send_bot_set_thf_ra_delay(name, newVal);
    end
end

local function render_nuke_rotation_row(name)
    local current = casual_nuke_rotations[name] or 3;
    local var     = get_combo_var(name, 'nukerot');
    imgui.SetVarValue(var, index_of(NUKE_ROT_OPTIONS, current) - 1);
    combo_row('Nuke Rotation', '##nukerot_' .. name, var, table.concat(NUKE_ROT_LABELS, '\0') .. '\0', 80);
    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = NUKE_ROT_OPTIONS[newIdx];
    if newVal ~= nil and newVal ~= current then
        casual_nuke_rotations[name] = newVal;
        autoutil.send_bot_set_casual_nuke_rotation(name, newVal);
    end
end

local function render_nuke_mb_row(name)
    local current = casual_nuke_mb_modes[name] or 'include';
    local var     = get_combo_var(name, 'nukemb');
    imgui.SetVarValue(var, index_of(NUKE_MB_OPTIONS, current) - 1);
    combo_row('MB Spells', '##nukemb_' .. name, var, table.concat(NUKE_MB_LABELS, '\0') .. '\0');
    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = NUKE_MB_OPTIONS[newIdx];
    if newVal ~= nil and newVal ~= current then
        casual_nuke_mb_modes[name] = newVal;
        autoutil.send_bot_set_casual_nuke_mb_mode(name, (newVal == 'include') and 1 or 0);
    end
end

local function render_add_control_row(name)
    local current = add_control_modes[name] or 'provoke';
    local var     = get_combo_var(name, 'addctl');
    imgui.SetVarValue(var, index_of(ADD_CTRL_OPTIONS, current) - 1);
    combo_row('Adds', '##addctl_' .. name, var, table.concat(ADD_CTRL_LABELS, '\0') .. '\0');
    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = ADD_CTRL_OPTIONS[newIdx];
    if newVal ~= nil and newVal ~= current then
        add_control_modes[name] = newVal;
        autoutil.send_bot_set_add_control(name, newIdx - 1);
    end
end

local function render_smn_avatar_row(name)
    local known = smn_known_summons[name] or {};
    if #known == 0 then return; end
    local current = smn_avatars[name] or 296;
    local var     = get_combo_var(name, 'smnavatar');
    local labels  = {};
    for _, spellId in ipairs(known) do
        table.insert(labels, SUMMON_LABEL[spellId] or ('Summon ' .. tostring(spellId)));
    end
    local idx = 1;
    for i, spellId in ipairs(known) do
        if spellId == current then idx = i; break; end
    end
    imgui.SetVarValue(var, idx - 1);
    combo_row('Avatar', '##smnavatar_' .. name, var, table.concat(labels, '\0') .. '\0', 120);
    local newIdx = imgui.GetVarValue(var) + 1;
    local newVal = known[newIdx];
    if newVal ~= nil and newVal ~= current then
        smn_avatars[name] = newVal;
        autoutil.send_smn_avatar(name, newVal);
    end
end

-- Tank actions: nudge Fwd / Back / To Me. Commands, not settings, but
-- co-located with the tank's other knobs.
local function render_tank_actions_row(name)
    local BTN_W = 58;
    local GAP   = 4;
    local x0    = imgui.GetCursorPosX();
    local row_y = imgui.GetCursorPosY();
    -- 'Position' label in the label column, then the buttons at the combo
    -- column X so they line up with the dropdowns on the other control rows.
    imgui.SetCursorPosX(x0 + MEMBER_INDENT);
    imgui.SetCursorPosY(row_y + LABEL_Y_OFFSET);
    imgui.Text('Position');
    imgui.SameLine(x0 + MEMBER_INDENT + CTRL_LABEL_W);
    imgui.SetCursorPosY(row_y);
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

-- BRD song roster: 4 stacked slot rows (front/back cluster). Sends the whole
-- roster on any change (server overwrites all 4 slots per packet).
local function render_brd_roster_rows(name)
    local roster = brd_roster[name] or { 0, 0, 0, 0 };
    local known  = brd_known[name]  or {};
    local options = { 0 };  -- Auto sentinel
    for _, sid in ipairs(known) do table.insert(options, sid); end
    local labels = {};
    for _, sid in ipairs(options) do table.insert(labels, song_label(sid)); end
    local joined = table.concat(labels, '\0') .. '\0';

    for slotIdx = 1, 4 do
        local currentSpell = roster[slotIdx] or 0;
        local currentIdx = 0;
        for i, sid in ipairs(options) do
            if sid == currentSpell then currentIdx = i - 1; break; end
        end
        local var = get_combo_var(name, 'brdslot' .. slotIdx);
        imgui.SetVarValue(var, currentIdx);
        combo_row(SLOT_LABELS[slotIdx], string.format('##brdslot_%s_%d', name, slotIdx), var, joined, 130);
        local newIdx = imgui.GetVarValue(var);
        if newIdx ~= currentIdx then
            local newSpell = options[newIdx + 1] or 0;
            roster[slotIdx] = newSpell;
            brd_roster[name] = roster;
            autoutil.send_brd_song_roster(name, roster[1], roster[2], roster[3], roster[4]);
        end
    end
end

-----------------------------------
-- Section definitions: which controls a member gets, and a row-count estimate
-- for the packing pass. Keyed by section role key.
-----------------------------------
local SECTION_ORDER = { 'tank', 'melee', 'heal', 'rdm', 'nuke', 'brd', 'smn' };
local SECTION_LABEL = {
    tank = 'Tank', melee = 'Melee', heal = 'Heal', rdm = 'RDM',
    nuke = 'Nuke', brd = 'BRD', smn = 'SMN',
};

-- Estimated control-row count for one member (drives height packing only).
local function control_rows_for(sectionKey, name)
    if sectionKey == 'tank'  then return 1 + (is_pld_flash_eligible(name) and 1 or 0); end
    if sectionKey == 'melee' then return (is_sata_eligible(name) and 1 or 0) + (is_thf_main(name) and 1 or 0); end
    if sectionKey == 'heal'  then return 1; end
    if sectionKey == 'rdm'   then return 3; end
    if sectionKey == 'nuke'  then return 2; end
    if sectionKey == 'brd'   then return 4; end
    if sectionKey == 'smn'   then return (#(smn_known_summons[name] or {}) > 0) and 1 or 0; end
    return 0;
end

-- Render one member's controls (already inside the section). Show-empty: the
-- name header always renders even when the member has no applicable control.
local function render_member(sectionKey, member)
    local name = member.name;
    -- Dim the name when this char has no applicable control in its section
    -- (show-empty member — e.g. a non-THF melee, or a SMN with no learned
    -- avatars), so it reads as "listed but nothing to set here".
    if not member.hasCtl then
        imgui.TextDisabled(name);
    else
        imgui.TextColored(1.0, 1.0, 1.0, 1.0, name);
    end

    if sectionKey == 'tank' then
        render_tank_actions_row(name);
        if is_pld_flash_eligible(name) then render_add_control_row(name); end
    elseif sectionKey == 'melee' then
        if is_sata_eligible(name) then render_sata_row(name); end
        if is_thf_main(name)      then render_thf_ra_row(name); end
    elseif sectionKey == 'heal' then
        render_heal_row(name);
    elseif sectionKey == 'rdm' then
        render_heal_row(name);
        render_nuke_rotation_row(name);
        render_nuke_mb_row(name);
    elseif sectionKey == 'nuke' then
        render_nuke_rotation_row(name);
        render_nuke_mb_row(name);
    elseif sectionKey == 'brd' then
        render_brd_roster_rows(name);
    elseif sectionKey == 'smn' then
        render_smn_avatar_row(name);
    end

    imgui.Dummy(0, H_MEMBER_GAP);
end

local function render_section(section)
    autoutil.section_head(SECTION_LABEL[section.key] or section.key);
    for _, member in ipairs(section.members) do
        render_member(section.key, member);
    end
end

-- Estimated pixel height of a section (header + members).
local function section_height(section)
    local h = H_HEADER + H_SECTION_GAP;
    for _, member in ipairs(section.members) do
        h = h + H_NAME + control_rows_for(section.key, member.name) * H_CTRL_ROW + H_MEMBER_GAP;
    end
    return h;
end

-----------------------------------
-- Build the ordered list of non-empty sections. Members = primary (if their
-- role lands in that section) + every headless bot with that role. Primary
-- first, then alphabetical.
-----------------------------------
local function build_sections()
    local buckets = {};  -- roleKey -> { {name, isPrimary}, ... }
    for _, key in ipairs(SECTION_ORDER) do buckets[key] = {}; end

    -- snap.bots role by lowercased name — authoritative combat role when the
    -- bot is in a fight; usually nil out of combat, and snap.bots only carries
    -- the bots the server could name-resolve at snapshot time (often a subset).
    local snapRole = {};
    for _, r in ipairs(bot_rows) do snapRole[r.name:lower()] = r.role; end

    local primary = primary_name_now();
    local plower  = (primary ~= '') and primary:lower() or nil;
    local seen    = {};

    local function add(name)
        if type(name) ~= 'string' or name == '' then return; end
        local lname = name:lower();
        if seen[lname] then return; end
        seen[lname] = true;
        local role = resolve_role(name, snapRole[lname]);
        if buckets[role] ~= nil then
            table.insert(buckets[role], {
                name = name,
                isPrimary = (plower ~= nil and lname == plower),
                hasCtl = control_rows_for(role, name) > 0,
            });
        end
    end

    -- Roster = primary + every sessioned alliance PC (the same source the Skill
    -- Ups tab uses — complete and reliable). snap.bots is only a supplement for
    -- any name not yet in the alliance-PC list.
    add(primary);
    for _, m in ipairs(autoutil.alliance_pcs or {}) do add(m.name); end
    for _, r in ipairs(bot_rows) do add(r.name); end

    local sections = {};
    for _, key in ipairs(SECTION_ORDER) do
        local members = buckets[key];
        if #members > 0 then
            table.sort(members, function(a, b)
                -- Members with controls first; dimmed (no-control) names sink
                -- to the bottom of the section. Then primary first, then name.
                if a.hasCtl ~= b.hasCtl then return a.hasCtl; end
                if a.isPrimary ~= b.isPrimary then return a.isPrimary; end
                return a.name < b.name;
            end);
            table.insert(sections, { key = key, label = SECTION_LABEL[key], members = members });
        end
    end
    return sections;
end

-- Choose the split index that best balances the two columns without splitting
-- a section. Returns k such that sections[1..k] go left, [k+1..n] go right.
local function balance_split(sections)
    local n = #sections;
    if n <= 1 then return n; end
    local total = 0;
    for _, s in ipairs(sections) do total = total + section_height(s); end
    local best_k, best_diff, prefix = 1, math.huge, 0;
    -- k ranges 1..n-1 so the right column keeps at least one section.
    for k = 1, n - 1 do
        prefix = prefix + section_height(sections[k]);
        local diff = math.abs(prefix - (total - prefix));
        if diff < best_diff then best_diff = diff; best_k = k; end
    end
    return best_k;
end

-----------------------------------
-- Column divider (mirrors item_ai_tab / autobots_ui _uc helper).
-----------------------------------
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

-- A bare imgui.Separator() spans the whole window content region and bleeds
-- across the column divider into the right column. Clip it to this column's
-- X range [x0, x0+COL_W] (same technique as autobots_ui.left_sep).
local function clipped_sep(x0)
    local _, wy = imgui.GetWindowPos();
    local wh    = imgui.GetWindowHeight();
    imgui.PushClipRect(x0, wy, x0 + COL_W, wy + wh, true);
    imgui.Separator();
    imgui.PopClipRect();
end

local function render_column(id, sections, lo, hi)
    imgui.BeginGroup();
    -- Left screen-X of this column (captured before Dummy advances the cursor)
    -- so the clipped section rule stays within the column even as the right
    -- column starts at a different X.
    local col_x = imgui.GetCursorScreenPos();
    imgui.Dummy(COL_W, 0);
    local first = true;
    for i = lo, hi do
        if not first then clipped_sep(col_x); imgui.Dummy(0, 4); end
        first = false;
        render_section(sections[i]);
    end
    imgui.EndGroup();
end

-- Auto-refresh the alliance-PC roster while this tab is shown so it populates
-- without needing the window reopened (send_list_alliance_pcs otherwise only
-- fires on window open). Throttled via os.time() (wall-clock SECONDS) — a
-- reliable unit, unlike ashita.timer.get_time whose scale isn't guaranteed to
-- be milliseconds (that mismatch is what left the Status tab permanently dim).
local last_roster_fetch_s = 0;
local ROSTER_REFRESH_S    = 4;

function role_ai_tab.render()
    -- Kick a roster refresh on entry + every few seconds (first call fires
    -- immediately since last_roster_fetch_s starts at 0), so switching to this
    -- tab fills the list within a frame instead of after a window reopen.
    local now_s = os.time();
    if now_s - last_roster_fetch_s >= ROSTER_REFRESH_S then
        last_roster_fetch_s = now_s;
        if autoutil.send_list_alliance_pcs then autoutil.send_list_alliance_pcs(); end
    end

    -- pcall guard — a leaked Push* from a mid-render error contaminates every
    -- downstream addon's frame. Matches item_ai_tab / status_tab.
    local ok, err = pcall(function()
        local sections = build_sections();
        if #sections == 0 then
            imgui.TextColored(0.85, 0.85, 0.85, 1.0, 'No party / alliance bots yet.');
            return;
        end

        local k = balance_split(sections);
        render_column('##roleai_left', sections, 1, k);
        if k < #sections then
            imgui.SameLine(0, 6);
            render_col_divider();
            imgui.SameLine(0, 6);
            render_column('##roleai_right', sections, k + 1, #sections);
        end
    end);
    if not ok then
        autoutil.log('AutoBots', 'role_ai_tab error: ' .. tostring(err));
    end
end

return role_ai_tab;
