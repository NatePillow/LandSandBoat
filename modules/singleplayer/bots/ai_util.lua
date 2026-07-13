-----------------------------------
-- Server-side AI: shared utilities used across the auto* role modules.
-- Ported from client-side. Functions take a `bot` (CCharEntity) as the operating
-- subject. Status effect IDs use xi.effect.* named constants.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('ai_util')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.ai_util = xi.singleplayer.bots.ai_util or {}
local ai_util = xi.singleplayer.bots.ai_util

-- Job table preserved from ai_util (used by job-string lookups)
ai_util.jobs = { 'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN' }

-----------------------------------
-- 1. log  (server-side: pushes a 0x179 LOG_MESSAGE event back to the primary)
--
-- Gated on xi.settings.singleplayer.BOT_AI_CHAT_LOG. Default off — role ticks
-- fire this every frame per bot (provoke_is_up, can_use_boost, can_rest,
-- Cure_P1/2/3/4, sc-open/close, etc.), which is fine for development but is
-- unwanted chat-line noise for normal play. Flip the setting true to bring
-- the diagnostic firehose back.
-----------------------------------
function ai_util.log(bot, tag, msg)
    if not (xi.settings.singleplayer and xi.settings.singleplayer.BOT_AI_CHAT_LOG) then
        return
    end
    if bot == nil then
        printf(string.format("[%s] %s", tostring(tag), tostring(msg)))
        return
    end
    local primary = bot:isHeadless()
        and GetPlayerByID(bot:getParentCharId())
        or bot
    if primary == nil then
        printf(string.format("[%s] %s", tostring(tag), tostring(msg)))
        return
    end
    -- Pack "[BotName][Tag] msg" into the Message[44] field, leave Tag[16]
    -- empty. Client ai_util.log (addons/libs/ai_util.lua) renders an
    -- empty-tag packet as msg-only, producing "[Penelope][AutoHeal] msg"
    -- without the wrapper brackets the tag path would add.
    local prefixed = '[' .. bot:getName() .. '][' .. tostring(tag) .. '] ' .. tostring(msg)
    BotPushLog(primary, '', prefixed)
end

-----------------------------------
-- 2. table_contains
-----------------------------------
function ai_util.table_contains(tbl, val)
    if tbl == nil then return false end
    for _, v in ipairs(tbl) do if v == val then return true end end
    return false
end

-----------------------------------
-- 3. table_contains_any
-----------------------------------
function ai_util.table_contains_any(tblB, tblA)
    for _, valueA in pairs(tblA) do
        if ai_util.table_contains(tblB, valueA) then return true end
    end
    return false
end

-----------------------------------
-- 4. starts_with
-----------------------------------
function ai_util.starts_with(val, start)
    if val == nil or start == nil or #start > #val then return false end
    return val:find('^' .. start) ~= nil
end

-----------------------------------
-- 5. round_to_two_decimals
-----------------------------------
function ai_util.round_to_two_decimals(num)
    return math.floor(num * 100 + 0.5) / 100
end

-----------------------------------
-- 6. get_entity_distance
--    Original: by Ashita serverId via Ashita entity manager.
--    Server-side: by serverId via GetEntityByID, then planar distance to bot.
-----------------------------------
function ai_util.get_entity_distance(bot, serverId)
    local target = GetEntityByID(serverId)
    if target == nil then return nil end
    local dx = target:getXPos() - bot:getXPos()
    local dz = target:getZPos() - bot:getZPos()
    return math.sqrt(dx * dx + dz * dz)
end

-----------------------------------
-- 7. get_entity  (server-side equivalent: GetEntityByID)
-----------------------------------
function ai_util.get_entity(serverId)
    return GetEntityByID(serverId)
end

-----------------------------------
-- 8. get_entity_name
-----------------------------------
function ai_util.get_entity_name(serverId)
    local entity = GetEntityByID(serverId)
    if entity == nil then return nil end
    return entity:getName()
end

-----------------------------------
-- 9. get_target_index
--    Server-side equivalent: targid (the in-zone target index).
-----------------------------------
function ai_util.get_target_index(serverId)
    local entity = GetEntityByID(serverId)
    if entity == nil then return nil end
    return entity.getTargID and entity:getTargID() or nil
end

-----------------------------------
-- 10. get_ms_since_epoch
-----------------------------------
function ai_util.get_ms_since_epoch()
    return math.floor(os.time() * 1000 + (os.clock() % 1.0) * 1000)
end

-----------------------------------
-- 11. remove_element
-----------------------------------
function ai_util.remove_element(tbl, val)
    for i, value in ipairs(tbl) do
        if value == val then return table.remove(tbl, i) end
    end
    return nil
end

-----------------------------------
-- 12. index_of
-----------------------------------
function ai_util.index_of(array, value)
    for i, v in ipairs(array) do
        if v == value then return i end
    end
    return nil
end

-----------------------------------
-- 13. get_party_server_ids
-----------------------------------
function ai_util.get_party_server_ids(bot)
    local ids = {}
    for _, member in ipairs(bot:getAlliance() or {}) do
        table.insert(ids, member:getID())
    end
    return ids
end

-----------------------------------
-- 14. get_lowest_key_by_value
-----------------------------------
function ai_util.get_lowest_key_by_value(tbl)
    local lowestKey, lowestValue = nil, nil
    for key, value in pairs(tbl) do
        if value ~= nil and (lowestValue == nil or value < lowestValue) then
            lowestKey = key
            lowestValue = value
        end
    end
    return lowestKey
end

-----------------------------------
-- 15. current_mp_percent
-----------------------------------
function ai_util.current_mp_percent(bot)
    return bot:getMPP()
end

-----------------------------------
-- 16. current_hp_percent
-----------------------------------
function ai_util.current_hp_percent(bot)
    return bot:getHPP()
end

-----------------------------------
-- 16b. Assist-observation helpers. The "assist" is the single bot other
-- bots mimic for target selection (alliance.assistCharId, populated at
-- spawn from cfg.roles.tank[1]). These functions answer "is the assist
-- in combat?" and "what mob is the assist currently swinging at?" — pure
-- engine-state reads, no caching. Moved here so both ai_ability and
-- ai_magic can use them without one depending on the other.
-----------------------------------
local function _resolve_assist(primary)
    if primary == nil then return nil end
    local assist = xi.singleplayer.bots.get_assist_entity()
    return assist or primary
end

-- Returns the alliance target mob entity when the alliance is actively
-- fighting (alliance.allianceTarget != 0 AND that mob exists AND alive),
-- else nil. Used as the single source of truth for "are we fighting right
-- now?" across role tick gates.
--
-- Contract: return VALUE is nil-or-entity. Callers using boolean context
-- (`if x then`) work because nil is falsy. Callers using `~= nil` also
-- work because non-fighting returns nil, not false.
--
-- Was `assist:isEngaged()` boolean — fragile: when the tank died mid-fight
-- (or hadn't started swinging yet, e.g. right after puller handoff), this
-- returned false even though the fight was ongoing. WHM would think fight
-- was over and cast Raise on the dead tank. Now driven by allianceTarget,
-- the same signal used everywhere else in the codebase. The `primary`
-- param is preserved for API compatibility but no longer used.
function ai_util.combat_active(primary)
    local A = xi.singleplayer.bots.alliance
    if A == nil then return nil end
    local tid = A.allianceTarget or 0
    if tid == 0 then return nil end
    local mob = GetEntityByID(tid)
    if mob == nil then return nil end
    if mob.isDead and mob:isDead() then return nil end
    return mob
end

-- True if the bot is mid-action: casting a spell, executing a WS, using
-- a JA, or in a ranged-attack windup. Used by every pool eligibility
-- filter to skip bots that can't queue another action right now, and by
-- ai_move to suppress movement during the action window.
function ai_util.is_busy_actioning(bot)
    if bot == nil then return false end
    if bot.isBotCasting         and bot:isBotCasting()         then return true end
    if bot.isBotWeaponSkilling  and bot:isBotWeaponSkilling()  then return true end
    if bot.isBotUsingAbility    and bot:isBotUsingAbility()    then return true end
    if bot.isBotRangedAttacking and bot:isBotRangedAttacking() then return true end
    return false
end

-- The mob the assist is currently swinging at — the engine-side
-- OBSERVATION of "what the alliance is fighting right now." This can
-- diverge from the COMMAND (alliance.allianceTarget): user picks mob A
-- via /be-attack but the assist can't engage; allianceTarget stays at
-- A while the assist's actual battle target is nil. Engine clears
-- engagement on mob death, so this naturally returns nil afterwards.
-- Returns nil if not in combat or the assist target is dead.
function ai_util.assist_target(bot)
    -- For headless: getParentCharId returns the primary's charId.
    -- For the primary themselves: getParentCharId returns 0 (no parent),
    -- so use bot directly. Without this branch, every caller that goes
    -- through assist_target (notably sc_effect → sc_close_window_start_ms)
    -- returned nil for the primary — visible as "primary closer never
    -- fires WS because no SKILLCHAIN effect can be resolved."
    local primary = bot:isHeadless() and GetPlayerByID(bot:getParentCharId()) or bot
    local assist  = _resolve_assist(primary)
    if assist == nil or not assist:isEngaged() then return nil end
    local target = assist.getTarget and assist:getTarget() or nil
    if target == nil or target:isDead() then return nil end
    return target
end

-----------------------------------
-- 17. get_current_target_server_id
--     Wrapper around the alliance target accessor for the original API name.
-----------------------------------
function ai_util.get_current_target_server_id(_)
    return xi.singleplayer.bots.get_alliance_target_id()
end

-----------------------------------
-- 18. get_current_target_index
-----------------------------------
function ai_util.get_current_target_index(bot)
    local serverId = ai_util.get_current_target_server_id(bot)
    if serverId == 0 then return nil end
    local entity = GetEntityByID(serverId)
    return entity and (entity.getTargID and entity:getTargID()) or nil
end

-----------------------------------
-- 19. get_member_index
--     Returns 1-based index into the party list (originals were 0-based).
-----------------------------------
function ai_util.get_member_index(bot, name)
    for i, member in ipairs(bot:getAlliance() or {}) do
        if member:getName() == name then return i end
    end
    return nil
end

-----------------------------------
-- 20. get_member_job
--     Returns the main-job byte index for the named member.
-----------------------------------
function ai_util.get_member_job(bot, name)
    for _, member in ipairs(bot:getAlliance() or {}) do
        if member:getName() == name then return member:getMainJob() end
    end
    return nil
end

-----------------------------------
-- 21. get_member_name  (by server ID — for member of bot's party)
-----------------------------------
function ai_util.get_member_name(bot, serverId)
    for _, member in ipairs(bot:getAlliance() or {}) do
        if member:getID() == serverId then return member:getName() end
    end
    return nil
end

-----------------------------------
-- 22. get_member_names_with_job
-----------------------------------
function ai_util.get_member_names_with_job(bot, jobName)
    local names = {}
    for _, member in ipairs(bot:getAlliance() or {}) do
        if ai_util.jobs[member:getMainJob()] == jobName then
            table.insert(names, member:getName())
        end
    end
    return names
end

-----------------------------------
-- 23. is_effect_active
-----------------------------------
function ai_util.is_effect_active(bot, buffId)
    if buffId == nil then return false end
    return bot:hasStatusEffect(buffId)
end

-- Single source of truth for "is this entity asleep" across every sleep-
-- family effect. Used by add-handling and crowd-control gates so adding a
-- new sleep mechanic (Repose, Sheep Song, etc.) only needs one update.
-- Repose currently lands SLEEP_I in LSB, so it's covered by the existing
-- entries — add it explicitly if/when an EFFECT_REPOSE is introduced.
local SLEEP_EFFECTS = {
    xi.effect.SLEEP_I,
    xi.effect.SLEEP_II,
    xi.effect.LULLABY,
}

function ai_util.is_asleep(entity)
    if entity == nil or entity.hasStatusEffect == nil then return false end
    for _, id in ipairs(SLEEP_EFFECTS) do
        if entity:hasStatusEffect(id) then return true end
    end
    return false
end

-----------------------------------
-- 24. is_any_effect_active
-----------------------------------
function ai_util.is_any_effect_active(bot, buffTbl)
    for _, id in ipairs(buffTbl) do
        if bot:hasStatusEffect(id) then return true end
    end
    return false
end

-----------------------------------
-- 25. has_neutralizing_effect
--     Original list: { 0, 2, 7, 14, 17, 19, 28 } — server-side names:
--     KO (0 — not a real effect, but original used 0), SLEEP_I, PETRIFICATION,
--     CHARM_I, CHARM_II, SLEEP_II, TERROR.
--     STUN added by us — bots were spamming JAs/spells while stunned because
--     the engine silently rejects each attempt (no error packet back to bot
--     AI). Centralized gate stops the burst at the role-tick layer.
-----------------------------------
local neutralizingEffects = {
    xi.effect.SLEEP_I, xi.effect.PETRIFICATION, xi.effect.CHARM_I,
    xi.effect.CHARM_II, xi.effect.SLEEP_II, xi.effect.TERROR,
    xi.effect.STUN,
}
function ai_util.has_neutralizing_effect(bot)
    if bot:getHP() == 0 then return true end  -- KO replaces the 0 case
    for _, buffId in ipairs(neutralizingEffects) do
        if ai_util.is_effect_active(bot, buffId) then return true end
    end
    return false
end

-----------------------------------
-- 26. weakened
-----------------------------------
function ai_util.weakened(bot) return ai_util.is_effect_active(bot, xi.effect.WEAKNESS) end

-----------------------------------
-- 27. silenced
-----------------------------------
function ai_util.silenced(bot) return ai_util.is_effect_active(bot, xi.effect.SILENCE) end

-----------------------------------
-- 28. poisoned
-----------------------------------
function ai_util.poisoned(bot) return ai_util.is_effect_active(bot, xi.effect.POISON) end

-----------------------------------
-- 29. paralyzed_or_silenced
-----------------------------------
function ai_util.paralyzed_or_silenced(bot)
    return ai_util.is_effect_active(bot, xi.effect.PARALYSIS) or ai_util.is_effect_active(bot, xi.effect.SILENCE)
end

-----------------------------------
-- 30. paralyzed_or_silenced_or_poisoned
-----------------------------------
function ai_util.paralyzed_or_silenced_or_poisoned(bot)
    return ai_util.is_effect_active(bot, xi.effect.PARALYSIS)
        or ai_util.is_effect_active(bot, xi.effect.SILENCE)
        or ai_util.is_effect_active(bot, xi.effect.POISON)
end

-----------------------------------
-- 31. can_rest
--     Original list: { 3, 128, 129, 130, 131, 132, 133, 134, 135, 0, 2, 7, 14, 17, 19 }
--     = POISON, BURN, FROST, CHOKE, RASP, SHOCK, DROWN, DIA, BIO, [KO via HP=0],
--       SLEEP_I, PETRIFICATION, CHARM_I, CHARM_II, SLEEP_II
-----------------------------------
local statusThatPreventRest = {
    xi.effect.POISON, xi.effect.BURN, xi.effect.FROST, xi.effect.CHOKE,
    xi.effect.RASP, xi.effect.SHOCK, xi.effect.DROWN, xi.effect.DIA, xi.effect.BIO,
    xi.effect.SLEEP_I, xi.effect.PETRIFICATION, xi.effect.CHARM_I, xi.effect.CHARM_II,
    xi.effect.SLEEP_II,
}
function ai_util.can_rest(bot)
    if bot:getHP() == 0 then return false end  -- KO case (originally id 0)
    for _, id in ipairs(statusThatPreventRest) do
        if ai_util.is_effect_active(bot, id) then return false end
    end
    return true
end

-----------------------------------
-- 32. is_resting
--     Original: entity manager status 33 = healing/resting.
--     Server-side: entity status enum HEALING; check via animation or status flag.
-----------------------------------
function ai_util.is_resting(bot)
    return bot.isBotResting and bot:isBotResting() or false
end

-----------------------------------
-- 33. start_rest
-----------------------------------
function ai_util.start_rest(bot)
    if bot.startBotResting then bot:startBotResting() end
end

-----------------------------------
-- 34. stop_rest
-----------------------------------
function ai_util.stop_rest(bot)
    if bot.stopBotResting then bot:stopBotResting() end
end

-----------------------------------
-- 34b. is_force_rested
--      True when the player explicitly told this bot to sit via Heal On.
--      Roles consult this at the top of their .tick() and bail out so the
--      bot doesn't fire Boost/buffs/etc. while seated — without this gate
--      ai_rest keeps re-adding HEALING after every ability auto-strips it
--      and the bot visually flickers between sit/stand. Player intent wins:
--      even getting hit doesn't release this — only Heal Off does.
-----------------------------------
function ai_util.is_force_rested(bot)
    local s = xi.singleplayer.bots.ensure_bot(bot:getID())
    return s.heal_override == 'force_on'
end

-----------------------------------
-- is_job
-----------------------------------
function ai_util.is_job(bot, jobName)
    return ai_util.jobs[bot:getMainJob()] == jobName
end

-----------------------------------
-- is_nin / is_smn — main-job convenience wrappers around is_job.
-- Kept here (not in ai_magic) because they're pure job identity checks,
-- shared across role_tank / role_melee / role_smn and any future NIN or
-- SMN sub-behavior.
-----------------------------------
function ai_util.is_nin(bot) return ai_util.is_job(bot, 'NIN') end
function ai_util.is_pld(bot) return ai_util.is_job(bot, 'PLD') end
function ai_util.is_smn(bot) return ai_util.is_job(bot, 'SMN') end
function ai_util.is_thf(bot) return ai_util.is_job(bot, 'THF') end

-----------------------------------
-- Multi-tank scope helpers. Return the list of tanks / PLDs / NINs that
-- share `bot`'s coordination scope, sorted by charId ascending for stable
-- rotation ordering. Scope is:
--   * multiEngageMode = false → alliance-wide (all 3 parties, one fight)
--   * multiEngageMode = true  → just bot's own party (each party its own fight)
--
-- Callers use these to compute rotation intervals (30/N s Provoke, 45/N s
-- Flash) and to slice the NIN debuff/wheel spell lists into contiguous
-- subsets so multiple NINs don't collide on the same spell.
-----------------------------------
local function alliance_or_party_members(bot)
    local A = xi.singleplayer.bots.alliance
    if bot == nil or bot.getAlliance == nil then return {} end
    if A and A.multiEngageMode then
        return bot.getParty and bot:getParty() or {}
    end
    return bot:getAlliance() or {}
end

local function role_of(charId)
    local A = xi.singleplayer.bots.alliance
    return A and A.roleMap and A.roleMap[charId] or nil
end

local function is_tank_role_member(m)
    return role_of(m:getID()) == xi.singleplayer.bots.Role.Tank
end

local function collect_sorted(members, filter)
    local out = {}
    for _, m in ipairs(members or {}) do
        if m and ai_util.isAlive(m) and filter(m) then table.insert(out, m) end
    end
    table.sort(out, function(a, b) return a:getID() < b:getID() end)
    return out
end

function ai_util.tanks_in_scope(bot)
    return collect_sorted(alliance_or_party_members(bot), is_tank_role_member)
end

function ai_util.plds_in_scope(bot)
    return collect_sorted(alliance_or_party_members(bot), function(m)
        return is_tank_role_member(m) and ai_util.is_pld(m)
    end)
end

-- NINs firing wheel/debuff behavior: any main-NIN in scope, regardless of
-- role (role_tank fires NIN-mainjob subroutines; role_melee also fires them
-- for off-tank NIN — see ai_magic ninjitsu block comment). We include ALL
-- main-job NINs in scope so the contiguous spell split accounts for every
-- bot that could try to cast a wheel/debuff spell this tick.
function ai_util.nins_in_scope(bot)
    return collect_sorted(alliance_or_party_members(bot), ai_util.is_nin)
end

-- THFs firing SATA / positioning behind tanks. Used by ai_formation to pin
-- each THF at a fixed offset behind an assigned tank so Trick Attack has
-- the tank-mob line reliably every fight, regardless of the alliance's
-- current battle formation.
function ai_util.thfs_in_scope(bot)
    return collect_sorted(alliance_or_party_members(bot), ai_util.is_thf)
end

-- Return `bot`'s 1-based index within `list` (nil if not present). Used
-- by NIN wheel/debuff subset resolution and Provoke rotation tiebreaks.
function ai_util.slot_index_in(bot, list)
    if bot == nil or list == nil then return nil end
    local myId = bot:getID()
    for i, m in ipairs(list) do
        if m:getID() == myId then return i end
    end
    return nil
end

-- Contiguous split of `list` into `count` chunks; returns the `slot`-th
-- chunk (1-based). Leftover items go to the first `#list % count` slots
-- so counts are balanced.
--
--   {A,B,C,D}, count=2 → slot 1 {A,B}, slot 2 {C,D}
--   {A,B,C,D}, count=3 → slot 1 {A,B}, slot 2 {C}, slot 3 {D}
--   {A,B,C,D,E,F}, count=2 → slot 1 {A,B,C}, slot 2 {D,E,F}
function ai_util.contiguous_slice(list, slot, count)
    if list == nil or slot == nil or count == nil or count <= 0 then return {} end
    if slot < 1 or slot > count then return {} end
    local n = #list
    if n == 0 then return {} end
    if count == 1 then return list end
    local base  = math.floor(n / count)
    local extra = n - base * count
    local startIdx, endIdx
    if slot <= extra then
        startIdx = (slot - 1) * (base + 1) + 1
        endIdx   = startIdx + base  -- (base+1) items
    else
        startIdx = extra * (base + 1) + (slot - extra - 1) * base + 1
        endIdx   = startIdx + base - 1
    end
    local out = {}
    for i = startIdx, endIdx do table.insert(out, list[i]) end
    return out
end

-----------------------------------
-- is_dead — HP-based check; the original Ashita addon read a status field
-- (status == 2 or 3) which isn't exposed the same way server-side.
-----------------------------------
function ai_util.is_dead(bot)
    return bot:getHP() == 0
end

-----------------------------------
-- Stateless entity / role predicates. Moved from autoai during the
-- autoai split. Parameter named `entity` (not `bot`) because main char,
-- trusts, and headless bots are all valid arguments.
-----------------------------------
function ai_util.isAlive(entity)
    return entity ~= nil and entity:getHP() > 0
end

function ai_util.isMageRole(role)
    return role == xi.singleplayer.bots.Role.Healer
        or role == xi.singleplayer.bots.Role.Nuker
        or role == xi.singleplayer.bots.Role.Rdm
        or role == xi.singleplayer.bots.Role.Brd
        or role == xi.singleplayer.bots.Role.Smn
end

function ai_util.isMeleeRole(role)
    return role == xi.singleplayer.bots.Role.Tank
        or role == xi.singleplayer.bots.Role.Melee
end

return m
