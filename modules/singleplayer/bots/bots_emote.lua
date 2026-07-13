-----------------------------------
-- Server-side AI: per-job emotes on alliance lifecycle events (level up,
-- death, HQ synth). Ported from client-side behavior. We hook the
-- player lifecycle callbacks and pick an emote per party member's main job —
-- jobs not in a table stay silent so the flavor doesn't spam the alliance.
--
-- HQ-synth: stubbed; needs a small C++ hook in synthutils to fire.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('bots_emote')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.bots_emote = xi.singleplayer.bots.bots_emote or {}
local bots_emote = xi.singleplayer.bots.bots_emote

-----------------------------------
-- Per-job emote pickers. Jobs not listed simply don't emote.
-----------------------------------
-- Camp-settling per-job emote. Fired by ai_formation.set_walking_formation
-- when the user switches to 'camp'. Intentionally empty: the mechanism
-- stays wired so a job can later be given an emote without touching
-- ai_formation, but no job emotes today. Add entries here keyed by job
-- name (`WAR = xi.emote.SIT`, etc.) to enable.
bots_emote.campEmoteByJob = {}

bots_emote.deathEmoteByJob = {
    -- Mourners: lose-the-spirits caster classes
    WHM = xi.emote.CRY,
    SCH = xi.emote.CRY,
    BRD = xi.emote.CRY,
    RDM = xi.emote.CRY,
    GEO = xi.emote.CRY,
    -- Edgelords: dark-aligned mages
    BLM = xi.emote.LAUGH,
    DRK = xi.emote.LAUGH,
    -- Sworn knights: somber farewell
    PLD = xi.emote.SIGH,
    RUN = xi.emote.SIGH,
}

bots_emote.levelUpEmoteByJob = {
    -- Cheerleaders: support and finesse classes
    PLD = xi.emote.PRAISE,
    BRD = xi.emote.PRAISE,
    DNC = xi.emote.PRAISE,
    WHM = xi.emote.CHEER,
    RDM = xi.emote.CHEER,
    SCH = xi.emote.CHEER,
    GEO = xi.emote.CHEER,
    -- Soldiers: respectful nod to a fellow warrior
    WAR = xi.emote.SALUTE,
    MNK = xi.emote.SALUTE,
    SAM = xi.emote.SALUTE,
    DRG = xi.emote.SALUTE,
    RUN = xi.emote.SALUTE,
}

bots_emote.raiseEmoteByJob = {
    -- Healers / support: "phew, got you back"
    WHM = xi.emote.CHEER,
    RDM = xi.emote.CHEER,
    SCH = xi.emote.CHEER,
    GEO = xi.emote.CHEER,
    -- Energetic support: "yay!"
    BRD = xi.emote.DANCE,
    DNC = xi.emote.DANCE,
    -- Contemplative warriors: "what happened?"
    MNK = xi.emote.THINK,
    NIN = xi.emote.THINK,
    -- THF: tease the unfortunate
    THF = xi.emote.POINT,
    -- Dark-aligned: gallows humor
    BLM = xi.emote.LAUGH,
    DRK = xi.emote.LAUGH,
    -- Sworn knights: honor the fallen-now-returned
    PLD = xi.emote.SALUTE,
    RUN = xi.emote.SALUTE,
    WAR = xi.emote.SALUTE,
    SAM = xi.emote.SALUTE,
    DRG = xi.emote.SALUTE,
}

-----------------------------------
-- Hard cap on emoters per trigger. Alliance-scope means up to 17 candidates;
-- without a cap a full-alliance level-up would dump 17 emote packets into
-- /say and feel like spam. 6 is a comfortable "small crowd" — the user sees
-- a reaction from each party plus a couple stragglers without saturating chat.
local MAX_EMOTERS_PER_TRIGGER = 6

-----------------------------------
-- For each alliance member of `subject` who is in the same zone and is not the
-- subject themselves, emote `tbl[mainJob]` (if any) aimed at the subject. If
-- `tbl` is nil, every living alliance member emotes `defaultEmote`. When more
-- than MAX_EMOTERS_PER_TRIGGER candidates qualify, randomly pick that many
-- (Fisher-Yates partial shuffle — biased-free) so the same characters don't
-- dominate every trigger.
-----------------------------------
local function partyEmoteByJob(subject, tbl, defaultEmote)
    if subject == nil then return end
    local alliance = subject.getAlliance and subject:getAlliance() or nil
    if alliance == nil then return end
    local subjectId   = subject:getID()
    local subjectZone = subject:getZoneID()

    -- Build the candidate list first; sampling and dispatch happen afterwards.
    local candidates = {}
    for _, member in ipairs(alliance) do
        if member ~= nil
            and member:getID() ~= subjectId
            and member:getZoneID() == subjectZone
            and not member:isDead()
        then
            local emoteId
            if tbl ~= nil then
                local jobName = xi.jobName[member:getMainJob()]
                local jobAbbr = jobName and jobName[1]
                emoteId = jobAbbr and tbl[jobAbbr]
            else
                emoteId = defaultEmote
            end
            if emoteId ~= nil then
                candidates[#candidates + 1] = { member = member, emoteId = emoteId }
            end
        end
    end

    local fireCount = math.min(#candidates, MAX_EMOTERS_PER_TRIGGER)
    -- Partial Fisher-Yates: only swap up to fireCount picks to the front. For
    -- 17 candidates picking 6 that's 6 swaps instead of a full 17-element shuffle.
    for i = 1, fireCount do
        local j = math.random(i, #candidates)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end

    for i = 1, fireCount do
        local pick = candidates[i]
        pick.member:sendEmote(subject, pick.emoteId, xi.emoteMode.ALL, false)
    end
end

-----------------------------------
-- Hook: level up → per-job emote at the leveling player
-----------------------------------
m:addOverride('xi.player.onPlayerLevelUp', function(player)
    super(player)
    partyEmoteByJob(player, bots_emote.levelUpEmoteByJob, nil)
end)

-----------------------------------
-- Hook: death → per-job emote at the fallen player
-----------------------------------
m:addOverride('xi.player.onPlayerDeath', function(player)
    super(player)
    partyEmoteByJob(player, bots_emote.deathEmoteByJob, nil)
end)

-----------------------------------
-- Hook: raise → per-job "welcome back" emote at the raised player. Fires for
-- both real-player Accept clicks (via 0x01A) and headless auto-accept (via
-- bots_listeners.poll calling :acceptRaise()). Routed through partyEmoteByJob
-- so it picks up the alliance scope + 6-cap automatically.
-----------------------------------
m:addOverride('xi.player.onPlayerRaise', function(player)
    super(player)
    partyEmoteByJob(player, bots_emote.raiseEmoteByJob, nil)
end)

-----------------------------------
-- Hook: synth finish → on HQ, every alliance member /claps at the crafter
-- (capped by partyEmoteByJob's MAX_EMOTERS_PER_TRIGGER).
--
-- synthResult values from synthutils.cpp's SYNTHESIS_* enum:
--   1 = SUCCESS  → normal synth, no emote
--   2 = HQ
--   3 = HQ2
--   4 = HQ3
-----------------------------------
m:addOverride('xi.player.onSynthFinish', function(player, synthResult)
    super(player, synthResult)
    -- HQ tier 1 or better: 2 (HQ), 3 (HQ2), 4 (HQ3).
    if (synthResult or 0) >= 2 then
        partyEmoteByJob(player, nil, xi.emote.CLAP)
    end
end)

-- Back-compat shim: pre-#205 code path called onHQSynth(player, grade) with
-- grade=0 for non-HQ and 1+ for HQ tiers. Now that the C++ hook fires
-- onSynthFinish directly, this is just a thin wrapper for any caller that
-- still uses the old name. New code should override onSynthFinish.
function bots_emote.onHQSynth(player, grade)
    if player == nil or (grade or 0) <= 0 then return end
    partyEmoteByJob(player, nil, xi.emote.CLAP)
end

return m
