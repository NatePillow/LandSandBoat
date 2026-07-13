-----------------------------------
-- Reduce Chaosbringer kill requirements for Blade of Darkness/Death quests
-----------------------------------
require('modules/module_utils')
require('scripts/globals/npc_util')
-----------------------------------
local m = Module:new('chaosbringer_reduced_kills')

m:addOverride('xi.server.onServerStart', function()
    super()

    -- Blade of Darkness: lower onZoneIn kill threshold from 100 to 1
    xi.module.modifyInteractionEntry('scripts/quests/bastok/Blade_of_Darkness', function(quest)
        for _, section in ipairs(quest.sections) do
            if section[xi.zone.BEADEAUX] and section[xi.zone.BEADEAUX].onZoneIn then
                section[xi.zone.BEADEAUX].onZoneIn = function(player, prevZone)
                    if
                        prevZone == xi.zone.PASHHOW_MARSHLANDS and
                        player:getCharVar('ChaosbringerKills') >= 1
                    then
                        return 121
                    end
                end
                break
            end
        end
    end)

    -- Blade of Death: lower onTrade kill threshold from 200 to 2
    xi.module.modifyInteractionEntry('scripts/quests/bastok/Blade_of_Death', function(quest)
        for _, section in ipairs(quest.sections) do
            if
                section[xi.zone.GUSGEN_MINES] and
                section[xi.zone.GUSGEN_MINES]['qm2'] and
                section[xi.zone.GUSGEN_MINES]['qm2'].onTrade
            then
                section[xi.zone.GUSGEN_MINES]['qm2'].onTrade = function(player, npc, trade)
                    if
                        npcUtil.tradeHasExactly(trade, xi.item.CHAOSBRINGER) and
                        player:getCharVar('ChaosbringerKills') >= 2
                    then
                        return quest:progressEvent(10)
                    end
                end
                break
            end
        end
    end)
end)

return m
