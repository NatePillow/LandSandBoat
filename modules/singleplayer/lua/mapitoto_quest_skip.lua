-----------------------------------
-- Skip the Full Speed Ahead chocobo minigame (jump straight to completion flag)
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('mapitoto_quest_skip')

m:addOverride('xi.server.onServerStart', function()
    super()

    local entity         = require('scripts/zones/Upper_Jeuno/npcs/Mapitoto')
    local originalFinish = entity.onEventFinish

    entity.onEventFinish = function(player, csid, option, npc)
        if (csid == 10223 or csid == 10224) and option == 1 then
            player:addQuest(xi.questLog.JEUNO, xi.quest.id.jeuno.FULL_SPEED_AHEAD)
            player:setCharVar('[QUEST]FullSpeedAhead', 4) -- Skip minigame
        else
            originalFinish(player, csid, option, npc)
        end
    end
end)

return m
