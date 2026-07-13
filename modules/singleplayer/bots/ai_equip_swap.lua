-----------------------------------
-- Server-side port of the client-side library
--
-- Loads AshitaCast-format XML gear configs (the same .xml files used by the
-- client-side ai_equip_swap addon) and swaps gear at PAI lifecycle transitions
-- using the server's existing entity:addListener event system:
--
--   MAGIC_START          → midmagic gear (after the cast time was computed
--                           with premagic gear that the caller already swapped)
--   MAGIC_STATE_EXIT     → idlegear
--   WEAPONSKILL_STATE_EXIT → idlegear
--   ABILITY_STATE_EXIT   → idlegear
--   RANGE_START          → midranged
--   RANGE_STATE_EXIT     → idlegear
--
-- Pre-action swaps (premagic / weaponskill / preranged / jobability) happen in
-- the caller (bot_magic / bot_ability) BEFORE bot:castSpell / weaponSkill /
-- rangedAttack / useJobAbility — that way the gear is on when the server
-- computes cast time / WS damage / ranged delay at action start.
--
-- The XML parser is preserved from ai_equip_swap verbatim (purpose-built for
-- AshitaCast, NOT a general XML parser). Condition evaluators use server-side
-- entity state (bot:getHPP(), VanadielHour(), bot:hasStatusEffect(), etc.)
-- instead of reading Ashita memory.
--
-- ── AshitaCast spec parity — what's supported and what's NOT ──
-- See /home/nate/Desktop/git/ffxi-ashita/config/AshitaCast/XML Structure.xml
-- and Variables.txt for the canonical reference. Big-picture status:
--
-- Sections supported: idlegear, premagic, midmagic, preranged, midranged,
-- jobability, weaponskill, petskill, petspell, gearlock. ✓ All 9 core
-- sections plus gearlock parse and dispatch.
--
-- Variables supported (eval_condition branches in this file):
--   * Player: p_hp, p_hpp, p_mp, p_mpp, p_tp, p_hpmax, p_mpmax, p_joblevel,
--     p_subjoblevel, p_status, p_mainjob, p_subjob, p_job, p_name, p_ismoving,
--     p_fireresist / p_iceresist / p_windresist / p_earthresist /
--     p_lightningresist / p_waterresist / p_lightresist / p_darkresist
--   * Environment: e_time, e_area, e_weather, e_weatherelement, e_day,
--     e_dayelement, e_moon, e_moonpct
--   * Action data: ad_id, ad_name, ad_type, ad_skill, ad_element, ad_recast,
--     ad_casttime, ad_mpcost, ad_mpaftercast, ad_mppaftercast
--   * Action target: at_id, at_index, at_hpp, at_distance, at_name, at_type
--     (populated only when a caller passes an action_target to equip_section;
--     idlegear leaves them zeroed per spec)
--   * Selected target: t_id, t_index, t_hpp, t_distance, t_name, t_type
--   * Party: pt_inparty, pt_count, pt_target, pt_actiontarget
--   * Alliance: a_inally, a_count, a_target, a_actiontarget
--   * Equipment: eq_main / eq_sub / ... (all 16 slots via the eq_* prefix)
--   * Pet: pet_active, pet_hpp, pet_tp, pet_status, pet_name, pet_distance
--   * Buffs: buffactive (name and ID, x# multiples, | OR, ! negate)
--
-- Rule features supported:
--   * Wildcards (*) in text-rule patterns (match_or upgrade)
--   * %rulename substitution in equip names and set names (expand_vars)
--   * $variable substitution from <variables> blocks (expand_vars)
--   * <if advanced="…"> algebraic expressions: |, &, =, !=, >=, >, <=, <,
--     +, -, **, /, parens / brackets / braces, ! unary negate (eval_advanced)
--   * Basic |-OR and &-AND in plain rule values, > / < / >= / <= / != / =
--     prefixes for numeric, ! prefix for negation
--
-- Re-trigger wiring:
--   * Action-driven via PAI listeners on every player entity (independent of
--     BotMode): MAGIC_STATE_ENTER, MAGIC_START, MAGIC_STATE_EXIT,
--     WEAPONSKILL_STATE_ENTER, WEAPONSKILL_STATE_EXIT, ABILITY_START,
--     ABILITY_STATE_EXIT, RANGE_STATE_ENTER, RANGE_START, RANGE_STATE_EXIT,
--     ENGAGE, DISENGAGE, EFFECT_GAIN(HEALING), EFFECT_LOSE(HEALING).
--     The *_STATE_ENTER events fire BEFORE cast/aim time math so premagic /
--     preranged gear (Fast Cast / Snapshot) reduces THIS action's wind-up;
--     *_START fires after announce for the midmagic/midranged damage-calc
--     swap; *_STATE_EXIT returns to idlegear. Bot AI also pre-swaps
--     symmetrically before bot:castSpell / weaponSkill / rangedAttack — both
--     routes converge on the same swap, idempotent.
--   * Tick-driven autoupdate: chainer on xi.singleplayer.bots.onBotTick at
--     the file's bottom, 1s throttle per bot, re-equips idlegear if already
--     in idlegear (action sections own their own gear until they exit).
--     Requires post_tick.cpp gate that fires onBotTick for primary in Off —
--     done in #227.
--
-- ── KNOWN GAPS — explicitly NOT implemented ──
--
-- 1. p_attack / p_defense stubbed to 0. Lua doesn't expose CBattleEntity::ATT()
--    / DEF() (computed stats, not raw mods). Adding requires 2 small bindings
--    in lua_baseentity.cpp. Skipped because the conditional is fundamentally
--    circular — your gear determines your attack/defense, so an XML rule
--    gating on them produces unstable swaps. Real configs use buffactive,
--    p_hpp, or p_mpp for the same intent.
--
-- 2. Non-action XML tags from <inputcommands> / midsection bodies are NOT
--    implemented: <change>, <cancel>, <return>, <doidlegear>, <setvar>,
--    <incvar>, <decvar>, <clearvars>, <registerbuff>, <clearbuff>,
--    <command>, <addtochat>. The XML parser ignores them. AshitaCast XMLs
--    use these for stateful flow control (PLD cure tier downgrade by mp
--    leftover, THF SATA→WS buff registry, etc.) — none of which the bots
--    do in spec-compliant ways today. Documented for future authors.
--
-- 3. <settings> flags not honored:
--    * buffupdate    — we only re-eval idlegear on EFFECT_GAIN/LOSE for
--                       HEALING, not arbitrary buffs. Configs that gate
--                       gear on "Refresh active" / "Sublimation Activated" /
--                       aftermath flags will only update on the next
--                       action-driven re-trigger, not the moment the buff
--                       lands. Generalize the EFFECT_* listener to a small
--                       allow-list if you want broader coverage.
--    * hpupdate      — we don't watch HP%. Skipped for perf; HP changes
--                       up to 20Hz in combat and re-evaluating idlegear
--                       on every tick would be wasteful. Action-exit
--                       re-evals catch HP changes naturally.
--    * autoupdate    — wired via the onBotTick chainer at 1s cadence
--                       (AshitaCast uses ~350ms). Coarser, but cheap.
--    * blockresends, predictivepet, statusupdate — client-side concerns,
--                       not relevant server-side.
--
-- 4. <sets> advanced features ignored: `baseset` inheritance, per-slot
--    `lock`, per-slot `priority`. Sets are flat name → slot map; the last
--    section wins, no priority arbitration. AshitaCast XMLs that rely on
--    a "lock" slot persisting across sections won't behave the same way.
--
-- 5. <include> for the DressMe gear-fetch helper is ignored. We don't have
--    DressMe equivalent server-side. The block parses but does nothing.
--
-- 6. petskill / petspell auto-fire is NOT wired. Both equip_petskill /
--    equip_petspell exist but no listener calls them — same as the original
--    AshitaCast addon (it expected users to wire them via <inputcommands>).
--    PUP/BST/SMN bots fighting with pets stay in pre-pet-action gear. If
--    pet WS / pet spell gear becomes important, hook PET_WEAPONSKILL_USE
--    and PET_MAGIC_START (or whatever the engine emits) and fan out.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_equip_swap')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.ai_equip_swap = xi.singleplayer.bots.ai_equip_swap or {}
local ai_equip_swap = xi.singleplayer.bots.ai_equip_swap

-- Per-bot current XML section ('idlegear' / 'premagic' / 'midmagic' / etc.).
-- Keyed by bot:getID(). Used by tick() to avoid clobbering an in-flight
-- mid-action gear set with idlegear. Originally a module-global string —
-- correct only as long as there's a single client, which doesn't hold for
-- a 12+ bot alliance sharing one Lua VM.
ai_equip_swap.current_section = ai_equip_swap.current_section or {}

-- Per-bot parsed-XML cache. Key = charId, value = { xml_root, sets_node, sections, gearlock_section, variables, job_name }
ai_equip_swap.cache = ai_equip_swap.cache or {}

-- Per-bot currently-equipped gear set, keyed by [botId] → { slot = item }.
-- Earlier I keyed this per-section (last_gear[botId][section_name]) which
-- was wrong: after midmagic equipped Z, transitioning to idlegear (cached
-- as X) compared X == X → dedupe skip → bot stayed in midmagic gear
-- forever. The correct dedupe key is "what's actually on the bot right
-- now", which is independent of which section computed it.
ai_equip_swap.last_gear = ai_equip_swap.last_gear or {}

function ai_equip_swap.destroy_state(botId)
    ai_equip_swap.current_section[botId] = nil
    ai_equip_swap.cache[botId]            = nil
    ai_equip_swap.missing_xml[botId]      = nil
    ai_equip_swap.last_gear[botId]        = nil
end

-- Negative cache — "(charId, job_name)" pairs we've already tried and confirmed
-- no XML exists for. Avoids retrying the file-exists check every action.
-- Cleared (per-char) when job_name changes via ensure_loaded.
ai_equip_swap.missing_xml = ai_equip_swap.missing_xml or {}

-- XML file directory, relative to the LSB root (where xi_map runs). Other
-- runtime-editable config categories live as sibling subdirs under
-- singleplayer/config/. Override with xi.singleplayer.bots.ai_equip_swap.xml_dir before
-- module load if needed.
ai_equip_swap.xml_dir = ai_equip_swap.xml_dir or 'singleplayer/config/equip/'

-- Slot name → server slot ID (matches xi.slot enum)
local SLOT_BY_NAME = {
    main = 0, sub = 1, range = 2, ammo = 3,
    head = 4, body = 5, hands = 6, legs = 7, feet = 8,
    neck = 9, waist = 10,
    ear1 = 11, lear = 11,
    ear2 = 12, rear = 12,
    ring1 = 13, lring = 13,
    ring2 = 14, rring = 14,
    back = 15,
}

-- Explicit equip order for send_equip_packets. Some bodies (e.g. Black Cloak)
-- have a `removeSlotID` mask that UNEQUIPS the head when the body is
-- equipped (charutils::EquipArmor:2335-2343 in C++). Iteration via pairs()
-- is undefined order, so a set with both <body> and <head> would equip them
-- in random order — lost the head half the time.
--
-- Convention: send HEAD before BODY so BODY wins. If user lists both in a
-- set with a restrictive body, the body's restriction strips the head —
-- that's the intended outcome (body's mask is authoritative). Weapons go
-- first so a 2H weapon's "remove sub" effect lands before any sub equip
-- attempt.
local SLOT_EQUIP_ORDER = {
    'main', 'sub', 'range', 'ammo',
    'head',
    'body',   -- after head, so body's removeSlotID can strip the head
    'hands', 'legs', 'feet',
    'neck', 'waist',
    'ear1', 'ear2', 'lear', 'rear',
    'ring1', 'ring2', 'lring', 'rring',
    'back',
}

-- ============================================================
-- Vana'diel time (1. get_vana_time)
-- Server has VanadielHour() / VanadielMinute() globals (defined in luautils).
-- ============================================================

local function get_vana_time()
    return {
        hour   = (VanadielHour   and VanadielHour())   or 0,
        minute = (VanadielMinute and VanadielMinute()) or 0,
    }
end

-- ============================================================
-- XML parser (lines 119-249 of ai_equip_swap — purpose-built for AshitaCast)
-- ============================================================

-- 2. find_tag_end
local function find_tag_end(content, start)
    local pos = start
    local in_quote = false
    local quote_char = nil
    while pos <= #content do
        local c = content:sub(pos, pos)
        if in_quote then
            if c == quote_char then in_quote = false end
        else
            if c == '"' or c == "'" then
                in_quote = true; quote_char = c
            elseif c == '>' then
                return pos
            end
        end
        pos = pos + 1
    end
    return nil
end

-- 3. parse_attrs
local function parse_attrs(tag_body)
    local attrs = {}
    for key, val in tag_body:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do
        attrs[key] = val
    end
    return attrs
end

-- 4. tokenize
local function tokenize(content)
    content = content:gsub('<!%-%-(.-)%-%->', '')  -- strip comments
    local tokens = {}
    local pos = 1
    local len = #content
    while pos <= len do
        local lt = content:find('<', pos, true)
        if lt == nil then
            local text = content:sub(pos):match('^%s*(.-)%s*$')
            if text ~= '' then table.insert(tokens, { type = 'text', value = text }) end
            break
        end
        if lt > pos then
            local text = content:sub(pos, lt - 1):match('^%s*(.-)%s*$')
            if text ~= '' then table.insert(tokens, { type = 'text', value = text }) end
        end
        local gt = find_tag_end(content, lt + 1)
        if gt == nil then break end
        local inner = content:sub(lt + 1, gt - 1)
        if inner:sub(1, 1) == '/' then
            local tagname = inner:match('^/([%w_]+)')
            if tagname then table.insert(tokens, { type = 'close', tag = tagname }) end
        elseif inner:sub(-1) == '/' then
            local tagname = inner:match('^([%w_]+)')
            if tagname then table.insert(tokens, { type = 'self', tag = tagname, attrs = parse_attrs(inner) }) end
        elseif inner:sub(1, 1) ~= '?' then
            local tagname = inner:match('^([%w_]+)')
            if tagname then table.insert(tokens, { type = 'open', tag = tagname, attrs = parse_attrs(inner) }) end
        end
        pos = gt + 1
    end
    return tokens
end

-- 5. build_tree
local function build_tree(tokens, start_pos)
    local open_tok = tokens[start_pos]
    local node = { tag = open_tok.tag, attrs = open_tok.attrs, children = {}, text = '' }
    local pos = start_pos + 1
    while pos <= #tokens do
        local tok = tokens[pos]
        if tok.type == 'close' then
            return node, pos + 1
        elseif tok.type == 'open' then
            local child, new_pos = build_tree(tokens, pos)
            table.insert(node.children, child)
            pos = new_pos
        elseif tok.type == 'self' then
            table.insert(node.children, { tag = tok.tag, attrs = tok.attrs, children = {}, text = '' })
            pos = pos + 1
        elseif tok.type == 'text' then
            node.text = tok.value
            pos = pos + 1
        else
            pos = pos + 1
        end
    end
    return node, pos
end

-- 6. parse_xml
local function parse_xml(content)
    local tokens = tokenize(content)
    for i, tok in ipairs(tokens) do
        if tok.type == 'open' then
            local root, _ = build_tree(tokens, i)
            return root
        end
    end
    return nil
end

-- ============================================================
-- Gear set resolution with baseset inheritance
-- ============================================================

-- 7. resolve_set
local function resolve_set(sets_node, set_name, visited)
    visited = visited or {}
    if visited[set_name] then return {} end
    visited[set_name] = true

    local set_node = nil
    for _, child in ipairs(sets_node.children) do
        if child.tag == 'set' and child.attrs.name == set_name then
            set_node = child; break
        end
    end
    if set_node == nil then return {} end

    local result = {}
    if set_node.attrs.baseset and set_node.attrs.baseset ~= '' then
        local base = resolve_set(sets_node, set_node.attrs.baseset, visited)
        for k, v in pairs(base) do result[k] = v end
    end
    for _, slot_node in ipairs(set_node.children) do
        if slot_node.text and slot_node.text ~= '' then
            result[slot_node.tag] = slot_node.text
        end
    end
    return result
end

-- ============================================================
-- Condition evaluation
-- ============================================================

-- 8. match_name_pattern
local function match_name_pattern(pattern, name)
    if name == nil then return false end
    local lname = name:lower()
    for part in (pattern .. '|'):gmatch('([^|]+)|') do
        part = part:match('^%s*(.-)%s*$')
        if part ~= '' then
            local lua_pat = '^' .. part:lower()
                :gsub('([%(%)%.%+%-%?%[%]%^%$%%])', '%%%1')
                :gsub('%*', '.*') .. '$'
            if lname:match(lua_pat) then return true end
        end
    end
    return false
end

-- 9. clean_str
local function clean_str(s)
    if s == nil then return nil end
    return (s:gsub('%z', ''))
end

-- 10. get_equipped_item_name (server-side: bot:getEquipID + name lookup)
local function get_equipped_item_name(bot, slot_id)
    if bot == nil or bot.getEquipID == nil then return '' end
    local itemId = bot:getEquipID(slot_id)
    if itemId == nil or itemId == 0 then return '' end
    -- Server has GetItemByID returning a CItem; use its English name
    local item = GetItemByID and GetItemByID(itemId)
    if item and item.getName then
        return clean_str(item:getName()) or ''
    end
    return ''
end

-- 11. get_buff_name
local function get_buff_name(buff_id)
    -- Server: status effect names aren't easily Lua-accessible by ID, but bot
    -- code rarely uses buff *names* in conditions — usually IDs. Fall back to
    -- empty so eval_buffactive's numeric path handles the common case.
    return nil
end

-- 12. get_all_buffs
local function get_all_buffs(bot)
    if bot == nil then return {} end
    local effects = bot:getStatusEffects() or {}
    local all = {}
    for _, eff in ipairs(effects) do
        -- Lua-side status-effect objects expose :getEffectType() or are { id, ... }
        local id = (type(eff) == 'table' and eff.id) or
                   (eff.getEffectType and eff:getEffectType()) or nil
        if id and id > 0 then table.insert(all, id) end
    end
    return all
end

-- 13. eval_buffactive
local function eval_buffactive(bot, cond_str)
    local all_buffs = get_all_buffs(bot)
    for part in (cond_str .. '|'):gmatch('([^|]+)|') do
        part = part:match('^%s*(.-)%s*$')
        local negated = part:sub(1, 1) == '!'
        if negated then part = part:sub(2) end
        local base, count_str = part:match('^(.+)x(%d+)$')
        local required = 1
        if base then required = tonumber(count_str) or 1 else base = part end
        local buff_id_num = tonumber(base)
        local base_lower  = base:lower()
        local count = 0
        for _, b in ipairs(all_buffs) do
            if buff_id_num then
                if b == buff_id_num then count = count + 1 end
            else
                local name = get_buff_name(b)
                if name and name == base_lower then count = count + 1 end
            end
        end
        local result = negated and (count < required) or (count >= required)
        if result then return true end
    end
    return false
end

-- 14. eval_numeric_cond
local function eval_numeric_cond(cond_str, value)
    if value == nil then return false end
    for part in (cond_str .. '|'):gmatch('([^|]+)|') do
        local all_true = true
        for sub in (part .. '&'):gmatch('([^&]+)&') do
            sub = sub:match('^%s*(.-)%s*$')
            local matched = false
            local op, num_str = sub:match('^([<>=!]+)%s*(.+)$')
            if op and num_str then
                local num = tonumber(num_str)
                if num then
                    if     op == '>'  then matched = value >  num
                    elseif op == '<'  then matched = value <  num
                    elseif op == '>=' then matched = value >= num
                    elseif op == '<=' then matched = value <= num
                    elseif op == '=' or op == '==' then matched = value == num
                    elseif op == '!=' then matched = value ~= num
                    end
                end
            else
                local num = tonumber(sub)
                if num then matched = (value == num) end
            end
            if not matched then all_true = false; break end
        end
        if all_true then return true end
    end
    return false
end

-- 15. eval_time_cond
local function eval_time_cond(cond_str)
    local t = get_vana_time()
    local current = t.hour + t.minute / 100.0
    return eval_numeric_cond(cond_str, current)
end

-- 16. match_or — exact or wildcard match against any of the |-separated parts.
-- Per spec, text rules may use `*` wildcards.
local function match_or(pattern, value)
    if value == nil then return false end
    local lval = tostring(value):lower()
    for part in (pattern .. '|'):gmatch('([^|]+)|') do
        part = part:match('^%s*(.-)%s*$'):lower()
        if part == lval then return true end
        if part:find('*', 1, true) then
            local lua_pat = '^' .. part
                :gsub('([%(%)%.%+%-%?%[%]%^%$%%])', '%%%1')
                :gsub('%*', '.*') .. '$'
            if lval:match(lua_pat) then return true end
        end
    end
    return false
end

-- 16b. expand_vars — replaces %rulename and $variablename references in a
-- string with their resolved values. Used in equip names, set names, etc.
-- Per spec: "%p_status" → player_info.status string; "$Shield" → variables.Shield.
-- The longest existing match is always preferred after a % or $ (per spec).
-- Returns the expanded string (unchanged if nothing matches).
local function _resolve_pct(name, player_info, spell_info)
    if player_info ~= nil and player_info[name] ~= nil then return tostring(player_info[name]) end
    if spell_info  ~= nil and spell_info[name]  ~= nil then return tostring(spell_info[name])  end
    return nil
end

local function expand_vars(str, player_info, spell_info, variables)
    if type(str) ~= 'string' or str == '' then return str end
    if not str:find('[%%$]') then return str end
    -- Walk char by char so we can do greedy longest-match identifier extraction.
    local out, i, n = {}, 1, #str
    while i <= n do
        local c = str:sub(i, i)
        if c == '%' or c == '$' then
            -- Greedy: identifier is the longest [%w_]+ run after the sigil.
            local j = i + 1
            while j <= n and str:sub(j, j):match('[%w_]') do j = j + 1 end
            local ident = str:sub(i + 1, j - 1)
            if ident == '' then
                -- Literal sigil (no identifier after) — keep as-is.
                out[#out + 1] = c
                i = i + 1
            else
                -- Greedy longest match: try the full identifier, then shorten
                -- one char at a time until something resolves (per spec).
                local resolved = nil
                local len = #ident
                while len > 0 do
                    local try = ident:sub(1, len)
                    local val
                    if c == '%' then
                        val = _resolve_pct(try:lower(), player_info, spell_info)
                    else
                        val = variables and variables[try]
                    end
                    if val ~= nil then
                        resolved = tostring(val)
                        -- Keep any trailing identifier chars verbatim.
                        out[#out + 1] = resolved
                        out[#out + 1] = ident:sub(len + 1)
                        break
                    end
                    len = len - 1
                end
                if resolved == nil then
                    -- Nothing matched; emit the sigil + identifier untouched.
                    out[#out + 1] = c
                    out[#out + 1] = ident
                end
                i = j
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- 16c. eval_advanced — parses the AshitaCast <if advanced="..."> mini-language.
-- Supports infix operators: |, &, =, !=, >=, >, <=, <, +, -, **, /
-- Grouping: (), [], {}.  Variables/rule references are expanded first (%/$).
-- All-string comparisons are case-insensitive. Anywhere a number is required,
-- non-numeric operands evaluate to 0.
local function eval_advanced(expr, player_info, spell_info, variables)
    if type(expr) ~= 'string' or expr == '' then return false end
    local expanded = expand_vars(expr, player_info, spell_info, variables):lower()
    -- Normalize bracket variants to plain parens for the recursive descent.
    expanded = expanded:gsub('[%[{]', '('):gsub('[%]}]', ')')

    -- Recursive-descent parser. Operator precedence (low to high):
    --   | (or)  >  & (and)  >  comparison (= != >= > <= <)  >  + -  >  ** /
    local pos = 1
    local skipws, parse_or, parse_and, parse_cmp, parse_add, parse_mul, parse_unary, parse_atom

    skipws = function()
        while pos <= #expanded and expanded:sub(pos, pos):match('%s') do pos = pos + 1 end
    end

    local function peek(s)
        skipws()
        return expanded:sub(pos, pos + #s - 1) == s
    end

    local function consume(s)
        if peek(s) then pos = pos + #s; return true end
        return false
    end

    local function tonum(v)
        if type(v) == 'number' then return v end
        if type(v) == 'boolean' then return v and 1 or 0 end
        return tonumber(v) or 0
    end
    local function tobool(v)
        if type(v) == 'boolean' then return v end
        if type(v) == 'number'  then return v > 0 end
        if type(v) == 'string'  then return v ~= '' and v ~= 'false' and v ~= '0' end
        return false
    end

    parse_atom = function()
        skipws()
        if consume('(') then
            local v = parse_or()
            consume(')')
            return v
        end
        -- Number literal
        local num = expanded:match('^(%-?%d+%.?%d*)', pos)
        if num then pos = pos + #num; return tonumber(num) end
        -- Bare token: scoop up everything until an operator / paren / whitespace.
        local tok = expanded:match("^([^|&=!<>%+%-%*/%(%) ]+)", pos)
        if tok and #tok > 0 then pos = pos + #tok; return tok end
        return ''
    end

    parse_unary = function()
        skipws()
        if consume('!') then
            local v = parse_unary()
            return not tobool(v)
        end
        return parse_atom()
    end

    parse_mul = function()
        local lhs = parse_unary()
        while true do
            skipws()
            if consume('**') then
                lhs = tonum(lhs) * tonum(parse_unary())
            elseif peek('/') and not peek('//') then
                consume('/')
                local rhs = tonum(parse_unary())
                lhs = (rhs == 0) and 0 or (tonum(lhs) / rhs)
            else break end
        end
        return lhs
    end

    parse_add = function()
        local lhs = parse_mul()
        while true do
            skipws()
            if consume('+') then
                lhs = tonum(lhs) + tonum(parse_mul())
            elseif consume('-') then
                lhs = tonum(lhs) - tonum(parse_mul())
            else break end
        end
        return lhs
    end

    parse_cmp = function()
        local lhs = parse_add()
        skipws()
        for _, op in ipairs({ '>=', '<=', '!=', '>', '<', '==', '=' }) do
            if consume(op) then
                local rhs = parse_add()
                local ln, rn = tonumber(tostring(lhs)), tonumber(tostring(rhs))
                if ln and rn then
                    if     op == '>=' then return ln >= rn
                    elseif op == '<=' then return ln <= rn
                    elseif op == '!=' then return ln ~= rn
                    elseif op == '>'  then return ln >  rn
                    elseif op == '<'  then return ln <  rn
                    else                   return ln == rn end
                end
                local ls, rs = tostring(lhs):lower(), tostring(rhs):lower()
                if     op == '!=' then return ls ~= rs
                elseif op == '='  or op == '==' then return ls == rs
                else return false end
            end
        end
        return lhs
    end

    parse_and = function()
        local lhs = parse_cmp()
        while true do
            skipws()
            if consume('&') then
                local rhs = parse_cmp()
                lhs = tobool(lhs) and tobool(rhs)
            else break end
        end
        return lhs
    end

    parse_or = function()
        local lhs = parse_and()
        while true do
            skipws()
            if consume('|') then
                local rhs = parse_and()
                lhs = tobool(lhs) or tobool(rhs)
            else break end
        end
        return lhs
    end

    local ok, result = pcall(parse_or)
    if not ok then return false end
    return tobool(result)
end

-- 17. eval_condition
local function eval_condition(bot, attrs, spell_info, player_info, variables)
    for key, val in pairs(attrs) do
        local negate = (key ~= 'buffactive') and (val:sub(1, 1) == '!')
        local check  = negate and val:sub(2) or val
        local ok = true

        -- Action data
        if     key == 'ad_type'         then ok = match_or(check, spell_info.type)
        elseif key == 'ad_name'         then ok = match_name_pattern(check, spell_info.name)
        elseif key == 'ad_skill'        then ok = match_or(check, spell_info.skill_name)
        elseif key == 'ad_id'           then ok = eval_numeric_cond(check, spell_info.id)
        elseif key == 'ad_element'      then ok = match_or(check, spell_info.element)
        elseif key == 'ad_recast'       then ok = eval_numeric_cond(check, spell_info.recast)
        elseif key == 'ad_casttime'     then ok = eval_numeric_cond(check, spell_info.casttime)
        elseif key == 'ad_mpcost'       then ok = eval_numeric_cond(check, spell_info.mpcost)
        elseif key == 'ad_mpaftercast'  then ok = eval_numeric_cond(check, spell_info.mpaftercast)
        elseif key == 'ad_mppaftercast' then ok = eval_numeric_cond(check, spell_info.mppaftercast)

        -- Player numeric
        elseif key == 'p_hp'  then ok = eval_numeric_cond(check, player_info.hp)
        elseif key == 'p_hpp' then ok = eval_numeric_cond(check, player_info.hpp)
        elseif key == 'p_mp'  then ok = eval_numeric_cond(check, player_info.mp)
        elseif key == 'p_mpp' then ok = eval_numeric_cond(check, player_info.mpp)
        elseif key == 'p_tp'  then ok = eval_numeric_cond(check, player_info.tp)
        elseif key == 'p_hpmax' then ok = eval_numeric_cond(check, player_info.hpmax)
        elseif key == 'p_mpmax' then ok = eval_numeric_cond(check, player_info.mpmax)
        elseif key == 'p_joblevel'    then ok = eval_numeric_cond(check, player_info.joblevel)
        elseif key == 'p_subjoblevel' then ok = eval_numeric_cond(check, player_info.subjoblevel)
        elseif key == 'p_attack'  then ok = eval_numeric_cond(check, player_info.attack)
        elseif key == 'p_defense' then ok = eval_numeric_cond(check, player_info.defense)
        elseif key == 'p_fireresist'      then ok = eval_numeric_cond(check, player_info.fireresist)
        elseif key == 'p_iceresist'       then ok = eval_numeric_cond(check, player_info.iceresist)
        elseif key == 'p_windresist'      then ok = eval_numeric_cond(check, player_info.windresist)
        elseif key == 'p_earthresist'     then ok = eval_numeric_cond(check, player_info.earthresist)
        elseif key == 'p_lightningresist' then ok = eval_numeric_cond(check, player_info.lightningresist)
        elseif key == 'p_waterresist'     then ok = eval_numeric_cond(check, player_info.waterresist)
        elseif key == 'p_lightresist'     then ok = eval_numeric_cond(check, player_info.lightresist)
        elseif key == 'p_darkresist'      then ok = eval_numeric_cond(check, player_info.darkresist)

        -- Player string
        elseif key == 'p_status'    then ok = match_or(check, player_info.status)
        elseif key == 'p_mainjob'   then ok = match_or(check, player_info.mainjob)
        elseif key == 'p_subjob'    then ok = match_or(check, player_info.subjob)
        elseif key == 'p_job'       then ok = match_or(check, player_info.job)
        elseif key == 'p_name'      then ok = match_or(check, player_info.name)
        elseif key == 'p_ismoving'  then ok = match_or(check, player_info.ismoving)

        -- Environment
        elseif key == 'e_time'           then ok = eval_time_cond(check)
        elseif key == 'e_area'           then ok = match_or(check, player_info.area)
        elseif key == 'e_weather'        then ok = match_or(check, player_info.weather)
        elseif key == 'e_weatherelement' then ok = match_or(check, player_info.weatherelement)
        elseif key == 'e_day'            then ok = match_or(check, player_info.day)
        elseif key == 'e_dayelement'     then ok = match_or(check, player_info.dayelement)
        elseif key == 'e_moon'           then ok = match_or(check, player_info.moon)
        elseif key == 'e_moonpct'        then ok = eval_numeric_cond(check, player_info.moonpct)

        -- Selected target (selected via cursor / /attack, NOT action target)
        elseif key == 't_hpp'      then ok = eval_numeric_cond(check, player_info.t_hpp)
        elseif key == 't_distance' then ok = eval_numeric_cond(check, player_info.t_distance)
        elseif key == 't_id'       then ok = eval_numeric_cond(check, player_info.t_id)
        elseif key == 't_index'    then ok = eval_numeric_cond(check, player_info.t_index)
        elseif key == 't_name'     then ok = match_or(check, player_info.t_name)
        elseif key == 't_type'     then ok = match_or(check, player_info.t_type)

        -- Action target (the target of the spell/WS/JA currently processing).
        -- Per spec, returns false in idlegear context (at_* table is zeroed).
        elseif key == 'at_hpp'      then ok = eval_numeric_cond(check, player_info.at_hpp)
        elseif key == 'at_distance' then ok = eval_numeric_cond(check, player_info.at_distance)
        elseif key == 'at_id'       then ok = eval_numeric_cond(check, player_info.at_id)
        elseif key == 'at_index'    then ok = eval_numeric_cond(check, player_info.at_index)
        elseif key == 'at_name'     then ok = match_or(check, player_info.at_name)
        elseif key == 'at_type'     then ok = match_or(check, player_info.at_type)

        -- Party
        elseif key == 'pt_inparty'      then ok = match_or(check, player_info.pt_inparty)
        elseif key == 'pt_count'        then ok = eval_numeric_cond(check, player_info.pt_count)
        elseif key == 'pt_target'       then ok = match_or(check, player_info.pt_target)
        elseif key == 'pt_actiontarget' then ok = match_or(check, player_info.pt_actiontarget)

        -- Alliance
        elseif key == 'a_inally'       then ok = match_or(check, player_info.a_inally)
        elseif key == 'a_count'        then ok = eval_numeric_cond(check, player_info.a_count)
        elseif key == 'a_target'       then ok = match_or(check, player_info.a_target)
        elseif key == 'a_actiontarget' then ok = match_or(check, player_info.a_actiontarget)

        -- Equipment slot lookups (eq_main / eq_sub / eq_head / ...)
        elseif SLOT_BY_NAME[key:gsub('^eq_', '')] ~= nil then
            ok = match_or(check, get_equipped_item_name(bot, SLOT_BY_NAME[key:gsub('^eq_', '')]))

        -- Pet
        elseif key == 'pet_active'   then ok = match_or(check, player_info.pet_active)
        elseif key == 'pet_hpp'      then ok = eval_numeric_cond(check, player_info.pet_hpp)
        elseif key == 'pet_tp'       then ok = eval_numeric_cond(check, player_info.pet_tp)
        elseif key == 'pet_status'   then ok = match_or(check, player_info.pet_status)
        elseif key == 'pet_name'     then ok = match_or(check, player_info.pet_name)
        elseif key == 'pet_distance' then ok = eval_numeric_cond(check, player_info.pet_distance)

        -- Buff check
        elseif key == 'buffactive' then ok = eval_buffactive(bot, val)

        -- Advanced rule: <if advanced="..."> expression. See eval_advanced.
        elseif key == 'advanced' then ok = eval_advanced(val, player_info, spell_info, variables)
        end

        if negate then ok = not ok end
        if not ok then return false end
    end
    return true
end

-- ============================================================
-- Section processing
-- ============================================================

-- 18. process_section
local function process_section(bot, section_node, spell_info, player_info, sets_node, variables)
    local gear = {}

    local function apply(slots)
        for slot, item in pairs(slots) do gear[slot] = item end
    end

    local function process_nodes(nodes)
        local idx = 1
        while idx <= #nodes do
            local node = nodes[idx]
            local tag  = node.tag

            if tag == 'equip' then
                if node.attrs.set and node.attrs.set ~= '' then
                    local set_name = expand_vars(node.attrs.set, player_info, spell_info, variables)
                    apply(resolve_set(sets_node, set_name, {}))
                else
                    local inline = {}
                    for _, slot_node in ipairs(node.children) do
                        if slot_node.text and slot_node.text ~= '' then
                            inline[slot_node.tag] = expand_vars(slot_node.text, player_info, spell_info, variables)
                        end
                    end
                    apply(inline)
                end
                idx = idx + 1
            elseif tag == 'if' then
                local cond_met = eval_condition(bot, node.attrs, spell_info, player_info, variables)
                if cond_met then process_nodes(node.children) end
                idx = idx + 1
                while idx <= #nodes do
                    local nxt = nodes[idx]
                    if nxt.tag == 'elseif' then
                        if not cond_met then
                            cond_met = eval_condition(bot, nxt.attrs, spell_info, player_info, variables)
                            if cond_met then process_nodes(nxt.children) end
                        end
                        idx = idx + 1
                    elseif nxt.tag == 'else' then
                        if not cond_met then process_nodes(nxt.children) end
                        idx = idx + 1
                        break
                    else break end
                end
            else
                idx = idx + 1
            end
        end
    end

    process_nodes(section_node.children)
    return gear
end

-- ============================================================
-- Serializer + save path — stubbed (XML edits come via 0x176 UPDATE_GEAR_XML
-- in the runtime-update flow, not in-process save).
-- ============================================================

-- 19. serialize_node
--   AshitaCast-compatible XML serializer (round-trips files produced by the
--   parser above). Self-closing tags when no text and no children; otherwise
--   open/close pair. Indented with tabs to match the input convention.
local function serialize_node(node, depth)
    depth        = depth or 0
    local indent = string.rep('\t', depth)
    local attr_s = ''
    -- Iterate attrs in stable order so the file diff stays clean across edits.
    local attr_keys = {}
    for k, _ in pairs(node.attrs or {}) do table.insert(attr_keys, k) end
    table.sort(attr_keys)
    for _, k in ipairs(attr_keys) do
        attr_s = attr_s .. string.format(' %s="%s"', k, tostring(node.attrs[k]))
    end

    local text     = node.text or ''
    local has_kids = node.children and #node.children > 0
    local has_text = text ~= ''

    if not has_kids and not has_text then
        return indent .. '<' .. node.tag .. attr_s .. '/>\n'
    end
    if has_text and not has_kids then
        return indent .. '<' .. node.tag .. attr_s .. '>' .. text .. '</' .. node.tag .. '>\n'
    end
    local s = indent .. '<' .. node.tag .. attr_s .. '>\n'
    for _, c in ipairs(node.children) do
        s = s .. serialize_node(c, depth + 1)
    end
    s = s .. indent .. '</' .. node.tag .. '>\n'
    return s
end

-- Helper: first child matching tag, optionally with attribute equality match.
local function find_child(node, tag, attrs_match)
    for _, c in ipairs(node.children or {}) do
        if c.tag == tag then
            if attrs_match == nil then return c end
            local ok = true
            for k, v in pairs(attrs_match) do
                if (c.attrs or {})[k] ~= v then ok = false; break end
            end
            if ok then return c end
        end
    end
    return nil
end

-----------------------------------
-- Public API
-----------------------------------

-- 21. load
--   Reads the XML file for char_name + job_name, parses it, caches the tree
--   per bot. The cached entry remembers the job_name so we can detect job
--   changes and reload (see ensure_loaded below).
function ai_equip_swap.load(bot, char_name, job_name)
    -- Pull body + mtime from the server's in-memory cache. mtime is the
    -- Option C coherency anchor — stored alongside the parsed tree, and
    -- compared on each lookup so external edits (addon CRUD writes or
    -- text-editor saves caught by configcache::poll within ~2 s) cause
    -- a re-parse automatically without callback plumbing. Missing files
    -- are normal — not every char has every job XML; return false silently.
    local config_name = char_name .. '_' .. job_name
    local body, mtime = GetServerConfig('equip', config_name)
    if body == nil then return false end
    local root = parse_xml(body)
    if root == nil then
        printf(string.format('bot_equip.load: parse failed: equip/%s.xml', config_name))
        return false
    end

    -- Index sections
    local entry = {
        xml_root  = root,
        sets_node = nil,
        sections  = {},
        variables = {},
        job_name  = job_name,    -- remembered for change detection
        char_name = char_name,
        mtime     = mtime,       -- Option C freshness anchor
    }
    for _, child in ipairs(root.children) do
        if child.tag == 'sets' then
            entry.sets_node = child
        elseif child.tag == 'variables' then
            for _, vnode in ipairs(child.children) do
                if vnode.tag == 'var' and vnode.attrs.name then
                    entry.variables[vnode.attrs.name] = vnode.text
                end
            end
        else
            -- Section tags (idlegear, premagic, midmagic, weaponskill, preranged,
            -- midranged, jobability, petskill, petspell, gearlock)
            entry.sections[child.tag] = child
        end
    end

    ai_equip_swap.cache[bot:getID()] = entry
    return true
end

-----------------------------------
-- Runtime targeted-update entry points.
--
-- Granular updates instead of pushing the whole XML body — the addon (automog
-- UI) sends just the field that changed: a set's slot, a swap-logic condition,
-- etc. Server modifies the in-memory parsed tree; the next gear swap picks up
-- the change.
--
-- Slot keys are AshitaCast tag names: main / sub / range / ammo / head / body
-- / hands / legs / feet / neck / waist / ear1 / ear2 / ring1 / ring2 / back.
-- ear1/ear2 and ring1/ring2 are distinct (different physical slots in FFXI).
--
-- update_set_slot — change one slot in one named set.
--   target_id - the headless bot's charId
--   set_name  - the set's name attribute (e.g. "VIT_Night")
--   slot_key  - one of the slot tags above
--   item_name - English item name as it appears in <slot> text
-----------------------------------
function ai_equip_swap.update_set_slot(target_id, set_name, slot_key, item_name)
    local entry = ai_equip_swap.cache[target_id]
    if entry == nil or entry.sets_node == nil then
        printf(string.format('bot_equip.update_set_slot: no cached gear for charId %d', target_id))
        return false
    end

    for _, set_node in ipairs(entry.sets_node.children) do
        if set_node.tag == 'set' and set_node.attrs.name == set_name then
            -- Update existing slot or append a new one
            for _, slot_node in ipairs(set_node.children) do
                if slot_node.tag == slot_key then
                    slot_node.text = item_name
                    return true
                end
            end
            table.insert(set_node.children,
                { tag = slot_key, attrs = {}, children = {}, text = item_name })
            return true
        end
    end
    printf(string.format('bot_equip.update_set_slot: set "%s" not found for charId %d', set_name, target_id))
    return false
end

-- Future expansion entry points — placeholders for the automog UI to call.
-- These will edit the <if>/<elseif>/<else>/<equip> trees in each section.
-- TODO: when automog UI gains swap-logic editing, fill these in.
function ai_equip_swap.update_section_node(target_id, section_name, path, attrs, text) return false end
function ai_equip_swap.add_section_node(target_id, section_name, path, node_spec)      return false end
function ai_equip_swap.remove_section_node(target_id, section_name, path)              return false end

-- Persistence: write the cached in-memory tree back to the file it was
-- loaded from, so runtime edits survive a server restart. Caller is
-- responsible for setting target_id correctly (the bot's char id).
function ai_equip_swap.persist_to_disk(target_id)
    local entry = ai_equip_swap.cache[target_id]
    if entry == nil or entry.xml_root == nil then return false end
    if entry.char_name == nil or entry.job_name == nil then return false end

    local path = ai_equip_swap.xml_dir .. entry.char_name .. '_' .. entry.job_name .. '.xml'
    local f = io.open(path, 'w')
    if f == nil then
        printf(string.format('bot_equip.persist_to_disk: cannot write %s', path))
        return false
    end
    f:write('<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n')
    f:write(serialize_node(entry.xml_root, 0))
    f:close()
    entry.dirty = false
    return true
end

-- 23. set_slot
--   Targeted single-slot edit on a named <set>. Mutates the in-memory tree
--   AND persists to disk so the change survives restart. Used by the
--   automog UI's gear-set tab to push one-item edits without re-sending the
--   full XML (orders of magnitude smaller payload than UPDATE_GEAR_XML).
--   Creates the slot child if it didn't exist, updates text if it did.
--   Returns true on success, false if the cache entry / sets / set isn't
--   resolvable.
function ai_equip_swap.set_slot(target_id, set_name, slot_key, item_name)
    local entry = ai_equip_swap.cache[target_id]
    if entry == nil or entry.sets_node == nil then return false end

    local set_node = find_child(entry.sets_node, 'set', { name = set_name })
    if set_node == nil then return false end

    local slot_node = find_child(set_node, slot_key)
    if slot_node == nil then
        slot_node = { tag = slot_key, attrs = {}, children = {}, text = '' }
        table.insert(set_node.children, slot_node)
    end

    slot_node.text = item_name or ''
    entry.dirty = true

    return ai_equip_swap.persist_to_disk(target_id)
end

-- Subtree-merge handler (set_subtree_equip + subtree_handlers wire-up)
-- was deleted. Reason: the loopback-HTTP config CRUD migration has the
-- addon serialize the entire AshitaCast XML in memory and PUT the whole
-- file on save. The 100 KB PUT is ~10 ms on loopback, the addon already
-- holds the parsed tree to render the editor, and the per-bot equip
-- cache picks up the change automatically via the mtime-on-read path in
-- ensure_loaded() below. No splice logic needed server-side anymore.

-- 24. reload — force re-load on next gear swap
function ai_equip_swap.reload(bot)
    ai_equip_swap.cache[bot:getID()] = nil
end

-- 25. ensure_loaded
--   Loads the gear XML if needed. Handles:
--     - Job change (cached entry's job_name != current) → drop cache, reload
--     - In-memory edits via update_set_slot → cache mutated in place, no reload
--     - "User has no XML for this job" → negative-cached so we don't re-stat
--       the file every action. Cleared when job changes.
--   Listeners are registered at login by the onGameIn hook regardless of
--   whether XML exists — this function is just the load/reload logic.
local function ensure_loaded(bot)
    local job = (xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.jobs and xi.singleplayer.bots.ai_util.jobs[bot:getMainJob()]) or 'WAR'
    local botId = bot:getID()
    local entry = ai_equip_swap.cache[botId]
    if entry ~= nil and entry.job_name == job then
        -- Option C freshness check: compare stored mtime against the
        -- server cache's current mtime for this file. If the cache has a
        -- newer body (CRUD write or watcher caught an external edit),
        -- evict so the load() below re-parses. Cheap int compare; the
        -- GetServerConfig call is a hashmap lookup, sub-microsecond.
        local _, current_mtime = GetServerConfig('equip', entry.char_name .. '_' .. job)
        if current_mtime == entry.mtime then return true end
        ai_equip_swap.cache[botId] = nil
    elseif entry ~= nil then
        -- Job changed → drop stale cache + clear any negative entry for the
        -- previous job so a job swap back triggers a re-load
        ai_equip_swap.cache[botId] = nil
        ai_equip_swap.missing_xml[botId] = nil
    end
    -- Negative cache short-circuit — we already know no XML exists for this
    -- char+job combination this session
    if ai_equip_swap.missing_xml[botId] == job then return false end

    local ok = ai_equip_swap.load(bot, bot:getName(), job)
    if not ok then
        ai_equip_swap.missing_xml[botId] = job
    end
    return ok
end

-- 26. get_section
local function get_section(bot, name)
    local entry = ai_equip_swap.cache[bot:getID()]
    if entry == nil then return nil end
    return entry.sections[name]
end

-- 27. build_spell_info — pulls metadata from the server's CSpell list via the
--     GetSpellMetaByID luautils binding (returns nil for unknown IDs).
-- Element ID → name lookup so ad_element matches AshitaCast's element strings.
-- Spell elements use a different numbering than xi.element (0-based).
local ELEMENT_BY_ID = {
    [0] = 'Fire', [1] = 'Earth', [2] = 'Water', [3] = 'Wind', [4] = 'Ice',
    [5] = 'Thunder', [6] = 'Light', [7] = 'Dark',
}

-- xi.element (used by VanadielDayElement / mob weather element) → AshitaCast
-- e_dayelement / e_weatherelement string. Per Variables.txt the values include
-- nonelemental ("none" for weatherelement only — day element omits NONE).
local DAY_ELEMENT_BY_ID = {
    [0] = 'none',  [1] = 'fire', [2] = 'ice',     [3] = 'wind',
    [4] = 'earth', [5] = 'thunder', [6] = 'water', [7] = 'light', [8] = 'dark',
}

-- xi.day enum (VanadielDayOfTheWeek) → AshitaCast e_day string
local DAY_BY_ID = {
    [0] = 'firesday', [1] = 'earthsday',    [2] = 'watersday',
    [3] = 'windsday', [4] = 'iceday',       [5] = 'lightningday',
    [6] = 'lightsday', [7] = 'darksday',
}

-- xi.weather enum → AshitaCast e_weather string. x2 suffix marks the
-- intensified variants (Hot Spell vs Heat Wave, Rain vs Squall, etc.).
local WEATHER_BY_ID = {
    [0] = 'clear',     [1] = 'sunshine',   [2] = 'clouds',
    [3] = 'fog',
    [4] = 'fire',      [5] = 'firex2',
    [6] = 'water',     [7] = 'waterx2',
    [8] = 'earth',     [9] = 'earthx2',
    [10] = 'wind',     [11] = 'windx2',
    [12] = 'ice',      [13] = 'icex2',
    [14] = 'thunder',  [15] = 'thunderx2',
    [16] = 'light',    [17] = 'lightx2',
    [18] = 'dark',     [19] = 'darkx2',
}

-- xi.weather → its element string (for e_weatherelement)
local WEATHER_ELEMENT_BY_ID = {
    [0] = 'none',  [1] = 'light', [2] = 'none',  [3] = 'none',
    [4] = 'fire',  [5] = 'fire',  [6] = 'water', [7] = 'water',
    [8] = 'earth', [9] = 'earth', [10] = 'wind', [11] = 'wind',
    [12] = 'ice',  [13] = 'ice',  [14] = 'thunder', [15] = 'thunder',
    [16] = 'light', [17] = 'light', [18] = 'dark', [19] = 'dark',
}

-- Mod IDs for the 8 elemental resist ranks (from scripts/enum/mod.lua).
local RESIST_MOD = {
    fire      = 192, ice    = 193, wind  = 194, earth = 195,
    lightning = 196, water  = 197, light = 198, dark  = 199,
}

-- Moon phase classification from VanadielMoonPhase percentage (0-100) and
-- VanadielMoonDirection (0 = waxing, 1 = waning). 8 phase names per spec.
local function classify_moon(pct, direction)
    if pct >= 95 then return 'fullmoon'  end
    if pct <= 5  then return 'newmoon'   end
    local waxing = (direction == 0)
    if waxing then
        if pct < 45 then return 'waxingcrescent' end
        if pct < 55 then return 'firstquarter'   end
        return 'waxinggibbous'
    else
        if pct > 55 then return 'waninggibbous'  end
        if pct > 45 then return 'lastquarter'    end
        return 'waningcrescent'
    end
end
-- Skill ID → AshitaCast skill_name string
local SKILL_BY_ID = {
    [32] = 'Divine Magic', [33] = 'Healing Magic', [34] = 'Enhancing Magic',
    [35] = 'Enfeebling Magic', [36] = 'Elemental Magic', [37] = 'Dark Magic',
    [38] = 'Summoning Magic', [39] = 'Ninjutsu', [40] = 'Singing',
    [41] = 'String', [42] = 'Wind', [43] = 'Blue Magic', [44] = 'Geomancy',
}
-- Skill ID → AshitaCast ad_type bucket (WhiteMagic / BlackMagic / Ninjutsu / etc.)
local TYPE_BY_SKILL = {
    [32] = 'WhiteMagic', [33] = 'WhiteMagic', [34] = 'WhiteMagic',
    [35] = 'BlackMagic', [36] = 'BlackMagic', [37] = 'BlackMagic',
    [38] = 'SummonerPact', [39] = 'Ninjutsu', [40] = 'BardSong',
    [43] = 'BlueMagic', [44] = 'Geomancy',
}

local function build_spell_info(bot, spell_id)
    if spell_id == nil or spell_id == 0 then
        return { id = 0, name = '', type = '', skill_name = '', element = '',
                 recast = 0, casttime = 0, mpcost = 0, mpaftercast = 0, mppaftercast = 0 }
    end
    local meta = GetSpellMetaByID and GetSpellMetaByID(spell_id) or nil
    if meta == nil then
        return {
            id = spell_id, name = '', type = '', skill_name = '', element = '',
            recast = 0, casttime = 0, mpcost = 0,
            mpaftercast = bot:getMP() or 0,
            mppaftercast = bot:getMPP() or 0,
        }
    end
    local skill = meta.skill or 0
    return {
        id          = meta.id or spell_id,
        name        = meta.name or '',
        type        = TYPE_BY_SKILL[skill] or '',
        skill_name  = SKILL_BY_ID[skill]   or '',
        element     = ELEMENT_BY_ID[meta.element or -1] or '',
        recast      = 0,
        casttime    = 0,
        mpcost      = meta.mpcost or 0,
        mpaftercast = (bot:getMP() or 0) - (meta.mpcost or 0),
        mppaftercast = bot:getMPP() or 0,
    }
end

-- 28. build_ability_info
local function build_ability_info(bot, ability_id)
    if ability_id == nil or ability_id == 0 then
        return { id = 0, name = '', type = '', skill_name = '' }
    end
    return { id = ability_id, name = '', type = '', skill_name = '' }
end

-- 29. build_player_info
-- action_target (optional): the entity that's the target of the action being
-- processed. Populates at_* fields per spec. Returns at_* zeroed when nil
-- (correct behavior in idlegear, where Variables.txt says "It will return
-- false if you try to call it inside idlegear").
local function build_player_info(bot, action_target)
    -- p_status mirrors the original Ashita addon's status string. Ashita read
    -- the client's entity-manager status enum (1=engaged, 33=resting, 2/3=dead).
    -- On BE we don't have that exact enum exposed for chars, but the underlying
    -- state machine answers each question directly — query that instead of
    -- inferring from the visual animation channel. Priority: dead > resting >
    -- engaged > idle.
    local status_str
    if bot.isDead and bot:isDead() then
        status_str = 'dead'
    elseif bot.isBotResting and bot:isBotResting() then
        status_str = 'resting'
    elseif bot.isEngaged and bot:isEngaged() then
        status_str = 'engaged'
    else
        status_str = 'idle'
    end
    -- p_ismoving: derived from the per-bot scratch lastMovedMs that ai_move
    -- stamps on every step. Considered "moving" if we stepped within the last
    -- 500ms. Falls back to false when scratch isn't populated (e.g. primary
    -- in BotMode.Off — manual play; could be improved later by reading the
    -- engine's m_lastMove field if exposed).
    -- lastMovedMs is wall-clock epoch ms (written by ai_move.stepToward via
    -- the canonical ai_util formula), so the comparison here MUST be against
    -- the same scale. `os.clock()*1000` is CPU time since process start (~10^7)
    -- and would never come close to epoch ms (~10^12), so the delta check
    -- would always be > 500 and `moving` would be stuck at false.
    local moving = false
    if xi.singleplayer.bots.ensure_bot ~= nil then
        local s = xi.singleplayer.bots.ensure_bot(bot:getID())
        local now_ms = xi.singleplayer.bots.ai_util.get_ms_since_epoch()
        if s and s.lastMovedMs and s.lastMovedMs > 0 and (now_ms - s.lastMovedMs) < 500 then
            moving = true
        end
    end

    -- p_*resist: 8 elemental resistance ranks via Mod IDs 192-199.
    local function res(modId) return (bot.getMod and bot:getMod(modId)) or 0 end

    -- Environment lookups via global Vanadiel functions.
    local dayId        = (VanadielDayOfTheWeek and VanadielDayOfTheWeek()) or -1
    local dayElemId    = (VanadielDayElement   and VanadielDayElement())   or 0
    local moonPct      = (VanadielMoonPhase    and VanadielMoonPhase())    or 0
    local moonDir      = (VanadielMoonDirection and VanadielMoonDirection()) or 0
    local weatherId    = (bot.getWeather and bot:getWeather(false))        or 0
    local area_name    = (bot.getZoneName and bot:getZoneName())           or ''

    -- Target snapshot (the bot's own selected target, NOT the action target —
    -- at_* is populated separately during action processing).
    local tgt          = bot.getTarget and bot:getTarget() or nil
    local t_id, t_idx, t_hpp, t_dist, t_name, t_type = 0, 0, 0, 0, '', ''
    if tgt ~= nil then
        t_id   = tgt.getID    and tgt:getID()    or 0
        t_idx  = tgt.getTargID and tgt:getTargID() or 0
        t_hpp  = tgt.getHPP   and tgt:getHPP()   or 0
        t_dist = bot.checkDistance and bot:checkDistance(tgt) or 0
        t_name = tgt.getName  and tgt:getName()  or ''
        if tgt.isMob and tgt:isMob() then       t_type = 'monster'
        elseif tgt.isPC and tgt:isPC() then     t_type = 'pc'
        elseif tgt.isNPC and tgt:isNPC() then   t_type = 'npc'
        elseif tgt:getID() == bot:getID() then  t_type = 'self'
        else                                     t_type = 'unknown' end
    end

    -- Pet snapshot.
    local pet = bot.getPet and bot:getPet() or nil
    local pet_active, pet_hpp, pet_tp_v, pet_status_str, pet_name, pet_distance =
        'false', 0, 0, '', '', 0
    if pet ~= nil then
        pet_active = 'true'
        pet_hpp    = pet.getHPP and pet:getHPP() or 0
        pet_tp_v   = pet.getTP  and pet:getTP()  or 0
        pet_name   = pet.getName and pet:getName() or ''
        pet_distance = bot.checkDistance and bot:checkDistance(pet) or 0
        if pet.isDead and pet:isDead() then     pet_status_str = 'dead'
        elseif pet.isEngaged and pet:isEngaged() then pet_status_str = 'engaged'
        else                                          pet_status_str = 'idle' end
    end

    return {
        hp     = bot:getHP(),
        hpp    = bot:getHPP(),
        mp     = bot:getMP(),
        mpp    = bot:getMPP(),
        tp     = bot:getTP(),
        hpmax  = bot.getMaxHP and bot:getMaxHP() or 0,
        mpmax  = bot.getMaxMP and bot:getMaxMP() or 0,
        joblevel    = bot.getMainLvl and bot:getMainLvl() or 0,
        subjoblevel = bot.getSubLvl  and bot:getSubLvl()  or 0,
        attack      = (bot.getStat and bot:getStat(xi.mod and xi.mod.ATT or 0)) or 0,
        defense     = (bot.getStat and bot:getStat(xi.mod and xi.mod.DEF or 0)) or 0,
        ismoving    = moving and 'true' or 'false',
        -- Elemental resistance ranks
        fireresist      = res(RESIST_MOD.fire),
        iceresist       = res(RESIST_MOD.ice),
        windresist      = res(RESIST_MOD.wind),
        earthresist     = res(RESIST_MOD.earth),
        lightningresist = res(RESIST_MOD.lightning),
        waterresist     = res(RESIST_MOD.water),
        lightresist     = res(RESIST_MOD.light),
        darkresist      = res(RESIST_MOD.dark),
        status = status_str,
        mainjob = (xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.jobs and xi.singleplayer.bots.ai_util.jobs[bot:getMainJob()]) or '',
        subjob  = (xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.jobs and xi.singleplayer.bots.ai_util.jobs[bot:getSubJob()])  or '',
        name = bot:getName(),
        -- Composed "MNK/WAR" string for p_job per spec.
        job  = ((xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.jobs and xi.singleplayer.bots.ai_util.jobs[bot:getMainJob()]) or '')
            .. '/' ..
            ((xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.jobs and xi.singleplayer.bots.ai_util.jobs[bot:getSubJob()])  or ''),
        -- Environment
        area            = area_name,
        weather         = WEATHER_BY_ID[weatherId]         or 'unknown',
        weatherelement  = WEATHER_ELEMENT_BY_ID[weatherId] or 'unknown',
        day             = DAY_BY_ID[dayId]                 or 'unknown',
        dayelement      = DAY_ELEMENT_BY_ID[dayElemId]     or 'unknown',
        moon            = classify_moon(moonPct, moonDir),
        moonpct         = moonPct,
        -- Selected target
        t_id = t_id, t_index = t_idx, t_hpp = t_hpp, t_distance = t_dist,
        t_name = t_name, t_type = t_type,
        -- Action target — populated only when action_target was supplied.
        -- Per spec, idlegear evaluation gets all-zero/empty values here.
        at_id       = (action_target and action_target.getID and action_target:getID()) or 0,
        at_index    = (action_target and action_target.getTargID and action_target:getTargID()) or 0,
        at_hpp      = (action_target and action_target.getHPP and action_target:getHPP()) or 0,
        at_distance = (action_target and bot.checkDistance and bot:checkDistance(action_target)) or 0,
        at_name     = (action_target and action_target.getName and action_target:getName()) or '',
        at_type     = (function()
            if action_target == nil then return '' end
            if action_target.isMob and action_target:isMob() then return 'monster' end
            if action_target.isPC  and action_target:isPC()  then return 'pc'      end
            if action_target.isNPC and action_target:isNPC() then return 'npc'     end
            if action_target.getID and action_target:getID() == bot:getID() then return 'self' end
            return 'unknown'
        end)(),
        -- Party / alliance.
        pt_inparty = ((bot.getPartySize and bot:getPartySize()) or 1) > 1 and 'true' or 'false',
        pt_count   = (bot.getPartySize and bot:getPartySize()) or 1,
        pt_target  = 'false', pt_actiontarget = 'false',
        a_inally   = ((bot.getAllianceSize and bot:getAllianceSize()) or 1) > 1 and 'true' or 'false',
        a_count    = (bot.getAllianceSize and bot:getAllianceSize()) or 1,
        a_target   = 'false', a_actiontarget = 'false',
        -- Pet
        pet_active   = pet_active,
        pet_hpp      = pet_hpp,
        pet_tp       = pet_tp_v,
        pet_status   = pet_status_str,
        pet_name     = pet_name,
        pet_distance = pet_distance,
    }
end

-- 30. send_equip_packets
--     Server-side: call bot:equipItem(itemId, slotId) per slot.
--
--     Item-name normalization: the item_basic.name column is snake_case
--     lowercase ('healers_bliaut') and GetItemIDByName does a literal LIKE
--     match. XMLs typically use display names ("Healer's Bliaut") with
--     apostrophes/spaces, which always miss. Mirror the WS-name fix in
--     ai_ability.use_ws: try the original first, then normalized
--     (lowercase + strip apostrophes + non-alnum → underscore + collapse).
-- Item-name → itemid resolution is now driven by a static Ashita-style
-- resources table at modules/singleplayer/lib/item_list.lua. Each entry has
-- both `en` (display/abbreviated, e.g. "Sniper's Ring +1") and `enl` (long
-- form, e.g. "sniper's ring +1"). We index by both into the same itemid so
-- XMLs written against either spelling resolve identically.
--
-- Indexes are CASE-INSENSITIVE: both the index keys and the lookup query
-- are lowercased. That means "Sniper's Ring +1" / "sniper's ring +1" /
-- "SNIPER'S RING +1" all resolve, AND when the resource file only carries
-- the `enl` form ("scorpion harness +1") it still matches an XML written
-- with display capitalization ("Scorpion Harness +1") via the enl index.
--
-- This replaces the prior GetItemIDByName + normalization cascade. The DB
-- column-LIKE behavior had two failure modes — `_` acting as a wildcard and
-- our two-form normalizer not covering every Ashita abbreviation. The
-- resources file is authoritative: if a name doesn't resolve here, it was
-- typed wrong (no silent fallback).
local _item_index_en  = {}
local _item_index_enl = {}
do
    local ok, items = pcall(require, 'modules/singleplayer/lib/item_list')
    if ok and type(items) == 'table' then
        for _, entry in pairs(items) do
            if type(entry) == 'table' and entry.id and entry.id > 0 then
                if entry.en  then _item_index_en [entry.en:lower()]  = entry.id end
                if entry.enl then _item_index_enl[entry.enl:lower()] = entry.id end
            end
        end
    else
        ShowWarning('ai_equip_swap: failed to load modules/singleplayer/lib/item_list — gear swaps will fail')
    end
end

local function resolve_item_id(name)
    if name == nil or name == '' then return 0 end
    local key = name:lower()
    return _item_index_en[key] or _item_index_enl[key] or 0
end

-- Equipment-bearing containers, in lookup order. equipItem silently no-ops
-- when the item isn't in the specified container, so we iterate every
-- container a player might keep gear in. LOC_INVENTORY first because that's
-- where headless bots' gear lives (their preloaded set never moves out).
-- Wardrobes 1-8 cover the primary's actual gear layout. LOC_MOGSAFE and
-- LOC_STORAGE are intentionally omitted — items in those can't be equipped
-- without first being moved to inventory/wardrobe.
local EQUIP_CONTAINERS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 } -- INVENTORY + WARDROBE..WARDROBE8

local function send_equip_packets(bot, gear)
    local changed = {}
    -- equipItemUnique is the singleplayer-fork's variant of equipItem that
    -- handles the two-of-same-item case (e.g. two Sniper's Ring +1 → ring1
    -- + ring2): it picks an inventory copy that isn't already equipped to
    -- a different slot than the requested target. Plain equipItem uses
    -- SearchItem (first match) which silently moves the same ring between
    -- equip slots, leaving the second copy in inventory untouched.
    if bot.equipItemUnique == nil then return changed end
    -- Walk slots in SLOT_EQUIP_ORDER (body before head, etc.) instead of
    -- pairs(gear) so restrictive bodies don't strip user-specified heads.
    for _, slot_name in ipairs(SLOT_EQUIP_ORDER) do
        local item_name = gear[slot_name]
        local slot_id = SLOT_BY_NAME[slot_name]
        if item_name ~= nil and slot_id ~= nil and item_name ~= '' then
            local itemId = resolve_item_id(item_name)
            if itemId > 0 then
                -- Walk every equipment-bearing container. Only the one
                -- that actually holds the item performs work (SearchItems
                -- returns empty elsewhere and the C++ silently returns).
                for _, container_id in ipairs(EQUIP_CONTAINERS) do
                    bot:equipItemUnique(itemId, container_id, slot_id)
                end
                changed[slot_name] = item_name
            end
        end
    end
    return changed
end

-- 32. format_changed
local function format_changed(changed)
    local parts = {}
    for slot, item in pairs(changed) do
        table.insert(parts, slot .. '=' .. item)
    end
    return table.concat(parts, ', ')
end

-- 33. equip_section
local function equip_section(bot, section_name, spell_info, action_target)
    -- elog noop by default; uncomment the printf line below when debugging
    -- ai_equip_swap section transitions, skip reasons, and successful swaps.
    local elog = function(msg)
        -- printf(string.format('[AutoEquip] %s %s', bot and bot:getName() or '?', msg))
    end
    if bot == nil then return false end
    if not ensure_loaded(bot) then
        elog(string.format('skip %s: ensure_loaded=false (no XML for %s_%s?)',
            section_name, bot:getName(),
            (xi.singleplayer.bots.ai_util and xi.singleplayer.bots.ai_util.jobs and xi.singleplayer.bots.ai_util.jobs[bot:getMainJob()]) or '?'))
        return false
    end
    ai_equip_swap.current_section[bot:getID()] = section_name
    local section = get_section(bot, section_name)
    if section == nil then
        elog(string.format('skip %s: section not present in XML', section_name))
        return false
    end
    local entry = ai_equip_swap.cache[bot:getID()]
    if entry == nil or entry.sets_node == nil then
        elog(string.format('skip %s: cache entry/sets_node missing', section_name))
        return false
    end
    local player_info = build_player_info(bot, action_target)
    local gear = process_section(bot, section, spell_info or {}, player_info, entry.sets_node, entry.variables or {})
    if next(gear) == nil then
        elog(string.format('skip %s: process_section produced no slot rules (no matching <if>/<else>?)', section_name))
        return false
    end

    -- Dedupe against what the bot is CURRENTLY WEARING (not what this
    -- section last computed). If the freshly computed gear matches the
    -- last-applied set slot-for-slot, no swap is needed. This is what
    -- prevents idle-tick spam while still letting section transitions
    -- (midmagic → idlegear) fire when the underlying gear actually differs.
    local botId = bot:getID()
    local prev  = ai_equip_swap.last_gear[botId]
    if prev ~= nil then
        local identical = true
        local prevCount, gearCount = 0, 0
        for k, _ in pairs(prev) do prevCount = prevCount + 1 end
        for k, _ in pairs(gear) do gearCount = gearCount + 1 end
        if prevCount ~= gearCount then
            identical = false
        else
            for slot, item in pairs(gear) do
                if prev[slot] ~= item then identical = false; break end
            end
        end
        if identical then return true end
    end

    local changed = send_equip_packets(bot, gear)
    if next(changed) == nil then
        -- gear was non-empty but every slot failed to equip. Show what was
        -- attempted so the user can see if it's missing items or name lookup.
        local attempted = {}
        for slot, item in pairs(gear) do table.insert(attempted, slot .. '=' .. tostring(item)) end
        elog(string.format('skip %s: send_equip_packets returned empty (item not in inventory or GetItemIDByName=0). attempted=[%s]',
            section_name, table.concat(attempted, ', ')))
        return true
    end
    -- Stamp the bot's currently-worn set so future calls (any section) can
    -- dedupe against actual state.
    ai_equip_swap.last_gear[botId] = gear

    -- #200 diagnostic: confirm ai_equip_swap is firing.
    elog(section_name .. ' → ' .. format_changed(changed))
    return true
end

-----------------------------------
-- Public swap entry points (called from bot_magic / bot_ability)
-----------------------------------

-- 34. tick
function ai_equip_swap.tick(bot)
    if bot == nil then return end
    if ai_equip_swap.current_section[bot:getID()] ~= 'idlegear' then return end
    equip_section(bot, 'idlegear', {})
end

-- 35. equip_premagic
function ai_equip_swap.equip_premagic(bot, spell_id, target)
    equip_section(bot, 'premagic', build_spell_info(bot, spell_id), target)
end

-- 36. equip_midcast
function ai_equip_swap.equip_midcast(bot, spell_id, target)
    equip_section(bot, 'midmagic', build_spell_info(bot, spell_id), target)
end

-- 37. equip_idlegear
function ai_equip_swap.equip_idlegear(bot)
    equip_section(bot, 'idlegear', {})
end

-- 38. equip_weaponskill
function ai_equip_swap.equip_weaponskill(bot, ws_id, target)
    equip_section(bot, 'weaponskill', {}, target)
end

-- 39. equip_preranged
function ai_equip_swap.equip_preranged(bot, target)
    equip_section(bot, 'preranged', {}, target)
end

-- 40. equip_midranged
function ai_equip_swap.equip_midranged(bot, target)
    equip_section(bot, 'midranged', {}, target)
end

-- 41. equip_petskill
function ai_equip_swap.equip_petskill(bot, skill_id, target)
    equip_section(bot, 'petskill', {}, target)
end

-- 42. equip_petspell
function ai_equip_swap.equip_petspell(bot, spell_id, target)
    equip_section(bot, 'petspell', build_spell_info(bot, spell_id), target)
end

-- 43. equip_jobability
function ai_equip_swap.equip_jobability(bot, ability_id, target)
    equip_section(bot, 'jobability', build_ability_info(bot, ability_id), target)
end

-- 44. equip_gearlock
--
-- Two phases:
--   1. equip_section('gearlock') equips the items for real so their stats
--      apply (matches every other section's behavior).
--   2. The same resolved gear table also drives applyStyleLock so the bot's
--      VISUAL appearance is pinned to the gearlock set. Once Style Lock is
--      on, every appearance push uses mainlook (composited from styleItems)
--      regardless of which gear set is currently equipped underneath. This
--      lets autoequip swap real gear for casting / WS while observers keep
--      seeing the user's intended "park" look.
--
-- equip_gearlock is for HEADLESS (whose inventory matches their XML) and
-- for explicit "park me" use on primary. For the routine login-time visual
-- lock on primary, use apply_gearlock_lockstyle below — same visual effect
-- without the equip_section side-effects that would persist gear changes
-- to char_equip.
function ai_equip_swap.equip_gearlock(bot)
    if bot == nil then return end
    equip_section(bot, 'gearlock', {})
    if bot.applyStyleLock == nil then return end
    local gear = ai_equip_swap.last_gear[bot:getID()]
    if gear == nil then return end
    -- Build a sparse {slotId -> itemId} table for the binding. Only the
    -- visual slots (0..8) matter; accessories don't render so we skip
    -- them. Items the lookup can't resolve get omitted, which is the
    -- same as clearing the slot in applyStyleLock (slot ends up as 0).
    local slotIds = {}
    for slot_name, item_name in pairs(gear) do
        local slot_id = SLOT_BY_NAME[slot_name]
        if slot_id ~= nil and slot_id < 9 then
            local id = resolve_item_id(item_name)
            if id > 0 then slotIds[slot_id] = id end
        end
    end
    bot:applyStyleLock(slotIds)
end

-- 44a. apply_gearlock_lockstyle
--
-- Visual-only: resolves the bot's <gearlock> section from XML and calls
-- applyStyleLock, but does NOT run equip_section. The previous client-
-- side path (autoequip addon → 0x053 Set) had a couple of long-standing
-- problems for primary:
--   * The addon's first XML fetch is lazy (waits for first UI open), so
--     the lockstyle wouldn't apply until the user opened the addon at
--     least once.
--   * Round-trips through the addon are noisy / fragile compared to the
--     server-resident path.
-- The server already has the XML on disk under singleplayer/config/equip/
-- AND the applyStyleLock binding, so doing this here on onGameIn is the
-- right home. Headless still goes through spawn-finalize equip_gearlock
-- (which is correct for them: they need the real equip too).
function ai_equip_swap.apply_gearlock_lockstyle(bot)
    if bot == nil then return end
    if bot.applyStyleLock == nil then return end
    if not ensure_loaded(bot) then return end
    local entry = ai_equip_swap.cache[bot:getID()]
    if entry == nil or entry.sets_node == nil then return end
    local section = get_section(bot, 'gearlock')
    if section == nil then return end
    local player_info = build_player_info(bot, nil)
    local gear = process_section(bot, section, {}, player_info, entry.sets_node, entry.variables or {})
    if next(gear) == nil then return end
    local slotIds = {}
    for slot_name, item_name in pairs(gear) do
        local slot_id = SLOT_BY_NAME[slot_name]
        if slot_id ~= nil and slot_id < 9 then
            local id = resolve_item_id(item_name)
            if id > 0 then slotIds[slot_id] = id end
        end
    end
    if next(slotIds) == nil then return end
    bot:applyStyleLock(slotIds)
end

-- 45. equip_set
function ai_equip_swap.equip_set(bot, set_name)
    if not ensure_loaded(bot) then return false end
    local entry = ai_equip_swap.cache[bot:getID()]
    if entry == nil or entry.sets_node == nil then return false end
    local gear = resolve_set(entry.sets_node, set_name, {})
    if next(gear) == nil then return false end
    send_equip_packets(bot, gear)
    return true
end

ai_equip_swap.resolve_set = resolve_set

-----------------------------------
-- Event-listener wiring (server-side)
-- Called from bot_ai when a bot spawns. Registers PAI event listeners that
-- swap gear at the right lifecycle points.
-----------------------------------
function ai_equip_swap.register_listeners(bot)
    if bot == nil or bot.addListener == nil then return end

    -- Magic: MAGIC_START fires after cast time is computed (premagic gear
    -- caller-swapped before bot:castSpell). Swap to midmagic so the effect
    -- calc at cast finish uses it.
    -- Magic. STATE_ENTER fires in CMagicState constructor BEFORE cast time is
    -- computed — premagic gear (Fast Cast, Cast Time Reduction) takes effect
    -- on THIS cast. MAGIC_START fires after announce, so midmagic gear applies
    -- to the eventual damage/effect calc at cast finish. Bot AI also pre-swaps
    -- before bot:castSpell; both routes converge idempotently.
    bot:addListener('MAGIC_STATE_ENTER', 'BOT_EQUIP_MAGIC_ENTER', function(caster, target, spell)
        local spellId = spell and spell.getID and spell:getID() or 0
        ai_equip_swap.equip_premagic(caster, spellId, target)
    end)

    bot:addListener('MAGIC_START', 'BOT_EQUIP_MAGIC_START', function(caster, target, spell, action)
        local spellId = spell and spell.getID and spell:getID() or 0
        ai_equip_swap.equip_midcast(caster, spellId, target)
    end)

    bot:addListener('MAGIC_STATE_EXIT', 'BOT_EQUIP_MAGIC_EXIT', function(caster, spell)
        ai_equip_swap.equip_idlegear(caster)
    end)

    -- Weapon skill. ENTER fires from CWeaponSkillState constructor right after
    -- the SkillStart packet (before SpendCost / damage resolution), giving the
    -- listener one engine tick to swap gear before Update() runs. STATE_EXIT
    -- fires when the animation completes. The bot-AI path additionally calls
    -- equip_weaponskill before bot:weaponSkill() — both routes converge on the
    -- same swap, idempotent. The ENTER fix is what makes manual primary WSes
    -- get their WS gear (mob/pet emit this naturally; player WS didn't until
    -- the engine change in weaponskill_state.cpp landed).
    bot:addListener('WEAPONSKILL_STATE_ENTER', 'BOT_EQUIP_WS_ENTER', function(actor, wsId)
        ai_equip_swap.equip_weaponskill(actor, wsId)
    end)

    bot:addListener('WEAPONSKILL_STATE_EXIT', 'BOT_EQUIP_WS_EXIT', function(actor, wsId)
        ai_equip_swap.equip_idlegear(actor)
    end)

    -- Job ability. ABILITY_START fires from C++ ability_state.cpp before the
    -- effect resolves, so jobability gear is on for the cost/effect calc.
    -- The bot AI path (ai_ability.use_ability) also calls equip_jobability
    -- preemptively — both routes converge on the same swap, idempotent.
    bot:addListener('ABILITY_START', 'BOT_EQUIP_ABILITY_START', function(actor, ability)
        local abilityId = ability and ability.getID and ability:getID() or 0
        ai_equip_swap.equip_jobability(actor, abilityId)
    end)

    bot:addListener('ABILITY_STATE_EXIT', 'BOT_EQUIP_ABILITY_EXIT', function(actor, ability)
        ai_equip_swap.equip_idlegear(actor)
    end)

    -- Engage / disengage. Re-evaluates the idlegear conditional XML so
    -- <if p_status="engaged"> branches pick the right set immediately.
    -- Manual primary actions (swing a sword without casting first) need this
    -- — without it, idlegear is only re-evaluated when a cast/WS/JA exits.
    bot:addListener('ENGAGE', 'BOT_EQUIP_ENGAGE', function(actor, target)
        ai_equip_swap.equip_idlegear(actor)
    end)

    bot:addListener('DISENGAGE', 'BOT_EQUIP_DISENGAGE', function(actor)
        ai_equip_swap.equip_idlegear(actor)
    end)

    -- Rest transitions. EFFECT_HEALING is added when the player presses /heal
    -- and removed when they stand. Re-eval idlegear so conditional XML branches
    -- like <if p_status="resting"> light up immediately.
    bot:addListener('EFFECT_GAIN', 'BOT_EQUIP_EFFECT_GAIN', function(actor, effect)
        local effectId = effect and effect.getEffectType and effect:getEffectType() or 0
        if effectId == xi.effect.HEALING then ai_equip_swap.equip_idlegear(actor) end
    end)
    bot:addListener('EFFECT_LOSE', 'BOT_EQUIP_EFFECT_LOSE', function(actor, effect)
        local effectId = effect and effect.getEffectType and effect:getEffectType() or 0
        if effectId == xi.effect.HEALING then ai_equip_swap.equip_idlegear(actor) end
    end)

    -- Ranged. STATE_ENTER fires in CRangeState constructor BEFORE delay is
    -- computed — preranged gear (Snapshot, Velocity Shot) takes effect on
    -- THIS shot's aim time. RANGE_START fires after delay is locked in, so
    -- midranged gear applies to the damage calc at shot finish.
    bot:addListener('RANGE_STATE_ENTER', 'BOT_EQUIP_RANGE_ENTER', function(actor, target)
        ai_equip_swap.equip_preranged(actor, target)
    end)

    bot:addListener('RANGE_START', 'BOT_EQUIP_RANGE_START', function(actor, action)
        ai_equip_swap.equip_midranged(actor)
    end)

    bot:addListener('RANGE_STATE_EXIT', 'BOT_EQUIP_RANGE_EXIT', function(actor, target, action)
        ai_equip_swap.equip_idlegear(actor)
    end)
end

-- Unregister all listeners for a bot (called from bot_ai on cascade cleanup)
function ai_equip_swap.unregister_listeners(bot)
    if bot == nil or bot.removeListener == nil then return end
    bot:removeListener('BOT_EQUIP_MAGIC_ENTER')
    bot:removeListener('BOT_EQUIP_MAGIC_START')
    bot:removeListener('BOT_EQUIP_MAGIC_EXIT')
    bot:removeListener('BOT_EQUIP_WS_ENTER')
    bot:removeListener('BOT_EQUIP_WS_EXIT')
    bot:removeListener('BOT_EQUIP_ABILITY_START')
    bot:removeListener('BOT_EQUIP_ABILITY_EXIT')
    bot:removeListener('BOT_EQUIP_ENGAGE')
    bot:removeListener('BOT_EQUIP_DISENGAGE')
    bot:removeListener('BOT_EQUIP_EFFECT_GAIN')
    bot:removeListener('BOT_EQUIP_EFFECT_LOSE')
    bot:removeListener('BOT_EQUIP_RANGE_ENTER')
    bot:removeListener('BOT_EQUIP_RANGE_START')
    bot:removeListener('BOT_EQUIP_RANGE_EXIT')
end

-----------------------------------
-- Register listeners on every char that zones in — unconditionally,
-- regardless of whether they have an XML config for their current job.
--
-- Why unconditional: a player can log in on a job they don't have XML for,
-- then switch to a job that does (via Nomad Moogle, change-of-job menu,
-- /sjob, etc.). If we only register listeners when XML loads on login, the
-- post-job-change action wouldn't fire the swap path. By always registering,
-- the listener calls equip_section → ensure_loaded → load on first action
-- after a job change, so gear swap "just works" mid-session.
--
-- The PAI events (MAGIC_START etc.) already trigger for ANY cast (bot AI or
-- manual). Once listeners are wired, gear swap is automatic.
--
-- onGameIn fires on initial login AND zone changes, so listeners are
-- idempotently re-registered. addListener with the same identifier replaces
-- an existing one, so this is safe to call repeatedly.
-----------------------------------
m:addOverride('xi.player.onGameIn', function(player, isFirstLogin, isZoning)
    super(player, isFirstLogin, isZoning)
    if player == nil then return end
    ai_equip_swap.register_listeners(player)
    -- Apply the primary's <gearlock> visual lock at login / zone-in. No
    -- client involvement, no addon load timing, no "open the addon UI
    -- once before it kicks in." Pure visual: doesn't touch real equip,
    -- so it can't corrupt char_equip the way equip_gearlock could.
    ai_equip_swap.apply_gearlock_lockstyle(player)
end)

-----------------------------------
-- autoupdate: AshitaCast's <settings><autoupdate>true</autoupdate>. Re-eval
-- idlegear at a coarse cadence so XML conditional state (HP/MP thresholds
-- crossed by regen, etc.) that wasn't tripped by a discrete event still
-- ends up in the right gear within ~1-2 seconds. Throttled to 1s per bot
-- to keep the cost negligible — XML parse + ~16 slot lookups, cheap on
-- modern hardware but redundant at 1Hz across every char in a zone.
-- Idlegear-only — action sections only re-equip on their own trigger.
-----------------------------------
local AUTOUPDATE_THROTTLE_MS = 1000
local autoupdate_next = {}

m:addOverride('xi.singleplayer.bots.onBotTick', function(entity, mode)
    if super then super(entity, mode) end
    if entity == nil then return end
    local id = entity:getID()
    local now_ms = math.floor(os.clock() * 1000)
    local due = autoupdate_next[id] or 0
    if now_ms < due then return end
    autoupdate_next[id] = now_ms + AUTOUPDATE_THROTTLE_MS

    -- Only re-eval when we're already in idlegear — action sections (cast/WS
    -- in flight) own their own gear until they exit. Mirrors ai_equip_swap.tick.
    if ai_equip_swap.current_section[id] == 'idlegear' then
        ai_equip_swap.equip_idlegear(entity)
    end
end)

return m
