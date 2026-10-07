--[[--------------------------------------------------------------------------
    tests/bsplight.lua

    Reads the baked light out of a compiled BSP (plain Lua 5.1, no GMod):
    every lightmapped face's luxels, each placed back in the world, so a test
    can ask how bright any part of the park actually is after vrad.

        local BL = require("bsplight")
        local bsp = BL.load("maps/petopia_bmx_fall.bsp")
        for _, s in ipairs(bsp.samples) do  -- s.x, s.y, s.z, s.nz, s.lum, s.mat
        local grid = BL.grid(bsp, box, 128)  -- cells of samples by layer

    Run directly for a map of the park in the terminal:

        lua5.1 tests/bsplight.lua maps/petopia_bmx_fall.bsp

    `lum` is the luxel's linear luminance on the 0..255 scale the BSP stores
    (ColorRGBExp32: rgb * 2^exp). The LDR lightmaps (lumps 7 and 8) are read;
    the HDR ones come from the same lights.
----------------------------------------------------------------------------]]

local BL = {}

local byte, floor, ldexp = string.byte, math.floor, math.ldexp

local function u8(d, o) return byte(d, o + 1) end
local function u16(d, o) local a, b = byte(d, o + 1, o + 2) return a + b * 256 end
local function i16(d, o) local v = u16(d, o) return v >= 32768 and v - 65536 or v end
local function i32(d, o)
    local a, b, c, e = byte(d, o + 1, o + 4)
    local v = a + b * 256 + c * 65536 + e * 16777216
    return v >= 2147483648 and v - 4294967296 or v
end
local function f32(d, o)
    local a, b, c, e = byte(d, o + 1, o + 4)
    local sign = e >= 128 and -1 or 1
    local exp = (e % 128) * 2 + floor(c / 128)
    local man = (c % 128) * 65536 + b * 256 + a
    if exp == 0 then
        if man == 0 then return 0 * sign end
        return sign * ldexp(man, -149)
    elseif exp == 255 then
        return man == 0 and sign * math.huge or 0 / 0
    end
    return sign * ldexp(man + 8388608, exp - 150)
end

BL.GAP = 24

local function lump(d, i)
    local o = 8 + i * 16
    return i32(d, o), i32(d, o + 4)
end

-- 3x3 solve by Cramer's rule: rows a, b, c (each {x, y, z}), rhs r
local function solve(a, b, c, r)
    local det = a[1] * (b[2] * c[3] - b[3] * c[2]) - a[2] * (b[1] * c[3] - b[3] * c[1]) + a[3] * (b[1] * c[2] - b[2] * c[1])
    if math.abs(det) < 1e-9 then return nil end
    local function d3(p, q, s)
        return p[1] * (q[2] * s[3] - q[3] * s[2]) - p[2] * (q[1] * s[3] - q[3] * s[1]) + p[3] * (q[1] * s[2] - q[2] * s[1])
    end
    local col = { { r[1], a[2], a[3] }, { r[2], b[2], b[3] }, { r[3], c[2], c[3] } }
    local x = d3(col[1], col[2], col[3]) / det
    col = { { a[1], r[1], a[3] }, { b[1], r[2], b[3] }, { c[1], r[3], c[3] } }
    local y = d3(col[1], col[2], col[3]) / det
    col = { { a[1], a[2], r[1] }, { b[1], b[2], r[2] }, { c[1], c[2], r[3] } }
    local z = d3(col[1], col[2], col[3]) / det
    return x, y, z
end

function BL.parse(d)
    assert(d:sub(1, 4) == "VBSP", "not a VBSP file")
    local out = { version = i32(d, 4), samples = {}, faces = 0 }
    -- planes (20 bytes: normal, dist, type)
    local po, pl = lump(d, 1)
    local planes = {}
    for i = 0, pl / 20 - 1 do
        local o = po + i * 20
        planes[i] = { f32(d, o), f32(d, o + 4), f32(d, o + 8), f32(d, o + 12) }
    end
    -- material names: texdata (32 bytes) -> string table -> string data
    local sdo = lump(d, 43)
    local sto = lump(d, 44)
    local tdo, tdl = lump(d, 2)
    local texname = {}
    for i = 0, tdl / 32 - 1 do
        local id = i32(d, tdo + i * 32 + 12)
        local s = sdo + i32(d, sto + id * 4)
        local e = d:find("\0", s + 1, true)
        texname[i] = d:sub(s + 1, e - 1):upper()
    end
    -- texinfo (72 bytes): texture vecs, lightmap vecs, flags, texdata
    local to, tl = lump(d, 6)
    local tex = {}
    for i = 0, tl / 72 - 1 do
        local o = to + i * 72
        local v = {}
        for k = 1, 16 do v[k] = f32(d, o + (k - 1) * 4) end
        tex[i] = { s = { v[9], v[10], v[11], v[12] }, t = { v[13], v[14], v[15], v[16] },
                   flags = i32(d, o + 64), mat = texname[i32(d, o + 68)] or "?" }
    end
    -- face outlines: vertexes (12 bytes), edges (2 x u16), surfedges (i32)
    local vo = lump(d, 3)
    local eo = lump(d, 12)
    local so = lump(d, 13)
    local function outline(o)
        local first, count = i32(d, o + 4), i16(d, o + 8)
        local pts = {}
        for k = 0, count - 1 do
            local se = i32(d, so + (first + k) * 4)
            local v = se >= 0 and u16(d, eo + se * 4) or u16(d, eo + (-se) * 4 + 2)
            local q = vo + v * 12
            pts[#pts + 1] = { f32(d, q), f32(d, q + 4), f32(d, q + 8) }
        end
        return pts
    end
    -- Is (x, y, z), on the face's plane, inside its outline (to `tol` units)?
    -- A lightmap is a rectangle; the luxels past a sloped or triangular
    -- face's edges are never lit, and must not count as dark.
    local function inside(pts, n, x, y, z, tol)
        local pos, neg = true, true
        for k = 1, #pts do
            local a, b = pts[k], pts[k % #pts + 1]
            local ex, ey, ez = b[1] - a[1], b[2] - a[2], b[3] - a[3]
            local px, py, pz = x - a[1], y - a[2], z - a[3]
            local c = (ey * pz - ez * py) * n[1] + (ez * px - ex * pz) * n[2] + (ex * py - ey * px) * n[3]
            local len = math.sqrt(ex * ex + ey * ey + ez * ez)
            if len > 0 then
                c = c / len
                if c < -tol then pos = false end
                if c > tol then neg = false end
            end
        end
        return pos or neg
    end

    local lo = lump(d, 8)
    local fo, fl = lump(d, 7)
    local walls = {}   -- the upright faces, for finding slots between them
    for i = 0, fl / 56 - 1 do
        local o = fo + i * 56
        local lofs = i32(d, o + 20)
        local style0 = u8(d, o + 16)
        if lofs >= 0 and style0 == 0 then
            local p = planes[u16(d, o)]
            -- the face's own plane: its normal is the face's (vrad reads it
            -- the same way; dface_t.side is not a flip here)
            local n = { p[1], p[2], p[3] }
            local dist = p[4]
            local t = tex[i16(d, o + 10)]
            local mx, my = i32(d, o + 28), i32(d, o + 32)
            local wx, wy = i32(d, o + 36), i32(d, o + 40)
            local rs, rt = { t.s[1], t.s[2], t.s[3] }, { t.t[1], t.t[2], t.t[3] }
            local pts = outline(o)
            local face = { n = n, dist = dist, pts = pts, samples = {} }
            if math.abs(n[3]) < 0.3 then
                local lo3, hi3 = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
                for _, q in ipairs(pts) do
                    for a = 1, 3 do lo3[a] = math.min(lo3[a], q[a]) hi3[a] = math.max(hi3[a], q[a]) end
                end
                face.lo, face.hi = lo3, hi3
                walls[#walls + 1] = face
            end
            out.faces = out.faces + 1
            for tt = 0, wy do
                for ss = 0, wx do
                    local x, y, z = solve(rs, rt, n, { ss + mx - t.s[4], tt + my - t.t[4], dist })
                    if x and inside(pts, n, x, y, z, 1) then
                        local k = lo + lofs + (tt * (wx + 1) + ss) * 4
                        local r, g, b, e = byte(d, k + 1, k + 4)
                        if e >= 128 then e = e - 256 end
                        local smp = {
                            x = x, y = y, z = z, nx = n[1], ny = n[2], nz = n[3], mat = t.mat,
                            lum = ldexp(0.299 * r + 0.587 * g + 0.114 * b, e),
                        }
                        out.samples[#out.samples + 1] = smp
                        face.samples[#face.samples + 1] = smp
                    end
                end
            end
        end
    end
    -- A slot: an upright face with another facing it less than BL.GAP units
    -- in front (two ramps built a hair apart). Nobody can see into one.
    for _, f in ipairs(walls) do
        for _, g in ipairs(walls) do
            local dn = f.n[1] * g.n[1] + f.n[2] * g.n[2] + f.n[3] * g.n[3]
            if dn < -0.99 then
                -- g's plane, seen from f: how far in front of f it stands
                local gap = -g.dist - f.dist   -- n_f = -n_g: distance along n_f
                if gap > -0.5 and gap < BL.GAP then
                    for _, smp in ipairs(f.samples) do
                        local p = { smp.x, smp.y, smp.z }
                        local ok = true
                        for a = 1, 3 do
                            if math.abs(f.n[a]) < 0.5 and (p[a] < g.lo[a] - 1 or p[a] > g.hi[a] + 1) then ok = false end
                        end
                        if ok then smp.slot = true end
                    end
                end
            end
        end
    end
    return out
end

function BL.load(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a")
    f:close()
    return BL.parse(d)
end

-- Which layer of the park a sample belongs to:
--   "floor"  the ground (the city's floor overlay covers it, but with the
--            city off it is what riders see)
--   "ride"   the tops and slopes of the ramps
--   "side"   the vertical sides and backs of the ramps
-- nil for what nobody sees from the park: the walls (hidden by the city's
-- facades), undersides, anything outside the box, a face turned to a wall
-- less than SLOT units away (the back of a ramp in a slot against the wall),
-- and a face in a slot less than GAP wide between two ramps: no camera in
-- the park can get in front of those.
BL.SLOT = 128
function BL.layer(s, box, floorZ)
    local x0, y0, x1, y1 = box[1], box[2], box[3], box[4]
    if s.x < x0 - 1 or s.x > x1 + 1 or s.y < y0 - 1 or s.y > y1 + 1 then return nil end
    if s.mat:find("BRICK", 1, true) then return nil end
    if s.nz < -0.3 or s.slot then return nil end
    if (s.nx < -0.5 and s.x - x0 < BL.SLOT) or (s.nx > 0.5 and x1 - s.x < BL.SLOT)
        or (s.ny < -0.5 and s.y - y0 < BL.SLOT) or (s.ny > 0.5 and y1 - s.y < BL.SLOT) then
        return nil
    end
    if s.nz > 0.3 then
        if s.z < floorZ + 2 then return "floor" end
        return "ride"
    end
    if s.z < floorZ + 2 then return nil end
    return "side"
end

-- Cells of `size` units over box {x0, y0, x1, y1}: each a table of layer ->
-- { n, sum, min, max, mean, list }. Keyed cells[ix][iy], ix/iy from 0.
function BL.grid(bsp, box, size, floorZ)
    local nx = math.ceil((box[3] - box[1]) / size)
    local ny = math.ceil((box[4] - box[2]) / size)
    local cells = { nx = nx, ny = ny, size = size, box = box }
    for ix = 0, nx - 1 do
        cells[ix] = {}
        for iy = 0, ny - 1 do cells[ix][iy] = {} end
    end
    for _, s in ipairs(bsp.samples) do
        local L = BL.layer(s, box, floorZ)
        if L then
            local ix = math.min(nx - 1, math.max(0, floor((s.x - box[1]) / size)))
            local iy = math.min(ny - 1, math.max(0, floor((s.y - box[2]) / size)))
            local c = cells[ix][iy]
            local a = c[L]
            if not a then a = { n = 0, sum = 0, min = math.huge, max = 0, list = {} } c[L] = a end
            a.n, a.sum = a.n + 1, a.sum + s.lum
            if s.lum < a.min then a.min = s.lum end
            if s.lum > a.max then a.max = s.lum end
            a.list[#a.list + 1] = s.lum
        end
    end
    for ix = 0, nx - 1 do
        for iy = 0, ny - 1 do
            for _, a in pairs(cells[ix][iy]) do
                a.mean = a.sum / a.n
                table.sort(a.list)
                a.p95 = a.list[math.max(1, math.ceil(#a.list * 0.95))]
                a.median = a.list[math.max(1, math.ceil(#a.list * 0.5))]
            end
        end
    end
    return cells
end

-- The park as text, north up: one character per cell, by the darkest layer's
-- median (space = black ... @ = blown out).
function BL.map(cells, layer)
    local chars = " .:-=+*#%@"
    local rows = {}
    for iy = cells.ny - 1, 0, -1 do
        local row = {}
        for ix = 0, cells.nx - 1 do
            local c = cells[ix][iy]
            local v
            if layer then v = c[layer] and c[layer].median
            else
                for _, a in pairs(c) do if not v or a.median < v then v = a.median end end
            end
            if not v then row[#row + 1] = "?"
            else row[#row + 1] = chars:sub(math.min(10, floor(v / 25) + 1), math.min(10, floor(v / 25) + 1)) end
        end
        rows[#rows + 1] = string.format("%6d %s", cells.box[2] + iy * cells.size, table.concat(row))
    end
    return table.concat(rows, "\n")
end

if arg and arg[0] and arg[0]:match("bsplight%.lua$") and arg[1] then
    local bsp = BL.load(arg[1])
    local box = { -256, -1792, 3584, 768 }
    local cells = BL.grid(bsp, box, 128, 64)
    for _, L in ipairs({ "floor", "ride", "side" }) do
        local lo, hi, n = math.huge, 0, 0
        for ix = 0, cells.nx - 1 do for iy = 0, cells.ny - 1 do
            local a = cells[ix][iy][L]
            if a then n = n + 1 lo = math.min(lo, a.median) hi = math.max(hi, a.p95) end
        end end
        print(string.format("%s: %d cells, darkest cell median %.1f, brightest cell p95 %.1f", L, n, lo, hi))
        print(BL.map(cells, L))
    end
end

return BL
