--[[--------------------------------------------------------------------------
    SkateGM on this map (github.com/the-schwilliam/SkateGM, the Skate 3
    add-on). SkateGM does not use Source's collision: it reads the BSP's
    brushes and builds its skater's world from their faces, and the city's
    colliders reach it only through cl_skategm.lua.

    2026-10-14, on the Workshop page: "you kind of just fall straight through
    the floor" with SkateGM. SkateGM drops a brush face it takes for hidden:
    four points just in front of it -- its middle, and 80% of the way out to
    each corner, 0.5 u off the face -- all inside other brushes. The floor was
    ONE brush, its top two triangles across the whole park; one triangle had
    its middle under a funbox and its corners in two walls and the east
    quarter pipe, so SkateGM dropped it, and the park's north-east half (two
    of the five spawns) had no floor. Measured with SkateGM 9.0's own map
    loader on the BSP (a 16 u grid of the park): 12,275 of 36,882 spots with
    no ground under them before, none with the floor in pieces
    (build_vmf.py floor_cells).
----------------------------------------------------------------------------]]

local F = require("lib.fixture")
local BL = require("bsplight")

local here = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")) or "tests"
local ROOT = here .. "/.."

-- CONTENTS_SOLID | WINDOW | GRATE | PLAYERCLIP: what SkateGM takes as solid
local PLAYER_SOLID = { 0x1, 0x2, 0x8, 0x10000 }
local function solidContents(c)
    for _, bit in ipairs(PLAYER_SOLID) do
        if math.floor(c / bit) % 2 == 1 then return true end
    end
    return false
end

local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function mul(a, s) return { a[1] * s, a[2] * s, a[3] * s } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end

-- A convex brush's faces from its planes, as SkateGM makes them: every corner
-- where three planes meet inside the rest, then each plane's corners in turn
-- around their middle.
local function brushFaces(planes)
    local pts = {}
    for a = 1, #planes do
        for b = a + 1, #planes do
            for c = b + 1, #planes do
                local A, B, C = planes[a], planes[b], planes[c]
                local det = dot(A, cross(B, C))
                if math.abs(det) > 1e-6 then
                    local p = mul(add(add(mul(cross(B, C), A[4]), mul(cross(C, A), B[4])), mul(cross(A, B), C[4])), 1 / det)
                    local inside = true
                    for _, q in ipairs(planes) do
                        if dot(q, p) > q[4] + 0.05 then inside = false break end
                    end
                    for _, o in ipairs(pts) do
                        local d = sub(o, p)
                        if dot(d, d) <= 0.01 then inside = false break end
                    end
                    if inside then pts[#pts + 1] = p end
                end
            end
        end
    end
    local faces = {}
    for _, pl in ipairs(planes) do
        local f = {}
        for _, p in ipairs(pts) do
            if math.abs(dot(pl, p) - pl[4]) < 0.1 then f[#f + 1] = p end
        end
        if #f >= 3 then
            local c = { 0, 0, 0 }
            for _, p in ipairs(f) do c = add(c, p) end
            c = mul(c, 1 / #f)
            local n = { pl[1], pl[2], pl[3] }
            local x = math.abs(n[1]) < 0.9 and cross(n, { 1, 0, 0 }) or cross(n, { 0, 1, 0 })
            local y = cross(n, x)
            table.sort(f, function(p, q)
                local u, v = sub(p, c), sub(q, c)
                return math.atan2(dot(u, y), dot(u, x)) < math.atan2(dot(v, y), dot(v, x))
            end)
            faces[#faces + 1] = { pts = f, n = n }
        end
    end
    return faces
end

local function inside(b, p)
    for _, q in ipairs(b.planes) do
        if q[1] * p[1] + q[2] * p[2] + q[3] * p[3] > q[4] then return false end
    end
    return true
end

-- Solid at p: inside a player-solid brush other than `skip` (SkateGM reads
-- this off the BSP tree, which is the brushes' union).
local function solidAt(brushes, p, skip)
    for _, b in ipairs(brushes) do
        if b ~= skip and b.solid and p[1] >= b.lo[1] and p[1] <= b.hi[1] and p[2] >= b.lo[2]
            and p[2] <= b.hi[2] and p[3] >= b.lo[3] and p[3] <= b.hi[3] and inside(b, p) then
            return true
        end
    end
    return false
end

local function prepare(brushes)
    for _, b in ipairs(brushes) do
        b.solid = solidContents(b.contents)
        b.faces = brushFaces(b.planes)
        b.lo, b.hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
        for _, f in ipairs(b.faces) do
            for _, p in ipairs(f.pts) do
                for k = 1, 3 do b.lo[k] = math.min(b.lo[k], p[k]) b.hi[k] = math.max(b.hi[k], p[k]) end
            end
        end
    end
    return brushes
end

-- Every triangle SkateGM would drop as hidden while part of it is open, for
-- every way of fanning each face (SkateGM's own fan start depends on its sort;
-- holding all of them is stricter). Open is judged just off the face (0.05 u):
-- a ramp's toe is thinner than SkateGM's 0.5 u for its first few units, and
-- there the ramp's own face is the ground. Returns { {t =, open =}, ... }.
local function lostFaces(brushes, step)
    local lost = {}
    for _, b in ipairs(brushes) do
        if b.solid and not b._skipFaces then
            for _, f in ipairs(b.faces) do
                local P, out = f.pts, mul(f.n, 0.5)
                for s = 1, #P do
                    for i = 1, #P - 2 do
                        local t = { P[s], P[(s + i - 1) % #P + 1], P[(s + i) % #P + 1] }
                        local c = mul(add(add(t[1], t[2]), t[3]), 1 / 3)
                        local near = mul(f.n, 0.05)
                        local four = { add(c, out) }
                        for k = 1, 3 do four[#four + 1] = add(add(c, mul(sub(t[k], c), 0.8)), out) end
                        local hidden = true
                        for _, q in ipairs(four) do
                            if not solidAt(brushes, q, b) then hidden = false break end
                        end
                        if hidden then
                            -- dropped: then all of it must really be covered
                            local e1, e2 = sub(t[2], t[1]), sub(t[3], t[1])
                            local long = math.max(math.sqrt(dot(e1, e1)), math.sqrt(dot(e2, e2)))
                            local m = math.max(1, math.ceil(long / step))
                            for u = 0, m do
                                for v = 0, m - u do
                                    local p = add(add(t[1], mul(e1, u / m)), mul(e2, v / m))
                                    local q = add(add(c, mul(sub(p, c), 0.98)), near)
                                    if not solidAt(brushes, q, b) then
                                        lost[#lost + 1] = { t = t, open = q }
                                        break
                                    end
                                end
                                if lost[#lost] and lost[#lost].t == t then break end
                            end
                        end
                    end
                end
            end
        end
    end
    return lost
end

local function box(x0, y0, z0, x1, y1, z1)
    return { contents = 1, planes = { { 1, 0, 0, x1 }, { -1, 0, 0, -x0 }, { 0, 1, 0, y1 },
                                      { 0, -1, 0, -y0 }, { 0, 0, 1, z1 }, { 0, 0, -1, -z0 } } }
end

T.test("skategm: the check finds the old one-brush floor's lost half (so it can find it again)", function()
    -- the old shell in miniature: one floor brush under a walled box, a funbox
    -- where the far triangle's middle lands, a quarter pipe in its far corner
    local brushes = prepare({
        box(-512, -2048, 0, 3840, 1024, 64),                                         -- the floor
        box(-512, -2048, 64, -256, 1024, 528), box(3584, -2048, 64, 3840, 1024, 528), -- walls
        box(-256, -2048, 64, 3584, -1792, 528), box(-256, 768, 64, 3584, 1024, 528),
        box(1855, -290, 64, 2401, 191, 150),                                         -- funbox 2
        box(3291, -1687, 64, 3584, -1067, 237),                                      -- quarter pipe
    })
    local lost = lostFaces(brushes, 64)
    local floor = 0
    for _, l in ipairs(lost) do if l.t[1][3] == 64 and l.t[2][3] == 64 and l.t[3][3] == 64 then floor = floor + 1 end end
    T.ok(floor >= 1, "the one-brush floor loses a triangle with open floor on it: " .. floor)
end)

-- The floor's pieces and the walls: what a skater stands on and rides into.
-- (Left out, known, the owner's call: the top wedge of each transition goes
-- to SkateGM's other hidden-face step, the coping's flat top being level with
-- it -- a slot beside each coping; and the flat ramp by the north-west quarter
-- pipe overlaps it by 6 u, its side a sliver above the pipe's curve.)
local function floorAndWalls(brushes)
    local out = {}
    for _, b in ipairs(brushes) do
        local floor = b.lo[3] == 0 and b.hi[3] == 64
        local wall = b.lo[3] == 64 and b.hi[3] == 528
            and (b.hi[1] <= -256 or b.lo[1] >= 3584 or b.hi[2] <= -1792 or b.lo[2] >= 768)
        if floor or wall then out[#out + 1] = b end
    end
    return out
end

T.test("skategm: no floor or wall face open to the park is dropped as hidden", function()
    local brushes = prepare(BL.brushes(ROOT .. "/maps/petopia_bmx_fall.bsp"))
    T.ok(#brushes > 145, "the floor is in pieces: " .. #brushes .. " brushes")
    local mine = floorAndWalls(brushes)
    T.ok(#mine > 60, "floor pieces and walls: " .. #mine)
    -- (only their faces are checked, against every brush)
    for _, b in ipairs(brushes) do b._skipFaces = true end
    for _, b in ipairs(mine) do b._skipFaces = nil end
    local lost = lostFaces(brushes, 16)
    local msg = {}
    for i = 1, math.min(4, #lost) do
        local t, q = lost[i].t, lost[i].open
        msg[#msg + 1] = string.format("(%d %d %d)-(%d %d %d)-(%d %d %d) open at (%.0f %.0f %.1f)",
            t[1][1], t[1][2], t[1][3], t[2][1], t[2][2], t[2][3], t[3][1], t[3][2], t[3][3], q[1], q[2], q[3])
    end
    T.eq(#lost, 0, "faces SkateGM drops with open park in front: " .. table.concat(msg, "; "))
end)

T.test("skategm: the floor pieces cover the floor exactly, each wholly under a ramp or wholly open", function()
    local brushes = prepare(BL.brushes(ROOT .. "/maps/petopia_bmx_fall.bsp"))
    local area, pieces = 0, 0
    for _, b in ipairs(brushes) do
        if b.lo[3] == 0 and b.hi[3] == 64 then
            pieces = pieces + 1
            area = area + (b.hi[1] - b.lo[1]) * (b.hi[2] - b.lo[2])
            -- open or covered, the same over all of it (a 5 x 5 grid of points
            -- just above it, 4 u in from its edges: past a ramp's thin toe)
            local seen = {}
            local inset = math.min(4, (b.hi[1] - b.lo[1]) / 4, (b.hi[2] - b.lo[2]) / 4)
            for i = 0, 4 do
                for j = 0, 4 do
                    local x = b.lo[1] + inset + (b.hi[1] - b.lo[1] - 2 * inset) * i / 4
                    local y = b.lo[2] + inset + (b.hi[2] - b.lo[2] - 2 * inset) * j / 4
                    seen[solidAt(brushes, { x, y, 64.05 }, b)] = true
                end
            end
            T.ok(not (seen[true] and seen[false]), string.format("floor piece %d %d - %d %d is half under something",
                b.lo[1], b.lo[2], b.hi[1], b.hi[2]))
        end
    end
    T.eq(area, (3840 + 512) * (1024 + 2048), "floor area (walls' undersides included)")
    T.ok(pieces < 100, "a modest number of pieces: " .. pieces)
end)

---------------------------------------------------------------------------
-- cl_skategm.lua: the city's colliders handed to SkateGM
---------------------------------------------------------------------------

-- A client on the map, its colliders made as the server would make them, and
-- a stand-in for SkateGM's client table.
local function skateClient()
    local sv, world = F.server()
    sv.env.game.GetMap = function() return "petopia_bmx_fall" end
    sv.env.BMX.City.SpawnSolids()
    local cl = F.client(world)
    local env = cl.env
    env.game.GetMap = function() return "petopia_bmx_fall" end
    -- (the city builds itself on the client's Think: what test_city gives it)
    env.Mesh = function(mat) return { mat = mat, Draw = function() end, Destroy = function() end } end
    env.MATERIAL_QUADS = 4
    env.CreateMaterial = function(name, shader, params) return { name = name, shader = shader, params = params } end
    env.mesh = { Begin = function() end, Position = function() end, TexCoord = function() end,
                 Color = function() end, AdvanceVertex = function() end, End = function() end }
    env.SysTime = os.clock
    local made = {}
    for _, s in ipairs(sv.env.ents.FindByClass("bmx_city_solid")) do
        local e = cl:clientEntity("bmx_city_solid")
        e:SetSolidName(s:GetSolidName())
        e:SetPos(s:GetPos())
        e:Think()                               -- the client builds once the name arrives
        made[#made + 1] = e
    end
    local S = { HullProviders = {}, LATER = {}, ViewPos = function(e) return e:GetPos() end }
    return env, S, made, cl
end

T.test("skategm: installs once SkateGM is there, once only, and not without it", function()
    local env, S = skateClient()
    local SK = env.BMX.City.SkateGM
    T.ok(SK, "cl_skategm loaded on the client")
    T.eq(SK.Install(nil), false, "no SkateGM: nothing")
    T.eq(SK.Install({}), false, "a SkateGM without hull providers: nothing")
    T.eq(SK.Install(S), true, "installed")
    T.eq(SK.Install(S), true, "again: already")
    T.eq(#S.HullProviders, 1, "one hull provider")
    T.eq(#S.ExtraFeeds, 1, "one feed")
    T.eq(#S.EntitySkippers, 1, "one skipper")
end)

T.test("skategm: SkateGM loading after the map is picked up within a few seconds", function()
    local env, _, _, cl = skateClient()
    local SK = env.BMX.City.SkateGM
    SK.Start()
    T.ok(env.timer.Exists("petopia_bmx_fall_skategm"), "waiting for SkateGM")
    cl:run(2.5)
    T.ok(env.timer.Exists("petopia_bmx_fall_skategm"), "still waiting while it is not there")
    local S = { HullProviders = {}, LATER = {} }
    env.SkateGM = S
    cl:run(1.5)
    T.eq(#S.HullProviders, 1, "installed once it turned up")
    -- (the engine's timer.Remove from inside the timer stops it; the test
    -- shim puts a repeating timer back after its call, so what is held here
    -- is that more calls change nothing)
    cl:run(3)
    T.eq(#S.HullProviders, 1, "and only once")
    T.eq(#S.ExtraFeeds, 1, "one feed")
end)

T.test("skategm: every collider near the skater goes to SkateGM as its own boxes, where the city put them", function()
    local env, S, made = skateClient()
    local SK = env.BMX.City.SkateGM
    SK.Install(S)
    T.ok(#made > 10, "colliders on the client: " .. #made)
    local L = env.BMX.City.Layout()
    local list, sig = {}, {}
    -- a skater mid-park: SkateGM asks for everything within 2500 u
    S.ExtraFeeds[1](env.Vector(1664, -512, 80), list, sig)
    T.ok(#list > 0, "fed: " .. #list)
    T.eq(#sig, #list, "a signature for each")
    local fed = 0
    for _, item in ipairs(list) do
        local name, x, y, z = item[1], item[2], item[3], item[4]
        T.ok(name:sub(1, #SK.PREFIX) == SK.PREFIX, "named " .. name)
        local s = L.solids[name:sub(#SK.PREFIX + 1)]
        T.ok(s, "a solid of the layout: " .. name)
        local hulls, isMesh = S.HullProviders[1](name)
        T.eq(type(hulls), "table", name .. " has a shape")
        T.eq(isMesh, false, name .. " as convex pieces")
        T.eq(#hulls, #s.boxes, name .. ": one piece a box")
        for i, h in ipairs(hulls) do
            T.eq(#h, 36 * 3, name .. ": twelve triangles a box")
            local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
            for k = 1, #h, 3 do
                for a = 1, 3 do lo[a] = math.min(lo[a], h[k + a - 1]) hi[a] = math.max(hi[a], h[k + a - 1]) end
            end
            -- placed where it is fed, the piece is the layout's box
            local b = s.boxes[i]
            T.near(lo[1] + x, b[1], 0.01, name .. " x0") T.near(lo[2] + y, b[2], 0.01, name .. " y0")
            T.near(lo[3] + z, b[3], 0.01, name .. " z0") T.near(hi[1] + x, b[4], 0.01, name .. " x1")
            T.near(hi[2] + y, b[5], 0.01, name .. " y1") T.near(hi[3] + z, b[6], 0.01, name .. " z1")
        end
        fed = fed + 1
    end
    -- the far ones are not fed
    local far = 0
    for _, e in ipairs(made) do
        if e:GetPos():DistToSqr(env.Vector(1664, -512, 80)) >= SK.RADIUS * SK.RADIUS then far = far + 1 end
    end
    T.eq(fed + far, #made, "every collider fed, or out of SkateGM's reach")
end)

T.test("skategm: the stand-in cube is never sent, and other entities are left to SkateGM", function()
    local env, S, made = skateClient()
    local SK = env.BMX.City.SkateGM
    SK.Install(S)
    local skip = S.EntitySkippers[1]
    T.eq(skip(made[1]), true, "a collider is skipped (it comes through the feed)")
    T.eq(skip({ GetClass = function() return "prop_physics" end, IsValid = function() return true end }), false, "a prop is not")
    T.eq(S.HullProviders[1]("models/props_c17/oildrum001.mdl"), nil, "other models: not ours")
    T.eq(S.HullProviders[1](SK.PREFIX .. "nothing_by_this_name"), S.LATER, "a collider not seen yet: asked again later")
end)
