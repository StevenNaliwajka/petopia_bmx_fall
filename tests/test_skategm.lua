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
-- (The top wedge of each transition goes to SkateGM's other hidden-face step,
-- the coping's flat top being level with it, and the flat ramp's side above the
-- north-west quarter pipe is a sliver SkateGM drops: those are handed back as
-- surface patches, below.)
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
-- The surface patches (lua/petopia_bmx_fall/cl_skategm_patches.lua, 1.0.3):
-- the map's own faces SkateGM's collision leaves pieces of out, handed back to
-- it as meshes. Generated, and measured, with SkateGM's own map loader
-- (tools/skategm/check.sh, at each smoothing preset: 365 spots without ground
-- beside the copings before, 0 after; the same grind rails; only funbox 2's
-- cracks left, below); held here against the BSP and SkateGM's hidden-face rule.
---------------------------------------------------------------------------

local function patchList()
    local chunk = assert(loadfile(ROOT .. "/lua/petopia_bmx_fall/cl_skategm_patches.lua"))
    local env = {}
    setfenv(chunk, env)
    chunk()
    return env.PetopiaBMXFall.SkateGMPatches
end

-- Each patch's triangles: { {a, b, c, n = outward unit normal}, ... }.
local function patchTris(p)
    local out = {}
    for k = 4, #p - 8, 9 do
        local a, b, c = { p[k], p[k + 1], p[k + 2] }, { p[k + 3], p[k + 4], p[k + 5] }, { p[k + 6], p[k + 7], p[k + 8] }
        local n = cross(sub(b, a), sub(c, a))
        local l = math.sqrt(dot(n, n))
        local t = { a, b, c, n = mul(n, 1 / l), area = l / 2, lo = {}, hi = {} }
        for k = 1, 3 do
            t.lo[k] = math.min(a[k], b[k], c[k]) - 0.2
            t.hi[k] = math.max(a[k], b[k], c[k]) + 0.2
        end
        out[#out + 1] = t
    end
    return out
end

-- Distance from p to triangle t (projected onto its plane, then clamped).
local function nearTri(t, p)
    local d = dot(sub(p, t[1]), t.n)
    local q = sub(p, mul(t.n, d))
    local inside = true
    for k = 1, 3 do
        local a, b = t[k], t[k % 3 + 1]
        if dot(cross(sub(b, a), sub(q, a)), t.n) < -1e-3 then inside = false break end
    end
    if inside then return math.abs(d) end
    local best = math.huge
    for k = 1, 3 do
        local a, b = t[k], t[k % 3 + 1]
        local ab = sub(b, a)
        local s = math.max(0, math.min(1, dot(sub(p, a), ab) / dot(ab, ab)))
        local e = sub(p, add(a, mul(ab, s)))
        best = math.min(best, math.sqrt(dot(e, e)))
    end
    return best
end

local function onPatch(tris, p, n)
    for _, t in ipairs(tris) do
        if p[1] >= t.lo[1] and p[1] <= t.hi[1] and p[2] >= t.lo[2] and p[2] <= t.hi[2]
            and p[3] >= t.lo[3] and p[3] <= t.hi[3] and dot(t.n, n) > 0.99 and nearTri(t, p) <= 0.1 then
            return true
        end
    end
    return false
end

local function allPatchTris(list)
    local all = {}
    for _, p in ipairs(list) do
        for _, t in ipairs(patchTris(p)) do all[#all + 1] = t end
    end
    return all
end

local function onFace(f, p)
    if math.abs(dot(f.n, p) - dot(f.n, f.pts[1])) > 0.05 then return false end
    for k = 1, #f.pts do
        local a, b = f.pts[k], f.pts[k % #f.pts + 1]
        local ab = sub(b, a)
        -- (how far inside its edge, in units)
        if dot(cross(ab, sub(p, a)), f.n) / math.sqrt(dot(ab, ab)) < -0.05 then return false end
    end
    return true
end

-- SkateGM's floors (faces turned up past 0.7) and its "ground in front"
-- lookup: the highest floor at x, y no higher than zmax.
local function floorIndex(brushes, extra)
    local floors = {}
    for _, b in ipairs(brushes) do
        if b.solid then
            for _, f in ipairs(b.faces) do
                if f.n[3] > 0.7 then floors[#floors + 1] = f end
            end
        end
    end
    for _, f in ipairs(extra or {}) do floors[#floors + 1] = f end
    return function(x, y, zmax)
        local best
        for _, f in ipairs(floors) do
            local inside = true
            for k = 1, #f.pts do
                local a, b = f.pts[k], f.pts[k % #f.pts + 1]
                if (b[1] - a[1]) * (y - a[2]) - (b[2] - a[2]) * (x - a[1]) < -1e-3 * (f.n[3] > 0 and 1 or -1) then
                    inside = false break
                end
            end
            if inside then
                local z = (dot(f.n, f.pts[1]) - f.n[1] * x - f.n[2] * y) / f.n[3]
                if z <= zmax + 1e-3 and (not best or z > best) then best = z end
            end
        end
        return best
    end
end

-- SkateGM's steep faces, for its "wall carries on above" test: every fan
-- triangle of every solid face turned less than 0.7 up, with its normal.
local function wallIndex(brushes)
    local walls = {}
    for _, b in ipairs(brushes) do
        if b.solid then
            for _, f in ipairs(b.faces) do
                local P = f.pts
                if math.abs(f.n[3]) < 0.7 then
                    for s = 1, #P do
                        for i = 1, #P - 2 do
                            local t = { P[s], P[(s + i - 1) % #P + 1], P[(s + i) % #P + 1], n = f.n }
                            t.lo, t.hi = {}, {}
                            for k = 1, 3 do
                                t.lo[k] = math.min(t[1][k], t[2][k], t[3][k]) - 0.1
                                t.hi[k] = math.max(t[1][k], t[2][k], t[3][k]) + 0.1
                            end
                            walls[#walls + 1] = t
                        end
                    end
                end
            end
        end
    end
    -- (cleanup::Walls::continues: a steep face other than `own`, facing as n,
    -- with p within 0.05 of its plane and inside its edges)
    return function(p, n, own)
        for _, t in ipairs(walls) do
            if p[1] >= t.lo[1] and p[1] <= t.hi[1] and p[2] >= t.lo[2] and p[2] <= t.hi[2] and p[3] >= t.lo[3] and p[3] <= t.hi[3]
                and dot(t.n, n) >= 0.99 and math.abs(dot(sub(p, t[1]), t.n)) <= 0.05
                and not (t[1] == own[1] and t[2] == own[2] and t[3] == own[3]) then
                local inside = true
                for k = 1, 3 do
                    if dot(cross(sub(t[k % 3 + 1], t[k]), sub(p, t[k])), t.n) < -1e-3 then inside = false break end
                end
                if inside then return true end
            end
        end
        return false
    end
end

-- SkateGM's hidden-face step (cleanup::remove_hidden_under_floor) for one
-- triangle: steep, and ground in front of its top edge, 1 u out, at its top's
-- height, at 15%, 50% and 85% along it -- unless it is the foot of a taller
-- wall (its "outline" rule, on by default: part of the edges down from its top
-- corner stands over 8 u clear of the ground in front, and the same wall
-- carries on 1 u above there; only a wall within a hair of upright can).
local function hiddenUnderFloor(t, below, continues)
    local n = cross(sub(t[2], t[1]), sub(t[3], t[1]))
    n = mul(n, 1 / math.sqrt(dot(n, n)))
    local h = math.sqrt(n[1] * n[1] + n[2] * n[2])
    if math.abs(n[3]) >= 0.7 or h * h < 0.25 then return false end
    local out = { n[1] / h, n[2] / h, 0 }
    local top = math.max(t[1][3], t[2][3], t[3][3])
    local tops = {}
    for k = 1, 3 do if t[k][3] > top - 0.5 then tops[#tops + 1] = t[k] end end
    local a, b = tops[1], tops[#tops]
    for _, s in ipairs({ 0.15, 0.5, 0.85 }) do
        local q = add(add(a, mul(sub(b, a), s)), out)
        local z = below(q[1], q[2], top + 1)
        if not z or z < top - 0.25 then return false end
    end
    if continues then
        local hi = 1
        for k = 2, 3 do if t[k][3] > t[hi][3] then hi = k end end
        local p0 = t[hi]
        for _, q in ipairs({ t[hi % 3 + 1], t[(hi + 1) % 3 + 1] }) do
            for _, s in ipairs({ 0.25, 0.5, 0.75 }) do
                local p = add(p0, mul(sub(q, p0), s))
                local f = add(p, out)
                local z = below(f[1], f[2], top + 1)
                if z and p[3] - z > 8 and continues(add(p, { 0, 0, 1 }), n, t) then return false end
            end
        end
    end
    return true
end

T.test("skategm: the surface patches are pieces of the map's own faces, open in front", function()
    local list = patchList()
    T.ok(#list >= 10, "patches: " .. #list)
    local brushes = prepare(BL.brushes(ROOT .. "/maps/petopia_bmx_fall.bsp", true))
    local faces = {}
    for _, b in ipairs(brushes) do
        if b.solid then for _, f in ipairs(b.faces) do faces[#faces + 1] = f end end
    end
    local off, shut, n, area = {}, {}, 0, 0
    for i, p in ipairs(list) do
        local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
        for _, t in ipairs(patchTris(p)) do
            n, area = n + 1, area + t.area
            for k = 1, 3 do
                for a = 1, 3 do lo[a] = math.min(lo[a], t[k][a]) hi[a] = math.max(hi[a], t[k][a]) end
            end
            -- (a sliver's normal tilts with its corners rounded in the file:
            -- the same way up is enough for one under 4 sq u)
            local home
            for _, f in ipairs(faces) do
                if dot(f.n, t.n) > (t.area < 4 and 0.9 or 0.999) and onFace(f, t[1]) and onFace(f, t[2]) and onFace(f, t[3]) then home = f break end
            end
            if not home then off[#off + 1] = string.format("%d (%.0f %.0f %.0f)", i, t[1][1], t[1][2], t[1][3]) end
            local c = mul(add(add(t[1], t[2]), t[3]), 1 / 3)
            if solidAt(brushes, add(c, mul(t.n, 0.25))) then shut[#shut + 1] = string.format("%d (%.0f %.0f %.0f)", i, c[1], c[2], c[3]) end
        end
        for a = 1, 3 do T.near(p[a], (lo[a] + hi[a]) / 2, 0.01, "patch " .. i .. " is fed by the middle of its box") end
    end
    T.ok(n > 20 and area > 100000, string.format("%d triangles, %.0f sq u", n, area))
    T.eq(#off, 0, "triangles on no face of the map: " .. table.concat(off, ", "))
    T.eq(#shut, 0, "triangles with solid right in front: " .. table.concat(shut, ", "))
end)

T.test("skategm: every transition's top that SkateGM hides is patched wherever it is open, up to its coping", function()
    local all = allPatchTris(patchList())
    -- (SkateGM's faces: from every side, bevels too; every way of fanning them)
    local brushes = prepare(BL.brushes(ROOT .. "/maps/petopia_bmx_fall.bsp"))
    local below, continues = floorIndex(brushes), wallIndex(brushes)
    local hidden, open, miss, seen = 0, 0, {}, {}
    for _, b in ipairs(brushes) do
        if b.solid then
            for _, f in ipairs(b.faces) do
                local P = f.pts
                for s = 1, #P do
                    for i = 1, #P - 2 do
                        local t = { P[s], P[(s + i - 1) % #P + 1], P[(s + i) % #P + 1] }
                        -- (a triangle comes up in several fans: once each)
                        local keys = {}
                        for k = 1, 3 do keys[k] = string.format("%.2f,%.2f,%.2f", t[k][1], t[k][2], t[k][3]) end
                        table.sort(keys)
                        local key = table.concat(keys, ";")
                        -- (and no sliver: three corners almost in a line, from a
                        -- bevel's near-twin corner, under 1 sq u or 0.5 u across;
                        -- the check passes those over too)
                        local e1, e2 = sub(t[2], t[1]), sub(t[3], t[1])
                        local c2 = cross(e1, e2)
                        local tarea = math.sqrt(dot(c2, c2)) / 2
                        local long = 0
                        for k = 1, 3 do local e = sub(t[k % 3 + 1], t[k]) long = math.max(long, math.sqrt(dot(e, e))) end
                        local sliver = tarea < 1 or 2 * tarea / long < 0.5
                        if not seen[key] and not sliver and hiddenUnderFloor(t, below, continues) then
                            seen[key] = true
                            hidden = hidden + 1
                            -- its open part, every 8 u: on a patch
                            local e1, e2 = sub(t[2], t[1]), sub(t[3], t[1])
                            local m = math.max(1, math.ceil(math.max(math.sqrt(dot(e1, e1)), math.sqrt(dot(e2, e2))) / 8))
                            local c = mul(add(add(t[1], t[2]), t[3]), 1 / 3)
                            for u = 0, m do
                                for v = 0, m - u do
                                    local p = add(c, mul(sub(add(add(t[1], mul(e1, u / m)), mul(e2, v / m)), c), 0.98))
                                    -- (open all the way out to 0.5 u in front, SkateGM's
                                    -- own reach for "in front": a point a hair from
                                    -- the coping, under it or at the lip, is the coping's)
                                    if not solidAt(brushes, add(p, mul(f.n, 0.05)), b) and not solidAt(brushes, add(p, mul(f.n, 0.25)), b)
                                        and not solidAt(brushes, add(p, mul(f.n, 0.5)), b) then
                                        open = open + 1
                                        if not onPatch(all, p, f.n) and #miss < 6 then
                                            miss[#miss + 1] = string.format("(%.0f %.0f %.1f) of (%.1f %.1f %.2f)-(%.1f %.1f %.2f)-(%.1f %.1f %.2f) n (%.2f %.2f %.2f)",
                                                p[1], p[2], p[3], t[1][1], t[1][2], t[1][3], t[2][1], t[2][2], t[2][3], t[3][1], t[3][2], t[3][3], f.n[1], f.n[2], f.n[3])
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    T.ok(hidden >= 20, "triangles SkateGM takes for hidden under a floor: " .. hidden)
    T.ok(open > 500, "points of them open to the park: " .. open)
    T.eq(#miss, 0, "open points of a hidden face with no patch: " .. table.concat(miss, " "))
end)

T.test("skategm: no patch is one SkateGM would take for hidden again", function()
    local list = patchList()
    local brushes = prepare(BL.brushes(ROOT .. "/maps/petopia_bmx_fall.bsp"))
    -- (judged as SkateGM judges an entity's faces: with the map's floors and
    -- the patches' own beside them)
    local extra = {}
    for _, t in ipairs(allPatchTris(list)) do
        if t.n[3] > 0.7 then extra[#extra + 1] = { pts = { t[1], t[2], t[3] }, n = t.n } end
    end
    local below, continues = floorIndex(brushes, extra), wallIndex(brushes)
    local again = {}
    for i, p in ipairs(list) do
        for _, t in ipairs(patchTris(p)) do
            if hiddenUnderFloor(t, below, continues) then again[#again + 1] = string.format("%d (%.0f %.0f %.0f)", i, t[1][1], t[1][2], t[1][3]) end
        end
    end
    T.eq(#again, 0, "patch triangles hidden under a floor: " .. table.concat(again, ", "))
end)

T.test("skategm: the known gaps are patched: the halfpipe's vert, a quarter pipe, a spine, the flat ramp's side", function()
    local all = allPatchTris(patchList())
    local brushes = prepare(BL.brushes(ROOT .. "/maps/petopia_bmx_fall.bsp", true))
    -- (a spot by a face, measured with the check, and the way that face looks:
    -- taken onto the BSP's own face there, then that point must be patched)
    local spots = {
        { "the halfpipe's west vert, 30 u under the coping", { 376, -752, 383 }, { 1, 0, 0.1 } },
        { "the north-west quarter pipe's top, under its coping", { 497, 696, 214 }, { 0, -0.94, 0.34 } },
        { "the south-west spine's west face, under its coping", { -42, -1496, 163 }, { -0.86, 0, 0.51 } },
        { "the flat ramp's side above the north-west quarter pipe", { 193, 669, 170 }, { 1, 0, 0 } },
    }
    for _, sp in ipairs(spots) do
        local n = mul(sp[3], 1 / math.sqrt(dot(sp[3], sp[3])))
        local at, best
        for _, b in ipairs(brushes) do
            if b.solid then
                for _, f in ipairs(b.faces) do
                    if dot(f.n, n) > 0.98 then
                        local d = dot(f.n, sp[2]) - dot(f.n, f.pts[1])
                        local q = sub(sp[2], mul(f.n, d))
                        if math.abs(d) < 3 and onFace(f, q) and (not best or math.abs(d) < best) then at, best = { q, f.n }, math.abs(d) end
                    end
                end
            end
        end
        T.ok(at, sp[1] .. ": a face of the map there")
        if at then T.ok(onPatch(all, at[1], at[2]), sp[1]) end
    end
end)

-- KNOWN, LEFT: funbox 2's west slope stays cracked along its corners in
-- SkateGM (it builds faces from vbsp's bevel planes too; up to ~100 sq u
-- triangles missing). A patch cannot mend a slope one can stand on: SkateGM
-- finds an entity's grind rails from the entity's own triangles alone, so every
-- edge of a walkable patch, with no ground of its own past it, became a rail
-- across the slope (five, measured). Mended by SkateGM taking only a brush's
-- real sides (vbsp marks the bevels), or a funbox 2 vbsp adds no near-twin
-- bevel to (a BSP rebuild).
T.test("skategm: no patch is a surface one can stand on (SkateGM would grow rails along its edges)", function()
    for i, p in ipairs(patchList()) do
        for _, t in ipairs(patchTris(p)) do
            T.ok(t.n[3] <= 0.65, string.format("patch %d: a triangle turned up %.2f", i, t.n[3]))
        end
    end
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
        -- (the surface patches are fed too: their own test, below)
        if name:sub(1, #SK.SURFACE) ~= SK.SURFACE then
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
    end
    -- the far ones are not fed
    local far = 0
    for _, e in ipairs(made) do
        if e:GetPos():DistToSqr(env.Vector(1664, -512, 80)) >= SK.RADIUS * SK.RADIUS then far = far + 1 end
    end
    T.eq(fed + far, #made, "every collider fed, or out of SkateGM's reach")
end)

T.test("skategm: the surface patches go to SkateGM as meshes, wound as given, those within its reach", function()
    local env, S = skateClient()
    local SK = env.BMX.City.SkateGM
    SK.Install(S)
    local list = patchList()
    T.eq(#SK.patches, #list, "every patch loaded on the client")
    -- a skater mid-park: all of them (the park is under 2500 u from its middle)
    local fed, sig = {}, {}
    S.ExtraFeeds[1](env.Vector(1664, -512, 80), fed, sig)
    local got = {}
    for _, item in ipairs(fed) do
        if item[1]:sub(1, #SK.SURFACE) == SK.SURFACE then
            got[#got + 1] = item
            T.ok(item[2] == 0 and item[3] == 0 and item[4] == 0 and item[5] == 0 and item[6] == 0 and item[7] == 0,
                item[1] .. " placed at the world's origin, unturned")
        end
    end
    local near = 0
    for _, p in ipairs(list) do
        local dx, dy, dz = p[1] - 1664, p[2] + 512, p[3] - 80
        if dx * dx + dy * dy + dz * dz < SK.RADIUS * SK.RADIUS then near = near + 1 end
    end
    T.eq(#got, near, "the patches within reach fed: " .. #got)
    T.ok(near >= #list - 2, "nearly all of the park's from its middle")
    for i, p in ipairs(list) do
        local name = SK.SURFACE .. i
        local hulls, isMesh, from = S.HullProviders[1](name)
        T.eq(isMesh, true, name .. " is a mesh (SkateGM's DefineModel mode 1: wound as given)")
        T.eq(#hulls, 1, name .. ": one soup")
        T.eq(#hulls[1], #p - 3, name .. ": the file's triangles")
        T.eq(hulls[1][1], p[4], name .. ": in the file's order")
        T.ok(type(from) == "string", name .. " says what it is")
    end
    -- far from the park: none
    local far = {}
    S.ExtraFeeds[1](env.Vector(20000, 20000, 80), far, {})
    for _, item in ipairs(far) do
        T.ok(item[1]:sub(1, #SK.SURFACE) ~= SK.SURFACE, "nothing of the park's surface fed from 20000 u away")
    end
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
