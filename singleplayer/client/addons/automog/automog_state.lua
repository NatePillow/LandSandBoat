-- AutoMog shared state.
--
-- Cross-tab mutable state plus the status-feed helpers. The main file and every
-- tab module require this so the selected character and the status history stay
-- a single source of truth rather than duplicated per tab. imgui-free; no draw
-- logic lives here.
--
-- (Extracted from the former monolithic automog.lua when the tabs were split
-- into sibling *_tab.lua files.)

local M = {}

-- Currently selected character driving every tab (char dropdown, task #109).
-- nil / '' means the primary character.
M.selected_char              = nil
M.char_selector_bootstrapped = false

-- Status feed: powers the History tab and the latest-status banner. Newest
-- entry first; each entry = { time, source, text, char }.
M.STATUS_HISTORY_MAX = 100
M.status_history     = {}
M.latest_status      = nil
M.prev_statuses      = {}   -- [source] = last-seen text (dedup for the poll)

-- AH category-browse cache. Shared because the outgoing query lives in
-- automog_common (send_ah_cat_query), the incoming reply is filled by the main
-- file's packet handler, and the AH tab reads it to render. One home avoids a
-- fork where the query resets one copy while the handler fills another.
M.ah_cat_cache         = {}     -- [cat_id] = { items = {...}, complete = bool }
M.ah_browse_requesting = false

-- Transfer op status + participating chars. Shared: the Transfer tab sets them,
-- the main file's AUTOMOG_TRANSFER_RESULT packet handler sets transfer_status,
-- and poll_statuses reads all three for the status feed.
M.transfer_status     = ''
M.transfer_left_char  = nil
M.transfer_right_char = nil

-- A status string worth recording (non-empty and not the idle sentinel).
function M.has_status(s)
    return s and s ~= '' and s ~= 'Idle'
end

-- Record a status line for the History tab / banner. No-op for idle/empty text.
function M.push_status(source, text, char_name)
    if not M.has_status(text) then return end
    local entry = { time = os.date('%H:%M:%S'), source = source, text = text, char = char_name }
    table.insert(M.status_history, 1, entry)
    if #M.status_history > M.STATUS_HISTORY_MAX then
        table.remove(M.status_history)
    end
    M.latest_status = entry
end

return M
