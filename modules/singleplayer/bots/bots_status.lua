-----------------------------------
-- bots_status: periodic push of headless status effects + portrait keys
-- (race/face) + main-job EXP to the primary's client so the autobots addon
-- can render the Status tab. Sends one GP_SERV_COMMAND_PARTY_STATUS (0x191)
-- packet per party in the alliance, every PUSH_INTERVAL_MS milliseconds —
-- plus an immediate force-push fires at the end of spawn_alliance so the
-- Status tab fills in within a tick of the alliance assembling instead of
-- waiting up to PUSH_INTERVAL_MS for the first scheduled push.
--
-- Hook point is xi.singleplayer.bots.onBotTick (driven every PostTick from
-- C++), with a per-primary timestamp gate so the actual push fires ~once
-- per 2s instead of on every tick. Each per-bot snapshot reads the bot's
-- current race/face + main-job EXP every push — cheap engine reads, and
-- captures level-ups / face-changes / face-paint without any subscribe-on-
-- change plumbing.
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('bots_status')

xi = xi or {}
xi.singleplayer = xi.singleplayer or {}
xi.singleplayer.bots = xi.singleplayer.bots or {}
xi.singleplayer.bots.bots_status = xi.singleplayer.bots.bots_status or {}
local bots_status = xi.singleplayer.bots.bots_status

-- Cadence. Was 5000ms — the old value left the Status tab blank for up to
-- ~9s after spawn (4s post-zone-in bot-AI delay + up to 5s push gate). 2s
-- gives the user a responsive Status feel without flooding the wire (each
-- push is at most 3 × 416 bytes for a full alliance).
local PUSH_INTERVAL_MS = 2000

-- Per-primary last-push timestamp keyed by primary:getID().
bots_status.lastPushMs = bots_status.lastPushMs or {}

local function ms_now() return math.floor(os.clock() * 1000) end

-----------------------------------
-- Build a packet payload for one party (subset of the alliance whose party
-- number == partyNumber). Returns a list { { name, race, face, expCurrent,
-- expToNext, effects[] }, ... } in alliance order, or nil if the party has
-- no members. Engine reads happen here — race/face/exp are queried each push
-- so level-ups and the rare face-change show up without explicit invalidation.
-----------------------------------
local function collect_party(primary, partyNumber)
    local alliance = primary.getAlliance and primary:getAlliance() or {}
    local out = {}
    for _, member in ipairs(alliance) do
        if member.getAllianceParty and member:getAllianceParty() == partyNumber then
            local effects = {}
            local list    = member.getStatusEffects and member:getStatusEffects() or {}
            for _, eff in ipairs(list) do
                local id = eff.getEffectType and eff:getEffectType() or 0
                if id > 0 then table.insert(effects, id) end
            end
            table.insert(out, {
                name       = member:getName(),
                race       = member.getRace            and member:getRace()            or 0,
                face       = member.getFace            and member:getFace()            or 0,
                expCurrent = member.getCurrentJobExp   and member:getCurrentJobExp()   or 0,
                expToNext  = member.getRequiredJobExp  and member:getRequiredJobExp()  or 0,
                effects    = effects,
            })
        end
    end
    if #out == 0 then return nil end
    return out
end

-----------------------------------
-- Push status for one primary's alliance (1-3 packets, one per party).
-----------------------------------
function bots_status.push_for_primary(primary)
    if primary == nil then return end
    for partyNumber = 1, 3 do
        local members = collect_party(primary, partyNumber)
        if members then
            PushPartyStatus(primary, partyNumber, members)
        end
    end
end

-----------------------------------
-- Force an immediate push and reset the gate so a follow-up tick won't
-- double-push within the same interval. Called from bots_spawn at the end
-- of spawn_alliance so the Status tab fills in as soon as the alliance is
-- assembled instead of waiting for the next gated tick. Safe to call from
-- anywhere — caller is responsible for not spamming it.
-----------------------------------
function bots_status.force_push(primary)
    if primary == nil then return end
    bots_status.lastPushMs[primary:getID()] = ms_now()
    bots_status.push_for_primary(primary)
end

-----------------------------------
-- Tick gate. Called from xi.singleplayer.bots.onBotTick once per ticking
-- char per PostTick. onBotTick fires for both headless bots AND primaries
-- with bot mode enabled, so the ticker may be a bot. The status packet has
-- to go to the PRIMARY's client session (bots are headless — no client to
-- receive). Resolve the primary from the parent char id, and key the rate-
-- limit gate on the primary's id so the push fires once per primary per
-- cycle, regardless of how many bots ticked through this hook in the same
-- window.
-----------------------------------
function bots_status.tick(ticker)
    if ticker == nil then return end
    local primary = ticker
    if ticker.isHeadless and ticker:isHeadless() then
        local parentId = ticker.getParentCharId and ticker:getParentCharId() or 0
        if parentId == 0 then return end
        primary = GetPlayerByID(parentId)
        if primary == nil then return end
    end
    local id = primary:getID()
    local now = ms_now()
    local last = bots_status.lastPushMs[id] or 0
    if now - last < PUSH_INTERVAL_MS then return end
    bots_status.lastPushMs[id] = now
    bots_status.push_for_primary(primary)
end

-----------------------------------
-- Clear the last-push timestamp when the primary logs out so a re-login
-- forces a fresh push within one tick instead of waiting for the previous
-- timestamp to fall outside the interval window.
-----------------------------------
function bots_status.destroy_state(primaryId)
    bots_status.lastPushMs[primaryId] = nil
end

-- Hook the per-PostTick C++ dispatch. The PUSH_INTERVAL_MS gate inside
-- tick() makes the actual packet build/send fire ~once per interval
-- regardless of how often onBotTick is called.
m:addOverride('xi.singleplayer.bots.onBotTick', function(player, botMode)
    super(player, botMode)
    bots_status.tick(player)
end)

return m
