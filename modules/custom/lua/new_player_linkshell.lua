-----------------------------------
-- Set if you want new players to get a linkshell
-----------------------------------
require('modules/module_utils')
require('scripts/globals/player')
-----------------------------------
local m = Module:new('new_player_linkshell')

m:addOverride('xi.player.charCreate', function(player)
    local lsName = 'GlobalLinkshell' -- Name of linkshell
    -- equip=false on purpose: base addLinkpearl's equip=true branch frees the
    -- just-bound linkpearl via LoadInventory (lua_baseentity.cpp:5179), leaving
    -- equipped_[SLOT_LINK2] dangling -> a garbage char_equip row -> crash on the
    -- next login. Adding it UNEQUIPPED skips that path; the player still gets the
    -- pearl in inventory and can equip it. Revert to true once the base bug is
    -- fixed (drop/re-order the LoadInventory in addLinkpearl).
    player:addLinkpearl(lsName, false)
    super(player)
end)

return m
