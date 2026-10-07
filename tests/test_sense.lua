--[[--------------------------------------------------------------------------
    The city has to make sense (sh_city.lua, cl_city.lua; 2026-10-07).

    What did not, and is checked here:
      - the subway trains came out of one building and drove into another:
        every line ended in a portal in a wall. Now a line crosses each wall
        over a low station house standing in a gap in the frontage, runs on
        down an open street past the back row and the skyline, and its trains
        come from, and go to, beyond the last building in the city
      - the ads were posters stuck among the windows two and three floors up.
        Now they are billboards: high on a facade, under its cornice, on a
        catwalk with floodlights, or on a roof on legs
      - the buildings were windows all the way down to the ground. Now the
        street floor is shops: false shop fronts with a fascia and a name, a
        window with what they sell, a door (with a way through the hedge to
        it), pilasters, a string course and, where nothing is in the way, an
        awning
      - the street lamps' glow hung a foot under the lamp heads
----------------------------------------------------------------------------]]

local F = require("lib.fixture")

-- each ramp's measured footprint (tests/test_city.lua has the story)
local RAMPS = {
    { "spiner2", -221, -1785, 155, -1208, 63, 179 },
    { "flatramp", -161, 481, 193, 767, 63, 177 },
    { "quarterpipe3", 187, 475, 807, 774, 63, 237 },
    { "halfpipe7", 324, -1037, 1515, -468, 64, 421 },
    { "flatramp", 559, -1791, 913, -1505, 63, 177 },
    { "funbox2", 572, -259, 1118, 222, 64, 150 },
    { "quarterpipe3", 811, 475, 1431, 774, 64, 237 },
    { "spiner2", 1386, -1703, 1963, -1327, 63, 179 },
    { "funbox2", 1855, -290, 2401, 191, 64, 150 },
    { "flatramp", 2151, -1009, 2437, -655, 63, 177 },
    { "funbox2", 2398, -1776, 2944, -1295, 64, 150 },
    { "spiner2", 2437, -1082, 2812, -505, 63, 179 },
    { "spiner2", 2805, -1082, 3180, -505, 63, 179 },
    { "rail2", 2914, -342, 3230, -330, 63, 139 },
    { "flatramp", 2929, -257, 3215, 97, 63, 177 },
    { "flatramp", 2929, 95, 3215, 449, 63, 177 },
    { "quarterpipe3", 3291, -1687, 3590, -1067, 64, 237 },
}

local function city()
    local sv, world = F.server()
    local cl = F.client(world)
    local City = cl.env.BMX.City
    return City, City.Build(City.Maps.gm_skatepark), cl
end

local function overlap(a, b, margin)
    margin = margin or 0
    return a[1] < b[4] + margin and a[4] > b[1] - margin
       and a[2] < b[5] + margin and a[5] > b[2] - margin
       and a[3] < b[6] + margin and a[6] > b[3] - margin
end

local function lineBox(l, a0, a1, c0, c1, z0, z1)
    if l.axis == "y" then return { l.at + c0, a0, z0, l.at + c1, a1, z1 } end
    return { a0, l.at + c0, z0, a1, l.at + c1, z1 }
end

-- the box a car of model M fills, at train `st`, car i
local function carBox(City, l, st, i, M)
    local x, y, z = City.CarPos(l, st, i, M.lift)
    local floor = z - M.lift
    local hl, hw = M.len / 2, M.w / 2
    if l.axis == "y" then return { x - hw, y - hl, floor, x + hw, y + hl, floor + M.h } end
    return { x - hl, y - hw, floor, x + hl, y + hw, floor + M.h }
end

--------------------------------------------------------------------------
-- Trains
--------------------------------------------------------------------------

T.test("sense: no train ever goes into or comes out of a building, all the way along its line", function()
    local City, L = city()
    local hits = {}
    for _, l in ipairs(L.lines) do
        local samples = 0
        -- every train, every car, every half second of four periods
        for t = 0, l.period * 4, 0.5 do
            for _, st in ipairs(City.TrainsAt(l, t)) do
                for _, M in ipairs(City.TrainModels) do
                    for i = 1, l.cars do
                        local box = carBox(City, l, st, i, M)
                        samples = samples + 1
                        for _, bd in ipairs(L.buildings) do
                            if overlap(box, bd) then
                                hits[#hits + 1] = string.format("%s car %d at t=%.1f inside a %s building", l.name, i, t, tostring(bd.side))
                            end
                        end
                    end
                end
            end
        end
        T.ok(samples > 100, l.name .. " sampled: " .. samples)
    end
    T.eq(#hits, 0, "cars in buildings: " .. table.concat(hits, "; ", 1, math.min(#hits, 5)))
end)

T.test("sense: the check has teeth (a train run into the old portal building is caught)", function()
    local City, L = city()
    local l = L.lines[1]
    -- the old layout: a building standing across the line on its north wall
    local wall = { l.at - 400, l.to - 4, 64, l.at + 400, l.to + 600, 1728 }
    local st = { head = (l.to - l.from) + 300, dir = 1, train = City.TrainLength(l.cars) }
    T.ok(overlap(carBox(City, l, st, 1, City.TrainModels[1]), wall), "a nose 300 past the wall is inside it")
end)

T.test("sense: the viaducts never pass through a building either, out to their very ends", function()
    local City, L = city()
    local V = City.Viaduct
    for _, l in ipairs(L.lines) do
        local hw = V.width / 2
        local structure = lineBox(l, l.from - l.extent, l.to + l.extent, -hw, hw, l.deck - V.slab - V.girder, l.deck + V.truss + 16)
        for _, bd in ipairs(L.buildings) do
            T.ok(not overlap(structure, bd), string.format("%s through a %s building at %d,%d", l.name, tostring(bd.side), bd[1], bd[2]))
        end
    end
end)

T.test("sense: a train appears and disappears beyond the last building of the city", function()
    local City, L = city()
    for _, l in ipairs(L.lines) do
        local ax = l.axis == "y" and 2 or 1
        -- how far the city reaches out past each wall the line crosses
        local lo, hi = l.from, l.to
        for _, bd in ipairs(L.buildings) do
            lo = math.min(lo, bd[ax])
            hi = math.max(hi, bd[ax + 3])
        end
        -- the nose sets off `runout` out (and the whole train behind it)
        T.ok(l.from - l.runout < lo - 256, l.name .. " sets off past the city's " .. (ax == 2 and "south" or "west") .. " edge (" .. lo .. ")")
        T.ok(l.to + l.runout > hi + 256, l.name .. " runs on past the city's " .. (ax == 2 and "north" or "east") .. " edge (" .. hi .. ")")
    end
end)

T.test("sense: where a line crosses a wall it passes over a low station house, in a gap in the frontage", function()
    local City, L = city()
    local V = City.Viaduct
    local def = City.Maps.gm_skatepark
    local n = 0
    for _, l in ipairs(L.lines) do
        local gb = l.deck - V.slab - V.girder
        local ends = l.axis == "y" and { "south", "north" } or { "west", "east" }
        local ax = l.axis == "y" and 1 or 2
        for _, side in ipairs(ends) do
            local st
            for _, bd in ipairs(L.rows[side]) do if bd.station == l.name then st = bd end end
            T.ok(st, l.name .. " has a station house on the " .. side .. " wall")
            if st then
                n = n + 1
                T.ok(st[ax] <= l.at - V.width / 2 - 64 and st[ax + 3] >= l.at + V.width / 2 + 64, l.name .. " " .. side .. " station spans the line")
                T.ok(st[6] <= gb - 64, l.name .. " " .. side .. " station's roof " .. st[6] .. " well under the girders " .. gb)
                T.ok(st[6] >= def.wallTop, l.name .. " " .. side .. " station still covers the wall")
                T.ok(st[3] <= def.ground, l.name .. " " .. side .. " station stands on the ground")
            end
            -- nothing else of that row stands in the line's way
            for _, bd in ipairs(L.rows[side]) do
                if not bd.station then
                    local top = bd.tower or bd
                    for _, b in ipairs({ bd, top }) do
                        T.ok(b[ax] >= l.at + V.width / 2 + 64 or b[ax + 3] <= l.at - V.width / 2 - 64,
                            l.name .. " " .. side .. " a neighbour keeps 64 off the truss")
                    end
                end
            end
        end
    end
    T.eq(n, 6, "a station house at both ends of all three lines")
end)

T.test("sense: the street a line runs down is open: no tower of the back row or the skyline stands in it", function()
    local City, L = city()
    local V = City.Viaduct
    local p = City.Maps.gm_skatepark.park
    for _, l in ipairs(L.lines) do
        local strip = l.axis == "y" and { l.at - V.width / 2 - 64, l.at + V.width / 2 + 64 } or { l.at - V.width / 2 - 64, l.at + V.width / 2 + 64 }
        local ax = l.axis == "y" and 1 or 2      -- the across axis
        for _, bd in ipairs(L.buildings) do
            if not bd.station then
                local across = bd[ax] < strip[2] and bd[ax + 3] > strip[1]
                T.ok(not across or (bd[6] <= l.deck - V.slab - V.girder - 64),
                    string.format("%s's street clear of a %s building at %d,%d", l.name, tostring(bd.side), bd[1], bd[2]))
            end
        end
    end
end)

T.test("sense: piers hold the line up all the way out, under its girders, standing in its street", function()
    local City, L = city()
    local V = City.Viaduct
    for _, l in ipairs(L.lines) do
        local gb = l.deck - V.slab - V.girder
        local out = 0
        for _, q in ipairs(L.faces.concrete2 or {}) do
            if q[18] == "via:" .. l.name then
                -- a crosshead's underside at the girders' foot, out past a wall
                local z = math.max(q[3], q[6], q[9], q[12])
                local cx, cy = (q[1] + q[7]) / 2, (q[2] + q[8]) / 2
                local a = l.axis == "y" and cy or cx
                if math.abs(z - gb) < 0.5 and (a < l.from - 256 or a > l.to + 256) then out = out + 1 end
            end
        end
        T.ok(out >= 10, l.name .. " has piers out over the city: " .. out .. " crosshead faces")
    end
end)

T.test("sense: two tracks: a train each way runs on its own side, and two never touch", function()
    local City, L = city()
    for _, l in ipairs(L.lines) do
        T.ok(City.TrackOffset(l, 1) == -City.TrackOffset(l, -1) and City.TrackOffset(l, 1) ~= 0, l.name .. " two tracks")
        -- right-hand running
        local r = City.TrackOffset(l, 1)
        if l.axis == "y" then T.ok(r > 0, l.name .. " northbound on the east track") else T.ok(r < 0, l.name .. " eastbound on the south track") end
        for t = 0, l.period * 4, 0.25 do
            local trains = City.TrainsAt(l, t)
            for i = 1, #trains do
                for j = i + 1, #trains do
                    local M = City.TrainModels[2]
                    for ci = 1, l.cars do
                        for cj = 1, l.cars do
                            T.ok(not overlap(carBox(City, l, trains[i], ci, M), carBox(City, l, trains[j], cj, M)),
                                l.name .. " two trains touch at " .. t)
                        end
                    end
                end
            end
        end
    end
end)

--------------------------------------------------------------------------
-- Billboards
--------------------------------------------------------------------------

T.test("sense: every ad is a billboard, up high: none down among the lower floors or the shops", function()
    local City, L = city()
    local def = City.Maps.gm_skatepark
    local minZ = City.BillboardMinZ(def)
    T.ok(minZ >= def.wallTop, "the lowest a billboard goes (" .. minZ .. ") is over the park's wall")
    T.ok(minZ >= def.ground + City.SHOP.h + City.SHOP.band + 2 * City.FLOOR, "and two floors over the shop fronts")
    local ads, wall, roof = 0, 0, 0
    for _, s in ipairs(L.signs) do
        if s.look == "ad" then
            ads = ads + 1
            T.ok(s.mount == "wall" or s.mount == "roof", s.text .. " is mounted as a billboard: " .. tostring(s.mount))
            local bottom = s.face[3] - s.fh / 2
            T.ok(bottom >= minZ, s.text .. " foot at " .. math.floor(bottom) .. ", over " .. minZ)
            if s.mount == "wall" then wall = wall + 1 else roof = roof + 1 end
        end
    end
    T.eq(ads, #def.billboards + 9, "every ad the map has is up")
    T.ok(wall >= 3 and roof >= 3, "on facades (" .. wall .. ") and on roofs (" .. roof .. ")")
end)

T.test("sense: a facade billboard is at the top, under the cornice, on a catwalk with a railing", function()
    local City, L = city()
    local grates = L.faces.grate or {}
    local rails = L.faces.rail or {}
    for _, s in ipairs(L.signs) do
        if s.mount == "wall" then
            local h = s.home
            local top = s.face[3] + s.fh / 2 + City.SIGN_LAMP.rise
            T.ok(top <= h[6] - 32, s.text .. " under the cornice")
            T.ok(top >= h[6] - 32 - 48 - 16, s.text .. " right up at the top of its building, not halfway down")
            T.ok(s.catwalk and s.catwalk[2] < s.face[3] - s.fh / 2 and s.catwalk[2] > s.face[3] - s.fh / 2 - 48, s.text .. " has a catwalk at its foot")
            -- the catwalk's grating spans the board, out in front of it
            local found = false
            for _, q in ipairs(grates) do
                local zq = q[3]
                if math.abs(zq - s.catwalk[2]) < 0.5 then
                    local ax = s.normal[1] ~= 0 and 2 or 1
                    local lo = math.min(q[ax], q[ax + 3], q[ax + 6], q[ax + 9])
                    local hi = math.max(q[ax], q[ax + 3], q[ax + 6], q[ax + 9])
                    if lo <= s.face[ax] - s.fw / 2 + 1 and hi >= s.face[ax] + s.fw / 2 - 1 then found = true end
                end
            end
            T.ok(found, s.text .. " catwalk grating spans the board")
            local railed = false
            for _, q in ipairs(rails) do
                if math.abs(math.min(q[3], q[9]) - s.catwalk[2]) < 0.5 then railed = true end
            end
            T.ok(railed, s.text .. " catwalk has a railing")
        end
    end
end)

T.test("sense: one billboard to a facade and to a roof; none on a station house, under the line", function()
    local City, L = city()
    local facades, roofs = {}, {}
    for _, s in ipairs(L.signs) do
        if s.mount == "wall" then
            T.ok(not facades[s.home], s.text .. " has its facade to itself") facades[s.home] = true
            T.ok(not s.home.station, s.text .. " not on a station house")
        elseif s.mount == "roof" then
            T.ok(not roofs[s.onRoof], s.text .. " has its roof to itself") roofs[s.onRoof] = true
            T.ok(not s.onRoof.station, s.text .. " not on a station house")
        end
    end
end)

--------------------------------------------------------------------------
-- Storefronts
--------------------------------------------------------------------------

-- the materials with windows in them (every style's window and street panels)
local function windowMats(City)
    local set = {}
    for _, st in pairs(City.Styles) do
        for _, m in ipairs(st.win) do set[m] = true end
        for _, m in ipairs(st.ground) do set[m] = true end
    end
    for _, st in pairs(City.Styles) do set[st.plain] = nil set[st.trim] = nil end
    return set
end

-- the frontage buildings' fronts over the park's walls: { side, bd, a0, a1, plane, n, ax }
local function fronts(City, L)
    local p = City.Maps.gm_skatepark.park
    local out = {}
    for _, side in ipairs({ "north", "south", "west", "east" }) do
        local ax = (side == "north" or side == "south") and 1 or 2
        local w0, w1 = ax == 1 and p[1] or p[2], ax == 1 and p[4] or p[5]
        for _, bd in ipairs(L.rows[side]) do
            local a0, a1 = math.max(bd[ax], w0), math.min(bd[ax + 3], w1)
            if a1 - a0 >= City.SHOP.minW then
                local plane = (side == "north") and bd[2] or (side == "south") and bd[5] or (side == "west") and bd[4] or bd[1]
                out[#out + 1] = { side = side, bd = bd, a0 = a0, a1 = a1, plane = plane, ax = ax }
            end
        end
    end
    return out
end

T.test("sense: the street floor is shops, wall to wall: every frontage building has shop fronts across it", function()
    local City, L = city()
    local S = City.SHOP
    local fs = fronts(City, L)
    T.ok(#fs >= 16, "frontage fronts: " .. #fs)
    for _, f in ipairs(fs) do
        local spans = {}
        for _, s in ipairs(L.signs) do
            if s.shop and s.shopOf == f.bd then
                spans[#spans + 1] = { s.a0, s.a1 }
                T.near(s.face[3] - s.fh / 2, City.Maps.gm_skatepark.ground, 0.01, tostring(s.text) .. " stands on the ground")
                T.near(s.fh, S.h, 0.01, tostring(s.text) .. " the street floor's height")
            end
        end
        T.ok(#spans >= 1, f.side .. " building at " .. f.a0 .. " has a shop front")
        table.sort(spans, function(a, b) return a[1] < b[1] end)
        if f.bd.station then
            T.eq(#spans, 1, "a station house has one front: the metro's entrance")
        else
            -- shop, pilaster, shop...: no gap wider than a pilaster
            local at = f.a0
            for _, sp in ipairs(spans) do
                T.ok(sp[1] - at <= S.pilaster + 0.01, f.side .. " no bare stretch before the shop at " .. sp[1])
                at = sp[2]
            end
            T.ok(f.a1 - at <= S.pilaster + 0.01, f.side .. " no bare stretch after the last shop, at " .. at)
        end
    end
end)

T.test("sense: not windows all the way down: no window on a frontage's street floor, facing the park", function()
    local City, L = city()
    local wins = windowMats(City)
    local S = City.SHOP
    local top = City.Maps.gm_skatepark.ground + S.h + S.band
    local bad = {}
    for _, f in ipairs(fronts(City, L)) do
        for mat in pairs(wins) do
            for _, q in ipairs(L.faces[mat] or {}) do
                local zmin = math.min(q[3], q[6], q[9], q[12])
                local pax = f.ax == 1 and 2 or 1          -- the plane's axis
                local onPlane = math.abs(q[pax] - f.plane) < 1 and math.abs(q[pax + 3] - f.plane) < 1 and math.abs(q[pax + 6] - f.plane) < 1
                local lo = math.min(q[f.ax], q[f.ax + 3], q[f.ax + 6])
                local hi = math.max(q[f.ax], q[f.ax + 3], q[f.ax + 6])
                if onPlane and zmin < top - 0.5 and lo < f.a1 - 0.5 and hi > f.a0 + 0.5 then
                    bad[#bad + 1] = f.side .. " " .. mat .. " at " .. math.floor(lo) .. " z " .. zmin
                end
            end
        end
    end
    T.eq(#bad, 0, "windows down at street level: " .. table.concat(bad, "; ", 1, math.min(#bad, 6)))
end)

T.test("sense: the check has teeth (without the shops, the street floor is windows and doors again)", function()
    local City = city()
    local B = City.Builder
    local was = B.storefronts
    B.storefronts = function() end
    local ok, L = pcall(City.Build, City.Maps.gm_skatepark)
    B.storefronts = was
    T.ok(ok, "built without shops")
    local wins, n = windowMats(City), 0
    for mat in pairs(wins) do
        for _, q in ipairs(L.faces[mat] or {}) do
            if math.min(q[3], q[6], q[9], q[12]) < 64 + City.SHOP.h and (q[18] or ""):find("^front:") then n = n + 1 end
        end
    end
    T.ok(n > 10, "the same city without shop fronts has street-floor windows: " .. n)
end)

T.test("sense: every shop has a name, something in its window, and a door; neighbours differ", function()
    local City, L = city()
    local shops, last = 0, {}
    for _, s in ipairs(L.signs) do
        if s.shop then
            shops = shops + 1
            T.ok(s.text and #s.text >= 3, "shop has a name: " .. tostring(s.text))
            T.ok(City.ShopWindows[s.kind] or s.kind == "metro", tostring(s.text) .. " sells something: " .. tostring(s.kind))
            T.ok(s.doorAt and s.doorAt > 0.05 and s.doorAt < 0.95, tostring(s.text) .. " has a door")
            T.ok(s.num and s.num ~= "", tostring(s.text) .. " has a number")
            if s.station then
                T.eq(s.kind, "metro", "a station house's front is the metro entrance")
            elseif last[s.side] then
                T.ok(last[s.side] ~= s.text, s.text .. " is not its neighbour's twin")
            end
            last[s.side] = s.text
            -- the face, its case and its pilasters stand in front of the wall, not in the park
            local nax = s.normal[1] ~= 0 and 1 or 2
            T.near(math.abs(s.face[nax] - s.wall), City.SHOP.case, 0.01, tostring(s.text) .. " stands just proud of its wall")
        end
    end
    T.ok(shops >= 20, "shops: " .. shops)
    local metro = 0
    for _, s in ipairs(L.signs) do if s.shop and s.kind == "metro" then metro = metro + 1 end end
    T.eq(metro, 6, "a metro entrance in each station house")
end)

T.test("sense: every shop door can be got to: a gap in the hedge, a path across the bed, no tree or lamp in the doorway", function()
    local City, L = city()
    local def = City.Maps.gm_skatepark
    local S = City.SHOP
    local leaves = {}
    for _, k in ipairs(City.LEAF_COLOURS) do leaves[k] = true end
    local behindBed = 0
    for _, s in ipairs(L.signs) do
        if s.shop and not s.station then
            local bed
            for _, b in ipairs(def.greenery.beds) do
                if b.side == s.side and s.doorA > b.from + 40 and s.doorA < b.to - 40 then bed = b end
            end
            if bed then
                behindBed = behindBed + 1
                local ax = (s.side == "north" or s.side == "south") and 1 or 2
                -- no hedge card in the doorway, low down in the bed
                for k in pairs(leaves) do
                    for _, q in ipairs(L.faces[k] or {}) do
                        local zq = math.min(q[3], q[6], q[9], q[12])
                        local lo = math.min(q[ax], q[ax + 3], q[ax + 6], q[ax + 9])
                        local hi = math.max(q[ax], q[ax + 3], q[ax + 6], q[ax + 9])
                        if zq < 100 and (q[18] or ""):find("^green:bed") and lo < s.doorA + S.door / 2 - 2 and hi > s.doorA - S.door / 2 + 2 then
                            local other = ax == 1 and 2 or 1
                            local d = math.abs(q[other] - (s.side == "north" and def.park[5] or s.side == "south" and def.park[2]
                                or s.side == "west" and def.park[1] or def.park[4]))
                            T.ok(d > 120, tostring(s.text) .. "'s door has a hedge across it")
                        end
                    end
                end
                -- a path across the bed to it
                local pathed = false
                for _, q in ipairs(L.faces.path or {}) do
                    local lo = math.min(q[ax], q[ax + 3], q[ax + 6])
                    local hi = math.max(q[ax], q[ax + 3], q[ax + 6])
                    if lo <= s.doorA - S.door / 2 + 1 and hi >= s.doorA + S.door / 2 - 1 then pathed = true end
                end
                T.ok(pathed, tostring(s.text) .. " has a path to its door")
                -- nothing growing or standing in the doorway
                for _, pl in ipairs(L.props) do
                    local along = ax == 1 and pl.x or pl.y
                    if pl.z < 200 and math.abs(along - s.doorA) < S.door / 2 + 12 then
                        local off = ax == 1 and math.abs(pl.y - s.face[2]) or math.abs(pl.x - s.face[1])
                        T.ok(off > 200, tostring(s.text) .. "'s door blocked by a " .. pl.kind)
                    end
                end
            end
        end
    end
    T.ok(behindBed >= 8, "shops behind a planting bed: " .. behindBed)
end)

T.test("sense: awnings over shop windows: clear of every ramp, tree and lamp", function()
    local City, L = city()
    T.ok(#L.awnings >= 3, "awnings: " .. #L.awnings)
    for _, aw in ipairs(L.awnings) do
        local b = aw.box
        for _, r in ipairs(RAMPS) do
            T.ok(not overlap(b, { r[2], r[3], r[6], r[4], r[5], r[7] }, 16), aw.shop.text .. "'s awning clear of " .. r[1])
        end
        for _, pl in ipairs(L.props) do
            local trunk = { pl.x - 14, pl.y - 14, pl.z, pl.x + 14, pl.y + 14, pl.z + 500 }
            T.ok(not overlap(b, trunk), aw.shop.text .. "'s awning clear of a " .. pl.kind)
        end
        -- under the fascia, over the window: not over the name, not down at the door's foot
        local zt = City.Maps.gm_skatepark.ground + City.SHOP.h - City.SHOP.fascia
        T.near(b[6], zt, 0.01, aw.shop.text .. "'s awning hangs from under its fascia")
        T.ok(b[3] > 64 + 100, aw.shop.text .. "'s awning is head height and up")
    end
end)

T.test("sense (client): every shop front paints its name, without an error", function()
    local City, L, cl = city()
    local env = cl.env
    local texts = {}
    env.surface.DrawPoly = function() end
    env.surface.DrawOutlinedRect = function() end
    env.draw.NoTexture = function() end
    env.surface.CreateFont = function() end
    env.surface.SetFont = function() end
    env.surface.GetTextSize = function(t) return #tostring(t) * 10, 20 end
    env.draw.SimpleText = function(t) texts[#texts + 1] = tostring(t) end
    City._layout = L
    local n = 0
    for _, s in ipairs(L.signs) do
        if s.shop then
            n = n + 1
            texts = {}
            local Fr = City.SignFrame(s)
            local ok, err = pcall(City.ShopSign, s, Fr.pw, Fr.ph)
            T.ok(ok, tostring(s.text) .. " paints: " .. tostring(err))
            local all = table.concat(texts, "|")
            T.ok(all:find(s.text, 1, true), tostring(s.text) .. " shows its name: " .. all)
            if not s.station then T.ok(all:find("OPEN", 1, true), tostring(s.text) .. " has its OPEN card") end
        end
    end
    T.ok(n >= 20, "shop fronts painted: " .. n)
    -- every kind of shop the map has has a window painter
    for _, shop in ipairs(City.Maps.gm_skatepark.storefronts.shops) do
        T.ok(City.ShopWindows[shop.kind], shop.text .. ": a window for " .. shop.kind)
    end
end)

--------------------------------------------------------------------------
-- Lamps
--------------------------------------------------------------------------

T.test("sense: the street lamps' glow is in the lamp head's lens, not a foot under it", function()
    local City, L = city()
    -- props_c17/lamppost03a_on, read off its .vvd: the head runs 69.4 to
    -- 105.1 out along the arm, its glowing underside at z 440.8
    local LENS_Z, HEAD0, HEAD1 = 440.8, 69.4, 105.1
    T.ok(City.LAMP.height <= LENS_Z and City.LAMP.height >= LENS_Z - 6, "glow just under the lens: " .. City.LAMP.height)
    T.ok(math.abs(City.LAMP.reach - (HEAD0 + HEAD1) / 2) <= 4, "glow at the middle of the head: " .. City.LAMP.reach)
    T.ok(#L.lamps >= 8, "lamps: " .. #L.lamps)
    for _, l in ipairs(L.lamps) do
        local dx, dy = l.head[1] - l.x, l.head[2] - l.y
        T.near(math.sqrt(dx * dx + dy * dy), City.LAMP.reach, 0.01, "head out along the arm")
        T.near(l.head[3] - l.z, City.LAMP.height, 0.01, "head at the lens's height over the lamp's foot")
        -- the post is a model standing on the bed, turned so its arm reaches the head
        local found = false
        for _, pl in ipairs(L.props) do
            if pl.kind == "lamp" and math.abs(pl.x - l.x) < 0.01 and math.abs(pl.y - l.y) < 0.01 then
                found = true
                T.near(pl.z, l.z, 0.01, "lamp model on the same foot")
                local yaw = math.rad(pl.yaw + 90)
                T.near(math.cos(yaw) * dx + math.sin(yaw) * dy, City.LAMP.reach, 0.5, "the model's arm points at its glow")
            end
        end
        T.ok(found, "a lamp post under the glow")
    end
end)
