--[[--------------------------------------------------------------------------
    The bike rental by the middle spawn (sh_city_maps.lua `rental`,
    sv_city.lua City.SpawnRental): the BMX addon's free vending machines, so a
    player gets a bike without the console or the Q menu.
----------------------------------------------------------------------------]]

local F = require("lib.fixture")

local SPAWNS = { { 1008, -421 }, { 2562, 0 }, { 195, -764 }, { 1707, -673 }, { 3212, -814 } }
local CENTRE = { (-256 + 3584) / 2, (-1792 + 768) / 2 }
local MACHINE = 40     -- u: half a vending machine's footprint, rounded up
local BAY = 110        -- u: how far in front of a machine its bike appears, and the bike

local function rampBoxes(sv)
    local out = {}
    for _, r in ipairs(sv.env.BMX.City.Maps.gm_skatepark.ramps) do out[#out + 1] = r end
    return out
end

local function near(x, y, box, margin)
    return x > box[2] - margin and x < box[4] + margin and y > box[3] - margin and y < box[5] + margin
end

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local function onMap(map)
    local sv = F.server({ map = map or "petopia_bmx_fall" })
    sv.env.game.GetMap = function() return map or "petopia_bmx_fall" end
    sv.env.BMX.City.SpawnRental()
    return sv
end

T.test("rental: the machines stand by the spawn nearest the middle of the park", function()
    local def = onMap().env.BMX.City.Maps.gm_skatepark
    T.ok(def.rental and #def.rental >= 1, "the map has a rental")
    local best, bd
    for _, sp in ipairs(SPAWNS) do
        local d = dist(sp[1], sp[2], CENTRE[1], CENTRE[2])
        if not bd or d < bd then best, bd = sp, d end
    end
    for _, r in ipairs(def.rental) do
        local d = dist(r.x, r.y, best[1], best[2])
        T.ok(d < 400, string.format("machine at %d,%d is %.0f u from the middle spawn", r.x, r.y, d))
    end
end)

T.test("rental: every machine and its bike bay is clear of the ramps, the piers and the spawns", function()
    local sv = onMap()
    local def = sv.env.BMX.City.Maps.gm_skatepark
    for _, r in ipairs(def.rental) do
        local a = math.rad(r.yaw or 0)
        local bx, by = r.x + math.cos(a) * BAY, r.y + math.sin(a) * BAY
        for _, rp in ipairs(rampBoxes(sv)) do
            T.ok(not near(r.x, r.y, rp, MACHINE + 40), r.x .. "," .. r.y .. " clear of " .. rp[1])
            T.ok(not near(bx, by, rp, 60), "its bay clear of " .. rp[1])
        end
        for _, p in ipairs(def.piers) do
            T.ok(dist(r.x, r.y, p.x, p.y) > p.size + MACHINE + 40, "clear of " .. p.name)
        end
        for _, sp in ipairs(SPAWNS) do
            T.ok(dist(bx, by, sp[1], sp[2]) > 96, "its bay is not on a spawn")
            T.ok(dist(r.x, r.y, sp[1], sp[2]) > 96, "nor the machine")
        end
        T.ok(r.x > def.park[1] + 100 and r.x < def.park[4] - 100 and r.y > def.park[2] + 100
            and r.y < def.park[5] - 100, "inside the park, off the planting beds")
    end
end)

T.test("rental: the server places the machines, on the floor, facing the spawn, and again after a cleanup", function()
    local sv = onMap()
    local E = sv.env
    local def = E.BMX.City.Maps.gm_skatepark
    local ms = E.ents.FindByClass("bmx_rental")
    T.eq(#ms, #def.rental, "one per entry")
    for _, m in ipairs(ms) do
        T.near(m:GetPos().z + m:OBBMins().z, def.park[3], 1e-6, "standing on the floor")
        local f = m:GetForward()
        T.ok(f.x < -0.99, "its face looks west, at the spawn")
    end
    E.hook.Run("PostCleanupMap")
    T.eq(#E.ents.FindByClass("bmx_rental"), #def.rental, "replaced, not doubled")
end)

T.test("rental: a player at the spawn walks up, rents, and is on a bike in the bay", function()
    local sv = onMap()
    local E = sv.env
    local m = E.ents.FindByClass("bmx_rental")[1]
    local ply = sv:player("New")
    ply:SetPos(m:GetPos() + E.Vector(-100, 0, 0))
    local bike = E.BMX.Rental.Rent(ply, m, "stock")
    T.ok(bike and bike:IsValid(), "rented")
    T.eq(ply:GetVehicle(), bike:GetPod(), "and riding")
    T.ok(bike:GetPos().x < m:GetPos().x, "in front of the machine, on the spawn's side")
end)

T.test("rental: no machines on a map without a city entry", function()
    local sv = onMap("gm_flatgrass")
    T.eq(#sv.env.ents.FindByClass("bmx_rental"), 0, "none")
end)
