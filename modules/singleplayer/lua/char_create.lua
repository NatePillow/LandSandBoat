-----------------------------------
-- Add trusts to new players
-----------------------------------
require('modules/module_utils')
require('scripts/globals/player')
-----------------------------------
local m = Module:new('char_create')

local function setupNationMissions(player)
    -- Set rank to 10 in all nations
    local startingNation = player:getNation()
    if (startingNation ~= xi.nation.SANDORIA) then
        player:setNation(xi.nation.SANDORIA)
        player:setRank(10)
    end
    if (startingNation ~= xi.nation.WINDURST) then
        player:setNation(xi.nation.WINDURST)
        player:setRank(10)
    end
    if (startingNation ~= xi.nation.BASTOK) then
        player:setNation(xi.nation.BASTOK)
        player:setRank(10)
    end
    player:setNation(startingNation)
    player:setRank(10)

    -- Complete all nation missions (0-23) for each nation so they appear in the mission log
    -- Nation missions use a completion bitfield; each must be set as current then completed in sequence
    for id = 0, 23 do
        player:addMission(xi.mission.log_id.SANDORIA, id)
        player:completeMission(xi.mission.log_id.SANDORIA, id)
    end
    for id = 0, 23 do
        player:addMission(xi.mission.log_id.BASTOK, id)
        player:completeMission(xi.mission.log_id.BASTOK, id)
    end
    for id = 0, 23 do
        player:addMission(xi.mission.log_id.WINDURST, id)
        player:completeMission(xi.mission.log_id.WINDURST, id)
    end

    -- Three nation rank 10 key items (in-mission grants from 3_3/4_1 missions)
    player:addKeyItem(xi.ki.ADVENTURERS_CERTIFICATE)  -- 2_3_0 mission reward
    player:addKeyItem(xi.ki.DELKFUTT_KEY)             -- 3_3 Jeuno appointment (in-mission)
    player:addKeyItem(xi.ki.ARCHDUCAL_AUDIENCE_PERMIT) -- 4_1 Magicite (in-mission)
    player:addKeyItem(xi.ki.SILVER_BELL)              -- 4_1 Magicite (in-mission)
    player:addKeyItem(xi.ki.AIRSHIP_PASS)             -- 4_1 Magicite (in-mission)
    player:addKeyItem(xi.ki.YAGUDO_TORCH)             -- 4_1 Magicite (in-mission)
    player:addKeyItem(xi.ki.PIECE_OF_PAPER)           -- Sandy 6_1 Leaute's Last Wishes reward
    player:addKeyItem(xi.ki.CRIMSON_ORB)              -- hidden quest (Davoi gate access)
    player:addKeyItem(xi.ki.CORUSCANT_ROSARY)         -- Jeuno quest: Mysteries of Beadeaux I
    player:addKeyItem(xi.ki.BLACK_MATINEE_NECKLACE)   -- Jeuno quest: Mysteries of Beadeaux II

    -- Three nation rank 10 flags (in-mission grants from 9_2 missions)
    player:addItem(xi.item.SAN_DORIAN_FLAG)
    player:addItem(xi.item.BASTOKAN_FLAG)
    player:addItem(xi.item.WINDURSTIAN_FLAG)           -- Windurst 9_2 mission reward

    -- Three nation rank 10 titles
    player:addTitle(xi.title.FODDERCHIEF_FLAYER)          -- Sandy 1_3 (in-mission)
    player:addTitle(xi.title.CERTIFIED_ADVENTURER)        -- 2_3_0 mission reward
    player:addTitle(xi.title.HAVE_WINGS_WILL_FLY)         -- 4_1 Magicite (in-mission)
    player:addTitle(xi.title.SAN_DORIAN_ROYAL_HEIR)       -- Sandy 9_2 mission reward
    player:addTitle(xi.title.HERO_AMONG_HEROES)           -- Bastok 9_2 mission reward
    player:addTitle(xi.title.FRESH_NORTH_WINDS_RECRUIT)   -- Windurst 1_1 (gate-guard title, in-mission)
    player:addTitle(xi.title.GUIDING_STAR)                -- Windurst 9_1 mission reward
    player:addTitle(xi.title.STAR_ORDAINED_WARRIOR)       -- Windurst 5_2 (in-mission)
    player:addTitle(xi.title.HERO_ON_BEHALF_OF_WINDURST)  -- Windurst 6_2 (in-mission)
    player:addTitle(xi.title.VICTOR_OF_THE_BALGA_CONTEST) -- Windurst 6_2 (in-mission)
    player:addTitle(xi.title.FUGITIVE_MINISTER_BOUNTY_HUNTER) -- Windurst 8_1 (in-mission)
    player:addTitle(xi.title.VESTAL_CHAMBERLAIN)          -- Windurst 9_2 mission reward
end

local function setupZilartMissions(player)
    -- Set Zilart mission progress to The Gate of the Gods (M13)
    -- completeMission() requires the mission to be active first (addMission sets it current)
    -- Rewards not handled by completeMission() directly; key items and titles granted manually below
    local zilartLog = xi.mission.log_id.ZILART
    player:addMission(zilartLog, xi.mission.id.zilart.THE_NEW_FRONTIER)
    player:completeMission(zilartLog, xi.mission.id.zilart.THE_NEW_FRONTIER)
    player:addMission(zilartLog, xi.mission.id.zilart.WELCOME_TNORG)
    player:completeMission(zilartLog, xi.mission.id.zilart.WELCOME_TNORG)
    player:addMission(zilartLog, xi.mission.id.zilart.KAZHAMS_CHIEFTAINESS)
    player:completeMission(zilartLog, xi.mission.id.zilart.KAZHAMS_CHIEFTAINESS)
    player:addMission(zilartLog, xi.mission.id.zilart.THE_TEMPLE_OF_UGGALEPIH)
    player:completeMission(zilartLog, xi.mission.id.zilart.THE_TEMPLE_OF_UGGALEPIH)
    player:addMission(zilartLog, xi.mission.id.zilart.HEADSTONE_PILGRIMAGE)
    player:completeMission(zilartLog, xi.mission.id.zilart.HEADSTONE_PILGRIMAGE)
    player:addMission(zilartLog, xi.mission.id.zilart.THROUGH_THE_QUICKSAND_CAVES)
    player:completeMission(zilartLog, xi.mission.id.zilart.THROUGH_THE_QUICKSAND_CAVES)
    player:addMission(zilartLog, xi.mission.id.zilart.THE_CHAMBER_OF_ORACLES)
    player:completeMission(zilartLog, xi.mission.id.zilart.THE_CHAMBER_OF_ORACLES)
    player:addMission(zilartLog, xi.mission.id.zilart.RETURN_TO_DELKFUTTS_TOWER)
    player:completeMission(zilartLog, xi.mission.id.zilart.RETURN_TO_DELKFUTTS_TOWER)
    player:addMission(zilartLog, xi.mission.id.zilart.ROMAEVE)
    player:completeMission(zilartLog, xi.mission.id.zilart.ROMAEVE)
    player:addMission(zilartLog, xi.mission.id.zilart.THE_TEMPLE_OF_DESOLATION)
    player:completeMission(zilartLog, xi.mission.id.zilart.THE_TEMPLE_OF_DESOLATION)
    player:addMission(zilartLog, xi.mission.id.zilart.THE_HALL_OF_THE_GODS)
    player:completeMission(zilartLog, xi.mission.id.zilart.THE_HALL_OF_THE_GODS)
    player:addMission(zilartLog, xi.mission.id.zilart.THE_MITHRA_AND_THE_CRYSTAL)
    player:completeMission(zilartLog, xi.mission.id.zilart.THE_MITHRA_AND_THE_CRYSTAL)
    player:addMission(zilartLog, xi.mission.id.zilart.THE_GATE_OF_THE_GODS)

    -- Zilart mission reward key items (permanent keeps; consumables excluded)
    -- DARK_FRAGMENT (M4) and all 7 headstone fragments (M5) are consumed at pedestals in M6 - excluded
    -- SACRIFICIAL_CHAMBER_KEY (M3) is consumed entering the M4 battlefield - excluded
    player:addKeyItem(xi.ki.MAP_OF_NORG)           -- M1 reward
    player:addKeyItem(xi.ki.PRISMATIC_FRAGMENT)    -- M7 reward; permanent, used only for NPC dialogue
    player:addKeyItem(xi.ki.CERULEAN_CRYSTAL)      -- M12 in-mission; permanent, never deleted

    -- Zilart mission reward titles
    player:addTitle(xi.title.BEARER_OF_THE_WISEWOMANS_HOPE)  -- M4
    player:addTitle(xi.title.BEARER_OF_THE_EIGHT_PRAYERS)    -- M5
    player:addTitle(xi.title.LIGHTWEAVER)                    -- M7
    player:addTitle(xi.title.SEALER_OF_THE_PORTAL_OF_THE_GODS) -- M10
end

local function setupCopMissions(player)
    -- Set CoP mission progress to Dawn (8-4, ready to start)
    -- CoP uses current > missionId for hasCompletedMission, so setting current = DAWN implies all prior missions complete
    local copLog = xi.mission.log_id.COP
    player:addMission(copLog, xi.mission.id.cop.DAWN)

    -- CoP in-mission key items (all permanent, none consumed by this point)
    player:addKeyItem(xi.ki.LIGHT_OF_HOLLA)                -- M1-2/1-3 Promyvion-Holla
    player:addKeyItem(xi.ki.LIGHT_OF_DEM)                  -- M1-2/1-3 Promyvion-Dem
    player:addKeyItem(xi.ki.LIGHT_OF_MEA)                  -- M1-2/1-3 Promyvion-Mea
    player:addKeyItem(xi.ki.LIGHT_OF_VAHZL)                -- M5-1 Promyvion-Vahzl
    player:addKeyItem(xi.ki.LIGHT_OF_ALTAIEU)              -- M7-5 The Warriors Path
    player:addKeyItem(xi.ki.PSOXJA_PASS)                   -- M3-5 Darkness Named
    player:addKeyItem(xi.ki.RELIQUIARIUM_KEY)              -- M4-3 The Secrets of Worship
    player:addKeyItem(xi.ki.VESSEL_OF_LIGHT)               -- M7-4 Calm Before the Storm
    player:addKeyItem(xi.ki.LETTERS_FROM_ULMIA_AND_PRISHE) -- M7-4 Calm Before the Storm
    player:addKeyItem(xi.ki.BRAND_OF_DAWN)                 -- M8-3 When Angels Fall
    player:addKeyItem(xi.ki.BRAND_OF_TWILIGHT)             -- M8-3 When Angels Fall

    -- CoP in-mission physical items
    player:addItem(xi.item.DUCAL_GUARDS_RING) -- M7-1 Chains and Bonds
    player:addItem(xi.item.TAVNAZIAN_RING)    -- M8-1 Garden of Antiquity

    -- CoP mission reward titles
    player:addTitle(xi.title.ANCIENT_FLAME_FOLLOWER) -- M1-3 The Mothercrystals
    player:addTitle(xi.title.DEAD_BODY)              -- M2-1 An Invitation West
    player:addTitle(xi.title.NAGMOLADAS_UNDERLING)   -- M4-2 The Savage
    player:addTitle(xi.title.THE_LOST_ONE)           -- M4-4 Slanderous Utterings
    player:addTitle(xi.title.TREADER_OF_AN_ICY_PAST) -- M5-3 Three Paths

    -- M5-3 Three Paths: one path must be chosen; defaulting to Tenzen (has most associated items)
    -- Alternatives: xi.title.COMPANION_OF_LOUVERANCE (no extra KIs) or xi.title.ULMIAS_SOULMATE (no extra KIs)
    player:addTitle(xi.title.TENZENS_ALLY)
    player:addKeyItem(xi.ki.ENVELOPE_FROM_MONBERAUX)
    player:addKeyItem(xi.ki.DELKFUTT_RECOGNITION_DEVICE)

    player:addTitle(xi.title.ESHANTARLS_COMRADE_IN_ARMS) -- M7-2 Flames in the Darkness
    player:addTitle(xi.title.PRISHES_BUDDY)              -- M7-3 Fire in the Eyes of Men
    player:addTitle(xi.title.SEEKER_OF_THE_LIGHT)        -- M7-5 The Warriors Path

    -- CoP in-mission titles (given mid-mission, not at completion)
    player:addTitle(xi.title.TRANSIENT_DREAMER)      -- M3-5 Darkness Named
    player:addTitle(xi.title.WARRIOR_OF_THE_CRYSTAL) -- M8-3 When Angels Fall
end

local function setupTrustSpells(player)
    local addSpellConfig = { silentLog = true, saveToDB = true, sendUpdate = false, }
    player:addSpell(xi.magic.spell.TRION, addSpellConfig)
    player:addSpell(xi.magic.spell.AYAME, addSpellConfig)
    player:addSpell(xi.magic.spell.GESSHO, addSpellConfig)
    player:addSpell(xi.magic.spell.AJIDO_MARUJIDO, addSpellConfig)
    player:addSpell(xi.magic.spell.KORU_MORU, addSpellConfig)
    player:addSpell(xi.magic.spell.KUPIPI, addSpellConfig)
    player:addSpell(xi.magic.spell.SHANTOTTO, addSpellConfig)
    player:addSpell(xi.magic.spell.JOACHIM, addSpellConfig)
    player:addSpell(xi.magic.spell.ULMIA, addSpellConfig)
    player:addSpell(xi.magic.spell.CHERUKIKI, addSpellConfig)
    player:addSpell(xi.magic.spell.KARAHA_BARUHA, addSpellConfig)
    player:addSpell(xi.magic.spell.KUKKI_CHEBUKKI, addSpellConfig)
    player:addSpell(xi.magic.spell.KAYEEL_PAYEEL, addSpellConfig)
    player:addSpell(xi.magic.spell.ROBEL_AKBEL, addSpellConfig)
    player:addSpell(xi.magic.spell.CURILLA, addSpellConfig)
    player:addSpell(xi.magic.spell.LION, addSpellConfig)
    player:addSpell(xi.magic.spell.PRISHE, addSpellConfig)
    player:addSpell(xi.magic.spell.IROHA, addSpellConfig)
    player:addSpell(xi.magic.spell.EXCENMILLE, addSpellConfig)
    player:addSpell(xi.magic.spell.RAINEMARD, addSpellConfig)
end

m:addOverride('xi.player.charCreate', function(player)
    print('char_create start')
    super(player)

    -- Gate ONLY the mission-progress headstart behind xi.settings.singleplayer.NEW_CHAR_MISSION_HEADSTART.
    -- Defaults to true to preserve the existing free-grant behavior. Flip to false in
    -- settings/singleplayer.lua for a "play from M1" playthrough — fresh chars then start at rank 1
    -- with no nation/RoZ/CoP progress, but still get trusts, teleports, rings, and KIs below.
    local missionHeadstart = xi.settings.singleplayer and xi.settings.singleplayer.NEW_CHAR_MISSION_HEADSTART
    if missionHeadstart == nil then missionHeadstart = true end

    if missionHeadstart then
        -- Finish all nation missions (rank 10 each)
        setupNationMissions(player)
        -- Start at Divine Might (RoZ M12 complete, M13 active)
        setupZilartMissions(player)
        -- Start at Dawn (CoP final mission)
        setupCopMissions(player)
    else
        print('char_create: NEW_CHAR_MISSION_HEADSTART = false; skipping mission headstart (trusts/teleports/KIs still granted below)')
    end

    -- Add Satchel
    player:changeContainerSize(xi.inv.MOGSATCHEL, xi.settings.main.START_INVENTORY)

     -- Utility rings
    player:addItem(xi.item.WARP_RING)
    player:addItem(28586) -- Craftmaster's ring

    -- Nation rings
    player:addItem(xi.item.SAN_DORIAN_RING)
    player:addItem(xi.item.BASTOKAN_RING)
    player:addItem(xi.item.WINDURSTIAN_RING)

    -- Each headstart bucket has its own bool. All default true (current behavior).
    -- Resolve once with defensive defaults so an old settings file without these
    -- entries still gets the headstart.
    local function setting(name, default)
        if xi.settings.singleplayer == nil then return default end
        local v = xi.settings.singleplayer[name]
        if v == nil then return default end
        return v
    end
    local trustsHeadstart   = setting('NEW_CHAR_TRUSTS_HEADSTART',   true)
    local teleportHeadstart = setting('NEW_CHAR_TELEPORT_HEADSTART', true)
    local lbHeadstart       = setting('NEW_CHAR_LB_HEADSTART',       true)

    -- Add trust spells (20 trusts)
    if trustsHeadstart then
        setupTrustSpells(player)
    else
        print('char_create: NEW_CHAR_TRUSTS_HEADSTART = false; skipping trust-spell headstart')
    end

    -- Homepoint + survival teleports AND gate-crystal KIs (gates the crystals
    -- and the home/survival points together — they're a single QoL bundle).
    if teleportHeadstart then
        for i = 0, 31 do
            for j = 0, 3 do
                player:addTeleport(xi.teleport.type.HOMEPOINT, i, j)
            end
        end
        for i = 0, 31 do
            for j = 0, 3 do
                player:addTeleport(xi.teleport.type.SURVIVAL, i, j)
            end
        end
        player:addKeyItem(xi.ki.HOLLA_GATE_CRYSTAL)
        player:addKeyItem(xi.ki.DEM_GATE_CRYSTAL)
        player:addKeyItem(xi.ki.MEA_GATE_CRYSTAL)
        player:addKeyItem(xi.ki.VAHZL_GATE_CRYSTAL)
        player:addKeyItem(xi.ki.YHOATOR_GATE_CRYSTAL)
        player:addKeyItem(xi.ki.ALTEPA_GATE_CRYSTAL)
    else
        print('char_create: NEW_CHAR_TELEPORT_HEADSTART = false; skipping teleport + gate-crystal headstart')
    end

    -- Limit-Break fetch KIs (let user opt into doing the LB chain naturally)
    if lbHeadstart then
        player:addKeyItem(xi.ki.ORCISH_CREST)
        player:addKeyItem(xi.ki.QUADAV_CREST)
        player:addKeyItem(xi.ki.YAGUDO_CREST)
        player:addKeyItem(xi.ki.SMILING_STONE)
        player:addKeyItem(xi.ki.SCOWLING_STONE)
        player:addKeyItem(xi.ki.SOMBER_STONE)
        player:addKeyItem(xi.ki.SPIRITED_STONE)
    else
        print('char_create: NEW_CHAR_LB_HEADSTART = false; skipping LB fetch-KI headstart')
    end
end)

return m
