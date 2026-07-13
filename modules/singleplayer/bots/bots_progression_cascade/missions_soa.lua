-----------------------------------
-- Seekers of Adoulin mission recipes for the cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
--
-- Post-ToAU content — KEEP-EXISTING ONLY. Only SoA 1-5 (Pioneer Registration)
-- is covered because the PIONEERS_BADGE KI it grants is the gate for entry
-- to Adoulin content that intersects with 75-era-relevant Coalition
-- assignments. No other SoA missions should be added without expanding
-- the cascade scope (see ../README.md § Scope).
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_missions_soa')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local mission = cascade.mission

do
    local sm = xi.mission.log_id.SOA
    local mi = xi.mission.id.soa

    cascade.recipes.soa = {
        mission(sm, mi.PIONEER_REGISTRATION,  'scripts/missions/soa/1_5_Pioneer_Registration',
            function(p) npcUtil.giveKeyItem(p, xi.ki.PIONEERS_BADGE) end),
    }
end

return m
