--[[--------------------------------------------------------------------------
    lua/petopia_bmx_fall/sh_settings.lua

    The city's settings, as rows in the BMX addon's one settings list
    (BMX.Settings: the Options > BMX menu, bmx_reset_client/_server,
    server.json). The convars are created where they always were (sh_city,
    cl_city, cl_city_mood). Without the addon there is no menu to add them to,
    and the convars work on their own.
----------------------------------------------------------------------------]]

local S = BMX and BMX.Settings
if not (S and S.Add and S.AddCategory) then return end

S.AddCategory("client", "world", "Scenery")
S.AddCategory("server", "world", "The park")

local function client(row) row.scope = "client" return S.Add(row) end
local function server(row) row.scope = "server" return S.Add(row) end

client{ name = "bmx_city_draw", kind = "bool", default = true, category = "world",
    label = "Draw the city",
    help = "Show the buildings and skyline around the park. Turn it off if the map runs slowly for you." }
client{ name = "bmx_city_trains", kind = "bool", default = true, category = "world",
    label = "Run the subway trains",
    help = "The trains that pass through the city's viaducts." }
client{ name = "bmx_city_signs", kind = "bool", default = true, category = "world",
    label = "Draw the city's signs",
    help = "Neon and shop signs on the buildings." }
client{ name = "bmx_city_plants", kind = "bool", default = true, category = "world",
    label = "Draw the trees and street lamps",
    help = "The trees in the park and on the roof gardens, and the lamps along the beds." }
client{ name = "bmx_city_mood", kind = "bool", default = true, category = "world",
    label = "Late-autumn sky and lamplight",
    help = "The golden afternoon sky, the haze over the city, the warm colour grade and the lamps' light." }
client{ name = "bmx_city_leaves", kind = "bool", default = true, category = "world",
    label = "Falling leaves",
    help = "Leaves letting go of the trees and drifting down on the wind." }
server{ name = "bmx_city", kind = "bool", default = true, category = "world",
    label = "Build the city",
    help = "Build the city around the park on maps that have one. Takes effect on the next map change." }
