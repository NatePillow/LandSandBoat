-----------------------------------
-- Account-wide progression cascade (singleplayer) — framework module.
--
-- Sync any quests + nation/expansion missions a primary character has
-- completed onto headless characters linked to that primary, on demand
-- via the autobots UI "Sync Quests" / "Sync Missions" buttons (wiring
-- lives in singleplayer/client/addons/autobots/). Recipes are the single
-- source of truth for what each quest/mission delivers; the button path
-- is authoritative over the full back-catalog, and the live cascade wrap
-- at bottom of this file replays through the same recipe.apply at runtime.
--
-- Recipe tables live in per-area files under bots_progression_cascade/
-- (bastok.lua, sandoria.lua, ..., missions_nations.lua, missions_cop.lua,
-- etc.). See bots_progression_cascade/README.md for the full architecture
-- and the procedure for adding or updating recipes. This file exposes the
-- quest() / mission() factories on the module table so subdir files can
-- reference them; alphabetical filename load makes this framework file
-- load before the subdir files.
--
-- Approach: "light synthetic completion" — each recipe loads its quest/
-- mission source module at sync time, calls npcUtil.completeQuest /
-- completeMission with the SCRIPT'S OWN reward table (registry-walk-like
-- dispatch), then runs the recipe's apply() closure to deliver every
-- inline grant (fame, gil, currency, KI, item, title, spell, etc.) that
-- lives outside the .reward block in the source quest script.
--
-- DELIVERY:
--   Items in quest/mission.reward and in apply() closures go to alt's
--   INVENTORY via npcUtil.giveItem. Recipes whose items won't fit are
--   DEFERRED (completion flag NOT flipped), reported to primary's chatline
--   ("X deferred (inventory full — clear space and re-press)") and logged
--   server-side. Re-pressing Sync after clearing space picks them up.
--
-- CROSS-NATION RANK:
--   mission.reward.rank lands in the recipe's nation (profile.rank[area]),
--   not the alt's current nation, via setRankByNation. A Bastok-current alt
--   that syncs from a Sandoria-rank-7 primary ends up Bastok rank N + Sandy
--   rank 7, with their own Bastok mission line untouched. The mission's
--   completion bits land in m_missionLog[area] regardless of current nation,
--   so a later nation-switch surfaces the mirrored progress as-if earned.
--
-- INTENTIONAL UTILITY-SYSTEM BULK MIRRORS:
--   Three cross-cutting mirrors bypass the recipe pass entirely — they cover
--   utility-system unlocks whose "acquisition" is retail-era tedium the
--   singleplayer fork routes around:
--     * sync_hidden_trust_spells_to — the 8 HiddenQuest trust spells
--     * sync_teleports_to — homepoints/outposts/survival guides/waypoints/
--                           abyssea/campaign/eschan bits
--     * AF1_COFFER_ITEMS mirror — 30 canonical AF1 head/legs coffer drops
--   See bots_progression_cascade/README.md § architecture for why these
--   three are exempt and why NO other bulk mirrors (fame, title, gil,
--   currency) exist — those are cascaded strictly per-quest via recipes.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('bots_progression_cascade')

xi              = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.bots_progression_cascade = xi.singleplayer.bots.bots_progression_cascade or {}

local bots_progression_cascade = xi.singleplayer.bots.bots_progression_cascade

-----------------------------------
-- Recipe factories
--
-- Recipes are the single source of truth for what each quest/mission
-- delivers. Every inline grant that lives outside the source script's
-- .reward block — fame, gil, currency, KIs, items, titles, spells, job
-- unlocks, weaponskill unlocks, level caps, container-size deltas — is
-- hand-transcribed into the recipe's apply() closure. The registry walk
-- pass covers the .reward block for every Quest:new / Mission:new class;
-- the recipe pass covers what the .reward block misses.
--
-- Maintenance: this is a 25-year-old MMORPG whose 75-era-and-earlier
-- rewards were frozen ~a decade ago. The one-time transcription pain has
-- essentially zero ongoing drift. See bots_progression_cascade/README.md
-- for the analysis procedure used to produce the initial coverage and
-- the scope cutoff (ToAU inclusive; post-ToAU expansions are out of
-- scope for new recipe work).
--
-- Each apply() returns a result table:
--   { status = 'applied' | 'deferred' | 'error', need = N, have = N }
--
-- 'deferred' = the target's inventory can't fit reward.item slots right now.
-- The completion flag is NOT flipped, so a re-press of Sync after the user
-- clears space will pick the recipe back up.
-----------------------------------

-- Normalize quest.reward.item / mission.reward.item into a list of {id, qty}.
-- Accepts the three forms npcUtil.giveItem supports:
--   number                     → one item, qty 1
--   {id, qty}                  → one item
--   { number | {id,qty} ... }  → list
local function reward_items(reward)
    local out = {}
    if reward == nil or reward.item == nil then return out end
    local function push(v)
        if type(v) == 'number' then
            table.insert(out, { v, 1 })
        elseif type(v) == 'table' and type(v[1]) == 'number' then
            table.insert(out, { v[1], v[2] or 1 })
        end
    end
    local it = reward.item
    if type(it) == 'number' then
        push(it)
    elseif type(it) == 'table' then
        if type(it[1]) == 'number' and type(it[2]) ~= 'table' then
            push(it)                                    -- single {id, qty}
        else
            for _, v in ipairs(it) do push(v) end       -- list
        end
    end
    return out
end

local function quest(area, qid, source, apply)
    return {
        kind   = 'quest',
        log    = area,
        qid    = qid,
        source = source,
        apply  = function(p)
            -- source: a script-path string (require its .reward), an inline
            -- reward table, or nil (no reward — the reward acts live wholly in
            -- the apply closure). nil/table covers unlocks whose source is a
            -- battlefield / NPC rather than a standalone quest script.
            local reward = {}
            if type(source) == 'string' then
                reward = require(source).reward or {}
            elseif type(source) == 'table' then
                reward = source
            end
            local items = reward_items(reward)
            local need  = #items
            local have  = p.getFreeSlotsCount and p:getFreeSlotsCount() or 255
            if need > 0 and have < need then
                return { status = 'deferred', need = need, have = have }
            end
            local ok = npcUtil.completeQuest(p, area, qid, reward)
            if ok == false then
                return { status = 'error', need = need, have = have }
            end
            if apply then apply(p) end
            return { status = 'applied', need = need, have = have }
        end,
    }
end

-- Map a mission log id to the matching nation id. Returns nil for non-nation
-- log lines (zilart/cop/toau/jeuno/etc) where reward.rank is meaningless.
local function nation_for_mission_log(area)
    if area == xi.mission.log_id.SANDORIA then return xi.nation.SANDORIA end
    if area == xi.mission.log_id.BASTOK   then return xi.nation.BASTOK   end
    if area == xi.mission.log_id.WINDURST then return xi.nation.WINDURST end
    return nil
end

local function mission(area, mid, source, apply)
    return {
        kind   = 'mission',
        log    = area,
        mid    = mid,
        source = source,
        apply  = function(p)
            local mn    = require(source)
            local items = reward_items(mn.reward)
            local need  = #items
            local have  = p.getFreeSlotsCount and p:getFreeSlotsCount() or 255
            if need > 0 and have < need then
                return { status = 'deferred', need = need, have = have }
            end

            -- Cross-nation rank handling. The engine's completeMission only
            -- writes reward.rank to the player's CURRENT nation. For a
            -- different-nation recipe (e.g. mirroring Sandy rank 7 onto a
            -- Bastok-current alt) we strip rank + rankPoints so npcUtil
            -- doesn't bump the alt's current-nation rank or reset their
            -- shared rank-bar, then apply the recipe's nation rank directly
            -- via setRankByNation after.
            local reward         = mn.reward or {}
            local recipeNation    = nation_for_mission_log(area)
            local crossNationRank = nil
            if recipeNation ~= nil and recipeNation ~= p:getNation()
               and type(reward.rank) == 'number' then
                crossNationRank = reward.rank
                local stripped = {}
                for k, v in pairs(reward) do
                    if k ~= 'rank' and k ~= 'rankPoints' then stripped[k] = v end
                end
                reward = stripped
            end

            -- Pre-align the mission pointer so completeMission's
            -- (current != missionID) gate doesn't reject the call. Without
            -- this, completion bits silently fail to flip when the alt is
            -- "behind" or never started the mission line — same addMission
            -- + completeMission pattern char_create's setupNationMissions
            -- uses to bulk-finish headstart missions.
            p:addMission(area, mid)

            local ok = npcUtil.completeMission(p, area, mid, reward)
            if ok == false then
                return { status = 'error', need = need, have = have }
            end

            -- Apply cross-nation rank with no-downgrade guard, matching
            -- npcUtil.completeMission's current-nation guard semantics.
            if crossNationRank ~= nil
               and p:getRank(recipeNation) < crossNationRank then
                p:setRankByNation(recipeNation, crossNationRank)
            end

            if apply then apply(p) end
            return { status = 'applied', need = need, have = have }
        end,
    }
end

bots_progression_cascade.recipes = bots_progression_cascade.recipes or {}

-- Expose factories so per-area recipe files in
-- modules/singleplayer/bots/bots_progression_cascade/*.lua can register their
-- recipes into bots_progression_cascade.recipes.<area> using the same shape
-- the block-scoped `do ... end` sections in this file use.
bots_progression_cascade.quest   = quest
bots_progression_cascade.mission = mission

-----------------------------------
-- AF1 coffer-drop mirror set
--
-- AF1 head + legs aren't quest rewards — they drop from Treasure Coffers in
-- specific zones (Castle Oztroja, Davoi, etc.) so the recipe table can't cover
-- them. Instead: at sync time, walk this canonical list per target; if primary
-- has the piece and target doesn't, deliver via addItem. Singleplayer fork
-- philosophy: if primary earned the AF, alts get it for free.
--
-- 15 jobs × 2 pieces (head + legs) = 30 items. AF1 body / hands / feet / weapon
-- ARE covered by quest recipes already (Bastok WAR_AF, MNK_AF, DRK_AF; Sandoria
-- PLD/RDM/WHM; Windurst THF/SMN AF; jeuno helpers Borghertz/DNC; cross-area).
-- This pass complements those.
-----------------------------------
bots_progression_cascade.AF1_COFFER_ITEMS = {
    -- WAR
    { id = xi.item.FIGHTERS_MASK,       name = 'FIGHTERS_MASK',       job = 'WAR', slot = 'head' },
    { id = xi.item.FIGHTERS_CUISSES,    name = 'FIGHTERS_CUISSES',    job = 'WAR', slot = 'legs' },
    -- MNK
    { id = xi.item.TEMPLE_CROWN,        name = 'TEMPLE_CROWN',        job = 'MNK', slot = 'head' },
    { id = xi.item.TEMPLE_HOSE,         name = 'TEMPLE_HOSE',         job = 'MNK', slot = 'legs' },
    -- WHM
    { id = xi.item.HEALERS_CAP,         name = 'HEALERS_CAP',         job = 'WHM', slot = 'head' },
    { id = xi.item.HEALERS_PANTALOONS,  name = 'HEALERS_PANTALOONS',  job = 'WHM', slot = 'legs' },
    -- BLM
    { id = xi.item.WIZARDS_PETASOS,     name = 'WIZARDS_PETASOS',     job = 'BLM', slot = 'head' },
    { id = xi.item.WIZARDS_TONBAN,      name = 'WIZARDS_TONBAN',      job = 'BLM', slot = 'legs' },
    -- RDM
    { id = xi.item.WARLOCKS_CHAPEAU,    name = 'WARLOCKS_CHAPEAU',    job = 'RDM', slot = 'head' },
    { id = xi.item.WARLOCKS_TIGHTS,     name = 'WARLOCKS_TIGHTS',     job = 'RDM', slot = 'legs' },
    -- THF
    { id = xi.item.ROGUES_BONNET,       name = 'ROGUES_BONNET',       job = 'THF', slot = 'head' },
    { id = xi.item.ROGUES_CULOTTES,     name = 'ROGUES_CULOTTES',     job = 'THF', slot = 'legs' },
    -- PLD
    { id = xi.item.VALOR_CORONET,       name = 'VALOR_CORONET',       job = 'PLD', slot = 'head' },
    { id = xi.item.VALOR_BREECHES,      name = 'VALOR_BREECHES',      job = 'PLD', slot = 'legs' },
    -- DRK
    { id = xi.item.CHAOS_BURGEONET,     name = 'CHAOS_BURGEONET',     job = 'DRK', slot = 'head' },
    { id = xi.item.CHAOS_FLANCHARD,     name = 'CHAOS_FLANCHARD',     job = 'DRK', slot = 'legs' },
    -- BST
    { id = xi.item.BEAST_HELM,          name = 'BEAST_HELM',          job = 'BST', slot = 'head' },
    { id = xi.item.BEAST_TROUSERS,      name = 'BEAST_TROUSERS',      job = 'BST', slot = 'legs' },
    -- BRD
    { id = xi.item.CHORAL_ROUNDLET,     name = 'CHORAL_ROUNDLET',     job = 'BRD', slot = 'head' },
    { id = xi.item.CHORAL_CANNIONS,     name = 'CHORAL_CANNIONS',     job = 'BRD', slot = 'legs' },
    -- RNG
    { id = xi.item.HUNTERS_BERET,       name = 'HUNTERS_BERET',       job = 'RNG', slot = 'head' },
    { id = xi.item.HUNTERS_BRACCAE,     name = 'HUNTERS_BRACCAE',     job = 'RNG', slot = 'legs' },
    -- SMN
    { id = xi.item.EVOKERS_HORN,        name = 'EVOKERS_HORN',        job = 'SMN', slot = 'head' },
    { id = xi.item.EVOKERS_SPATS,       name = 'EVOKERS_SPATS',       job = 'SMN', slot = 'legs' },
    -- SAM
    { id = xi.item.SAOTOME_KABUTO,      name = 'SAOTOME_KABUTO',      job = 'SAM', slot = 'head' },
    { id = xi.item.SAOTOME_HAIDATE,     name = 'SAOTOME_HAIDATE',     job = 'SAM', slot = 'legs' },
    -- NIN
    { id = xi.item.HACHIYA_HATSUBURI,   name = 'HACHIYA_HATSUBURI',   job = 'NIN', slot = 'head' },
    { id = xi.item.HACHIYA_HAKAMA,      name = 'HACHIYA_HAKAMA',      job = 'NIN', slot = 'legs' },
    -- DRG
    { id = xi.item.DRACHEN_ARMET,       name = 'DRACHEN_ARMET',       job = 'DRG', slot = 'head' },
    { id = xi.item.DRACHEN_BRAIS,       name = 'DRACHEN_BRAIS',       job = 'DRG', slot = 'legs' },
}

-- Recipe tables for Bastok quests and Bastok/Sandy/Windy nation missions
-- have been moved to per-area files under bots_progression_cascade/ — see
-- bastok.lua and missions_nations.lua in that directory, and README.md for
-- the load-order and factory-plumbing rationale.


-----------------------------------
-- Hidden Trust spell mirror (#178 follow-up)
--
-- The 8 individual hiddenQuests/Trust_*.lua files use HiddenQuest:new (not
-- Quest:new), so they're absent from xi.QuestRegistry and the bit-copy
-- registry walk doesn't see them. Each grants a single trust spell at
-- completion. We don't know primary's hidden-quest completion bits via
-- hasCompletedQuest — but we don't need to: the spell IS the persistent
-- artifact. If primary can call Cherukiki, the hidden quest is done. So
-- mirror by spell presence: walk every trust spell primary has and
-- target doesn't, addSpell on target. Idempotent + tolerant of new trust
-- additions (just add to the list).
--
-- Combined with the Trust_Bastok recipe above (regular Quest with 4
-- spells), this closes the trust-spell cascade gap completely.
-----------------------------------
local HIDDEN_TRUST_SPELLS = {
    xi.magic.spell.CHERUKIKI,
    xi.magic.spell.INGRID,
    xi.magic.spell.MAAT,
    xi.magic.spell.NASHMEIRA,
    xi.magic.spell.PRISHE,
    xi.magic.spell.SHANTOTTO,
    xi.magic.spell.SHIKAREE_Z,
    xi.magic.spell.ULMIA,
}

function bots_progression_cascade.sync_hidden_trust_spells_to(primary, target)
    local stats = { applied = 0, skipped = 0 }
    for _, spellId in ipairs(HIDDEN_TRUST_SPELLS) do
        if primary:hasSpell(spellId) and not target:hasSpell(spellId) then
            target:addSpell(spellId, { silentLog = true })
            stats.applied = stats.applied + 1
        else
            stats.skipped = stats.skipped + 1
        end
    end
    return stats
end

-----------------------------------
-- Sync API
-----------------------------------

-- Iterate every recipe across every area, filtered by kind.
local function eachRecipe(kind)
    return coroutine.wrap(function()
        for _, areaRecipes in pairs(bots_progression_cascade.recipes) do
            for _, r in ipairs(areaRecipes) do
                if r.kind == kind then
                    coroutine.yield(r)
                end
            end
        end
    end)
end

-- ShowInfo wrapper — falls back to print() if ShowInfo isn't in scope (some
-- module load orderings). Tagged so server log greps filter cleanly.
local function srvlog(msg)
    local line = string.format('[bots_progression_cascade] %s', msg)
    if ShowInfo then ShowInfo(line) else print(line) end
end

-- Apply one recipe to `target` iff `primary` has it complete and `target` doesn't.
-- Returns the result string for stats tallying:
--   'applied' / 'deferred' / 'error' / 'skipped' (when no diff to apply)
--
-- Recipes MAY supply custom completion predicates via optional `hasPrimary`
-- and `hasTarget` fields (functions taking a player, returning bool). Used
-- for quests whose completion isn't tracked in the standard quest/mission
-- bitfields — e.g. HiddenQuest cipher/AF chains that live in CharVars or
-- inventory item presence. Default falls back to hasCompletedQuest /
-- hasCompletedMission when those fields aren't provided.
function bots_progression_cascade.maybe_apply(primary, target, r)
    local hasOnPrimary, hasOnTarget
    if r.hasPrimary and r.hasTarget then
        hasOnPrimary = r.hasPrimary(primary)
        hasOnTarget  = r.hasTarget(target)
    elseif r.kind == 'quest' then
        hasOnPrimary = primary:hasCompletedQuest(r.log, r.qid)
        hasOnTarget  = target:hasCompletedQuest(r.log, r.qid)
    else
        hasOnPrimary = primary:hasCompletedMission(r.log, r.mid)
        hasOnTarget  = target:hasCompletedMission(r.log, r.mid)
    end

    if not (hasOnPrimary and not hasOnTarget) then return 'skipped' end

    local ok, result = pcall(r.apply, target)
    if not ok then
        srvlog(string.format('ERROR %s log=%s id=%s target=%s: %s',
            r.kind, tostring(r.log), tostring(r.qid or r.mid),
            target:getName(), tostring(result)))
        return 'error'
    end

    local status = (type(result) == 'table' and result.status) or 'applied'
    if status == 'deferred' then
        srvlog(string.format('DEFER %s log=%s id=%s target=%s (need %d slots, has %d)',
            r.kind, tostring(r.log), tostring(r.qid or r.mid),
            target:getName(), result.need, result.have))
    end
    return status
end

-----------------------------------
-- Registry walk pass — reward-block cascade for every Quest:new / Mission:new.
--
-- The Interaction framework's Quest:new / Mission:new self-register into
-- xi.QuestRegistry[log][qid] and xi.MissionRegistry[log][mid] at script
-- load (~99% coverage). Each registered object exposes :complete(player)
-- which calls npcUtil.completeQuest / completeMission with the script's
-- own static .reward table. For any quest primary has completed and
-- target hasn't, calling quest:complete(target) delivers the full .reward
-- block (gil, items, fame, title, KIs) and sets the completion bit.
--
-- The recipe pass runs FIRST in syncToTarget so recipes get their inline
-- apply-closure grants delivered; the registry walk runs second and
-- naturally skips quests the recipe pass already handled (via the
-- build_recipe_keyset skip-set + target:hasCompletedQuest gating).
--
-- Known non-Quest:new legacy scripts (tutorial / flyers_for_regine /
-- full_speed_ahead) are not in xi.QuestRegistry. If those become worth
-- cascading, add bespoke recipes in bots_progression_cascade/orphans.lua.
-----------------------------------

-- Build a (log, key) → recipe skip-set so the registry pass doesn't double-
-- apply rewards for entries the recipe table already handles. The recipe's
-- `apply` callback may include side-effects (unlockJob etc.) that aren't
-- in quest.reward, so the recipe is authoritative for its curated quest.
local function build_recipe_keyset(kind)
    local set = {}
    for r in eachRecipe(kind) do
        local key = (kind == 'quest') and r.qid or r.mid
        set[r.log] = set[r.log] or {}
        set[r.log][key] = true
    end
    return set
end

-- Per-(target, kind) registry walk. Iterates xi.QuestRegistry or
-- xi.MissionRegistry; for each entry that primary has completed and target
-- doesn't AND that isn't already handled by the curated recipe table, call
-- :complete(target). Inventory-full deferrals come back as completeQuest
-- returning false; we count them as 'deferred' so the chatline message
-- mirrors the recipe-pass diagnostics.
local function registry_walk_target(primary, target, kind)
    local stats = { applied = 0, deferred = 0, errors = 0, skipped = 0, candidates = 0 }
    local registry = (kind == 'quest') and xi.QuestRegistry or xi.MissionRegistry
    if type(registry) ~= 'table' then return stats end

    local skip = build_recipe_keyset(kind)

    for log, byKey in pairs(registry) do
        for key, obj in pairs(byKey) do
            stats.candidates = stats.candidates + 1
            if skip[log] and skip[log][key] then
                stats.skipped = stats.skipped + 1
            else
                local hasPrimary, hasTarget
                if kind == 'quest' then
                    hasPrimary = primary:hasCompletedQuest(log, key)
                    hasTarget  = target:hasCompletedQuest(log, key)
                else
                    hasPrimary = primary:hasCompletedMission(log, key)
                    hasTarget  = target:hasCompletedMission(log, key)
                end

                if hasPrimary and not hasTarget then
                    -- Pre-align mission pointer for completeMission's
                    -- (current != missionID) gate. Quests don't have this
                    -- pointer concept — completeQuest works regardless.
                    if kind == 'mission' and target.addMission then
                        target:addMission(log, key)
                    end

                    local ok, result = pcall(function() return obj:complete(target) end)
                    if not ok then
                        srvlog(string.format('REGISTRY ERROR %s log=%s id=%s target=%s: %s',
                            kind, tostring(log), tostring(key),
                            target:getName(), tostring(result)))
                        stats.errors = stats.errors + 1
                    elseif result == false then
                        -- Most common cause: inventory full (giveItem returned
                        -- false). User clears space and re-presses Sync.
                        stats.deferred = stats.deferred + 1
                    else
                        stats.applied = stats.applied + 1
                    end
                else
                    stats.skipped = stats.skipped + 1
                end
            end
        end
    end
    return stats
end

-- Per-(target, kind) sync. Recipe pass first (curated side-effects applied
-- correctly for the structural quests), then registry walk for the long
-- tail (~99% of quests have a registered Quest object with .reward).
local function syncToTarget(primary, target, kind)
    local stats = { applied = 0, deferred = 0, errors = 0, skipped = 0, candidates = 0 }
    for r in eachRecipe(kind) do
        stats.candidates = stats.candidates + 1
        local status = bots_progression_cascade.maybe_apply(primary, target, r)
        stats[status] = (stats[status] or 0) + 1
    end

    -- Registry pass — folded into the same stats so the chatline reports
    -- a single applied/deferred/error count covering both passes.
    local reg = registry_walk_target(primary, target, kind)
    stats.applied   = stats.applied   + reg.applied
    stats.deferred  = stats.deferred  + reg.deferred
    stats.errors    = stats.errors    + reg.errors
    stats.candidates = stats.candidates + reg.candidates
    -- reg.skipped is "already had it / in recipe set / primary doesn't have"
    -- — informational only; not folded into the report to avoid noise.

    return stats
end

function bots_progression_cascade.sync_quests_to(primary, target)
    return syncToTarget(primary, target, 'quest')
end

function bots_progression_cascade.sync_missions_to(primary, target)
    return syncToTarget(primary, target, 'mission')
end

-- Aggregate stats across multiple targets and report to primary's chatline +
-- server log. The chatline is concise (one screen-line); the server log spells
-- out the detected-vs-done breakdown for diagnostics.
local function aggregateAndReport(primary, kind, targets)
    local agg = { applied = 0, deferred = 0, errors = 0, skipped = 0, candidates = 0, perTarget = {} }
    local label = (kind == 'quest') and 'Quests' or 'Missions'

    for _, t in ipairs(targets) do
        local s = syncToTarget(primary, t, kind)
        agg.applied   = agg.applied   + s.applied
        agg.deferred  = agg.deferred  + s.deferred
        agg.errors    = agg.errors    + s.errors
        agg.skipped   = agg.skipped   + s.skipped
        agg.candidates = agg.candidates + s.candidates
        table.insert(agg.perTarget, { name = t:getName(), stats = s })
    end

    -- Server log: detection breakdown + per-target results.
    srvlog(string.format(
        'Sync %s by "%s": detected %d candidate recipe(s) across %d target(s); ' ..
        'applied=%d deferred=%d errors=%d skipped=%d',
        label, primary:getName(), agg.candidates, #targets,
        agg.applied, agg.deferred, agg.errors, agg.skipped))
    for _, pt in ipairs(agg.perTarget) do
        srvlog(string.format('  target "%s": applied=%d deferred=%d errors=%d skipped=%d',
            pt.name, pt.stats.applied, pt.stats.deferred, pt.stats.errors, pt.stats.skipped))
    end

    -- Chatline to primary: concise summary with actionable hint if needed.
    local msg = string.format('Sync %s: %d applied', label, agg.applied)
    if agg.deferred > 0 then
        msg = msg .. string.format(', %d deferred (inventory full — clear space and re-press)', agg.deferred)
    end
    if agg.errors > 0 then
        msg = msg .. string.format(', %d errors (see server log)', agg.errors)
    end
    primary:printToPlayer(msg .. '.')
    return agg.applied
end

-- AF mirror pass: walk bots_progression_cascade.AF1_COFFER_ITEMS; if primary has the item and
-- target doesn't, deliver via addItem (if inventory has space, else defer).
-- Per-target log line spells out every piece delivered + deferred by name so
-- the user can verify the sync actually happened.
function bots_progression_cascade.sync_af_items_to(primary, target)
    local stats = {
        delivered     = 0,
        deferred      = 0,
        already_held  = 0,
        not_on_primary = 0,
        delivered_names = {},
        deferred_names  = {},
    }
    for _, piece in ipairs(bots_progression_cascade.AF1_COFFER_ITEMS) do
        if not primary:hasItem(piece.id) then
            stats.not_on_primary = stats.not_on_primary + 1
        elseif target:hasItem(piece.id) then
            stats.already_held = stats.already_held + 1
        else
            local free = target.getFreeSlotsCount and target:getFreeSlotsCount() or 0
            if free <= 0 then
                stats.deferred = stats.deferred + 1
                table.insert(stats.deferred_names, piece.name)
            else
                target:addItem(piece.id)
                stats.delivered = stats.delivered + 1
                table.insert(stats.delivered_names, piece.name)
            end
        end
    end
    return stats
end

local function syncAFItemsAll(primary, targets)
    local total = { delivered = 0, deferred = 0 }
    -- Pre-count how many of the 30 canonical pieces the primary actually has —
    -- helpful header for the server log so you know if there's even anything
    -- to mirror this round.
    local primaryHas = 0
    for _, piece in ipairs(bots_progression_cascade.AF1_COFFER_ITEMS) do
        if primary:hasItem(piece.id) then primaryHas = primaryHas + 1 end
    end
    srvlog(string.format(
        'AF mirror by "%s": primary has %d of %d canonical AF1 coffer pieces, %d target(s)',
        primary:getName(), primaryHas, #bots_progression_cascade.AF1_COFFER_ITEMS, #targets))

    for _, t in ipairs(targets) do
        local s = bots_progression_cascade.sync_af_items_to(primary, t)
        total.delivered = total.delivered + s.delivered
        total.deferred  = total.deferred  + s.deferred

        local parts = {}
        if s.delivered > 0 then
            table.insert(parts, string.format('delivered %d (%s)',
                s.delivered, table.concat(s.delivered_names, ', ')))
        end
        if s.deferred > 0 then
            table.insert(parts, string.format('deferred %d inv-full (%s)',
                s.deferred, table.concat(s.deferred_names, ', ')))
        end
        if s.already_held > 0 then
            table.insert(parts, string.format('already_held %d', s.already_held))
        end
        if #parts == 0 then table.insert(parts, 'nothing to mirror') end
        srvlog(string.format('  target "%s": %s', t:getName(), table.concat(parts, '; ')))
    end
    return total
end

function bots_progression_cascade.sync_quests(primary, targets)
    if primary == nil or targets == nil then return 0 end
    -- Sync Quests does THREE passes:
    --   1. Recipe + registry-walk cascade (covers Quest:new objects).
    --   2. AF1 coffer-drop item mirror.
    --   3. Hidden trust-spell mirror (the 8 HiddenQuest:new trust quests
    --      that don't appear in xi.QuestRegistry — see #178 audit).
    -- All three fold under the same UI button (per user spec: "no separate
    -- items button"). Combined applied count is returned to the C++ caller
    -- so the SYNC_ACK packet reflects the total.
    local questApplied = aggregateAndReport(primary, 'quest', targets)
    local af           = syncAFItemsAll(primary, targets)
    if af.delivered > 0 or af.deferred > 0 then
        local msg = string.format('Sync AF: %d piece(s) mirrored', af.delivered)
        if af.deferred > 0 then
            msg = msg .. string.format(', %d deferred (inventory full)', af.deferred)
        end
        primary:printToPlayer(msg .. '.')
    end

    -- Hidden trust spell pass.
    local trustApplied = 0
    for _, t in ipairs(targets) do
        local s = bots_progression_cascade.sync_hidden_trust_spells_to(primary, t)
        trustApplied = trustApplied + s.applied
    end
    if trustApplied > 0 then
        primary:printToPlayer(string.format(
            'Sync Hidden Trusts: %d spell(s) mirrored.', trustApplied))
    end

    return questApplied + af.delivered + trustApplied
end

function bots_progression_cascade.sync_missions(primary, targets)
    if primary == nil or targets == nil then return 0 end
    return aggregateAndReport(primary, 'mission', targets)
end

-----------------------------------
-- Sync Teleports
-----------------------------------
-- Cascade the full teleport bitfield surface from primary onto each
-- headless. Walks every TELEPORT_TYPE value and copies set bits via
-- addTeleport. Idempotent — hasTeleport gate skips bits the target
-- already owns so re-running this is cheap.
--
-- Engine surface (src/map/zone.h):
--   * Single uint32 fields (no set index): OUTPOST_SANDY/BASTOK/WINDY,
--     RUNIC_PORTAL, PAST_MAW, ABYSSEA_CONFLUX (per-zone byte),
--     CAMPAIGN_SANDY/BASTOK/WINDY, ESCHAN_PORTAL
--   * 4 × uint32 arrays (set index 0..3): HOMEPOINT, SURVIVAL
--   * 2 × uint32 array, flat bit space 0..63: WAYPOINT
--   * Per-zone uint8 array (MAX_ABYSSEAZONES=9): ABYSSEA_CONFLUX
-- addTeleport(type, bitPos, [setOrZone]) wraps bit OR-in for all of
-- these; we walk bit-by-bit so a single addTeleport binding covers
-- every field shape.
local TELEPORT_T = {
    OUTPOST_SANDY   = 0,
    OUTPOST_BASTOK  = 1,
    OUTPOST_WINDY   = 2,
    RUNIC_PORTAL    = 3,
    PAST_MAW        = 4,
    ABYSSEA_CONFLUX = 5,
    CAMPAIGN_SANDY  = 6,
    CAMPAIGN_BASTOK = 7,
    CAMPAIGN_WINDY  = 8,
    HOMEPOINT       = 9,
    SURVIVAL        = 10,
    WAYPOINT        = 11,
    ESCHAN_PORTAL   = 12,
}

local MAX_ABYSSEAZONES = 9  -- mirrors charentity.h MAX_ABYSSEAZONES

-- Walk a uint32 bitfield and addTeleport every set bit on the target.
-- setOrZone defaults to 0 (no-arg variant for getTeleport bindings).
-- target:hasTeleport gates the call so we only add bits the target
-- doesn't already own — keeps the addTeleport ShowError logs quiet on
-- re-syncs.
local function cascade_uint32(primary, target, teleType, srcBits, setOrZone)
    if srcBits == nil or srcBits == 0 then return 0 end
    local added = 0
    for b = 0, 31 do
        if bit.band(srcBits, bit.lshift(1, b)) ~= 0 then
            local owned
            if setOrZone == nil then
                owned = target:hasTeleport(teleType, b)
            else
                owned = target:hasTeleport(teleType, b, setOrZone)
            end
            if not owned then
                if setOrZone == nil then
                    target:addTeleport(teleType, b)
                else
                    target:addTeleport(teleType, b, setOrZone)
                end
                added = added + 1
            end
        end
    end
    return added
end

-- Per-target cascade. Returns count of bits newly added (for reporting).
function bots_progression_cascade.sync_teleports_to(primary, target)
    if primary == nil or target == nil then return 0 end
    local total = 0

    -- Single-uint32 fields. getTeleport returns the raw uint32.
    local single = {
        TELEPORT_T.OUTPOST_SANDY,   TELEPORT_T.OUTPOST_BASTOK, TELEPORT_T.OUTPOST_WINDY,
        TELEPORT_T.RUNIC_PORTAL,    TELEPORT_T.PAST_MAW,
        TELEPORT_T.CAMPAIGN_SANDY,  TELEPORT_T.CAMPAIGN_BASTOK, TELEPORT_T.CAMPAIGN_WINDY,
        TELEPORT_T.ESCHAN_PORTAL,
    }
    for _, t in ipairs(single) do
        total = total + cascade_uint32(primary, target, t, primary:getTeleport(t), nil)
    end

    -- HOMEPOINT / SURVIVAL: 4 × uint32 arrays. getTeleportTable returns a
    -- table indexed 1..4 with the raw access values.
    for _, t in ipairs({ TELEPORT_T.HOMEPOINT, TELEPORT_T.SURVIVAL }) do
        local tbl = primary:getTeleportTable(t)
        if type(tbl) == 'table' then
            for set = 0, 3 do
                total = total + cascade_uint32(primary, target, t, tbl[set + 1] or 0, set)
            end
        end
    end

    -- WAYPOINT: 2 × uint32 array exposed as a flat 64-bit space (engine
    -- splits bitval into index/bit internally). hasTeleport for WAYPOINT
    -- uses the flat bitPos directly without a set arg.
    local wpTbl = primary:getTeleportTable(TELEPORT_T.WAYPOINT)
    if type(wpTbl) == 'table' then
        for index = 0, 1 do
            local bits = wpTbl[index + 1] or 0
            if bits ~= 0 then
                for b = 0, 31 do
                    if bit.band(bits, bit.lshift(1, b)) ~= 0 then
                        local flatBit = index * 32 + b
                        if not target:hasTeleport(TELEPORT_T.WAYPOINT, flatBit) then
                            target:addTeleport(TELEPORT_T.WAYPOINT, flatBit)
                            total = total + 1
                        end
                    end
                end
            end
        end
    end

    -- ABYSSEA_CONFLUX: per-zone uint8 (9 zones). getTeleport takes a zone
    -- index as the second arg. addTeleport / hasTeleport take (type, bit,
    -- zone). Each zone stores up to 8 bits.
    for zone = 0, MAX_ABYSSEAZONES - 1 do
        local bits = primary:getTeleport(TELEPORT_T.ABYSSEA_CONFLUX, zone) or 0
        if bits ~= 0 then
            for b = 0, 7 do
                if bit.band(bits, bit.lshift(1, b)) ~= 0 then
                    if not target:hasTeleport(TELEPORT_T.ABYSSEA_CONFLUX, b, zone) then
                        target:addTeleport(TELEPORT_T.ABYSSEA_CONFLUX, b, zone)
                        total = total + 1
                    end
                end
            end
        end
    end

    return total
end

-- Alliance-wide cascade. Aggregates the per-target counts, reports both
-- to the primary's chatline (concise) and server log (per-target spell
-- out) — mirrors aggregateAndReport's pattern for quests/missions.
function bots_progression_cascade.sync_teleports(primary, targets)
    if primary == nil or targets == nil then return 0 end
    local total = 0
    local perTarget = {}
    for _, t in ipairs(targets) do
        local added = bots_progression_cascade.sync_teleports_to(primary, t)
        total = total + added
        table.insert(perTarget, { name = t:getName(), added = added })
    end

    srvlog(string.format(
        'Sync Teleports by "%s": added %d bit(s) across %d target(s)',
        primary:getName(), total, #targets))
    for _, pt in ipairs(perTarget) do
        srvlog(string.format('  target "%s": added=%d', pt.name, pt.added))
    end

    primary:printToPlayer(string.format('Sync Teleports: %d added.', total))
    return total
end

-----------------------------------
-- Live cascade — wrap npcUtil.completeQuest / completeMission so that when
-- an alliance primary completes a quest or mission in normal gameplay,
-- every headless in their alliance immediately gets the SAME recipe
-- treatment the Sync buttons deliver. This is a QoL bonus; the button-
-- driven path is authoritative and must work independently.
--
-- Symmetry with the button path: the wrap looks up the matching recipe by
-- (log, id) and fires recipe.apply(headless), which dispatches BOTH the
-- .reward block via completeQuest AND any inline grants transcribed in the
-- recipe's apply closure. Falling back to the raw original(h, ...) call
-- for quests/missions without a recipe means the ~99% registry-walk-only
-- coverage still cascades in real time via .reward alone.
--
-- Why wrap inside a player-event hook instead of at module load: this
-- file's module body runs during moduleutils::LoadLuaModules, which is
-- BEFORE scripts/globals/npc_util.lua is loaded into the global namespace.
-- npcUtil doesn't exist yet at module-body time. Deferring to the first
-- onPlayerLogin guarantees npcUtil is present; the wrapper is idempotent
-- via the _cascade_wrapped sentinel so repeat-login calls are a no-op.
-- Login also fires after the per-area recipe files in the subdirectory
-- have all loaded, so recipes.<area> is fully populated by then.
-----------------------------------

local function is_primary_with_alliance(player)
    if player == nil or xi.singleplayer == nil or xi.singleplayer.bots == nil then return false end
    local A = xi.singleplayer.bots.alliance
    if A == nil then return false end
    return A.mainCharId ~= nil and A.mainCharId == player:getID()
end

local function get_headless_alliance(primary)
    local out = {}
    local A   = xi.singleplayer.bots and xi.singleplayer.bots.alliance
    if A == nil or type(A.headlessCharIds) ~= 'table' then return out end
    for _, charId in ipairs(A.headlessCharIds) do
        local h = GetPlayerByID(charId)
        if h ~= nil then table.insert(out, h) end
    end
    return out
end

-- (log, id) → recipe caches for the live wrap. Built lazily on first
-- cascade dispatch after login so per-area subdir files have registered
-- their recipe tables. Cheap to rebuild; wrap flushes via _lookup_dirty
-- sentinel if a future path ever needs to invalidate.
local _quest_recipe_lookup   = nil
local _mission_recipe_lookup = nil

local function build_recipe_lookup(kind)
    local idx = {}
    for _, areaRecipes in pairs(bots_progression_cascade.recipes) do
        for _, r in ipairs(areaRecipes) do
            if r.kind == kind then
                local key = (kind == 'quest') and r.qid or r.mid
                idx[r.log] = idx[r.log] or {}
                idx[r.log][key] = r
            end
        end
    end
    return idx
end

local function get_quest_recipe(log, qid)
    if _quest_recipe_lookup == nil then
        _quest_recipe_lookup = build_recipe_lookup('quest')
    end
    return _quest_recipe_lookup[log] and _quest_recipe_lookup[log][qid]
end

local function get_mission_recipe(log, mid)
    if _mission_recipe_lookup == nil then
        _mission_recipe_lookup = build_recipe_lookup('mission')
    end
    return _mission_recipe_lookup[log] and _mission_recipe_lookup[log][mid]
end

local function ensure_cascade_wrap()
    if npcUtil == nil then return end

    -- Wrap completeQuest. After the original returns true (primary got the
    -- bit + reward block), look up the matching recipe and fire its apply
    -- closure on each headless — dispatching .reward + inline grants in
    -- one shot. Recipe-less quests fall back to raw original() so the ~99%
    -- registry-walk coverage still cascades in real time.
    --
    -- Headless's own call also flows through this wrapper, but
    -- is_primary_with_alliance is false for them so no infinite recursion.
    if npcUtil.completeQuest and not npcUtil._cascade_wrapped_quest then
        npcUtil._cascade_wrapped_quest = true
        local original = npcUtil.completeQuest
        npcUtil.completeQuest = function(player, area, quest, params)
            local result = original(player, area, quest, params)
            if result and is_primary_with_alliance(player) then
                local recipe = get_quest_recipe(area, quest)
                for _, h in ipairs(get_headless_alliance(player)) do
                    if not h:hasCompletedQuest(area, quest) then
                        if recipe ~= nil then
                            -- Recipe.apply handles .reward via require(source)
                            -- + npcUtil.completeQuest AND the inline apply
                            -- closure with hand-transcribed grants.
                            pcall(recipe.apply, h)
                        else
                            -- No recipe — fall back to plain .reward replay
                            -- for registry-walk-only quests.
                            pcall(original, h, area, quest, params)
                        end
                    end
                end
            end
            return result
        end
    end

    -- Same shape for completeMission. Recipe-driven when available, plain
    -- replay otherwise. Cross-nation rank handling is baked into the recipe
    -- factory (see nation_for_mission_log + setRankByNation dispatch in
    -- the mission() closure) so it flows through recipe.apply automatically.
    if npcUtil.completeMission and not npcUtil._cascade_wrapped_mission then
        npcUtil._cascade_wrapped_mission = true
        local original = npcUtil.completeMission
        npcUtil.completeMission = function(player, area, mission, params)
            local result = original(player, area, mission, params)
            if result and is_primary_with_alliance(player) then
                local recipe = get_mission_recipe(area, mission)
                for _, h in ipairs(get_headless_alliance(player)) do
                    if not h:hasCompletedMission(area, mission) then
                        if recipe ~= nil then
                            pcall(recipe.apply, h)
                        else
                            -- Pre-align the headless's mission pointer for
                            -- the (current != missionID) gate.
                            if h.addMission then h:addMission(area, mission) end
                            pcall(original, h, area, mission, params)
                        end
                    end
                end
            end
            return result
        end
    end
end

-- Install the wrap on first player login. Idempotent — subsequent logins
-- see the sentinel flags and no-op. Login fires after globals are loaded,
-- so npcUtil is guaranteed to exist.
m:addOverride('xi.player.onPlayerLogin', function(player)
    super(player)
    ensure_cascade_wrap()
end)

return m
