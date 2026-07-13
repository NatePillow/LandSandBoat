-----------------------------------
-- Server-side port of the client-side library
--
-- Each headless bot polls its own treasure pool on the per-bot tick (called
-- from xi.singleplayer.bots.onBotTick) and:
--   - LOTs items whose id is in any active group's id list, or whose name
--     matches a named-item entry
--   - PASSes items that are not wanted (auto-pass keeps the pool moving so
--     wanted items resolve faster, matching client-side behavior)
--   - Tracks outstanding named lots per bot in `bots_spawn.activeLots` so a
--     dropped wanted item isn't double-lotted before it resolves
--
-- Groups (client-side calls them activeGroups):
--   craftables : hardcoded crystal + rare craft material id list (port of
--                client-side crystalItemIds + craftItemIds)
--
-- Named items: per-bot list of item names the bot will lot. Initially empty;
-- task #42 (automog lot tab) will let the primary push entries at runtime via
-- 0x176 — that integration point is documented at the bottom of this file.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_lot')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.ai_lot = xi.singleplayer.bots.ai_lot or {}
local ai_lot = xi.singleplayer.bots.ai_lot

-----------------------------------
-- Group definitions live as JSON files under singleplayer/config/lot/.
-- A group file looks like:
--   { "ids": [4096, 4097, 658, ...] }
-- The ai_lot.groups cache is per-process; entries are populated on first use
-- (load_group) and busted when the ai_lot addon pushes an edit via 0x180
-- (set_subtree_lot below). Group names are resolved at display time via the
-- ResourceManager — internally everything keys off ID.
-----------------------------------
ai_lot.groups = ai_lot.groups or {}

local CONFIG_DIR = 'singleplayer/config/lot/'

local function load_group(groupName)
    if groupName == nil or groupName == '' then return nil end
    -- Pull body + mtime from the server cache. Store mtime alongside the
    -- parsed group so we can detect external edits and reparse (Option C
    -- coherency pattern — pull-based, no callback plumbing).
    local body, mtime = GetServerConfig('lot', groupName)
    if body == nil then return nil end
    local cached = ai_lot.groups[groupName]
    if cached ~= nil and cached._mtime == mtime then return cached end
    local json   = require('modules/singleplayer/lib/json')
    local ok, data = pcall(json.decode, json, body)
    if not ok or type(data) ~= 'table' then return nil end
    local group = { _mtime = mtime }
    if type(data.ids) == 'table' then
        for _, id in ipairs(data.ids) do table.insert(group, id) end
    end
    ai_lot.groups[groupName] = group
    return group
end

ai_lot.load_group = load_group

-----------------------------------
-- Per-bot scratch lives on alliance.bot[charId] (#221). The lot fields
-- (activeGroups, namedItems, activeLots) are part of the consolidated schema.
-----------------------------------
local function get_state(bot)
    return xi.singleplayer.bots.ensure_bot(bot:getID())
end

-----------------------------------
-- Utility: lowercase trim of an item resource name. Returns '' if unresolvable.
-----------------------------------
local function name_for_id(itemId)
    if itemId == nil or itemId == 0 then return '' end
    local item = GetItemByID(itemId)
    if item == nil then return '' end
    return string.lower(item:getName() or '')
end

-----------------------------------
-- Lookup helpers
-----------------------------------
local function list_contains_id(list, itemId)
    for _, id in ipairs(list) do
        if id == itemId then return true end
    end
    return false
end

local function list_contains_str(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function should_lot(bot, state, itemId)
    -- Group match (lazy-load the group's config file on first reference).
    -- Groups are id-only — name matching was dropped in favor of the addon's
    -- search-by-name picker which resolves names → ids before saving.
    for groupName in pairs(state.activeGroups) do
        local list = load_group(groupName)
        if list ~= nil and list_contains_id(list, itemId) then
            return true
        end
    end
    -- Per-bot named item match (still name-based; lives outside groups).
    if #state.namedItems > 0 then
        local nm = name_for_id(itemId)
        if nm ~= '' and list_contains_str(state.namedItems, nm) then
            return true
        end
    end
    -- Lot List match: bot is on this item's lot-list, grace window elapsed,
    -- and we don't already have one in inventory. The grace window lets a
    -- burst of per-bot adds (from the addon's Apply button) all land before
    -- any bot acts so the whole list lots the first drop together.
    local primaryId = bot.getParentCharId and bot:getParentCharId() or nil
    if primaryId ~= nil
       and ai_lot.lot_list_ready(primaryId, itemId, bot:getName())
       and not bot:hasItem(itemId)
    then
        return true
    end
    return false
end

-----------------------------------
-- Public: configure a bot's lotting preferences.
-- Called from automog UI handler / 0x176 dispatch in the future.
-----------------------------------
function ai_lot.start(bot, groupSet, names)
    local s = get_state(bot)
    s.activeGroups = {}
    s.namedItems   = {}
    s.activeLots   = {}
    if type(groupSet) == 'table' then
        for _, g in ipairs(groupSet) do s.activeGroups[g] = true end
    end
    if type(names) == 'table' then
        for _, n in ipairs(names) do
            table.insert(s.namedItems, string.lower(n))
        end
    end
end

-- "Disable lotting for this bot" = clear the data the tick reads. should_lot
-- returns false when activeGroups + namedItems are both empty, so the bot
-- still ticks but lots for nothing. Forces explicit reconfigure on next
-- start(), which is fine — same state you'd be in after a reconnect.
function ai_lot.stop(bot)
    local s = get_state(bot)
    s.activeGroups = {}
    s.activeLots   = {}
    s.namedItems   = {}
end

function ai_lot.add_named(bot, name)
    local s = get_state(bot)
    local n = string.lower(name)
    if not list_contains_str(s.namedItems, n) then
        table.insert(s.namedItems, n)
    end
end

function ai_lot.remove_named(bot, name)
    local s = get_state(bot)
    local n = string.lower(name)
    for i, v in ipairs(s.namedItems) do
        if v == n then
            table.remove(s.namedItems, i)
            s.activeLots[n] = nil
            break
        end
    end
end

function ai_lot.add_group(bot, groupName)
    get_state(bot).activeGroups[groupName] = true
end

function ai_lot.remove_group(bot, groupName)
    get_state(bot).activeGroups[groupName] = nil
end

-----------------------------------
-- HTTP-routed group assignment.
--
-- Called from the config_http_server POST /lot/assignment handler. Resolves
-- the named char (primary or owned headless) to a live entity; if found and
-- is a PC, toggles the group on the bot's activeGroups set. If the named
-- char isn't currently spawned, silently no-ops (assignments are session-
-- scoped to the bot's spawn lifecycle; no persistence layer).
--
-- Returns true on a successful apply, false if the char wasn't a live PC.
-----------------------------------
function ai_lot.set_assignment_for_char(charName, groupName, on)
    if charName == nil or charName == '' or groupName == nil or groupName == '' then
        return false
    end
    local target = GetPlayerByName(charName)
    if target == nil then
        return false
    end
    if on then
        ai_lot.add_group(target, groupName)
    else
        ai_lot.remove_group(target, groupName)
    end
    return true
end

-----------------------------------
-- Lot Lists: per-(primary, itemId) → set of bot names that should each
-- receive ONE of this item. Set entries are removed when the bot acquires
-- one (inventory check during tick). Empty itemId entry is dropped.
--
-- Each entry carries a `modified` timestamp set on every add. should_lot
-- waits LOT_LIST_GRACE_S after the most recent change before letting any bot
-- act on the entry, so a burst of per-bot adds from the addon's Apply button
-- all land before the first bot lots. Without the grace window, the first
-- bot to tick could lot solo and resolve the slot before later additions
-- arrive on the wire.
--
-- Shape:
--   ai_lot.lot_lists[primaryId] = {
--     [itemId] = {
--       members  = { ["Brutus"] = true, ["Freya"] = true, ... },
--       modified = os.clock(),
--     },
--   }
-----------------------------------
ai_lot.lot_lists = ai_lot.lot_lists or {}
local LOT_LIST_GRACE_S = 0.5  -- > one bot-tick (400ms), invisible to user

function ai_lot.lot_list_add(primary, itemId, botName)
    if primary == nil or itemId == nil or itemId == 0 or botName == nil or botName == '' then return end
    local primaryId = primary:getID()
    ai_lot.lot_lists[primaryId] = ai_lot.lot_lists[primaryId] or {}
    local entry = ai_lot.lot_lists[primaryId][itemId]
    if entry == nil then
        entry = { members = {}, modified = os.clock() }
        ai_lot.lot_lists[primaryId][itemId] = entry
    end
    entry.members[botName] = true
    entry.modified         = os.clock()
end

function ai_lot.lot_list_remove(primaryId, itemId, botName)
    local lots = ai_lot.lot_lists[primaryId]
    if lots == nil or lots[itemId] == nil then return end
    lots[itemId].members[botName] = nil
    if next(lots[itemId].members) == nil then
        lots[itemId] = nil
    end
    if next(lots) == nil then
        ai_lot.lot_lists[primaryId] = nil
    end
end

function ai_lot.lot_list_clear(primaryId, itemId)
    local lots = ai_lot.lot_lists[primaryId]
    if lots == nil then return end
    lots[itemId] = nil
    if next(lots) == nil then
        ai_lot.lot_lists[primaryId] = nil
    end
end

-- Returns true iff this bot is on the lot list for (primary, itemId) AND
-- the grace window has elapsed (so a burst of per-bot adds has settled).
function ai_lot.lot_list_ready(primaryId, itemId, botName)
    local lots = ai_lot.lot_lists[primaryId]
    if lots == nil or lots[itemId] == nil then return false end
    local entry = lots[itemId]
    if not entry.members[botName] then return false end
    return (os.clock() - (entry.modified or 0)) >= LOT_LIST_GRACE_S
end

-----------------------------------
-- Tick entry point. Called from xi.singleplayer.bots.onBotTick once per second per bot.
-- Walks the bot's treasure pool, lots wanted items, passes unwanted ones.
-----------------------------------
function ai_lot.tick(bot)
    -- Runs for both headless AND primary. Primary autolot is quality-of-life:
    -- speed up pool resolution by passing on items the bot has no want for
    -- AND someone else has already lotted (leave-alone branch below preserves
    -- the slot when no one has an opinion, so the primary can still manually
    -- lot anything they care about that wasn't pre-configured).
    local s = get_state(bot)

    local pool = bot:getTreasurePool()
    if pool == nil then return end
    local items = pool:getItems()
    if items == nil then return end

    for _, entry in ipairs(items) do
        local itemId  = entry.id or 0
        local slotId  = entry.slotId
        if itemId ~= 0 and slotId ~= nil then
            -- Walk the pool entry's `lotters` array twice in one pass:
            -- (1) detect whether we've already acted (skip duplicate),
            -- (2) detect whether anyone *else* has placed a positive lot.
            --
            -- LotInfo.lot is uint16: 0 = pass, >0 = lot value. We only
            -- auto-pass if at least one other member positively lotted the
            -- item — that guarantees pool resolution will distribute it to
            -- the highest lotter immediately. If nobody lotted, we leave it
            -- alone so the item sits in the pool (primary may still lot it
            -- manually) instead of being destroyed by everyone passing.
            local alreadyActed     = false
            local otherLotterFound = false
            if entry.lotters ~= nil then
                local botId = bot:getID()
                for _, lotter in ipairs(entry.lotters) do
                    if lotter.member ~= nil then
                        if lotter.member:getID() == botId then
                            alreadyActed = true
                        elseif (lotter.lot or 0) > 0 then
                            otherLotterFound = true
                        end
                    end
                end
            end

            if not alreadyActed then
                if should_lot(bot, s, itemId) then
                    local nm = name_for_id(itemId)
                    if nm ~= '' and list_contains_str(s.namedItems, nm) and s.activeLots[nm] == nil then
                        s.activeLots[nm] = slotId
                    end
                    bot:botLotItem(slotId, math.random(1, 999))
                elseif otherLotterFound then
                    bot:botPassItem(slotId)
                end
                -- else: leave the slot untouched; we have no opinion and
                -- nobody else has either. Item sits until someone lots or
                -- the FFXI pool timeout drops it.
            end
        end
    end
end

-----------------------------------
-- Cleanup: when a slot resolves (item won/lost/dropped), the pool clears it
-- on the C++ side. Our `activeLots` map can grow stale across resolutions if
-- the same named item keeps dropping. Reconcile on each tick by clearing any
-- entry whose slot no longer holds that item.
-----------------------------------
function ai_lot.reconcile(bot)
    local s = get_state(bot)
    if next(s.activeLots) == nil then return end

    local pool = bot:getTreasurePool()
    if pool == nil then return end
    local items = pool:getItems()
    if items == nil then return end

    -- Build a slot → itemId map for quick lookup
    local slotToItem = {}
    for _, entry in ipairs(items) do
        slotToItem[entry.slotId] = entry.id
    end

    for nm, slot in pairs(s.activeLots) do
        local currentId = slotToItem[slot]
        if currentId == nil or currentId == 0 then
            -- Slot empty: the lot resolved. Drop the tracking.
            s.activeLots[nm] = nil
        else
            -- Slot occupied: did the name still match?
            local curName = name_for_id(currentId)
            if curName ~= nm then
                s.activeLots[nm] = nil
            end
        end
    end

    -- Lot List inventory cleanup: any item we're listed for and now own
    -- means the lot succeeded somewhere, so drop ourselves from that entry.
    local primaryId = bot.getParentCharId and bot:getParentCharId() or nil
    if primaryId ~= nil and ai_lot.lot_lists[primaryId] ~= nil then
        local botName = bot:getName()
        for itemId, entry in pairs(ai_lot.lot_lists[primaryId]) do
            if entry.members[botName] and bot:hasItem(itemId) then
                ai_lot.lot_list_remove(primaryId, itemId, botName)
            end
        end
    end
end

-----------------------------------
-- Wire into the per-bot tick. xi.singleplayer.bots.onBotTick is dispatched from C++ on
-- every PostTick; we just chain our handler in.
-----------------------------------
local function on_tick(bot)
    ai_lot.reconcile(bot)
    ai_lot.tick(bot)
end

m:addOverride('xi.singleplayer.bots.onBotTick', function(player, botMode)
    super(player, botMode)
    if player == nil then return end
    on_tick(player)
end)

-----------------------------------
-- Future integration point (task #42, automog UI lot tab):
--   The primary will push per-bot lot preferences via the 0x176 headless
--   command pipeline. Suggested namespace + subcommands:
--     namespace 0x04 AUTOLOT
--       0x01 START      Payload: char Name[8] + group bitmask + named-item ref
--       0x02 STOP       Payload: char Name[12]
--       0x03 ADD_NAMED  Payload: char Name[8] + item name ref
--       0x04 RM_NAMED   Payload: char Name[8] + item name ref
--   Wire those into xi.singleplayer.bots.onCommand once the UI is in place; the public
--   accessors ai_lot.start / stop / add_named / remove_named / add_group /
--   remove_group already exist for that purpose.
-----------------------------------

-- Subtree write-back handler (set_subtree_lot + subtree_handlers wire-up)
-- was deleted alongside bots_config.lua. Reason: the loopback-HTTP config
-- CRUD migration has the addon PUT the full JSON body directly. Cache
-- invalidation is handled implicitly by the mtime-vs-cached check on the
-- GetServerConfig() call inside the group-load path above — HTTP PUT writes
-- through configcache::putAndPersist so the mtime advances atomically, and
-- the next lot decision picks up the new body.

return m
