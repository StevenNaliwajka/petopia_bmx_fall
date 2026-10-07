--[[--------------------------------------------------------------------------
    autorun/petopia_bmx_fall.lua

    The petopia_bmx_fall map's Lua: the city around the park (buildings,
    viaducts and trains, billboards, greenery) and its late-autumn mood. The
    BSP (maps/petopia_bmx_fall.bsp) is the park; this is everything around it.

    It is part of the map, not of the BMX vehicle addon or the BMX (Mode)
    gamemode, and it needs neither: the city is plain Lua under BMX.City (the
    family's namespace, and the bmx_city_* convar names players already have),
    and it only builds on the maps sh_city_maps.lua lists. When the BMX addon
    is installed its settings rows show up in Options > BMX too.

    Load order, as the old lines in the addon's loader had it:
        sh_city        the layout builder (and the bmx_city convar)
        sh_city_maps   which maps have a city
        sh_settings    the rows in the addon's settings list, if it is there
        sv_city        the colliders (bmx_city_solid) and admin commands
        cl_city        draws the city, runs the subway trains
        cl_city_mood   its late-autumn sky, haze, lamp light, falling leaves
----------------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

BMX = BMX or {}
PetopiaBMXFall = PetopiaBMXFall or {}
PetopiaBMXFall.Version = "1.0.0"

local SHARED = {
    "petopia_bmx_fall/sh_city.lua",
    "petopia_bmx_fall/sh_city_maps.lua",
    "petopia_bmx_fall/sh_settings.lua",
}
local SERVER_FILES = {
    "petopia_bmx_fall/sv_city.lua",
}
local CLIENT_FILES = {
    "petopia_bmx_fall/cl_city.lua",
    "petopia_bmx_fall/cl_city_mood.lua",
}
PetopiaBMXFall.Files = { shared = SHARED, server = SERVER_FILES, client = CLIENT_FILES }

if SERVER then
    for _, f in ipairs(SHARED) do AddCSLuaFile(f) end
    for _, f in ipairs(CLIENT_FILES) do AddCSLuaFile(f) end
end
for _, f in ipairs(SHARED) do include(f) end
if SERVER then
    for _, f in ipairs(SERVER_FILES) do include(f) end
else
    for _, f in ipairs(CLIENT_FILES) do include(f) end
end

MsgN("[petopia_bmx_fall] ", PetopiaBMXFall.Version, " loaded (", SERVER and "server" or "client", ")")
