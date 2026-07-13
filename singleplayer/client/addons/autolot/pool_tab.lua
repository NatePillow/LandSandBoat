-- AutoLot Treasure Pool tab.
--
-- Two responsibilities:
--   1. tick() — every frame, snapshot the live treasure pool from
--      AshitaCore:GetDataManager():GetInventory():GetTreasureItem(0..9) and
--      maintain a deduped cache (by item id) of the last UNIQUE_CACHE_SIZE
--      items seen this session. Same item dropping twice updates `last_seen`
--      but stays one entry in the cache.
--   2. draw() — render the live slots (status ≠ 0) as read-only rows.
--
-- The cache is exposed via M.get_cache() for the Drop History tab to render
-- the same data sorted by recency. The + Group / Lot List per-row actions live
-- on that Drop History tab; the live pool is display-only (a pool slot is
-- transient, so the persistent history entry is the better action surface).

local M = {}

local autoutil
local groups_tab

-- ============================================================
-- State
-- ============================================================

local UNIQUE_CACHE_SIZE = 100
local POOL_SIZE         = 10  -- FFXI's treasure pool has exactly 10 slots
local POOL_LIFETIME_S   = 300 -- server treasure_livetime = 5min (treasure_pool.cpp)

-- Per-slot appearance tracking for a client-derived TTL. Ashita v3's
-- treasureitem_t.TimeToLive reads as a huge/garbage value in this build (same
-- unreliable-field class as .Status, which the scan below already works
-- around), so instead of trusting it we time each slot's current item from
-- when we first observed it and count down against POOL_LIFETIME_S. slot ->
-- { id, first = os.time() }.
local pool_slot_seen = {}

-- Live snapshot, indexed by 0..POOL_SIZE-1. Each slot: { id, count, lot,
-- winning_lot, winner_name, ttl } or nil for empty slots.
local live_pool = {}

-- Cache, deduped by item id. Array { entry, ... } newest first. Each entry:
--   { id, name, first_seen, last_seen }
-- Also indexed by id in cache_by_id for O(1) update on re-drop.
local cache       = {}
local cache_by_id = {}

-- ============================================================
-- Init + lifecycle
-- ============================================================

function M.init(deps)
    autoutil   = deps.autoutil
    groups_tab = deps.groups_tab
end

function M.on_load()   end
function M.on_unload() end

-- ============================================================
-- Pool scan + cache update (called once per render frame from autolot.lua)
-- ============================================================

local function item_name(res_mgr, id)
    if id == nil or id == 0 then return '' end
    local res = res_mgr:GetItemById(id)
    if res == nil or res.Name == nil then return '' end
    return tostring(res.Name[0]):gsub('%z', '')
end

-- Ids present in the pool on the previous tick. tick() runs every render
-- frame, so an item sitting in the pool is re-noted hundreds of times; we only
-- bump `count` on the absent->present edge (a genuinely new sighting), not
-- every frame. Otherwise the live entry's count ticks upward continuously.
local seen_prev_frame = {}

local function note_in_cache(id, name, is_new_sighting)
    local now = os.time()
    local existing = cache_by_id[id]
    if existing ~= nil then
        existing.last_seen = now
        if is_new_sighting then
            existing.count = (existing.count or 1) + 1
        end
        return
    end
    local entry = { id = id, name = name, first_seen = now, last_seen = now, count = 1 }
    table.insert(cache, 1, entry)
    cache_by_id[id] = entry
    -- Evict the oldest when over budget.
    while #cache > UNIQUE_CACHE_SIZE do
        local dropped = table.remove(cache)
        if dropped ~= nil then cache_by_id[dropped.id] = nil end
    end
end

function M.tick()
    -- Try DataManager first (the convenience wrapper), fall back to the
    -- MemoryManager direct path if DataManager's inventory isn't wired.
    -- Some Ashita v3 builds expose treasure pool only through one of
    -- the two; iterating both lets us survive either configuration
    -- without the user having to know which.
    local dm  = AshitaCore.GetDataManager   and AshitaCore:GetDataManager()
    local mm  = AshitaCore.GetMemoryManager and AshitaCore:GetMemoryManager()
    local invs = {}
    if dm and dm.GetInventory then table.insert(invs, dm:GetInventory()) end
    if mm and mm.GetInventory then table.insert(invs, mm:GetInventory()) end

    local res_mgr = AshitaCore:GetResourceManager()
    local seen_this_frame = {}
    for slot = 0, POOL_SIZE - 1 do
        -- Walk both inventory accessors; first one to return a non-empty
        -- TreasureItem for this slot wins. ti.Status check removed —
        -- Ashita v3's TreasureItem doesn't expose a meaningful Status
        -- field (it's either 0 or undefined depending on build), so the
        -- old "ti.Status ~= 0" gate dropped EVERY pool entry. ItemId
        -- alone is sufficient: a non-zero ItemId means a real item is
        -- in that pool slot.
        local entry = nil
        for _, inv in ipairs(invs) do
            if inv and inv.GetTreasureItem then
                local ti = inv:GetTreasureItem(slot)
                if ti ~= nil and ti.ItemId ~= nil and ti.ItemId ~= 0 then
                    local nm = item_name(res_mgr, ti.ItemId)
                    -- Client-derived TTL: start (or restart, if the slot's item
                    -- changed) the timer when we first see this item in the slot.
                    local seen = pool_slot_seen[slot]
                    if seen == nil or seen.id ~= ti.ItemId then
                        seen = { id = ti.ItemId, first = os.time() }
                        pool_slot_seen[slot] = seen
                    end
                    entry = {
                        id           = ti.ItemId,
                        name         = (nm ~= '' and nm) or ('item#' .. ti.ItemId),
                        count        = ti.Count or 1,
                        lot          = ti.Lot or 0,
                        winning_lot  = ti.WinningLot or 0,
                        winner_name  = tostring(ti.WinningLotterName or ''):gsub('%z', ''),
                        ttl          = math.max(0, POOL_LIFETIME_S - (os.time() - seen.first)),
                    }
                    if nm ~= '' then
                        note_in_cache(ti.ItemId, nm, not seen_prev_frame[ti.ItemId])
                        seen_this_frame[ti.ItemId] = true
                    end
                    break
                end
            end
        end
        if entry == nil then pool_slot_seen[slot] = nil end
        live_pool[slot] = entry
    end
    seen_prev_frame = seen_this_frame
end

-- Exposed for recent_tab.
function M.get_cache() return cache end

-- ============================================================
-- draw
-- ============================================================

-- Text width in px, tolerant of Ashita's CalcTextSize returning a number,
-- an {x,y} table, or a plain array.
local function text_w(s)
    local a = imgui.CalcTextSize(s or '')
    if type(a) == 'number' then return a end
    if type(a) == 'table'  then return a.x or a[1] or 0 end
    return #(s or '') * 7
end
M.text_w = text_w

-- Trim a name to fit max_px, appending an ellipsis only when it actually
-- overflows. FFXI item display names (Ashita res.Name) are SE's already-
-- abbreviated short forms — "Scp. Harness +1", "Mrc.Cpt. Doublet" — fitted to
-- the vanilla inventory grid, so this only bites for the longer material/seal
-- names, and only when they'd collide with a row's flush-right buttons.
-- Fitting by pixel width (not a magic char count) means a name that already
-- fits is never clipped, whatever the window width.
local function truncate_to_width(name, max_px)
    name = name or ''
    if max_px <= 0 or text_w(name) <= max_px then return name end
    local dots = text_w('...')
    for i = #name - 1, 1, -1 do
        if text_w(name:sub(1, i)) + dots <= max_px then
            return name:sub(1, i) .. '...'
        end
    end
    return '...'
end
M.truncate_to_width = truncate_to_width  -- shared with the Drop History tab

local function draw_pool_row(slot, e)
    -- Read-only row: item id + name + TTL. No buttons (the + Group / Lot List
    -- actions live on the Drop History tab now), so the name has the full row
    -- width and needs no trimming. No slot index / count — one item per slot.
    local ttl = e.ttl or 0
    imgui.Text(string.format('%-5d  %s   (ttl %d:%02d)',
        e.id, e.name, math.floor(ttl / 60), ttl % 60))
end

function M.draw()
    autoutil.section_head('Live Treasure Pool')
    imgui.Spacing()
    imgui.TextDisabled('Items currently in the pool. Use the Drop History tab to add items to a group or set a lot list.')
    imgui.Separator()
    imgui.Dummy(0, 6)

    local active = 0
    for slot = 0, POOL_SIZE - 1 do
        if live_pool[slot] ~= nil then active = active + 1 end
    end

    if active == 0 then
        imgui.TextDisabled('(pool is empty)')
    else
        imgui.BeginChild('##pool_rows', 0, 0, false)
        for slot = 0, POOL_SIZE - 1 do
            local e = live_pool[slot]
            if e ~= nil then
                draw_pool_row(slot, e)
                imgui.Dummy(0, 1)
            end
        end
        imgui.EndChild()
    end
end

return M
