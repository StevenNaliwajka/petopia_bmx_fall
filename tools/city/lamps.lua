-- Write the city's street lamp heads for the map compiler:
--   lua5.1 tools/city/lamps.lua > mapsrc/city_lamps.txt
-- mapsrc/build_vmf.py puts a baked `light` at each one, so the lamps really
-- light the ramps under them (the Lua side only lights models and the floor
-- overlay). tests/test_lighting.lua fails if this file and the city drift.
SERVER, CLIENT = false, true
bit = { bor = function(...) return 0 end }
game = { GetMap = function() return "petopia_bmx_fall" end }
local root = (arg[0]:match("^(.*)/tools/city/") or ".") .. "/lua/"
dofile(root .. "petopia_bmx_fall/sh_city.lua")
dofile(root .. "petopia_bmx_fall/sh_city_maps.lua")
local L = BMX.City.Build(BMX.City.Maps.petopia_bmx_fall)
io.write("# x y z of every street lamp head (tools/city/lamps.lua; do not edit)\n")
for _, l in ipairs(L.lamps) do
    io.write(string.format("%d %d %d\n", math.floor(l.head[1] + 0.5), math.floor(l.head[2] + 0.5), math.floor(l.head[3] + 0.5)))
end
