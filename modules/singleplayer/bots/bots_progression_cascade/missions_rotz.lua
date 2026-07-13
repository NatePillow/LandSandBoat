-----------------------------------
-- Rise of the Zilart mission recipes for the cascade.
-- See ../README.md for mechanism and how-to-add-recipes.
-----------------------------------
require('modules/module_utils')
local m = Module:new('bots_progression_cascade_missions_rotz')

local cascade = xi.singleplayer.bots.bots_progression_cascade
local mission = cascade.mission

do
    local rm = xi.mission.log_id.ZILART
    local mi = xi.mission.id.zilart

    cascade.recipes.rotz = {

        mission(rm, mi.THE_NEW_FRONTIER,            'scripts/missions/rotz/01_The_New_Frontier'),
        mission(rm, mi.WELCOME_TNORG,               'scripts/missions/rotz/02_Welcome_to_Norg'),
        mission(rm, mi.KAZHAMS_CHIEFTAINESS,        'scripts/missions/rotz/03_Kazhams_Chieftainess'),
        mission(rm, mi.THE_TEMPLE_OF_UGGALEPIH,     'scripts/missions/rotz/04_The_Temple_of_Uggalepih'),
        mission(rm, mi.HEADSTONE_PILGRIMAGE,        'scripts/missions/rotz/05_Headstone_Pilgrimage',
            function(p)
                -- 7 elemental fragment KIs, collected across the mission arc.
                -- The last-collected fragment triggers mission:complete; cascade
                -- grants all 7 so headless matches state.
                npcUtil.giveKeyItem(p, xi.ki.LIGHTNING_FRAGMENT)
                npcUtil.giveKeyItem(p, xi.ki.WIND_FRAGMENT)
                npcUtil.giveKeyItem(p, xi.ki.ICE_FRAGMENT)
                npcUtil.giveKeyItem(p, xi.ki.WATER_FRAGMENT)
                npcUtil.giveKeyItem(p, xi.ki.LIGHT_FRAGMENT)
                npcUtil.giveKeyItem(p, xi.ki.EARTH_FRAGMENT)
                npcUtil.giveKeyItem(p, xi.ki.FIRE_FRAGMENT)
            end),
        mission(rm, mi.THROUGH_THE_QUICKSAND_CAVES, 'scripts/missions/rotz/06_Through_the_Quicksand_Caves'),
        mission(rm, mi.THE_CHAMBER_OF_ORACLES,      'scripts/missions/rotz/07_The_Chamber_of_Oracles'),
        mission(rm, mi.RETURN_TO_DELKFUTTS_TOWER,   'scripts/missions/rotz/08_Return_to_Delkfutts_Tower'),
        mission(rm, mi.ROMAEVE,                     'scripts/missions/rotz/09_RoMaeve'),
        mission(rm, mi.THE_TEMPLE_OF_DESOLATION,    'scripts/missions/rotz/10_The_Temple_of_Desolation'),
        mission(rm, mi.THE_HALL_OF_THE_GODS,        'scripts/missions/rotz/11_The_Hall_of_the_Gods'),
        mission(rm, mi.THE_MITHRA_AND_THE_CRYSTAL,  'scripts/missions/rotz/12_The_Mithra_and_the_Crystal'),
        mission(rm, mi.THE_GATE_OF_THE_GODS,        'scripts/missions/rotz/13_The_Gate_of_the_Gods'),
        mission(rm, mi.ARK_ANGELS,                  'scripts/missions/rotz/14_Ark_Angels',
            function(p)
                -- 5 Ark Angel shard KIs. Each Ark Angel BCNM normally drops one;
                -- the Divine Might branch grants all 5 at once. Cascade always
                -- delivers all 5 since they're all needed to progress.
                npcUtil.giveKeyItem(p, xi.ki.SHARD_OF_APATHY)
                npcUtil.giveKeyItem(p, xi.ki.SHARD_OF_ARROGANCE)
                npcUtil.giveKeyItem(p, xi.ki.SHARD_OF_ENVY)
                npcUtil.giveKeyItem(p, xi.ki.SHARD_OF_COWARDICE)
                npcUtil.giveKeyItem(p, xi.ki.SHARD_OF_RAGE)
            end),
        mission(rm, mi.THE_SEALED_SHRINE,           'scripts/missions/rotz/15_The_Sealed_Shrine'),
        mission(rm, mi.THE_CELESTIAL_NEXUS,         'scripts/missions/rotz/16_The_Celestial_Nexus'),
        mission(rm, mi.AWAKENING,                   'scripts/missions/rotz/17_Awakening'),
    }
end

return m
