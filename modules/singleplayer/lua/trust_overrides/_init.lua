-----------------------------------
-- SINGLEPLAYER trust spawn override dispatcher
--
-- The fork keeps upstream's scripts/actions/spells/trust/<name>.lua files
-- vanilla (one inline SINGLEPLAYER-marked hook at the top of onMobSpawn) and
-- ships the fork's replacement spawn behavior here in
-- modules/singleplayer/lua/trust_overrides/<name>.lua.
--
-- REPLACE (not compose) is the contract: gambits are priority-ordered, so a
-- fork override owns the entire spawn body. The mirrored file paths make it
-- trivial to diff upstream vs fork during a rebase and decide whether to
-- pull any new upstream behavior into the fork override.
--
-- Filename convention: _init.lua sorts first in ASCII so this dispatcher
-- registers its namespace before any per-trust file in the same directory
-- calls registerSpawn().
-----------------------------------

local m = Module:new('trust_override__init')

xi.singleplayer       = xi.singleplayer or {}
xi.singleplayer.trust = xi.singleplayer.trust or {}

local overrides = {}

-- Per-trust override files call this at top-level to register a complete
-- replacement onMobSpawn body. Name is the trust's identifying key (matches
-- the second argument to maybeOverrideSpawn at the upstream call site).
function xi.singleplayer.trust.registerSpawn(name, fn)
    overrides[name] = fn
end

-- Called from the SINGLEPLAYER hook at the top of every fork-edited
-- upstream trust file. Returns true if a fork override ran (caller
-- short-circuits upstream). Returns false if no override is registered
-- OR the CUSTOM_TRUST_LOGIC setting is disabled (caller falls through
-- to upstream's body unchanged).
--
-- The setting is read on every spawn so it can be toggled at runtime via
-- reload without restarting the server.
function xi.singleplayer.trust.maybeOverrideSpawn(mob, name)
    if not (xi.settings.singleplayer and xi.settings.singleplayer.CUSTOM_TRUST_LOGIC) then
        return false
    end

    local fn = overrides[name]
    if fn then
        fn(mob)
        return true
    end
    return false
end

return m
