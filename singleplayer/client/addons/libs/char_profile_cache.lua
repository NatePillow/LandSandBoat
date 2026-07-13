-- char_profile_cache: per-char snapshot of stats + equipment + jobs/exp,
-- delivered by the server-side 0x1A8 CHAR_PROFILE in response to a
-- 0x1A7 GET_CHAR_PROFILE request. Used by the automog Status tab to render
-- a character's stats / equipment / jobs / exp without the periodic 0x191
-- PARTY_STATUS push having to grow with all that data.
--
-- Usage:
--   local cp = require('char_profile_cache')
--   cp.on_incoming_packet(id, size, data)   -- call from addon's incoming_packet event
--   cp.request(charName)                    -- send 0x1A7 (authoritative target check is server-side)
--   cp.ensure(charName)                     -- request only if not cached/in-flight (debounced)
--   local profile = cp.get(charName)        -- returns nil until reply arrives
--
-- profile shape (after a reply has been parsed):
--   {
--       name        = 'Brutus',
--       mj, ml, sj, sl  = 13, 13, 6, 6,
--       race, face      = 0..7, 0..7,
--       hp_cur, hp_max  = 980, 980,
--       mp_cur, mp_max  = 0, 0,
--       exp_cur, exp_to = 1200, 5000,
--       stat_base       = { STR=12, DEX=10, ... },
--       stat_bonus      = { STR=+4, DEX=-1, ... },
--       atk, def, acc, eva, ratk, racc,
--       resist_meva = { fire, ice, wind, earth, thunder, water, light, dark },
--       equipment   = { [1]=itemId(main), [2]=sub, ..., [16]=back }, 1-indexed
--       updated_ms  = ms_now,
--   }

local M = {}

local GET_CHAR_PROFILE_OPCODE  = 0x1A7
local CHAR_PROFILE_RESP_OPCODE = 0x1A8

-- Debounce repeat requests for the same char within this many seconds. The
-- server's reply is cheap but the addon's per-char cache only needs a refresh
-- when the user actually does something that could move stats / gear.
local REQUEST_DEBOUNCE_S = 1.5

local per_char = {}   -- name -> profile table (or in-flight stub)
local callbacks = {}  -- name -> { fn, fn, ... } pending callbacks

local function ms_now()
    return ashita.timer.get_time and ashita.timer.get_time() or os.clock() * 1000
end

local function fire_callbacks(name)
    local list = callbacks[name]
    if list == nil then return end
    callbacks[name] = nil
    local prof = per_char[name]
    for _, cb in ipairs(list) do
        local ok, err = pcall(cb, prof)
        if not ok then print(string.format('[char_profile] cb error for %s: %s', name, tostring(err))) end
    end
end

-- 24-byte send: 4 header + 16 CharName + 4 padding
function M.request(charName)
    if charName == nil or charName == '' then return end
    local bytes = {}
    for i = 1, 24 do bytes[i] = 0 end
    bytes[1] = 0xA7
    bytes[2] = 0x01
    local nm = charName:sub(1, 15)
    for i = 1, #nm do bytes[4 + i] = nm:byte(i) end
    AddOutgoingPacket(GET_CHAR_PROFILE_OPCODE, bytes)

    -- Mark in-flight so ensure() doesn't double-send.
    local entry = per_char[charName] or {}
    entry.loading           = true
    entry.last_request_ms   = ms_now()
    per_char[charName]      = entry
end

-- Request only if we don't have a recent cache. Returns true if a cache hit
-- (caller can render immediately), false if a fetch was kicked.
function M.ensure(charName)
    if charName == nil or charName == '' then return true end
    local entry = per_char[charName]
    if entry and entry.updated_ms then
        return true  -- cache hit
    end
    if entry and entry.loading then
        local since = ms_now() - (entry.last_request_ms or 0)
        if since < REQUEST_DEBOUNCE_S * 1000 then
            return false  -- already pending
        end
    end
    M.request(charName)
    return false
end

function M.get(charName)
    local entry = per_char[charName]
    if entry and entry.updated_ms then return entry end
    return nil
end

function M.is_loading(charName)
    local entry = per_char[charName]
    return entry ~= nil and entry.loading == true and entry.updated_ms == nil
end

function M.on_loaded(charName, callback)
    if M.get(charName) ~= nil then
        callback(M.get(charName))
        return
    end
    callbacks[charName] = callbacks[charName] or {}
    table.insert(callbacks[charName], callback)
end

-- ============================================================
-- Wire parse. PacketData layout matches the C++ definition in
-- 0x1a8_char_profile.h - keep in sync if either side changes.
-- All multi-byte fields are little-endian.
-- ============================================================
local function u16le(data, off) return data:byte(off) + data:byte(off + 1) * 256 end
local function s16le(data, off)
    local v = u16le(data, off)
    if v >= 0x8000 then v = v - 0x10000 end
    return v
end
local function u32le(data, off)
    return data:byte(off)
         + data:byte(off + 1) * 256
         + data:byte(off + 2) * 65536
         + data:byte(off + 3) * 16777216
end
local function s32le(data, off)
    local v = u32le(data, off)
    if v >= 0x80000000 then v = v - 0x100000000 end
    return v
end

function M.on_incoming_packet(id, size, data)
    if id ~= CHAR_PROFILE_RESP_OPCODE then return false end

    -- Body starts at 5 (after 4-byte header).
    local base = 5

    -- Name[16]
    local name = data:sub(base, base + 15):gsub('%z+.*', '')
    base = base + 16

    -- mj, ml, sj, sl (4 bytes)
    local mj = data:byte(base); local ml = data:byte(base + 1)
    local sj = data:byte(base + 2); local sl = data:byte(base + 3)
    base = base + 4

    -- race, face, padding[2]
    local race = data:byte(base); local face = data:byte(base + 1)
    base = base + 4

    -- HP/MP 32-bit signed each
    local hp_cur = s32le(data, base);     local hp_max = s32le(data, base + 4)
    local mp_cur = s32le(data, base + 8); local mp_max = s32le(data, base + 12)
    base = base + 16

    -- Exp
    local exp_cur = u32le(data, base); local exp_to = u32le(data, base + 4)
    base = base + 8

    -- StatBase[7] uint16
    local stat_keys = { 'STR', 'DEX', 'VIT', 'AGI', 'INT', 'MND', 'CHR' }
    local stat_base = {}
    for i = 1, 7 do
        stat_base[stat_keys[i]] = u16le(data, base + (i - 1) * 2)
    end
    base = base + 14
    -- StatBonus[7] int16
    local stat_bonus = {}
    for i = 1, 7 do
        stat_bonus[stat_keys[i]] = s16le(data, base + (i - 1) * 2)
    end
    base = base + 14

    -- Combat: Atk, Def, Acc, Eva, Ratk, Racc (int16 each)
    local atk  = s16le(data, base);     local def  = s16le(data, base + 2)
    local acc  = s16le(data, base + 4); local eva  = s16le(data, base + 6)
    local ratk = s16le(data, base + 8); local racc = s16le(data, base + 10)
    base = base + 12

    -- ResistMeva[8] int16 (fire, ice, wind, earth, thunder, water, light, dark)
    local resist_keys = { 'fire', 'ice', 'wind', 'earth', 'thunder', 'water', 'light', 'dark' }
    local resist_meva = {}
    for i = 1, 8 do
        resist_meva[resist_keys[i]] = s16le(data, base + (i - 1) * 2)
    end
    base = base + 16

    -- Equipment[16] uint16 (1-indexed in cache for Lua convention)
    local equipment = {}
    for i = 1, 16 do
        equipment[i] = u16le(data, base + (i - 1) * 2)
    end
    base = base + 32

    -- Skills[64] uint16: WorkingSkills copy. Low 15 bits = value, high bit
    -- (0x8000) = CAPPED (vanilla renders capped skills blue). Indexed by skill
    -- id 0..63 (combat 1-12 & 25-31, magic 32-45; see SKILLTYPE server-side).
    local skills = {}
    for i = 0, 63 do
        local raw = u16le(data, base + i * 2)
        skills[i] = { value = raw % 0x8000, capped = raw >= 0x8000 }
    end
    base = base + 128

    if name == nil or name == '' then return true end

    per_char[name] = {
        name        = name,
        mj = mj, ml = ml, sj = sj, sl = sl,
        race = race, face = face,
        hp_cur = hp_cur, hp_max = hp_max,
        mp_cur = mp_cur, mp_max = mp_max,
        exp_cur = exp_cur, exp_to = exp_to,
        stat_base   = stat_base,
        stat_bonus  = stat_bonus,
        atk = atk, def = def, acc = acc, eva = eva,
        ratk = ratk, racc = racc,
        resist_meva = resist_meva,
        equipment   = equipment,
        skills      = skills,
        updated_ms  = ms_now(),
        loading     = false,
    }
    fire_callbacks(name)
    return true
end

function M.invalidate(charName)
    if charName == nil or charName == '' then return end
    per_char[charName] = nil
end

return M
