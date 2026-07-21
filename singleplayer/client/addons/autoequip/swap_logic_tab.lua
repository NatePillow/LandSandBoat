-- Swap-logic raw text editor.
--
-- Replaces an earlier GUI tree editor (condition picker + action picker +
-- add-block popup, ~900 lines). That UI never paid off — AshitaCast XML is
-- short enough that a multi-line textarea is faster to read AND faster to
-- edit than a row-by-row tree builder, and the GUI couldn't represent every
-- valid AshitaCast construct anyway. The textarea gets out of the way and
-- lets the user paste rules directly.
--
-- Per section, the textarea shows the raw XML that lives INSIDE the
-- corresponding section tag (idlegear, premagic, midmagic, ...). Whatever
-- the user types becomes the new inner XML when they hit Save: we wrap
-- their text in the section tag, run autoequip.parse_xml on it, and
-- replace the section's children. The full xml_root is then PUT to the
-- HTTP config endpoint by the existing save_section flow.
--
-- Whitespace caveat: the canonical serializer (libs/autoequip.lua
-- serialize_node) does not preserve user-entered indentation / blank
-- lines across a save + reload. After Save the textarea will redraw
-- the canonically-formatted text. Inside one editing session the user's
-- typed whitespace is preserved.
--
-- Runtime scope (unchanged): the autoequip lib's executor consumes
-- idlegear, premagic, midmagic, preranged, midranged, jobability,
-- weaponskill, petskill, petspell, gearlock. Tags outside that list are
-- still parsed and saved but never executed — typing them in here won't
-- raise errors, they'll just be inert.

local M = {}

local autoequip
local autoutil

-- ============================================================
-- Display labels + section order (kept verbatim from the previous editor
-- so the rail looks the same to users).
-- ============================================================

local DISPLAY_LABEL = {
    idlegear    = 'Idle Gear',
    premagic    = 'Precast',
    midmagic    = 'Midcast',
    preranged   = 'Pre Ranged',
    midranged   = 'Mid Ranged',
    jobability  = 'Job Ability',
    weaponskill = 'Weaponskill',
    petskill    = 'Pet Skill',
    petspell    = 'Pet Spell',
    gearlock    = 'Gear Lock',
}

local SECTION_ORDER = {
    'idlegear',
    'premagic', 'midmagic',
    'preranged', 'midranged',
    'jobability', 'weaponskill',
    'petskill', 'petspell',
    'gearlock',
}

-- ============================================================
-- State
-- ============================================================

local active_section     = 'idlegear'
local last_seen_xml_root = nil    -- pointer identity check; cleared on reload

-- Per-section ImGuiVar buffers + last-canonical-text snapshot.
-- buffers[section]       = ImGuiVar (CDSTRING) backing the InputText
-- canonical_text[section] = serialize-of-the-tree at last reseed
-- The buffer is dirty iff the var's current value != canonical_text.
-- 64KB per section — autoequip XMLs cap around 100KB total and the
-- largest single section in practice is ~10KB. We zero out and reseed
-- on on_xml_loaded so a config swap doesn't show stale text.
local BUFFER_BYTES   = 65536
local buffers        = {}
local canonical_text = {}

-- Dirty: derived from buf != canonical comparison on every draw. We
-- also keep a per-section "save failed last parse" message so the user
-- isn't left guessing why their Save did nothing.
local last_parse_error = {}

local pending_nav = nil  -- section the user clicked while another was dirty

-- ============================================================
-- Init + lifecycle
-- ============================================================

function M.init(deps)
    autoequip = deps.autoequip
    autoutil  = deps.autoutil
end

function M.on_load()
    -- Buffers are lazy-created in get_buffer() on first draw; deferring
    -- avoids touching imgui APIs during the addon's bootstrap phase
    -- (some bindings reject CreateVar before the imgui context is ready).
end

function M.on_unload()
    for _, v in pairs(buffers) do
        if v ~= nil then imgui.DeleteVar(v) end
    end
    buffers        = {}
    canonical_text = {}
end

-- Called by autoequip.lua after a fresh XML loads. Reseed every buffer
-- from the new tree so we don't display stale text.
function M.on_xml_loaded()
    last_seen_xml_root = nil
    canonical_text     = {}
    last_parse_error   = {}
    pending_nav        = nil
    for tag, v in pairs(buffers) do
        if v ~= nil then imgui.SetVarValue(v, '') end
    end
end

-- ============================================================
-- XML helpers — section lookup + inner-text serialize + parse
-- ============================================================

local function find_child(parent, tag)
    if parent == nil then return nil end
    for _, child in ipairs(parent.children or {}) do
        if child.tag == tag then return child end
    end
    return nil
end

-- find_or_create_section(tag) — return the <tag> node under <ashitacast>,
-- creating an empty one if missing. Mirrors the helper from the previous
-- editor so saves on a brand-new section work without manual XML edits.
local function find_or_create_section(tag)
    if autoequip.xml_root == nil then return nil end
    local existing = find_child(autoequip.xml_root, tag)
    if existing ~= nil then return existing end
    local node = { tag = tag, attrs = {}, children = {}, text = '' }
    table.insert(autoequip.xml_root.children, node)
    return node
end

-- Serialize the children of a section into one text block, with each
-- top-level child at depth=0 so the user sees them flush left. Returns
-- '' for empty / nil sections.
local function section_inner_text(section_node)
    if section_node == nil or #section_node.children == 0 then return '' end
    local parts = {}
    for _, child in ipairs(section_node.children) do
        table.insert(parts, autoequip.serialize_node(child, 0))
    end
    return table.concat(parts, '\n')
end

-- Parse user text as the inner content of a section. Wrap it in the
-- section tag so parse_xml gets a single root, then return its children.
-- Returns (children, nil) on success, (nil, error_msg) on parse failure.
local function parse_section_inner(text, section_tag)
    text = text or ''
    local wrapped = '<' .. section_tag .. '>\n' .. text .. '\n</' .. section_tag .. '>'
    local ok, root = pcall(autoequip.parse_xml, wrapped)
    if not ok or root == nil or root.tag ~= section_tag then
        local err = (not ok) and tostring(root) or 'parse returned no node'
        return nil, err
    end
    return root.children or {}, nil
end

-- ============================================================
-- Save / Discard
-- ============================================================

local function file_basename()
    if autoequip.loaded_char == nil or autoequip.loaded_job == nil then return nil end
    return autoequip.loaded_char .. '_' .. autoequip.loaded_job:upper() .. '.xml'
end

local function save_section(section_tag)
    local file = file_basename()
    if file == nil then
        autoutil.log('AutoEquip', 'save_section: no XML loaded')
        return
    end

    -- Reparse the user's text and replace the section's children in-place.
    -- If parse fails we keep the on-disk file untouched and surface the
    -- error in the UI — typing-mid-edit shouldn't be able to corrupt the
    -- saved config.
    local buf = buffers[section_tag]
    if buf == nil then
        autoutil.log('AutoEquip', 'save_section: no buffer for ' .. section_tag)
        return
    end
    local typed = imgui.GetVarValue(buf) or ''
    local children, err = parse_section_inner(typed, section_tag)
    if children == nil then
        last_parse_error[section_tag] = err
        return
    end
    last_parse_error[section_tag] = nil

    local section_node = find_or_create_section(section_tag)
    if section_node == nil then
        autoutil.log('AutoEquip', 'save_section: cannot find or create section ' .. section_tag)
        return
    end
    section_node.children = children
    canonical_text[section_tag] = section_inner_text(section_node)
    -- Reseed the buffer with the canonicalized text so the editor reflects
    -- exactly what was saved. Whitespace re-normalizes here; this is the
    -- one user-visible side-effect documented in the file header.
    imgui.SetVarValue(buf, canonical_text[section_tag])

    local body = autoequip.serialize_full()
    if body == nil then
        autoutil.log('AutoEquip', 'save_section: serialize_full returned nil')
        return
    end
    local http = require('http_client')
    http.put('/configs/equip/' .. file, body, 'application/xml', function(code, _, _, http_err)
        if code == 200 or code == 201 then
            if pending_nav ~= nil then
                active_section = pending_nav
                pending_nav    = nil
            end
        elseif code == nil then
            autoutil.log('AutoEquip', string.format('save_section[%s]: %s', section_tag, tostring(http_err)))
        else
            autoutil.log('AutoEquip', string.format('save_section[%s]: PUT returned %s', section_tag, tostring(code)))
        end
    end)
end

local function discard_section(section_tag)
    -- Revert the textarea to whatever the tree currently says. No server
    -- refetch needed — the tree is the authoritative pre-edit state.
    last_parse_error[section_tag] = nil
    local section_node = find_child(autoequip.xml_root, section_tag)
    local text = section_inner_text(section_node)
    canonical_text[section_tag] = text
    local buf = buffers[section_tag]
    if buf ~= nil then imgui.SetVarValue(buf, text) end
    if pending_nav ~= nil then
        active_section = pending_nav
        pending_nav    = nil
    end
end

-- ============================================================
-- Buffer / dirty bookkeeping
-- ============================================================

local function ensure_buffer(section_tag)
    if buffers[section_tag] == nil then
        buffers[section_tag] = imgui.CreateVar(ImGuiVar_CDSTRING, BUFFER_BYTES)
    end
    if canonical_text[section_tag] == nil then
        local node = find_child(autoequip.xml_root, section_tag)
        local text = section_inner_text(node)
        canonical_text[section_tag] = text
        imgui.SetVarValue(buffers[section_tag], text)
    end
    return buffers[section_tag]
end

local function is_dirty(section_tag)
    local buf = buffers[section_tag]
    if buf == nil then return false end
    local typed = imgui.GetVarValue(buf) or ''
    return typed ~= (canonical_text[section_tag] or '')
end

-- ============================================================
-- Section editor pane
-- ============================================================

local function draw_section_editor(section_tag)
    imgui.Text(DISPLAY_LABEL[section_tag] or section_tag)
    imgui.SameLine(0, 12)
    imgui.TextDisabled('Raw XML — anything inside <' .. section_tag .. '> ... </' .. section_tag .. '>')

    if last_parse_error[section_tag] then
        imgui.Dummy(0, 4)
        imgui.TextColored(1.0, 0.4, 0.4, 1.0, 'Parse error: ' .. tostring(last_parse_error[section_tag]))
    end

    imgui.Dummy(0, 4)
    imgui.Separator()
    imgui.Dummy(0, 4)

    local buf = ensure_buffer(section_tag)
    local h   = math.max(200, (M._outer_h or 800) - 130)

    if imgui.InputTextMultiline then
        -- Ashita v3 mirrors the C++ ImGui signature (ADKv3/imgui.h:310):
        --   InputTextMultiline(label, buf, buf_size, size_x, size_y, flags)
        -- with the ImVec2 size expanded into two number args (same way
        -- BeginChild takes width,height). buf_size MUST be the buffer's real
        -- capacity. The previous call passed (buf, -1, h): -1 landed in the
        -- buf_size slot, so ImGui sized the edit buffer to SIZE_MAX on
        -- activation and crashed the instant you clicked in — and h landed in
        -- size_x, which is why the width never obeyed any tuning. With buf_size
        -- correct, size_x = -1 fills to the pane's right edge (no PushItemWidth
        -- needed — the size arg drives it) and size_y = h sets the height.
        imgui.InputTextMultiline('##sl_text_' .. section_tag, buf, BUFFER_BYTES, -1, h)
    else
        imgui.PushItemWidth(-1)
        imgui.InputText('##sl_text_' .. section_tag, buf, BUFFER_BYTES)
        imgui.PopItemWidth()
    end
end

-- ============================================================
-- draw — left rail + right pane
-- ============================================================

function M.draw()
    if autoequip.xml_root == nil then
        imgui.TextDisabled('No XML loaded - open the Gear tab and load a config first.')
        return
    end

    -- xml_root identity change → reseed canonical buffers. The on_xml_loaded
    -- hook should cover this, but defensive identity check makes correctness
    -- not depend on the load flow remembering to fire the hook.
    if last_seen_xml_root ~= autoequip.xml_root then
        last_seen_xml_root = autoequip.xml_root
        canonical_text     = {}
    end

    -- Capture the OUTER autoequip window's size here, BEFORE entering
    -- any BeginChild. Once inside a child, GetWindowSize returns the
    -- child's own size, which is useless for figuring out how big to
    -- make the InputTextMultiline (because the child is auto-fitting
    -- to that very widget — circular). The chrome budgets account for
    -- the rail width + gap on the x-axis and title bar + tab strip +
    -- header row on the y-axis. Stash on module-level fields so
    -- draw_section_editor can read them.
    local outer_w, outer_h = imgui.GetWindowSize()
    M._outer_w = outer_w or 640
    M._outer_h = outer_h or 800

    -- Rail height = pane height = outer minus title + tab strip + a
    -- small padding budget. Explicit height stops the rail/pane from
    -- auto-fitting around small content and lets the text editor
    -- claim the full vertical space.
    local PANE_CHROME_H = 80
    local pane_h = math.max(200, M._outer_h - PANE_CHROME_H)

    -- Explicit right-pane width. Ashita v3's imgui binding treats
    -- BeginChild width=0 as LITERAL zero (not "fill remaining"), and
    -- GetContentRegionAvailWidth inside a zero-wide child reports a
    -- tiny value — the InputTextMultiline then sizes to that and the
    -- editor never grows even when the outer window does. Compute the
    -- pane width here from the outer window: rail (180) + SameLine
    -- gap (12) + a small chrome budget (16) for the outer's left/right
    -- padding and the pane's own inner padding.
    local PANE_CHROME_W = 180 + 12 + 16
    local pane_w = math.max(200, M._outer_w - PANE_CHROME_W)

    imgui.BeginChild('##sl_rail', 180, pane_h, true)
    for _, sec in ipairs(SECTION_ORDER) do
        local label = (DISPLAY_LABEL[sec] or sec)
        if is_dirty(sec) then label = '* ' .. label end
        if imgui.Selectable(label .. '##sl_' .. sec, sec == active_section) then
            if sec ~= active_section then
                if is_dirty(active_section) then
                    pending_nav = sec
                else
                    active_section = sec
                end
            end
        end
    end
    imgui.EndChild()
    imgui.SameLine(0, 12)

    imgui.BeginChild('##sl_pane', pane_w, pane_h, false)

    -- Save / Discard are always present so the pane's controls don't shift as
    -- the section flips dirty<->clean; when clean they dim (alpha 0.35) and go
    -- inert -- clicks only fire while dirty.
    local dirty = is_dirty(active_section)
    if not dirty then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.35) end
    if imgui.Button('Save##save_active') and dirty then
        save_section(active_section)
    end
    imgui.SameLine(0, 6)
    if imgui.Button('Discard##discard_active') and dirty then
        discard_section(active_section)
    end
    if not dirty then imgui.PopStyleVar() end
    if dirty then
        imgui.SameLine(0, 12)
        imgui.TextDisabled('unsaved changes')
    end
    imgui.Separator()
    imgui.Dummy(0, 4)
    if pending_nav ~= nil and is_dirty(active_section) then
        imgui.TextColored(1.0, 0.7, 0.2, 1.0,
            string.format('Unsaved changes in %s - Save or Discard to switch to %s.',
                DISPLAY_LABEL[active_section] or active_section,
                DISPLAY_LABEL[pending_nav]    or pending_nav))
        imgui.SameLine(0, 8)
        if imgui.Button('Cancel##cancel_nav') then pending_nav = nil end
        imgui.Separator()
        imgui.Dummy(0, 4)
    end

    draw_section_editor(active_section)
    imgui.EndChild()
end

return M
