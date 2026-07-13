-----------------------------------
-- All treasure chest/coffer spawn points active simultaneously.
-- Each location respawns at the same position after 3 minutes.
-- Extra NPCs are created dynamically at runtime; no DB entries required.
-----------------------------------
require('modules/module_utils')
require('scripts/globals/treasure')
-----------------------------------
local m = Module:new('treasure_all_spawn_points')

-- Allow the treasure system to recognise dynamically-created entities.
xi.treasure.npcTable['DE_Treasure_Chest' ] = xi.treasure.type.CHEST
xi.treasure.npcTable['DE_Treasure_Coffer'] = xi.treasure.type.COFFER

local CHEST_LOOK  = '0x0000C00300000000000000000000000000000000'
local COFFER_LOOK = '0x0000C10300000000000000000000000000000000'

local function onTrade(player, npc, trade)
    xi.treasure.onTrade(player, npc, trade, 0, 0)
end

local function onTrigger(player, npc)
    xi.treasure.onTrigger(player, npc)
end

local function spawnExtras(zone, zoneId, tType, look)
    local positions = xi.treasure.posTable[zoneId] and xi.treasure.posTable[zoneId][tType]
    if not positions then return end

    local name = tType == xi.treasure.type.CHEST and 'Treasure_Chest' or 'Treasure_Coffer'

    for i = 2, #positions do
        local pos = positions[i]
        zone:insertDynamicEntity({
            name        = name,
            packetName  = name == 'Treasure_Chest' and 'Treasure Chest' or 'Treasure Coffer',
            x           = pos[1],
            y           = pos[2],
            z           = pos[3],
            rotation    = pos[4],
            look        = look,
            entityFlags = 3,
            namevis     = 0,
            widescan    = 0,
            onTrade     = onTrade,
            onTrigger   = onTrigger,
        })
    end
end

m:addOverride('xi.treasure.initZone', function(zone)
    local zoneId = zone:getID()
    local ID     = zones[zoneId]

    if ID.npc.TREASURE_CHEST then
        local npc = GetNPCByID(ID.npc.TREASURE_CHEST)
        if npc then
            local pos = xi.treasure.posTable[zoneId][xi.treasure.type.CHEST][1]
            npc:setStatus(xi.status.NORMAL)
            npc:setPos(pos[1], pos[2], pos[3], pos[4])
        end
        spawnExtras(zone, zoneId, xi.treasure.type.CHEST, CHEST_LOOK)
    end

    if ID.npc.TREASURE_COFFER then
        local npc = GetNPCByID(ID.npc.TREASURE_COFFER)
        if npc then
            local pos = xi.treasure.posTable[zoneId][xi.treasure.type.COFFER][1]
            npc:setStatus(xi.status.NORMAL)
            npc:setPos(pos[1], pos[2], pos[3], pos[4])
        end
        spawnExtras(zone, zoneId, xi.treasure.type.COFFER, COFFER_LOOK)
    end
end)

-- Respawn each chest/coffer at its own fixed position after 3 minutes.
m:addOverride('xi.treasure.moveTreasure', function(npc, _)
    local x = npc:getXPos()
    local y = npc:getYPos()
    local z = npc:getZPos()
    local r = npc:getRotPos()

    npc:setLocalVar('opened', 1)

    npc:queue(5000, function(npcEntity)
        npcEntity:entityAnimationPacket(xi.animationString.STATUS_DISAPPEAR)
        npcEntity:setLocalVar('opened', 0)
    end)

    npc:queue(7000, function(npcEntity)
        npcEntity:hideNPC(180)
    end)

    npc:queue(10000, function(npcEntity)
        npcEntity:setPos(x, y, z, r)
        npcEntity:entityAnimationPacket(xi.animationString.STATUS_VISIBLE)
        npcEntity:setLocalVar('traded', 0)
    end)
end)

return m
