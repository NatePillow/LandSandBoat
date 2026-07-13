-----------------------------------
-- All Padfoot instances drop the high-value loot (ignore realPadfoot)
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('padfoot_always_drops')

m:addOverride('xi.server.onServerStart', function()
    super()

    local entity = require('scripts/zones/Lufaise_Meadows/mobs/Padfoot')
    entity.onMobInitialize = function(mob)
        xi.mob.updateNMSpawnPoint(mob)

        mob:addImmunity(xi.immunity.DARK_SLEEP)
        mob:addImmunity(xi.immunity.LIGHT_SLEEP)
        mob:addImmunity(xi.immunity.PLAGUE)
        mob:addImmunity(xi.immunity.SILENCE)
        mob:addImmunity(xi.immunity.TERROR)

        mob:addListener('ITEM_DROPS', 'ITEM_DROPS_PADFOOT', function(mobArg, loot)
            loot:addGroup(xi.drop_rate.GUARANTEED,
                {
                    { item = xi.item.ASSAILANTS_RING, weight = 750 },
                    { item = xi.item.ASTRAL_EARRING,  weight = 250 },
                })
            loot:addGroup(xi.drop_rate.GUARANTEED,
                {
                    { item = xi.item.ASSAILANTS_RING, weight = 750 },
                    { item = xi.item.ASTRAL_EARRING,  weight = 250 },
                })
        end)
    end
end)

return m
