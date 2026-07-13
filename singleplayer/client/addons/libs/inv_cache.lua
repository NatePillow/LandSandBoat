-- Server-driven inventory cache shared by addons. Char-keyed.
--
-- The server is authoritative for container contents and capacities; this lib
-- mirrors them into a per-char Lua-side table and exposes lookups so each addon
-- doesn't have to re-implement the same plumbing.
--
-- Two data sources feed the cache:
--   1. GET /chars/<name>/inventory — the full snapshot, for any char. One
--      request, one response.
--   2. Retail delta packets (0x020 ITEM_ATTR / 0x01E ITEM_NUM) — the client
--      receives these natively whenever a local-player slot changes, so the
--      snapshot stays fresh without refetching. Local player only; a headless
--      target has no delta source and needs an explicit refetch.
--
-- The snapshot used to arrive as packets (0x16D + 0x16E for the local player,
-- 0x18F + 0x190 for anyone else). That was slow for a structural reason: the
-- map server only flushes a char's outbound queue when a client packet arrives,
-- and each flush is capped at 32 packets. 0x16D made the server push one 0x020
-- per item across all 18 containers, so a few hundred items cost tens of client
-- round-trips. HTTP has neither the queue nor the round-trip gating.
--
-- Wire from the host addon:
--   - call M.on_incoming_packet(id, size, data) at the top of the addon's
--     incoming_packet handler; returns true if the packet was claimed.
--   - call M.send_inv_request(charName) to refresh.
--   - call http_client.tick() once per frame (the host addon already must).
--   - read M.get_bag(charName, bag_id), M.get_container_max(charName, bag_id),
--     M.is_loading(charName) as needed.
--
-- Because each Ashita addon has its own Lua state, every addon that requires
-- this lib maintains its own copy of the cache fed by its own fetches.

local JSON        = require('json')
local http_client = require('http_client')

local M = {}

local INV_REQUEST_DEBOUNCE    = 3.0

-- per_char[name] = { bags[bag_id][slot] = {id,count}, caps[bag_id] = max,
--                    loading = bool, last_request = number, req_gen = number }
--
-- req_gen rises on every fetch or sort. A reply whose generation no longer
-- matches is dropped: without it a slow fetch landing after a newer one (or
-- after a sort) would overwrite fresh data with a stale snapshot and clear
-- `loading` while the newer request is still in flight.
local per_char = {}

local function get_or_make(name)
    if name == nil or name == '' then return nil end
    if per_char[name] == nil then
        per_char[name] = { bags = {}, caps = {}, loading = false,
                           last_request = -INV_REQUEST_DEBOUNCE, req_gen = 0 }
    end
    return per_char[name]
end

local function local_name()
    local party = AshitaCore:GetDataManager():GetParty()
    return (party and party:GetMemberName(0)) or ''
end

-- ============================================================
-- Packet handler. Returns true when the packet was claimed so the host addon
-- can skip further dispatch for that ID.
-- ============================================================
function M.on_incoming_packet(id, size, data)
    if id == 0x020 then
        -- Local-only ITEM_ATTR for one slot.
        local name = local_name()
        local entry = get_or_make(name)
        if entry == nil then return false end
        local count    = struct.unpack('I', data, 5)
        local item_no  = struct.unpack('H', data, 13)
        local category = struct.unpack('B', data, 15)
        local slot     = struct.unpack('B', data, 16)
        if not entry.bags[category] then entry.bags[category] = {} end
        if item_no == 0 then
            entry.bags[category][slot] = nil
        else
            entry.bags[category][slot] = { id = item_no, count = count }
        end
        return true
    end

    if id == 0x01E then
        -- Local-only ITEM_NUM (quantity update).
        local name  = local_name()
        local entry = get_or_make(name)
        if entry == nil then return false end
        local count    = struct.unpack('I', data, 5)
        local category = struct.unpack('B', data, 9)
        local slot     = struct.unpack('B', data, 10)
        if entry.bags[category] and entry.bags[category][slot] then
            if count == 0 then
                entry.bags[category][slot] = nil
            else
                entry.bags[category][slot].count = count
            end
        end
        return true
    end

    return false
end

-- ============================================================
-- Apply a decoded GET /chars/<name>/inventory body onto a cache entry. Bags
-- and caps are rebuilt off to the side and swapped in together so a caller
-- reading mid-parse never sees a half-populated inventory.
-- ============================================================
local function apply_snapshot(entry, snap)
    local bags = {}
    local caps = {}
    for bag_id = 0, 17 do
        -- Server sends a JSON array indexed 0..17; Lua decodes it 1-based.
        caps[bag_id] = tonumber(snap.caps and snap.caps[bag_id + 1]) or 255
    end
    for _, it in ipairs(snap.items or {}) do
        local bag  = tonumber(it.bag)
        local slot = tonumber(it.slot)
        local id   = tonumber(it.itemId)
        local cnt  = tonumber(it.count)
        if bag ~= nil and slot ~= nil and id ~= nil and cnt ~= nil and id ~= 0 and cnt > 0 then
            if bags[bag] == nil then bags[bag] = {} end
            bags[bag][slot] = { id = id, count = cnt }
        end
    end
    entry.bags = bags
    entry.caps = caps
end

-- ============================================================
-- Outgoing: ask the server for a refresh of <charName>'s inventory. Debounced
-- per-char so spamming the UI doesn't flood the link.
--
-- `force` skips the debounce — used by the post-sort refetch, where we know
-- the contents just changed and a stale-cache read would show the pre-sort
-- layout.
-- ============================================================
function M.send_inv_request(charName, force)
    charName = charName or local_name()
    local entry = get_or_make(charName)
    if entry == nil then return end
    local now = os.clock()
    if not force and now - entry.last_request < INV_REQUEST_DEBOUNCE then return end
    entry.last_request = now
    entry.bags         = {}
    entry.caps         = {}
    entry.loading      = true
    entry.req_gen      = entry.req_gen + 1
    local gen          = entry.req_gen

    http_client.get('/chars/' .. charName .. '/inventory', function(code, body, _, err)
        if entry.req_gen ~= gen then return end
        entry.loading = false
        if err ~= nil or code ~= 200 then
            print(string.format('[inv_cache] inventory fetch failed for %s: %s',
                charName, err or ('HTTP ' .. tostring(code))))
            return
        end
        local ok, snap = pcall(function() return JSON:decode(body) end)
        if not ok or type(snap) ~= 'table' then
            print(string.format('[inv_cache] malformed inventory body for %s', charName))
            return
        end
        apply_snapshot(entry, snap)
    end)
end

-- ============================================================
-- Sort (stack-consolidate) a char's container. Server-side equivalent of
-- the standard /sortinv client toggle - mainly for headless bots which
-- have no client to send the standard 0x03A. Server walks the named char's
-- container and merges same-itemId stacks into the minimum number of slots;
-- we then refetch the snapshot so this cache updates in-place.
-- charName must be the caller's primary or a headless owned by them; the
-- server-side applier validates and fails the op on unauthorized targets.
-- bagId defaults to 0 = LOC_INVENTORY (the only one the addon currently
-- needs to sort).
-- ============================================================
function M.send_sort_inventory(charName, bagId)
    if charName == nil or charName == '' then return end
    bagId = bagId or 0

    local entry = get_or_make(charName)
    local gen   = nil
    if entry ~= nil then
        entry.bags    = {}
        entry.caps    = {}
        entry.loading = true
        entry.req_gen = entry.req_gen + 1
        gen           = entry.req_gen
    end

    -- The sort mutates containers, so the server applies it on the main thread
    -- via op_registry. Only once the op reports success are the char_inventory
    -- writes complete — refetching before that would read the pre-sort layout.
    local body = { by = local_name(), bag = bagId }
    http_client.await_op('/chars/' .. charName .. '/sort-inventory', body, nil,
        function(_, err)
            if entry ~= nil and entry.req_gen ~= gen then return end
            if err ~= nil then
                if entry ~= nil then entry.loading = false end
                print(string.format('[inv_cache] sort failed for %s: %s', charName, tostring(err)))
                return
            end
            M.send_inv_request(charName, true)
        end)
end

-- ============================================================
-- Lazy variant: only request if we don't already have a populated cache
-- for charName. Used by char-swap paths (selecting a different char in
-- automog) so flipping between previously-loaded chars is instant — no
-- network round-trip, no UI flicker. Returns true if we already had a
-- cached inventory (caller can render immediately), false if a fetch
-- was triggered (caller may want to show a loading state).
-- ============================================================
function M.ensure_inventory(charName)
    charName = charName or local_name()
    local entry = per_char[charName]
    -- Already loaded with at least one bag → trust the cache. For the local
    -- player the retail delta packets (0x020 / 0x01E) keep it fresh without an
    -- explicit refetch. A cross-char target has no delta source, so callers
    -- that need current data for a headless must send_inv_request themselves.
    if entry and not entry.loading and next(entry.bags) ~= nil then
        return true
    end
    -- Currently in-flight (someone else already asked) → don't double-send.
    if entry and entry.loading then
        return false
    end
    M.send_inv_request(charName)
    return false
end

-- ============================================================
-- Lookups
-- ============================================================

-- Returns the container's max slot count (0+ = available, -1 = not available).
-- Falls back to Ashita's data manager for the local char before the first
-- snapshot lands.
function M.get_container_max(charName, bag_id)
    -- One-arg compatibility: caller didn't pass a name, default to local.
    if bag_id == nil then bag_id = charName; charName = local_name() end
    local entry = per_char[charName]
    if entry and entry.caps[bag_id] ~= nil then
        return entry.caps[bag_id] == 255 and -1 or entry.caps[bag_id]
    end
    if charName == local_name() then
        local cap = AshitaCore:GetDataManager():GetInventory():GetContainerMax(bag_id)
        if cap > 1 then return cap - 1 end
        return -1
    end
    return -1
end

-- Raw access to one bag's slot table (never nil — empty table when absent).
function M.get_bag(charName, bag_id)
    if bag_id == nil then bag_id = charName; charName = local_name() end
    local entry = per_char[charName]
    if entry == nil then return {} end
    return entry.bags[bag_id] or {}
end

-- All bags for a char (rarely needed externally).
function M.get_all(charName)
    charName = charName or local_name()
    local entry = per_char[charName]
    return entry and entry.bags or {}
end

function M.is_loading(charName)
    charName = charName or local_name()
    local entry = per_char[charName]
    return entry and entry.loading or false
end

return M
