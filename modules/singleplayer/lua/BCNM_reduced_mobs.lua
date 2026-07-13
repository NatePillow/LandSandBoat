-----------------------------------
-- Reduce mob count in selected BCNMs for singleplayer (removes 4 of 7 mobs per group)
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('BCNM_reduced_mobs')

m:addOverride('xi.server.onServerStart', function()
    super()

    -- Balga's Dais: Steamed Sprouts
    local balgasID = zones[xi.zone.BALGAS_DAIS]
    local sprouts  = require('scripts/battlefields/Balgas_Dais/steamed_sprouts')
    sprouts.groups[1].mobIds =
    {
        {
            balgasID.mob.DVOROVOI,      -- Dvorovoi
            --balgasID.mob.DVOROVOI + 1,  -- Domovoi
            --balgasID.mob.DVOROVOI + 2,  -- Domovoi
            balgasID.mob.DVOROVOI + 3,  -- Domovoi
            balgasID.mob.DVOROVOI + 4,  -- Domovoi
            balgasID.mob.DVOROVOI + 5,  -- Domovoi
            --balgasID.mob.DVOROVOI + 6,  -- Domovoi
            --balgasID.mob.DVOROVOI + 7,  -- Domovoi
        },

        {
            balgasID.mob.DVOROVOI + 9,  -- Dvorovoi
            --balgasID.mob.DVOROVOI + 10, -- Domovoi
            --balgasID.mob.DVOROVOI + 11, -- Domovoi
            balgasID.mob.DVOROVOI + 12, -- Domovoi
            balgasID.mob.DVOROVOI + 13, -- Domovoi
            balgasID.mob.DVOROVOI + 14, -- Domovoi
            --balgasID.mob.DVOROVOI + 15, -- Domovoi
            --balgasID.mob.DVOROVOI + 16, -- Domovoi
        },

        {
            balgasID.mob.DVOROVOI + 18, -- Dvorovoi
            --balgasID.mob.DVOROVOI + 19, -- Domovoi
            --balgasID.mob.DVOROVOI + 20, -- Domovoi
            balgasID.mob.DVOROVOI + 21, -- Domovoi
            balgasID.mob.DVOROVOI + 22, -- Domovoi
            balgasID.mob.DVOROVOI + 23, -- Domovoi
            --balgasID.mob.DVOROVOI + 24, -- Domovoi
            --balgasID.mob.DVOROVOI + 25, -- Domovoi
        },
    }

    -- Horlais Peak: Tails of Woe
    local horlaisID = zones[xi.zone.HORLAIS_PEAK]
    local tails     = require('scripts/battlefields/Horlais_Peak/tails_of_woe')
    tails.groups[1].mobIds =
    {
        {
            horlaisID.mob.HELLTAIL_HARRY,
            --horlaisID.mob.HELLTAIL_HARRY + 1,
            --horlaisID.mob.HELLTAIL_HARRY + 2,
            horlaisID.mob.HELLTAIL_HARRY + 3,
            horlaisID.mob.HELLTAIL_HARRY + 4,
            horlaisID.mob.HELLTAIL_HARRY + 5,
            --horlaisID.mob.HELLTAIL_HARRY + 6,
            --horlaisID.mob.HELLTAIL_HARRY + 7,
        },

        {
            horlaisID.mob.HELLTAIL_HARRY + 9,
            --horlaisID.mob.HELLTAIL_HARRY + 10,
            --horlaisID.mob.HELLTAIL_HARRY + 11,
            horlaisID.mob.HELLTAIL_HARRY + 12,
            horlaisID.mob.HELLTAIL_HARRY + 13,
            horlaisID.mob.HELLTAIL_HARRY + 14,
            --horlaisID.mob.HELLTAIL_HARRY + 15,
            --horlaisID.mob.HELLTAIL_HARRY + 16,
        },

        {
            horlaisID.mob.HELLTAIL_HARRY + 18,
            --horlaisID.mob.HELLTAIL_HARRY + 19,
            --horlaisID.mob.HELLTAIL_HARRY + 20,
            horlaisID.mob.HELLTAIL_HARRY + 21,
            horlaisID.mob.HELLTAIL_HARRY + 22,
            horlaisID.mob.HELLTAIL_HARRY + 23,
            --horlaisID.mob.HELLTAIL_HARRY + 24,
            --horlaisID.mob.HELLTAIL_HARRY + 25,
        },
    }
end)

return m
