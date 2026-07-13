_addon.author  = 'Nate';
_addon.name    = 'AutoDps';
_addon.version = '1.0';

require 'common';
require 'imguidef';

local autoutil = require('autoutil');

-- ============================================================
-- Single-window DPS reader for the server-driven 0x17C dps_update packet.
-- Server tracks per-bot DPS in modules/singleplayer/lua/bot_dps.lua and pushes
-- a snapshot to the primary every ~2s while a bot is engaged, plus one final
-- summary on disengage. We accumulate one row per bot, sort by DPS, and render.
-- ============================================================

local CATEGORIES = {
    { key = 'm',  label = 'melee'  },
    { key = 'r',  label = 'ranged' },
    { key = 'w',  label = 'ws'     },
    { key = 'mg', label = 'magic'  },
    { key = 'mb', label = 'burst'  },
    { key = 'ja', label = 'ja'     },
};

-- bots[charId] = { name, isFinal, total, activeMs, dps, cats[6] = {dmg,hits,misses}, last_update_ms }
local bots    = {};
local ui_open = nil;

-- Try to resolve a charId to a friendly display name via Ashita's party
-- manager (ServerId column == charid for PCs in LSB). Falls back to "Bot
-- <id>" so the row is always identifiable.
local function resolve_name(charId)
    local party = AshitaCore:GetDataManager():GetParty();
    for slot = 0, 17 do
        if party:GetMemberServerId(slot) == charId then
            local nm = party:GetMemberName(slot);
            if nm and nm ~= '' then return nm; end
        end
    end
    return string.format('Bot %d', charId);
end

-- Read a little-endian u32 from a 1-indexed byte offset.
local function read_u32_le(data, off)
    return data:byte(off)
         + data:byte(off + 1) * 256
         + data:byte(off + 2) * 65536
         + data:byte(off + 3) * 16777216;
end

local function read_u16_le(data, off)
    return data:byte(off) + data:byte(off + 1) * 256;
end

-- 0x17C layout (1-indexed Lua byte offsets):
--   header[4]
--   CharId       @ 0x05  (u32)
--   IsFinal      @ 0x09  (u8)
--   Padding[3]   @ 0x0A
--   TotalDamage  @ 0x0D  (u32)
--   ActiveMs     @ 0x11  (u32)
--   Categories   @ 0x15  6 × { Damage[u32] + Hits[u16] + Misses[u16] = 8 bytes }
local function on_dps_update(id, size, data)
    if id ~= 0x17c then return; end
    if size < 68 then return; end

    local charId      = read_u32_le(data, 0x05);
    local isFinal     = data:byte(0x09);
    local totalDamage = read_u32_le(data, 0x0D);
    local activeMs    = read_u32_le(data, 0x11);

    local cats = {};
    for i = 0, 5 do
        local base = 0x15 + i * 8;
        cats[i + 1] = {
            damage = read_u32_le(data, base),
            hits   = read_u16_le(data, base + 4),
            misses = read_u16_le(data, base + 6),
        };
    end

    local entry = bots[charId] or { name = resolve_name(charId) };
    entry.isFinal  = (isFinal ~= 0);
    entry.total    = totalDamage;
    entry.activeMs = activeMs;
    entry.cats     = cats;
    entry.dps      = (activeMs > 0) and (totalDamage * 1000.0 / activeMs) or 0;
    entry.last_update_ms = autoutil.get_ms_since_epoch();
    -- If we still don't have a real name (e.g. bot zoned out), retry resolve.
    if entry.name:sub(1, 4) == 'Bot ' then entry.name = resolve_name(charId); end
    bots[charId] = entry;
end

-- ============================================================
-- Render
-- ============================================================

local function fmt_categories(cats)
    local parts = {};
    for i, cat in ipairs(CATEGORIES) do
        local v = cats[i];
        if v and v.damage > 0 then
            local total_swings = v.hits + v.misses;
            local acc_str = total_swings > 0
                and string.format(' %d%%', math.floor(v.hits / total_swings * 100))
                or  '';
            table.insert(parts, string.format('%s %d%s', cat.label, v.damage, acc_str));
        end
    end
    return table.concat(parts, '  ');
end

local function render()
    if ui_open == nil or not imgui.GetVarValue(ui_open) then return; end

    imgui.SetNextWindowSize(640, 360, ImGuiSetCond_FirstUseEver);
    autoutil.push_solid_window_bg();
    if not imgui.Begin('AutoDps', ui_open) then
        imgui.End();
        autoutil.pop_solid_window_bg();
        return;
    end

    if imgui.Button('Reset##dps_reset', 80, 0) then
        bots = {};
    end
    imgui.SameLine();
    imgui.TextDisabled('Server-driven (0x17C); rows turn green on disengage summary');

    imgui.Separator();
    imgui.Dummy(0, 4);

    local sorted = {};
    for _, b in pairs(bots) do table.insert(sorted, b); end
    table.sort(sorted, function(a, b) return a.dps > b.dps; end);

    if #sorted == 0 then
        imgui.TextDisabled('(no data - waiting for server)');
    else
        for _, b in ipairs(sorted) do
            if b.isFinal then imgui.PushStyleColor(ImGuiCol_Text, 0.6, 1.0, 0.6, 1.0); end
            imgui.Text(string.format('%-14s %7.1f dps  %8d dmg  %.0fs',
                b.name, b.dps, b.total, b.activeMs / 1000.0));
            if b.isFinal then imgui.PopStyleColor(); end
            local cat_line = fmt_categories(b.cats or {});
            if cat_line ~= '' then
                imgui.TextDisabled('  ' .. cat_line);
            end
        end
    end

    imgui.End();
    autoutil.pop_solid_window_bg();
end

-- ============================================================
-- Events
-- ============================================================

ashita.register_event('load', function()
    autoutil.tag = 'AutoDps';
    ui_open = imgui.CreateVar(ImGuiVar_BOOLCPP);
    imgui.SetVarValue(ui_open, false);
    autoutil.send_request_server_ident();
end);

ashita.register_event('unload', function()
    if ui_open ~= nil then imgui.DeleteVar(ui_open); ui_open = nil; end
end);

ashita.register_event('incoming_packet', function(id, size, data)
    on_dps_update(id, size, data);
    -- Zone change wipes bot data — they aren't ours anymore.
    if id == 0x00A then bots = {}; end
    return false;
end);

ashita.register_event('command', function(cmd, _nType)
    local args = cmd:args();
    if args[1] ~= '/autodps' then return false; end

    if args[2] == 'reset' then
        bots = {};
        autoutil.log('AutoDps', 'Reset.');
        return true;
    end
    if args[2] == 'hide' then
        if ui_open then imgui.SetVarValue(ui_open, false); end
        return true;
    end
    -- Default / 'show' / 'toggle' / no args — flip visibility.
    if ui_open then imgui.SetVarValue(ui_open, not imgui.GetVarValue(ui_open)); end
    return true;
end);

ashita.register_event('render', function()
    render();
end);
