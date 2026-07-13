-- Shared item stat diff: parse + colored render.
--
-- Single source of truth for "what stats does this item description carry"
-- and "render the delta vs another item with green/red colored text."
--
-- Used by:
--   * autoequip / gear_tab.lua  — Gear set picker's Confirm panel
--   * automog   / automog.lua   — Status tab's equipment-swap Confirm panel
--
-- Adding a new stat: append to STAT_MULTI below. The fallback gmatch loop
-- catches generic +N / -N suffixed stats automatically (STR+5, etc.) so
-- only multi-word stats with FFXI-canonical labels need entries.

require 'common'

local M = {}

-- Multi-word stats. parse_item_stats's gmatch fallback only catches
-- single-token stats (STR+5, INT+3, etc.) — anything with a space in the
-- label needs an explicit entry here keyed to its canonical abbreviation
-- so the diff column groups e.g. "Attack +10" / "Atk +12" cleanly.
local STAT_MULTI = {
    { 'Accuracy', 'ACC' }, { 'Attack', 'ATK' }, { 'Evasion', 'EVA' },
    { 'Ranged Accuracy', 'RACC' }, { 'Ranged Attack', 'RATK' },
    { 'Magic Accuracy', 'MACC' }, { 'Magic Evasion', 'MEVA' },
    { 'Magic Attack Bonus', 'MAB' }, { 'Magic Defense Bonus', 'MDB' },
    { 'Store TP', 'STP' }, { 'Subtle Blow', 'SB' },
    { 'Double Attack', 'DA' }, { 'Triple Attack', 'TA' },
    { 'Crit hit rate', 'Crit' }, { 'Haste', 'Haste' }, { 'Enmity', 'Enmity' },
}
M.STAT_MULTI = STAT_MULTI

-- Parse the FFXI item description string into a flat { STAT = signedDelta }
-- table. Handles DEF / Damage / Delay numerics, the multi-word stat list
-- above, and a generic single-token +N / -N fallback so common stats like
-- "STR+5 / DEX+3 / VIT-2" land without needing explicit entries.
function M.parse_item_stats(desc)
    local s = {}
    if not desc or desc == '' then return s end
    local def = desc:match('DEF:%s*(%d+)')
    if def then s['DEF'] = tonumber(def) end
    -- FFXI weapon descriptions abbreviate base damage as "DMG:18" (no space,
    -- sometimes an augment sign "DMG:+3"); the old "[Dd]amage:" pattern never
    -- matched, so weapon DMG diffs silently dropped. Keep the long form as a
    -- fallback for any item that spells it out.
    local dmg = desc:match('DMG:%s*%+?(%d+)') or desc:match('[Dd]amage:%s*(%d+)')
    if dmg then s['DMG'] = tonumber(dmg) end
    local dly = desc:match('[Dd]elay:%s*(%d+)')
    if dly then s['DLY'] = tonumber(dly) end
    for _, pair in ipairs(STAT_MULTI) do
        local sign, val = desc:match(pair[1] .. '([%+%-])(%d+)')
        if sign and val then s[pair[2]] = tonumber(val) * (sign == '-' and -1 or 1) end
    end
    for stat, sign, val in desc:gmatch('([A-Z][A-Z%d]+)([%+%-])(%d+)') do
        if not s[stat] then s[stat] = tonumber(val) * (sign == '-' and -1 or 1) end
    end
    return s
end

-- Item description lookup by FFXI display name. Returns '' for unknown
-- items or items with no description so callers can skip rendering
-- without a nil check.
function M.get_item_desc(name)
    if not name or name == '' then return '' end
    local res = AshitaCore:GetResourceManager():GetItemByName(name, 0)
    if not res or not res.Description or not res.Description[0] then return '' end
    return tostring(res.Description[0]):gsub('%z', '')
end

-- Render the colored stat-diff strip comparing old → new item. Caller is
-- responsible for the surrounding chrome (separator above, Confirm /
-- Cancel below). Layout: 3 stats per row, comma-spaced via SameLine(0,14),
-- green text for positive deltas (0.40, 0.90, 0.40), red for negative
-- (0.90, 0.35, 0.35). No-op when both items resolve to identical stats.
function M.render_stat_diff(oldName, newName)
    local old_stats = M.parse_item_stats(M.get_item_desc(oldName))
    local new_stats = M.parse_item_stats(M.get_item_desc(newName))
    local diff      = {}
    local seen      = {}
    for k, v in pairs(new_stats) do
        seen[k] = true
        local d = v - (old_stats[k] or 0)
        if d ~= 0 then table.insert(diff, { key = k, d = d }) end
    end
    for k, v in pairs(old_stats) do
        if not seen[k] then table.insert(diff, { key = k, d = -v }) end
    end
    if #diff == 0 then return end
    table.sort(diff, function(a, b) return a.key < b.key end)
    imgui.Dummy(0, 10)
    imgui.Separator()
    imgui.Dummy(0, 5)
    for i, entry in ipairs(diff) do
        local sign  = entry.d > 0 and '+' or ''
        local label = string.format('%s  %s%d', entry.key, sign, entry.d)
        if entry.d > 0 then
            imgui.PushStyleColor(ImGuiCol_Text, 0.40, 0.90, 0.40, 1.0)
        else
            imgui.PushStyleColor(ImGuiCol_Text, 0.90, 0.35, 0.35, 1.0)
        end
        imgui.Text(label)
        imgui.PopStyleColor()
        if i % 3 ~= 0 and i < #diff then imgui.SameLine(0, 14) end
    end
end

return M
