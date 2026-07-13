-----------------------------------
-- Remove time-of-day and weather despawn restrictions from NMs
-----------------------------------
require('modules/module_utils')
-----------------------------------
local m = Module:new('nullify_mob_spawn_conditions')

-- Replace onMobRoam with a no-op for all NMs whose entire roam handler was a despawn check
local noopRoams =
{
    'xi.zones.Gusgen_Mines.mobs.Asphyxiated_Amsel.onMobRoam',
    'xi.zones.Gusgen_Mines.mobs.Burned_Bergmann.onMobRoam',
    'xi.zones.Gusgen_Mines.mobs.Crushed_Krause.onMobRoam',
    'xi.zones.Gusgen_Mines.mobs.Pulverized_Pfeffer.onMobRoam',
    'xi.zones.Gusgen_Mines.mobs.Smothered_Schmidt.onMobRoam',
    'xi.zones.Gusgen_Mines.mobs.Wounded_Wurfel.onMobRoam',
    'xi.zones.Bostaunieux_Oubliette.mobs.Manes.onMobRoam',
    'xi.zones.Bostaunieux_Oubliette.mobs.Shii.onMobRoam',
    'xi.zones.Rolanberry_Fields.mobs.Black_Triple_Stars.onMobRoam',
    'xi.zones.Inner_Horutoto_Ruins.mobs.Magicked_Bones.onMobRoam',
    'xi.zones.Misareaux_Coast.mobs.Odqan.onMobRoam',
    'xi.zones.Konschtat_Highlands.mobs.Haty.onMobRoam',
    'xi.zones.Konschtat_Highlands.mobs.Bendigeit_Vran.onMobRoam',
    'xi.zones.Sacrarium.mobs.Elel.onMobRoam',
    'xi.zones.Cape_Teriggan.mobs.Kreutzet.onMobRoam',
    'xi.zones.Western_Altepa_Desert.mobs.Dahu.onMobRoam',
    'xi.zones.Yuhtunga_Jungle.mobs.Bayawak.onMobRoam',
    'xi.zones.Attohwa_Chasm.mobs.Citipati.onMobRoam',
}

for _, path in ipairs(noopRoams) do
    m:addOverride(path, function(mob) end)
    local spawnPath = path:gsub('%.onMobRoam$', '.onMobSpawn')
    m:addOverride(spawnPath, function(mob)
        mob:setLocalVar('noAutoDespawn', 1)
    end)
end

-- Dosetsu Tree: despawn check is in onMobDisengage, not onMobRoam
m:addOverride('xi.zones.Qufim_Island.mobs.Dosetsu_Tree.onMobDisengage', function(mob) end)
m:addOverride('xi.zones.Qufim_Island.mobs.Dosetsu_Tree.onMobSpawn', function(mob)
    mob:setLocalVar('noAutoDespawn', 1)
end)

-- King Vinegarroon: preserve the regen logic, skip the weather despawn check
m:addOverride('xi.zones.Western_Altepa_Desert.mobs.King_Vinegarroon.onMobRoam', function(mob)
    local hour = VanadielHour()
    if hour >= 6 and hour <= 20 then
        mob:setMod(xi.mod.REGEN, 150)
    else
        mob:setMod(xi.mod.REGEN, 300)
    end
end)
m:addOverride('xi.zones.Western_Altepa_Desert.mobs.King_Vinegarroon.onMobSpawn', function(mob)
    mob:setLocalVar('noAutoDespawn', 1)
end)

-- Leshonki: preserve the regen logic, skip the time-of-day despawn check
m:addOverride('xi.zones.The_Boyahda_Tree.mobs.Leshonki.onMobRoam', function(mob)
    local hour = VanadielHour()
    if hour >= 6 and hour < 18 then
        mob:setMod(xi.mod.REGEN, 160)
    else
        mob:setMod(xi.mod.REGEN, 0)
    end
end)
m:addOverride('xi.zones.The_Boyahda_Tree.mobs.Leshonki.onMobSpawn', function(mob)
    mob:setLocalVar('noAutoDespawn', 1)
end)

return m
