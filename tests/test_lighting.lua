--[[--------------------------------------------------------------------------
    The park's light: the BSP's baked lightmaps (maps/petopia_bmx_fall.bsp,
    read luxel by luxel by tests/bsplight.lua), the city's floor overlay and
    building shading (sh_city.lua), and the mood's grade.

    What went wrong once and must not again (2026-10-07):
      - the west eighth of the park sat in near-black shade: a 28-degree sun
        behind a 464-unit wall throws a shadow ~870 units deep, and the only
        light in it was a dim sky fill (_ambient 70). The south-west spine,
        35 units off that wall, was darkest of all.
      - everything else was washed out: a 400 sun blew the sunlit slopes past
        300, the floor overlay's lamp pools clipped to white, the city's walls
        were all 0.62..0.98 bright, and the grade desaturated the frame.

    The grid: 128-unit cells over the play box, each split into the floor,
    the ramps' riding surfaces and their upright sides. A cell's median luxel
    must clear DARK for its layer; its 95th percentile must stay under BLOWN.
----------------------------------------------------------------------------]]

local F = require("lib.fixture")
local BL = require("bsplight")

local here = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")) or "tests"
local ROOT = here .. "/.."
local BOX = { -256, -1792, 3584, 768 }   -- the play box (mapsrc/build_vmf.py)
local FLOOR = 64
local CELL = 128
local MIN_SAMPLES = 8                     -- fewer luxels than this: a sliver, not judged

-- linear luxel luminance, 0..255 scale (see bsplight.lua). Measured before
-- the fix: the west strip's floor 0..25, the SW spine's slopes 25..45 and its
-- sides 10..15; the brightest slopes 315.
local DARK = { floor = 45, ride = 45, side = 18 }
local BLOWN = 240

local bspCache
local function bsp()
    bspCache = bspCache or BL.load(ROOT .. "/maps/petopia_bmx_fall.bsp")
    return bspCache
end

local function cellName(cells, ix, iy)
    return string.format("(%d..%d, %d..%d)", BOX[1] + ix * CELL, BOX[1] + (ix + 1) * CELL,
        BOX[2] + iy * CELL, BOX[2] + (iy + 1) * CELL)
end

T.test("lighting: the BSP has its lightmaps, and they cover the whole park", function()
    local b = bsp()
    T.ok(#b.samples > 20000, "luxels read: " .. #b.samples)
    local cells = BL.grid(b, BOX, CELL, FLOOR)
    local empty = {}
    for ix = 0, cells.nx - 1 do
        for iy = 0, cells.ny - 1 do
            if not next(cells[ix][iy]) then empty[#empty + 1] = cellName(cells, ix, iy) end
        end
    end
    T.eq(#empty, 0, "cells with no lit surface at all: " .. table.concat(empty, " "))
end)

T.test("lighting: no part of the park is left in the dark (every cell, every layer)", function()
    local cells = BL.grid(bsp(), BOX, CELL, FLOOR)
    local dark = {}
    for ix = 0, cells.nx - 1 do
        for iy = 0, cells.ny - 1 do
            for layer, a in pairs(cells[ix][iy]) do
                if a.n >= MIN_SAMPLES and a.median < DARK[layer] then
                    dark[#dark + 1] = string.format("%s %s median %.1f < %d", layer, cellName(cells, ix, iy), a.median, DARK[layer])
                end
            end
        end
    end
    T.eq(#dark, 0, #dark .. " dark cells:\n      " .. table.concat(dark, "\n      ") .. "\n" .. BL.map(cells))
end)

T.test("lighting: nothing is blown out (no cell's brightest 5% past BLOWN)", function()
    local cells = BL.grid(bsp(), BOX, CELL, FLOOR)
    local hot = {}
    for ix = 0, cells.nx - 1 do
        for iy = 0, cells.ny - 1 do
            for layer, a in pairs(cells[ix][iy]) do
                if a.n >= MIN_SAMPLES and a.p95 > BLOWN then
                    hot[#hot + 1] = string.format("%s %s p95 %.1f", layer, cellName(cells, ix, iy), a.p95)
                end
            end
        end
    end
    T.eq(#hot, 0, #hot .. " blown-out cells:\n      " .. table.concat(hot, "\n      "))
end)

T.test("lighting: the low sun still reads -- sunlit slopes well above the shade, not one flat level", function()
    local cells = BL.grid(bsp(), BOX, CELL, FLOOR)
    local list = {}
    for ix = 0, cells.nx - 1 do
        for iy = 0, cells.ny - 1 do
            local a = cells[ix][iy].ride
            if a and a.n >= MIN_SAMPLES then list[#list + 1] = a.median end
        end
    end
    table.sort(list)
    T.ok(#list > 100, "ride cells: " .. #list)
    local lo, hi = list[math.ceil(#list * 0.1)], list[math.ceil(#list * 0.9)]
    T.ok(hi / lo >= 1.8, string.format("sunlit (p90 %.1f) / shade (p10 %.1f) = %.2f, want >= 1.8", hi, lo, hi / lo))
end)

--------------------------------------------------------------------------
-- The map source: the lights the BSP was built from.
--------------------------------------------------------------------------
local function vmfEntities()
    local f = assert(io.open(ROOT .. "/mapsrc/petopia_bmx_fall.vmf", "r"))
    local text = f:read("*a")
    f:close()
    local ents = {}
    for body in text:gmatch("\nentity\n{(.-)\n}") do
        local e = {}
        for k, v in body:gmatch('\t"([^"]+)" "([^"]*)"') do if not e[k] then e[k] = v end end
        e._connections = {}
        for k, v in body:gmatch('\t\t"([^"]+)" "([^"]*)"') do e._connections[#e._connections + 1] = { k, v } end
        ents[#ents + 1] = e
    end
    return ents
end

local function nums(s)
    local t = {}
    for n in s:gmatch("%-?[%d%.]+") do t[#t + 1] = tonumber(n) end
    return t
end

T.test("lighting: the sun is moderate and the sky fill strong enough for the shade", function()
    local sun
    for _, e in ipairs(vmfEntities()) do if e.classname == "light_environment" then sun = e end end
    T.ok(sun, "a light_environment")
    local L, A = nums(sun._light), nums(sun._ambient)
    T.between(L[4], 150, 300, "sun brightness (400 blew the slopes out)")
    T.between(A[4], 120, 260, "sky fill brightness (70 left the shade black)")
    T.ok(A[3] >= A[1], "the shade is cool against the warm sun: ambient " .. sun._ambient)
    T.ok(L[1] > L[3], "the sun is warm: " .. sun._light)
end)

T.test("lighting: HDR auto-exposure is clamped, so it can't lift the frame into a wash", function()
    local tm, auto
    for _, e in ipairs(vmfEntities()) do
        if e.classname == "env_tonemap_controller" then tm = e end
        if e.classname == "logic_auto" then auto = e end
    end
    T.ok(tm and tm.targetname, "an env_tonemap_controller with a name")
    T.ok(auto, "a logic_auto to set it up")
    local set = {}
    for _, c in ipairs(auto._connections) do
        local target, input, value = c[2]:match("^([^,]+),([^,]+),([^,]*)")
        if target == tm.targetname then set[input] = tonumber(value) end
    end
    T.ok(set.SetAutoExposureMax and set.SetAutoExposureMax <= 1.25, "max exposure: " .. tostring(set.SetAutoExposureMax))
    T.ok(set.SetAutoExposureMin and set.SetAutoExposureMin >= 0.4, "min exposure: " .. tostring(set.SetAutoExposureMin))
    T.ok(set.SetBloomScale and set.SetBloomScale <= 0.3, "bloom: " .. tostring(set.SetBloomScale))
end)

T.test("lighting: every street lamp the city stands is a baked light in the map, and no others drift", function()
    local sv = F.server()
    local City = sv.env.BMX.City
    local L = City.Build(City.Maps.petopia_bmx_fall)
    -- mapsrc/city_lamps.txt is what build_vmf.py reads (tools/city/lamps.lua)
    local f = assert(io.open(ROOT .. "/mapsrc/city_lamps.txt", "r"))
    local file = {}
    for line in f:lines() do
        if not line:match("^#") and line:match("%d") then file[#file + 1] = nums(line) end
    end
    f:close()
    T.eq(#file, #L.lamps, "lamps in mapsrc/city_lamps.txt vs the city (rerun tools/city/lamps.lua)")
    for i, l in ipairs(L.lamps) do
        local p = file[i]
        T.ok(p and math.abs(p[1] - l.head[1]) < 1 and math.abs(p[2] - l.head[2]) < 1 and math.abs(p[3] - l.head[3]) < 1,
            "lamp " .. i .. " where the city has it")
    end
    local lights = {}
    for _, e in ipairs(vmfEntities()) do
        if e.classname == "light" then lights[#lights + 1] = nums(e.origin) end
    end
    for i, l in ipairs(L.lamps) do
        local found = false
        for _, o in ipairs(lights) do
            if math.abs(o[1] - l.head[1]) < 2 and math.abs(o[2] - l.head[2]) < 2 and math.abs(o[3] - l.head[3]) < 64 then found = true end
        end
        T.ok(found, "a light under lamp head " .. i)
    end
end)

--------------------------------------------------------------------------
-- The city's own light (it is unlit geometry: sh_city.lua bakes it).
--------------------------------------------------------------------------
local function layout()
    local sv = F.server()
    local City = sv.env.BMX.City
    local def = City.Maps.petopia_bmx_fall
    return City.Build(def), def
end

T.test("lighting: the floor overlay is never clipped white nor dark, over a grid of the whole park", function()
    local L, def = layout()
    local p, fl = def.park, def.floor
    local G = 128
    local nx, ny = math.ceil((p[4] - p[1]) / G), math.ceil((p[5] - p[2]) / G)
    local cells, lo, hi = {}, math.huge, 0
    for _, key in ipairs({ "slab", "pave_brick", "pave_cobble", "kerbline" }) do
        for _, q in ipairs(L.faces[key] or {}) do
            for c = 0, 3 do
                local x, y = q[c * 3 + 1], q[c * 3 + 2]
                local r, g, b = q[19 + c * 3], q[20 + c * 3], q[21 + c * 3]
                local ix = math.min(nx - 1, math.floor((x - p[1]) / G))
                local iy = math.min(ny - 1, math.floor((y - p[2]) / G))
                cells[ix * 1000 + iy] = true
                T.ok(math.max(r, g, b) <= 1.0, string.format("vertex at (%d, %d) clips: %.2f %.2f %.2f", x, y, r, g, b))
                local lum = 0.299 * r + 0.587 * g + 0.114 * b
                lo, hi = math.min(lo, lum), math.max(hi, lum)
            end
        end
    end
    local n = 0
    for _ in pairs(cells) do n = n + 1 end
    T.eq(n, nx * ny, "every cell of the park has lit floor")
    T.ok(lo >= 0.4, "darkest floor vertex: " .. lo)
    T.ok(hi <= 0.95, "brightest floor vertex: " .. hi)
    -- under a lamp it is clearly brighter than out in the open
    T.ok(hi - lo >= 0.2, string.format("lamp pools stand out: %.2f .. %.2f", lo, hi))
end)

T.test("lighting: the floor's west strip lies in the wall's shadow, a shade darker, never black", function()
    local L, def = layout()
    local p, fl = def.park, def.floor
    local function lum(x, y)
        local best
        for _, q in ipairs(L.faces.slab or {}) do
            for c = 0, 3 do
                if math.abs(q[c * 3 + 1] - x) < 1 and math.abs(q[c * 3 + 2] - y) < 1 then
                    best = 0.299 * q[19 + c * 3] + 0.587 * q[20 + c * 3] + 0.114 * q[21 + c * 3]
                end
            end
        end
        return best
    end
    -- open floor mid-park vs the floor by the west wall, both far from lamps
    local open, shade = lum(1600, -1152), lum(256, -1152)
    T.ok(open and shade, "floor vertices found")
    T.ok(shade < open - 0.03, string.format("shaded %.3f vs open %.3f", shade, open))
    T.ok(shade >= open * 0.8, string.format("but not dark: shaded %.3f vs open %.3f", shade, open))
end)

T.test("lighting: the city's walls show the low sun -- lit faces well above those turned away, none glaring", function()
    local L, def = layout()
    local mood = def.mood.light
    local lit, shade = 0, math.huge
    for key, list in pairs(L.faces) do
        for _, q in ipairs(list) do
            if not q[19] and (q[18] or ""):match("^front") then
                -- a wall: its normal from the quad's edges
                local ax, ay, az = q[4] - q[1], q[5] - q[2], q[6] - q[3]
                local bx, by, bz = q[10] - q[1], q[11] - q[2], q[12] - q[3]
                local nz = ax * by - ay * bx
                local len = math.sqrt((ay * bz - az * by) ^ 2 + (az * bx - ax * bz) ^ 2 + nz ^ 2)
                if len > 0 and math.abs(nz / len) < 0.3 then
                    lit, shade = math.max(lit, q[17]), math.min(shade, q[17])
                end
            end
        end
    end
    T.ok(lit / shade >= 1.5, string.format("sunlit wall %.2f / wall turned away %.2f", lit, shade))
    T.ok(lit * math.max(mood[1], mood[2], mood[3]) <= 0.95, "the brightest wall, coloured by the hour: " .. lit * mood[1])
end)

T.test("lighting: the grade adds contrast and keeps the colour (no lift, no wash)", function()
    local _, def = layout()
    local g = def.mood.grade
    T.ok((g.contrast or 1) >= 1.1, "contrast " .. tostring(g.contrast))
    T.ok((g.brightness or 0) <= 0, "brightness " .. tostring(g.brightness))
    T.ok((g.colour or 1) >= 1.0, "saturation " .. tostring(g.colour))
    local f = def.mood.fog
    T.ok(f.start >= 2500, "the haze stays off the park: starts at " .. f.start)
end)
