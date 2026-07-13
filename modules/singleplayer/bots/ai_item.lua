-----------------------------------
-- Server-side port of the client-side library
--
-- Consumable item helpers (potion / ether / antidote / remedy / ninja tools).
-- entity:hasItem() / entity:findItem(), and replaces /item slash command
-- dispatch with entity:useItem(location, slotId, target).
--
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_item')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.item = xi.singleplayer.bots.item or {}
local ai_item = xi.singleplayer.bots.item

-- Item IDs (verified against sql/item_basic.sql):
--   4155 = Remedy
--   4148 = Antidote
--   4150 = Eye Drops
--   4151 = Echo Drops
--   4154 = Holy Water
--   1179 = Shihei (ninja tool)
--   5314 = Shihei Toolbag (12-stack equivalent)
local ITEM_REMEDY         = 4155
local ITEM_ANTIDOTE       = 4148
local ITEM_EYE_DROPS      = 4150
local ITEM_ECHO_DROPS     = 4151
local ITEM_HOLY_WATER     = 4154
local ITEM_SHIHEI         = 1179
local ITEM_SHIHEI_TOOLBAG = 5314

-- HP potion + MP ether tiers, STRONGEST → WEAKEST. have_potion / use_potion
-- walk these in order and pick the first inventory hit, so the bot burns
-- its best stock first and the weaker tiers act as overflow when the
-- strong ones run out. Order matters; do not sort.
local HP_POTION_TIERS = {
    5254,                         -- Hyper Potion
    4127, 4126, 4125, 4124,       -- Max-Potion +3, +2, +1, base
    4123, 4122, 4121, 4120,       -- X-Potion   +3, +2, +1, base
    4119, 4118, 4117, 4116,       -- Hi-Potion  +3, +2, +1, base
    4112,                         -- Potion
}
local MP_ETHER_TIERS = {
    5255,                         -- Hyper Ether
    4143, 4142, 4141, 4140,       -- Pro-Ether   +3, +2, +1, base
    4139, 4138, 4137, 4136,       -- Super Ether +3, +2, +1, base
    4135, 4134, 4133, 4132,       -- Hi-Ether    +3, +2, +1, base
    4128,                         -- Ether
}

-- Strongest-tier scan. Returns the item ID we should burn this tick, or
-- nil if the bot has nothing in the list.
local function best_in_tiers(bot, tiers)
    for _, itemId in ipairs(tiers) do
        if bot:hasItem(itemId) then return itemId end
    end
    return nil
end

-- Local helper to fire the right entity:useItem() — finds the item slot then
-- delegates to the server-side action queue. Exposed publicly via
-- ai_item.use_item_by_id so ai_command can dispatch /item verbs.
local function use_item_by_id(bot, itemId, target)
    local item = bot:findItem(itemId)
    if item == nil then return false end
    target = target or bot
    bot:useItem(item:getLocationID(), item:getSlotID(), target)
    return true
end
ai_item.use_item_by_id = use_item_by_id

-----------------------------------
-- 1. have_item
-----------------------------------
function ai_item.have_item(bot, itemId)
    return bot:hasItem(itemId)
end

-----------------------------------
-- 2. have_remedy
-----------------------------------
function ai_item.have_remedy(bot)
    if ai_item.have_item(bot, ITEM_REMEDY) then return true end
    xi.singleplayer.bots.ai_util.log(bot, 'AutoItem', 'No Remedy found!')
    return false
end

-----------------------------------
-- 3. use_remedy
-----------------------------------
function ai_item.use_remedy(bot)
    return use_item_by_id(bot, ITEM_REMEDY, bot)
end

-----------------------------------
-- 4. have_potion  — any tier; see HP_POTION_TIERS.
-----------------------------------
function ai_item.have_potion(bot)
    if best_in_tiers(bot, HP_POTION_TIERS) ~= nil then return true end
    xi.singleplayer.bots.ai_util.log(bot, 'AutoItem', 'No HP potion found!')
    return false
end

-----------------------------------
-- 5. use_potion  — burns the strongest tier in inventory.
-----------------------------------
function ai_item.use_potion(bot)
    local id = best_in_tiers(bot, HP_POTION_TIERS)
    if id == nil then return false end
    return use_item_by_id(bot, id, bot)
end

-----------------------------------
-- 6. have_ether  — any tier; see MP_ETHER_TIERS.
-----------------------------------
function ai_item.have_ether(bot)
    if best_in_tiers(bot, MP_ETHER_TIERS) ~= nil then return true end
    xi.singleplayer.bots.ai_util.log(bot, 'AutoItem', 'No MP ether found!')
    return false
end

-----------------------------------
-- 7. use_ether  — burns the strongest tier in inventory.
-----------------------------------
function ai_item.use_ether(bot)
    local id = best_in_tiers(bot, MP_ETHER_TIERS)
    if id == nil then return false end
    return use_item_by_id(bot, id, bot)
end

-----------------------------------
-- 8. have_antidote
-----------------------------------
function ai_item.have_antidote(bot)
    if ai_item.have_item(bot, ITEM_ANTIDOTE) then return true end
    xi.singleplayer.bots.ai_util.log(bot, 'AutoItem', 'No Antidote found!')
    return false
end

-----------------------------------
-- 9. use_antidote
-----------------------------------
function ai_item.use_antidote(bot)
    return use_item_by_id(bot, ITEM_ANTIDOTE, bot)
end

-----------------------------------
-- 10. have_shihei
-----------------------------------
function ai_item.have_shihei(bot)
    return ai_item.have_item(bot, ITEM_SHIHEI)
end

-----------------------------------
-- 11. have_shihei_toolbag
-----------------------------------
function ai_item.have_shihei_toolbag(bot)
    return ai_item.have_item(bot, ITEM_SHIHEI_TOOLBAG)
end

-----------------------------------
-- 12. use_shihei_toolbag
-----------------------------------
function ai_item.use_shihei_toolbag(bot)
    return use_item_by_id(bot, ITEM_SHIHEI_TOOLBAG, bot)
end

-----------------------------------
-- 13. status-cure items (echo drops / eye drops / holy water)
--     Mirror antidote pattern but no chat log on miss — the Role AI
--     policy walker will already have decided to attempt this; absent
--     stock just cascades to Remedy fallback silently.
-----------------------------------
function ai_item.have_echo_drops(bot) return ai_item.have_item(bot, ITEM_ECHO_DROPS) end
function ai_item.use_echo_drops(bot)  return use_item_by_id(bot, ITEM_ECHO_DROPS, bot) end

function ai_item.have_eye_drops(bot)  return ai_item.have_item(bot, ITEM_EYE_DROPS) end
function ai_item.use_eye_drops(bot)   return use_item_by_id(bot, ITEM_EYE_DROPS, bot) end

function ai_item.have_holy_water(bot) return ai_item.have_item(bot, ITEM_HOLY_WATER) end
function ai_item.use_holy_water(bot)  return use_item_by_id(bot, ITEM_HOLY_WATER, bot) end

-----------------------------------
-- Role AI policy
--
-- Alliance-wide per-role item-usage settings driven by the Role AI tab.
-- Replaces the legacy single NM Mode flag with a per-role × per-type
-- matrix. Storage lives on xi.singleplayer.bots.alliance.rolePolicy:
--   alliance.rolePolicy[roleKey][typeKey]            = mode
--   alliance.rolePolicy[roleKey].statusFlags[key]    = bool
--
-- Roles:  tank / melee / heal / rdm / nuke
-- Types:  hp   / mp    / status
-- Modes:  off / nm / always
--
-- Lives here (vs a standalone role_policy module) because role_* file
-- names are reserved for AI tick decision loops; policy state is item
-- code and shares lifecycle with the try_* helpers below.
-----------------------------------

-- Canonical packet-byte → key mappings. Wire-format contract shared with
-- the client (autoutil.RoleAi* + role_ai_tab.lua); never reorder these.
local ROLE_BY_INDEX = { [0] = 'tank', [1] = 'melee', [2] = 'heal', [3] = 'rdm', [4] = 'nuke', [5] = 'brd', [6] = 'smn' }
local TYPE_BY_INDEX = { [0] = 'hp',   [1] = 'mp',    [2] = 'status' }
local MODE_BY_INDEX = { [0] = 'off',  [1] = 'nm',    [2] = 'always' }

-- Status list — canonical order is the wire-format key. Each entry pairs
-- an engine effect with the cheapest specific cure item (nil = no specific
-- cure). Adding a new status: append here AND mirror the index in
-- autoutil.RoleAiStatusList. Never reorder; statusKey is a wire byte.
--   specific_have / specific_use — paired ai_item helpers; nil = no
--                                  specific cure item exists.
--   remedy_cures                — true iff Remedy clears this status
--                                  (canonical 5: Blind / Disease / Para /
--                                  Poison / Silence).
--   Plague / Petrify / Slow / Bind / Doom intentionally absent — no item
--   cure path makes the checkbox inert.
local STATUS_LIST = {
    { key = 0, label = 'Poison',   effect = xi.effect.POISON,    specific_have = 'have_antidote',   specific_use = 'use_antidote',   remedy_cures = true  },
    { key = 1, label = 'Silence',  effect = xi.effect.SILENCE,   specific_have = 'have_echo_drops', specific_use = 'use_echo_drops', remedy_cures = true  },
    { key = 2, label = 'Blind',    effect = xi.effect.BLINDNESS, specific_have = 'have_eye_drops',  specific_use = 'use_eye_drops',  remedy_cures = true  },
    { key = 3, label = 'Paralyze', effect = xi.effect.PARALYSIS, specific_have = nil,               specific_use = nil,              remedy_cures = true  },
    { key = 4, label = 'Curse',    effect = xi.effect.CURSE_I,   specific_have = 'have_holy_water', specific_use = 'use_holy_water', remedy_cures = false },
    { key = 5, label = 'Disease',  effect = xi.effect.DISEASE,   specific_have = nil,               specific_use = nil,              remedy_cures = true  },
}

local STATUS_BY_KEY = {}
for _, entry in ipairs(STATUS_LIST) do STATUS_BY_KEY[entry.key] = entry end

-- Default-ticked statuses: Poison / Silence / Blind / Paralyze. Others
-- start unchecked — they're rare and Remedy is expensive.
local DEFAULT_STATUS_ON = { [0] = true, [1] = true, [2] = true, [3] = true }

-- Fixed thresholds (user-locked spec: 20% for both). Exposed on ai_item
-- so callers / tests can read them without spelunking.
ai_item.HP_THRESHOLD = 20
ai_item.MP_THRESHOLD = 20

-- Melee MP gate — only DRK and BLU benefit from ethers in the melee role.
-- NIN's MP need is utsusemi-tight but excluded per user spec.
local MELEE_MP_JOBS = { DRK = true, BLU = true }

-- Lazy-init the policy table on the alliance. Defaults to all-Off (explicit
-- opt-in) so a fresh alliance doesn't burn consumables on the first fight.
-- Default-ticked statuses are stored on the policy so the addon's first
-- snapshot read matches what the UI renders.
local function ensure_policy()
    if xi.singleplayer.bots.alliance == nil then return nil end
    local A = xi.singleplayer.bots.alliance
    if A.rolePolicy == nil then
        A.rolePolicy = {}
        for _, role in pairs(ROLE_BY_INDEX) do
            A.rolePolicy[role] = {
                hp     = 'off',
                mp     = 'off',
                status = 'off',
                statusFlags = {},
            }
            for _, entry in ipairs(STATUS_LIST) do
                A.rolePolicy[role].statusFlags[entry.key] = DEFAULT_STATUS_ON[entry.key] == true
            end
        end
    end
    return A.rolePolicy
end

-- Bot state stores role as the xi.singleplayer.bots.Role enum int. Translate
-- to the policy key. Skillup + Idle have no policy and resolve to nil — the
-- caller treats nil as 'off'.
local function role_key_from_enum(roleInt)
    local R = xi.singleplayer.bots.Role or {}
    if roleInt == R.Tank   then return 'tank'   end
    if roleInt == R.Melee  then return 'melee'  end
    if roleInt == R.Healer then return 'heal'   end
    if roleInt == R.Rdm    then return 'rdm'    end
    if roleInt == R.Nuker  then return 'nuke'   end
    if roleInt == R.Brd    then return 'brd'    end
    if roleInt == R.Smn    then return 'smn'    end
    return nil
end

local function role_for_bot(bot)
    local state = xi.singleplayer.bots.ensure_bot and xi.singleplayer.bots.ensure_bot(bot:getID())
    if state == nil then return nil end
    return role_key_from_enum(state.role)
end

local function mode_allows(mode, isNm)
    if mode == 'always' then return true end
    if mode == 'nm' and isNm then return true end
    return false
end

local function mode_for(bot, typ)
    local rp = ensure_policy()
    if rp == nil then return 'off' end
    local role = role_for_bot(bot)
    if role == nil or rp[role] == nil then return 'off' end
    return rp[role][typ] or 'off'
end

-----------------------------------
-- Setters — called from luautils OnRoleAiSet* hooks.
-----------------------------------
function ai_item.set_role_ai_mode(primary, roleIdx, typeIdx, modeIdx)
    local rp = ensure_policy()
    if rp == nil then return end
    local role = ROLE_BY_INDEX[tonumber(roleIdx) or -1]
    local typ  = TYPE_BY_INDEX[tonumber(typeIdx) or -1]
    local mode = MODE_BY_INDEX[tonumber(modeIdx) or -1]
    if role == nil or typ == nil or mode == nil then return end
    rp[role][typ] = mode
    printf(string.format('ai_item.set_role_ai_mode: %s.%s -> %s', role, typ, mode))
end

function ai_item.set_role_ai_status_flag(primary, roleIdx, statusKey, on)
    local rp = ensure_policy()
    if rp == nil then return end
    local role = ROLE_BY_INDEX[tonumber(roleIdx) or -1]
    local key  = tonumber(statusKey) or -1
    if role == nil then return end
    if STATUS_BY_KEY[key] == nil then return end
    rp[role].statusFlags[key] = (on == true)
    printf(string.format('ai_item.set_role_ai_status_flag: %s.status[%d] -> %s',
        role, key, tostring(on == true)))
end

-----------------------------------
-- Snapshot — flatten policy into the wire format the addon expects (modes
-- as integer indices, statusFlags as a key→bool map). Wired into
-- bots.send_state_snapshot so the Role AI tab seeds from server state on reload.
-----------------------------------
local function index_of_mode(modeName)
    for i, v in pairs(MODE_BY_INDEX) do if v == modeName then return i end end
    return 0
end

function ai_item.role_ai_snapshot()
    local rp = ensure_policy()
    if rp == nil then return {} end
    local out = {}
    for roleIdx, role in pairs(ROLE_BY_INDEX) do
        local entry = rp[role] or {}
        out[tostring(roleIdx)] = {
            hp     = index_of_mode(entry.hp     or 'off'),
            mp     = index_of_mode(entry.mp     or 'off'),
            status = index_of_mode(entry.status or 'off'),
            statusFlags = entry.statusFlags or {},
        }
    end
    return out
end

-----------------------------------
-- Role-policy-driven item action helpers. Each returns true iff an item
-- was consumed this tick — callers propagate so the role tick bails and
-- re-enters next tick. Priority order at the call site is HP → Status →
-- MP (see ai_ability.process_pre_ability_checks /
-- ai_magic.process_pre_cast_checks).
-----------------------------------
function ai_item.try_hp_item(bot)
    local mode = mode_for(bot, 'hp')
    if mode == 'off' then return false end
    if not mode_allows(mode, xi.singleplayer.bots.ability.is_nm(bot)) then return false end
    if xi.singleplayer.bots.ai_util.current_hp_percent(bot) > ai_item.HP_THRESHOLD then return false end
    if not ai_item.have_potion(bot) then return false end
    xi.singleplayer.bots.ai_util.log(bot, 'AutoItem', 'try_hp_item')
    ai_item.use_potion(bot)
    return true
end

function ai_item.try_mp_item(bot)
    local mode = mode_for(bot, 'mp')
    if mode == 'off' then return false end
    if not mode_allows(mode, xi.singleplayer.bots.ability.is_nm(bot)) then return false end
    if xi.singleplayer.bots.ai_util.current_mp_percent(bot) > ai_item.MP_THRESHOLD then return false end
    -- Melee role: gate MP items to DRK / BLU only (user-locked spec).
    local role = role_for_bot(bot)
    if role == 'melee' then
        local mainJob = xi.singleplayer.bots.ai_util.jobs[bot:getMainJob()]
        if not MELEE_MP_JOBS[mainJob] then return false end
    end
    if not ai_item.have_ether(bot) then return false end
    xi.singleplayer.bots.ai_util.log(bot, 'AutoItem', 'try_mp_item')
    ai_item.use_ether(bot)
    return true
end

function ai_item.try_status_item(bot)
    local mode = mode_for(bot, 'status')
    if mode == 'off' then return false end
    local state = ensure_policy()
    if state == nil then return false end
    local role = role_for_bot(bot)
    if role == nil or state[role] == nil then return false end
    local flags = state[role].statusFlags or {}

    -- ('poison' mode retired — was a rest-blocker-only filter; same
    -- behavior is now expressed by ticking only the Poison checkbox with
    -- Status = Always.)

    if not mode_allows(mode, xi.singleplayer.bots.ability.is_nm(bot)) then return false end

    -- Collect every enabled+afflicted status first. Split into the
    -- Remedy-curable subset (Poison/Silence/Blind/Paralyze/Disease) so
    -- the multi-status branch only counts statuses Remedy would actually
    -- clear. Curse can't trigger Remedy preference no matter what else
    -- is afflicted — it needs Holy Water specifically.
    local afflicted, remedyable = {}, {}
    for _, entry in ipairs(STATUS_LIST) do
        if flags[entry.key] == true and entry.effect ~= nil
           and xi.singleplayer.bots.ai_util.is_effect_active(bot, entry.effect) then
            table.insert(afflicted, entry)
            if entry.remedy_cures then table.insert(remedyable, entry) end
        end
    end
    if #afflicted == 0 then return false end

    -- Multi-status case: one Remedy clears 2+ ailments at once. Only
    -- counts the Remedy-curable subset — a Curse + Poison combo still
    -- wants Antidote (cheap) for Poison, not Remedy.
    if #remedyable >= 2 and ai_item.have_remedy(bot) then
        local labels = {}
        for _, e in ipairs(remedyable) do table.insert(labels, e.label) end
        xi.singleplayer.bots.ai_util.log(bot, 'AutoItem',
            'status:remedy:multi:' .. table.concat(labels, '+'))
        ai_item.use_remedy(bot)
        return true
    end

    -- Single-status (or no Remedy in stock): specific item first per
    -- status, Remedy fallback only when this status is one Remedy
    -- actually cures. Curse without Holy Water in stock = no action
    -- this tick (Remedy wouldn't help). Silent on miss.
    for _, entry in ipairs(afflicted) do
        if entry.specific_have ~= nil and ai_item[entry.specific_have](bot) then
            xi.singleplayer.bots.ai_util.log(bot, 'AutoItem', 'status:' .. entry.label .. ':specific')
            ai_item[entry.specific_use](bot)
            return true
        end
        if entry.remedy_cures and ai_item.have_remedy(bot) then
            xi.singleplayer.bots.ai_util.log(bot, 'AutoItem', 'status:' .. entry.label .. ':remedy')
            ai_item.use_remedy(bot)
            return true
        end
    end
    return false
end

-- is_potent_poisoned retired — Role AI Status policy (Poison checkbox)
-- now drives antidote use unconditionally on any Poison affliction. The
-- old sub-power >= 10 hp/tick gate was a "this hurts enough to burn an
-- item" heuristic; the user expressed preference for the simpler "if
-- enabled, fire on any Poison" semantic.

-----------------------------------
-- On-demand food across all headless in a named food config.
--
-- Wire entry: C2S 0x17D USE_FOOD_CONFIG → luautils::OnUseFoodFromConfig →
-- here. The addon's `/autobots food <name>` fires this in one round-trip
-- instead of the upstream cross-client `/mst /item` chain (which never
-- worked for headless chars since they have no client to receive).
--
-- Server-resolved (same pattern as spawn + alliance configs): we load the
-- JSON, look up each food item by name, and fire bot:useItem on each
-- headless that's linked to the requesting primary.
-----------------------------------
function xi.singleplayer.bots.item.use_food_from_config(primary, configName)
    if primary == nil or configName == nil or configName == '' then return end

    -- Read from server config cache (kept fresh by configcache::poll).
    local body = GetServerConfig('food', configName)
    if body == nil then
        primary:printToPlayer(string.format('use_food_from_config: food/%s.json not found.', configName))
        return
    end
    local json   = require('modules/singleplayer/lib/json')
    local ok, cfg = pcall(json.decode, json, body)
    if not ok or type(cfg) ~= 'table' then
        primary:printToPlayer(string.format('use_food_from_config: failed to parse food/%s.json.', configName))
        return
    end

    -- Record the active food config name on the alliance for snapshot
    -- replies (S2C 0x1A5). Set before the loop so a later partial failure
    -- still surfaces the user's intended choice on the next reload.
    if xi.singleplayer.bots.alliance ~= nil then
        xi.singleplayer.bots.alliance.foodConfigName = configName
    end

    local primaryId = primary:getID()
    local fed       = 0
    for charName, foodName in pairs(cfg) do
        local target = GetPlayerByName(charName)
        -- Feed the primary themselves OR any headless linked to this primary.
        -- Other primaries' bots / random in-world chars are skipped even if
        -- their name happens to appear in the config.
        local isOurs = target ~= nil and (
            target:getID() == primaryId or
            (target:isHeadless() and target:getParentCharId() == primaryId)
        )
        if isOurs then
            -- item_basic.name is stored lowercase with underscores
            -- (e.g. "meat_mithkabob"). Food configs use display names with
            -- spaces and proper case ("Meat Mithkabob"). GetItemIDByName does
            -- a `LIKE ?` against the DB form, so without normalization every
            -- lookup misses. Lowercase + spaces→underscores produces the DB
            -- key. Keep the original `foodName` for the error message so the
            -- user sees what they typed if it still doesn't resolve.
            local lookupName = (foodName or ''):lower():gsub(' ', '_')
            local foodId = GetItemIDByName and GetItemIDByName(lookupName) or 0
            if foodId > 0 then
                if use_item_by_id(target, foodId, target) then
                    fed = fed + 1
                end
            else
                primary:printToPlayer(string.format(
                    'use_food_from_config: unknown food "%s" for %s.', foodName, charName))
            end
        end
    end

    primary:printToPlayer(string.format(
        'use_food_from_config: fed %d headless from "%s".', fed, configName))
end

-----------------------------------
-- AUTOMATED food consumption (rebuff on buff-drop) — open design question,
-- NOT implemented. Separate from the on-demand path above.
--
-- Per-character food assignment data already exists at config/food/<name>.json
-- (map of char-name → food-item-name). The client-side flow was
-- `/autobots food <name>` → cross-client `/mst <char> /item "<food>" <me>`
-- chat commands, which dead-ends server-side since headless chars have no
-- client to receive cross-client commands.
--
-- A server-side implementation would be straightforward (load the JSON,
-- name → itemId lookup, bot:useItem on spawn + when food buff drops), but
-- the dev is not yet sure if automated food use is the right direction.
-- Open questions:
--   - Should headless bots burn food autonomously, or should food usage stay
--     player-directed via an addon UI button?
--   - Food costs gil; auto-rebuffing on drop could chew through stacks fast
--     during a long session.
--   - Does the alliance even meaningfully benefit from food bonuses for
--     headless DPS, or is that a tuning detail better left to the player?
--
-- Leaving as a known open question rather than shipping a default behavior
-- that may turn out to be wrong.
-----------------------------------

return m
