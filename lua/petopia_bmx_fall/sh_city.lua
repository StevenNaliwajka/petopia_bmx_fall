--[[--------------------------------------------------------------------------
    lua/petopia_bmx_fall/sh_city.lua

    The city around the park: buildings on every side instead of a bare wall,
    rising into a skyline, with elevated subway viaducts crossing overhead and
    trains running over them.

    WHY IT IS BUILT IN LUA AND NOT IN HAMMER. The park maps are somebody else's
    BSPs (gm_skatepark is a Workshop map), and a map cannot be edited without
    decompiling, recompiling and redistributing it. Everything here is drawn and
    collided from the addon instead, from a per-map DEFINITION (see
    sh_city_maps.lua), so "make the world bigger" is editing a table.

    HOW A WHOLE CITY FITS AROUND A SEALED BOX MAP. gm_skatepark is one box: a
    brick wall to z=528 and toolsskybox above it. Sky faces are not drawn as
    geometry -- the sky shows through where nothing else wrote -- so geometry
    OUTSIDE the box is visible from inside it as long as somebody draws it.
    The engine will not (entities out in the void have no visleaf), so
    cl_city.lua draws the meshes itself, from a render hook.

    So the frontage stands on the wall line, its facade a few units inside the
    park so it covers the brick, and every building's body lies out in the
    void. Nothing out there can be reached -- the wall and the sky brushes are
    solid -- so the buildings need no collision at all. The parts that ARE
    inside the box (the viaducts and the piers that hold them up) are made solid
    by bmx_city_solid entities, server and client both.

    DETERMINISM. Layout is generated from a seed with a private generator (never
    math.random), so the server's colliders, every client's meshes and the
    offline tests all build the same city, every session.

    OUTPUT. BMX.City.Build(def) returns plain numbers, not Vectors, so it runs
    as fast in the test shim as in the game:
        layout.faces[mat]  = { {x1,y1,z1, x2,y2,z2, x3,y3,z3, x4,y4,z4,
                                u1,v1, u2,v2, shade, group}, ... }   (quads, TL TR BR BL)
                             group: which part of the city ("via:line1",
                             "front:north", "sky:3"...), so the client can
                             draw near parts first and skip ones out of view
        layout.solids      = { {name, {x0,y0,z0, x1,y1,z1}, ...}, ... }
        layout.lines       = subway lines the trains run on
        layout.signs       = text panels
        layout.buildings   = the boxes, for tests and bmx_city_info
----------------------------------------------------------------------------]]

BMX = BMX or {}
BMX.City = BMX.City or {}
local City = BMX.City

City.Maps = City.Maps or {}

-- 1 texel = 0.25 units, the scale HL2 itself lays building_template at, which
-- makes one 512-pixel panel one 128-unit floor: a Source storey.
City.FLOOR = 128

--------------------------------------------------------------------------
-- Materials. Every surface the city can use, with the size in world units of
-- one repeat of its texture. `alpha` materials are alpha-tested (the truss
-- panels are mostly holes). cl_city.lua turns each into an UnlitGeneric copy:
-- the HL2 originals are LightmappedGeneric, which has no lightmap on a mesh.
--------------------------------------------------------------------------
local function bt(id, w, h) return { tex = "building_template/building_template" .. id, w = w or 128, h = h or 128 } end

City.Materials = {
    -- brick
    brick_plain = bt("001a"), brick_win = bt("001b"), brick_board = bt("001d"),
    brick_door = bt("001h"), brick_trim = bt("001k", 128, 32),
    -- white stone
    white_plain = bt("002a"), white_win = bt("002b"), white_win2 = bt("002c"),
    white_door = bt("002e"), white_win3 = bt("002n"), white_trim = bt("002k", 128, 32),
    white_niche = bt("002f"),
    -- grey stone
    grey_plain = bt("003a"), grey_win = bt("003d"), grey_win2 = bt("003e"),
    grey_arch = bt("003o"), grey_shop = bt("003j"), grey_trim = bt("003i", 128, 32),
    -- pediments
    ped_plain = bt("004a"), ped_win = bt("004b"), ped_win2 = bt("004d"),
    ped_shutter = bt("004c"), ped_trim = bt("004f", 128, 32),
    -- yellow render
    yel_plain = bt("005a"), yel_arch = bt("005b"), yel_win = bt("005l"),
    yel_arch2 = bt("005j"), yel_trim = bt("005g", 128, 32),
    olive_win = bt("005c"), olive_win2 = bt("005d"),
    -- modern
    glass_grey = bt("006a"), glass_dark = bt("006b"), conc_plain = bt("007a"),
    conc_ribbon = bt("007b"), conc_ribbon2 = bt("007c"), conc_ribbon3 = bt("007h"),
    conc_shop = bt("010b"), conc_shop2 = bt("010c"), glass_black = bt("009e"),
    -- red brick
    -- (010h and 010i are boarded-up windows; 011b is the plain red brick)
    red_plain = bt("010h"), red_arch = bt("010i"), red_arch2 = bt("011b"), red_brick = bt("011b"),
    red_shutter = bt("011c", 128, 128),
    -- ochre
    ochre_plain = bt("012a"), ochre_win = bt("012b"), ochre_win2 = bt("012g"),
    ochre_win3 = bt("012h"), ochre_door = bt("012l"),
    -- tan classical
    tan_plain = bt("013a"), tan_win = bt("013b"), tan_win2 = bt("013c"),
    tan_door = bt("013g"), tan_arch = bt("013f"),
    -- dark render, big windows
    dark_plain = bt("021a"), dark_win = bt("021c"), dark_win2 = bt("021b"),
    dark_win3 = bt("021h"),
    cream_plain = bt("022a"), cream_win = bt("022c"), cream_win2 = bt("022b"),
    cream_ribbon = bt("022g"),
    -- stone classical
    stone_plain = bt("029a"), stone_win = bt("029b"), stone_arch = bt("029d"),
    stone_tall = bt("029f"), stone_door = bt("028d"), stone_trim = bt("029i", 128, 32),

    -- roofs and structure
    roof = { tex = "building_template/roof_template001a", w = 256, h = 256 },
    roof2 = { tex = "building_template/roof_template001b", w = 256, h = 256 },
    concrete = { tex = "concrete/concretewall022a", w = 128, h = 128 },
    concrete2 = { tex = "concrete/concretewall010a", w = 128, h = 128 },
    steel = { tex = "metal/metalwall048a", w = 128, h = 128 },
    girder = { tex = "metal/metaltruss015a", w = 256, h = 64, alpha = true },
    truss = { tex = "metal/metaltruss011a", w = 224, h = 224, alpha = true },
    grate = { tex = "metal/metalgrate016a", w = 128, h = 128, alpha = true },
    black = { tex = "vgui/white", w = 128, h = 128, color = { 0.02, 0.02, 0.025 } },
    signpanel = { tex = "vgui/white", w = 128, h = 128, color = { 0.07, 0.08, 0.1 } },
    -- a sign's case (painted steel) and a floodlight's lens
    signcase = { tex = "metal/metalwall048a", w = 128, h = 128, color = { 0.42, 0.42, 0.45 } },
    lamplens = { tex = "vgui/white", w = 128, h = 128, color = { 1.0, 0.93, 0.74 }, lit = true },

    -- greenery: planting beds, roof gardens, ivy. It is late autumn: the
    -- ivy art is green, so `mul` (the material's $color, which may go past 1
    -- where a vertex colour cannot) turns it to the reds and golds of a New
    -- England fall. 01 and 02 hang from their top edge, 03 climbs from its
    -- bottom edge; 512 px each, alpha in the texture.
    grass = { tex = "nature/grassfloor002a", w = 128, h = 128, mul = { 1.25, 1.0, 0.55 } },
    soil = { tex = "nature/dirtfloor006a", w = 128, h = 128 },
    ivy_hang = { tex = "decals/ivy01", w = 128, h = 128, alpha = true, mul = { 2.1, 0.75, 0.4 } },
    ivy_hang2 = { tex = "decals/ivy02", w = 128, h = 128, alpha = true, mul = { 1.9, 1.15, 0.4 } },
    ivy_climb = { tex = "decals/ivy03", w = 128, h = 128, alpha = true, mul = { 2.2, 0.8, 0.4 } },
    -- the bushes and hedges: the same leaves on crossed cards, in four colours
    leaves_red = { tex = "decals/ivy03", w = 128, h = 128, alpha = true, mul = { 2.4, 0.62, 0.38 } },
    leaves_orange = { tex = "decals/ivy03", w = 128, h = 128, alpha = true, mul = { 2.3, 1.1, 0.34 } },
    leaves_gold = { tex = "decals/ivy03", w = 128, h = 128, alpha = true, mul = { 2.2, 1.38, 0.3 } },
    leaves_rust = { tex = "decals/ivy03", w = 128, h = 128, alpha = true, mul = { 1.55, 0.78, 0.36 } },
    -- fallen leaves on the ground: the leaf art again, flat, in drifts
    litter_red = { tex = "decals/ivy03", w = 128, h = 128, alpha = true, mul = { 2.0, 0.6, 0.35 } },
    litter_orange = { tex = "decals/ivy03", w = 128, h = 128, alpha = true, mul = { 2.1, 1.05, 0.35 } },
    litter_brown = { tex = "decals/ivy03", w = 128, h = 128, alpha = true, mul = { 1.4, 0.85, 0.45 } },
    -- the park floor, laid over the map's one concrete slab
    slab = { tex = "concrete/concretefloor016a", w = 256, h = 256 },
    pave_brick = { tex = "brick/brickfloor001a", w = 128, h = 128 },
    -- the paths across the beds to the shop doors
    path = { tex = "brick/brickfloor001a", w = 64, h = 64 },
    pave_cobble = { tex = "stone/stonefloor011a", w = 192, h = 192 },
    kerbline = { tex = "concrete/concretewall010a", w = 64, h = 64 },
    rail = { tex = "metal/metalgrate016a", w = 64, h = 64, alpha = true },
}

--------------------------------------------------------------------------
-- Plants: the models the greenery is made of. Only models that ship in
-- GMod's own VPKs (hl2_misc, garrysmod), never content_hl2: a player without
-- HL2 mounted would see ERROR signs. r and h are the model's reach and
-- height in units, measured on the server (OBBMins/OBBMaxs), for culling.
--------------------------------------------------------------------------
City.Plants = {
    tree       = { model = "models/props_foliage/tree_deciduous_01a.mdl", r = 215, h = 436 },
    tree2      = { model = "models/props_foliage/tree_springers_01a.mdl", r = 215, h = 436 },
    tree_small = { model = "models/props_foliage/tree_deciduous_03a.mdl", r = 130, h = 250 },
    sapling    = { model = "models/props_foliage/tree_deciduous_03b.mdl", r = 85, h = 137 },
    poplar     = { model = "models/props_foliage/tree_poplar_01.mdl", r = 185, h = 1120 },
    -- not a plant, but drawn the same way; `still`: no swaying in the wind
    lamp       = { model = "models/props_c17/lamppost03a_on.mdl", r = 110, h = 450, still = true },
}
-- lamppost03a_on: 450 tall; its lamp head hangs off the arm along the
-- model's +y, from 69 to 105 out, its glowing underside (the
-- lamppost03a_glow lens) at z 441 (read from the model's own vertices,
-- props_c17/lamppost03a_on.vvd, 2026-10-07). The glow goes just under the
-- lens, at its middle -- it used to sit at 420, a foot under the lamp.
City.LAMP = { reach = 87, height = 438 }
City.LITTER = { "litter_red", "litter_orange", "litter_brown", "litter_orange" }
City.LEAF_COLOURS = { "leaves_red", "leaves_orange", "leaves_gold", "leaves_rust", "leaves_orange" }

--------------------------------------------------------------------------
-- Building styles: what goes on the street floor, the floors above, and the
-- cornice. `win` lists window panels; a building picks one as its main panel
-- and may pick a second as an accent column.
--------------------------------------------------------------------------
City.Styles = {
    brick  = { ground = { "brick_door", "brick_board" }, win = { "brick_win" },
               plain = "brick_plain", trim = "brick_trim" },
    white  = { ground = { "white_door", "white_niche", "white_plain" }, win = { "white_win", "white_win2", "white_win3" },
               plain = "white_plain", trim = "white_trim" },
    grey   = { ground = { "grey_shop", "grey_arch" }, win = { "grey_win", "grey_win2" },
               plain = "grey_plain", trim = "grey_trim" },
    ped    = { ground = { "stone_door", "ped_shutter" }, win = { "ped_win", "ped_win2", "ped_shutter" },
               plain = "ped_plain", trim = "ped_trim" },
    yellow = { ground = { "ochre_door", "yel_arch2" }, win = { "yel_win", "yel_arch", "olive_win" },
               plain = "yel_plain", trim = "yel_trim" },
    ochre  = { ground = { "ochre_door", "ochre_win2" }, win = { "ochre_win", "ochre_win2", "ochre_win3" },
               plain = "ochre_plain", trim = "yel_trim" },
    tan    = { ground = { "tan_door", "tan_arch" }, win = { "tan_win", "tan_win2" },
               plain = "tan_plain", trim = "grey_trim" },
    red    = { ground = { "red_shutter", "red_arch2" }, win = { "red_arch" },
               plain = "red_brick", trim = "brick_trim" },
    stone  = { ground = { "stone_door", "stone_arch" }, win = { "stone_win", "stone_tall" },
               plain = "stone_plain", trim = "stone_trim" },
    dark   = { ground = { "conc_shop", "conc_shop2" }, win = { "dark_win", "dark_win2", "dark_win3" },
               plain = "dark_plain", trim = "grey_trim" },
    cream  = { ground = { "conc_shop2", "conc_shop" }, win = { "cream_win", "cream_win2", "cream_ribbon" },
               plain = "cream_plain", trim = "white_trim" },
    office = { ground = { "conc_shop", "conc_shop2" }, win = { "conc_ribbon", "conc_ribbon2", "conc_ribbon3" },
               plain = "conc_plain", trim = "grey_trim" },
    glass  = { ground = { "conc_shop2", "conc_shop" }, win = { "glass_grey", "glass_dark", "glass_black" },
               plain = "conc_plain", trim = "grey_trim" },
}

-- The building_template panels with no window, door or opening in them
-- (looked at, 2026-10-07): every style's `plain` must be one, since a plain
-- panel is what stands behind a sign (tests/test_signs.lua).
City.WindowlessPanels = { "001a", "002a", "003a", "004a", "005a", "007a", "011b", "012a", "013a",
                          "021a", "022a", "029a" }

--------------------------------------------------------------------------
-- A seeded generator: Park-Miller minimal standard. Exact in doubles
-- (16807 * 2^31 < 2^53), so every realm and the test shim agree bit for bit.
--------------------------------------------------------------------------
local function Rng(seed)
    local s = math.floor(seed) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    local r = {}
    function r.float() s = (s * 16807) % 2147483647 return (s - 1) / 2147483646 end
    function r.int(a, b) return a + math.floor(r.float() * (b - a + 1)) end
    function r.pick(t) return t[r.int(1, #t)] end
    function r.chance(p) return r.float() < p end
    return r
end
City.Rng = Rng

--------------------------------------------------------------------------
-- The builder.
--------------------------------------------------------------------------
local B = {}
B.__index = B
City.Builder = B      -- for the tests (tests/test_signs.lua turns the window blanking off)

local function newBuilder(def)
    local b = setmetatable({ def = def, faces = {}, solids = {}, lines = {}, signs = {},
                             buildings = {}, props = {}, lamps = {}, quads = 0 }, B)
    local v = def.view or def.park
    b.view = { v[1], v[2], v[3], v[4], v[5], v[6] }
    -- The sun, from the map's light_environment: shading is baked into vertex
    -- colour, so a face turned to the sun is lit and the far sides are not.
    local p, y = math.rad(def.sunPitch or 30), math.rad(def.sunYaw or 0)
    b.sun = { math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), math.sin(p) }
    return b
end

-- Is any point of the viewing volume in front of this plane? A face nobody
-- inside the park can ever see the front of is never emitted: the backs of
-- buildings, the floors, the far sides of piers.
function B:facing(px, py, pz, nx, ny, nz)
    local v = self.view
    local mx = nx > 0 and v[4] or v[1]
    local my = ny > 0 and v[5] or v[2]
    local mz = nz > 0 and v[6] or v[3]
    return (mx - px) * nx + (my - py) * ny + (mz - pz) * nz > 0.5
end

-- A face's light: roofs full, undersides deep in shade, walls by how
-- squarely they face the low sun. The spread between a sunlit wall and one
-- turned away is what gives the city its late-afternoon contrast (it was
-- 0.62..0.98, and every street read the same flat bright).
function B:shade(nx, ny, nz, tint)
    local s = self.sun
    local d = nx * s[1] + ny * s[2] + nz * s[3]
    local k
    if nz > 0.5 then k = 0.94
    elseif nz < -0.5 then k = 0.36
    else k = 0.58 + 0.4 * math.max(d, 0) - 0.1 * math.max(-d, 0) end
    return k * (tint or 1)
end

-- One quad from its top-left corner `o`, a unit right axis `u` and a unit down
-- axis `w`, `len` along u and `hgt` along w. Texture coordinates are in
-- repeats of the material's size, offset by (u0, v0) units, so panels line up
-- across seams.
function B:quad(mat, o, u, w, len, hgt, n, tint, u0, v0, cull)
    if len <= 0.01 or hgt <= 0.01 then return end
    if cull ~= false and not self:facing(o[1], o[2], o[3], n[1], n[2], n[3]) then return end
    local M = City.Materials[mat]
    if not M then error("BMX city: no material " .. tostring(mat), 2) end
    local list = self.faces[mat]
    if not list then list = {} self.faces[mat] = list end
    local x1, y1, z1 = o[1], o[2], o[3]
    local x2, y2, z2 = x1 + u[1] * len, y1 + u[2] * len, z1 + u[3] * len
    local x4, y4, z4 = x1 + w[1] * hgt, y1 + w[2] * hgt, z1 + w[3] * hgt
    local x3, y3, z3 = x2 + w[1] * hgt, y2 + w[2] * hgt, z2 + w[3] * hgt
    u0, v0 = u0 or 0, v0 or 0
    list[#list + 1] = { x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4,
        u0 / M.w, v0 / M.h, (u0 + len) / M.w, (v0 + hgt) / M.h,
        self:shade(n[1], n[2], n[3], tint), self.group or "misc" }
    self.quads = self.quads + 1
end

-- The four vertical faces of an axis-aligned box, as {origin(top-left), right,
-- normal, length}. Right is (-n) x up: the viewer's right looking at the face.
local function sides(x0, y0, x1, y1, z)
    return {
        { o = { x0, y0, z }, u = { 1, 0, 0 },  n = { 0, -1, 0 }, len = x1 - x0 },  -- -y face
        { o = { x1, y1, z }, u = { -1, 0, 0 }, n = { 0, 1, 0 },  len = x1 - x0 },  -- +y face
        { o = { x0, y1, z }, u = { 0, -1, 0 }, n = { -1, 0, 0 }, len = y1 - y0 },  -- -x face
        { o = { x1, y0, z }, u = { 0, 1, 0 },  n = { 1, 0, 0 },  len = y1 - y0 },  -- +x face
    }
end
City.Sides = sides

local DOWN = { 0, 0, -1 }

-- A plain box: every visible face in one material (or {side=, top=, bottom=}).
function B:box(x0, y0, z0, x1, y1, z1, mats, tint)
    if type(mats) == "string" then mats = { side = mats, top = mats, bottom = mats } end
    for _, s in ipairs(sides(x0, y0, x1, y1, z1)) do
        self:quad(mats.side, s.o, s.u, DOWN, s.len, z1 - z0, s.n, tint, 0, 0)
    end
    if mats.top then
        self:quad(mats.top, { x0, y1, z1 }, { 1, 0, 0 }, { 0, -1, 0 }, x1 - x0, y1 - y0, { 0, 0, 1 }, tint)
    end
    if mats.bottom then
        self:quad(mats.bottom, { x0, y0, z0 }, { 1, 0, 0 }, { 0, 1, 0 }, x1 - x0, y1 - y0, { 0, 0, -1 }, tint)
    end
end

function B:solid(name, x0, y0, z0, x1, y1, z1)
    local s = self.solids[name]
    if not s then s = { name = name, boxes = {} } self.solids[name] = s self.solids[#self.solids + 1] = s end
    s.boxes[#s.boxes + 1] = { x0, y0, z0, x1, y1, z1 }
end

--------------------------------------------------------------------------
-- A facade: one vertical face of a building, in floors of City.FLOOR.
--
--   street floor   the style's ground panels, a door every few bays
--   upper floors   one window panel, with an optional accent column
--   cornice        a trim band that sticks out, with a dark underside
--
-- `fromZ` skips everything below it: a side face hidden by the neighbour
-- beside it starts at the neighbour's roof, so its hidden part is never drawn.
--------------------------------------------------------------------------
function B:facade(s, z0, z1, style, pick, tint, fromZ, street)
    local F = City.FLOOR
    local n = s.n
    if not self:facing(s.o[1], s.o[2], s.o[3], n[1], n[2], n[3]) then return end
    local bays = math.floor(s.len / F)
    local margin = (s.len - bays * F) / 2

    local function at(along, z)
        return { s.o[1] + s.u[1] * along, s.o[2] + s.u[2] * along, z }
    end

    -- The edge strips that don't make a whole bay are plain wall.
    local floors = math.floor((z1 - z0) / F + 0.001)
    local top = z0 + floors * F
    local startZ = math.max(z0, fromZ or z0)
    if margin > 0.5 and top > startZ then
        self:quad(style.plain, at(0, top), s.u, DOWN, margin, top - startZ, n, tint, 0, 0)
        self:quad(style.plain, at(s.len - margin, top), s.u, DOWN, margin, top - startZ, n, tint, 0, 0)
    end
    if z1 - top > 0.5 then
        self:quad(style.plain, at(0, z1), s.u, DOWN, s.len, z1 - top, n, tint, 0, 0)
    end

    for f = 0, floors - 1 do
        local zb = z0 + f * F
        local zt = zb + F
        if zt > startZ + 0.5 then
            local h = zt - math.max(zb, startZ)
            -- Merge runs of the same panel into one quad: the panels tile
            -- sideways, so a run is one quad with the texture repeated.
            local runMat, runStart, runLen = nil, 0, 0
            local function flush()
                if runMat then
                    self:quad(runMat, at(margin + runStart, zt), s.u, DOWN, runLen, h, n, tint, 0, 0)
                end
            end
            for i = 0, bays - 1 do
                local m
                if f == 0 and street then m = pick.ground(i) else m = pick.upper(i, f) end
                -- a sign stands in front of this bay: blank wall, no window
                -- for the sign to cover (tests/test_signs.lua)
                if self.blanks then
                    local p0, p1 = at(margin + i * F, 0), at(margin + (i + 1) * F, 0)
                    local ax = n[1] ~= 0 and 2 or 1
                    if self:blanked(n, n[1] ~= 0 and s.o[1] or s.o[2], math.min(p0[ax], p1[ax]), math.max(p0[ax], p1[ax]), zb, zt) then
                        m = style.plain
                    end
                end
                if m == runMat then
                    runLen = runLen + F
                else
                    flush()
                    runMat, runStart, runLen = m, i * F, F
                end
            end
            flush()
        end
    end
end

-- Is the bay a0..a1 (along the face, world units) by z0..z1 of a face with
-- normal n standing at `plane` behind a sign? self.blanks holds each wall
-- sign's footprint with a margin: { n, plane, a0, a1, z0, z1 }.
City.SIGN_BLANK_DEPTH = 400
function B:blanked(n, plane, a0, a1, z0, z1)
    for _, k in ipairs(self.blanks or {}) do
        if k.n[1] == n[1] and k.n[2] == n[2] then
            -- how far in front of this face the sign stands
            local gap = (k.plane - plane) * (n[1] ~= 0 and n[1] or n[2])
            if gap > -1 and gap < City.SIGN_BLANK_DEPTH and a0 < k.a1 and a1 > k.a0 and z0 < k.z1 and z1 > k.z0 then
                return true
            end
        end
    end
    return false
end

-- The cornice: a 32-unit trim band proud of the face, along its whole length.
function B:cornice(s, z, style, tint, depth)
    depth = depth or 8
    local n = s.n
    local o = { s.o[1] + n[1] * depth - s.u[1] * depth, s.o[2] + n[2] * depth - s.u[2] * depth, z }
    local len = s.len + depth * 2
    self:quad(style.trim, o, s.u, DOWN, len, 32, n, tint, 0, 0)
    -- underside: the shadow line that makes it read as a ledge from below
    local under = { o[1], o[2], z - 32 }
    self:quad(style.plain, under, s.u, { -n[1], -n[2], 0 }, len, depth, { 0, 0, -1 }, tint * 0.7, 0, 0)
end

--------------------------------------------------------------------------
-- One building: a box with facades, a roof and a cornice, plus an optional
-- setback tower on top.
--------------------------------------------------------------------------
-- `dry`: take this building's draws from the generator and build nothing (a
-- lot a street now runs through), so every building after it comes out of
-- the seed exactly as it did before the street was cut.
function B:building(bd, rng, dry)
    local style = City.Styles[bd.style] or City.Styles.brick
    local tint = bd.tint or 1
    local main = bd.win or rng.pick(style.win)
    local accent = rng.chance(0.4) and rng.pick(style.win) or nil
    local accentEvery = rng.int(3, 5)
    local doorAt = rng.int(0, 2)
    if dry then return end
    local doorMat, shopMat = style.ground[1], style.ground[2] or style.ground[1]
    local pick = {
        ground = function(i) if (i % 4) == doorAt then return doorMat end return shopMat end,
        upper = function(i, f)
            if accent and (i % accentEvery) == 0 then return accent end
            return main
        end,
    }
    local x0, y0, z0, x1, y1, z1 = bd[1], bd[2], bd[3], bd[4], bd[5], bd[6]
    for _, s in ipairs(sides(x0, y0, x1, y1, z1)) do
        local fromZ = bd.hidden and bd.hidden[s.n[1] .. "," .. s.n[2]] or nil
        self:facade(s, z0, z1, style, pick, tint, fromZ, bd.street)
        if bd.cornice ~= false then self:cornice(s, z1, style, tint) end
    end
    self:quad(bd.roof or "roof", { x0, y1, z1 }, { 1, 0, 0 }, { 0, -1, 0 }, x1 - x0, y1 - y0, { 0, 0, 1 }, tint)
    self.buildings[#self.buildings + 1] = bd
end

--------------------------------------------------------------------------
-- The frontage: the row of buildings standing on the park's wall, side by
-- side, their facades just inside it.
--
-- A side is { axis = "x"|"y", at = wall coordinate, out = +1|-1 (away from the
-- park), from, to (along the wall) }.
--------------------------------------------------------------------------
local function toBox(side, a0, a1, near, far, z0, z1)
    -- near/far: distances OUTWARD from the wall line (near may be negative:
    -- inside the park by that much)
    local n0, n1 = side.at + side.out * near, side.at + side.out * far
    local lo, hi = math.min(n0, n1), math.max(n0, n1)
    if side.axis == "x" then
        -- the wall runs along x (a north/south wall at y = at)
        return { a0, lo, z0, a1, hi, z1 }
    else
        return { lo, a0, z0, hi, a1, z1 }
    end
end

-- Cut a length into lots of whole bays.
local function lots(rng, from, to, minW, maxW)
    local F = City.FLOOR
    local out, a = {}, from
    while to - a > 0.5 do
        local w = rng.int(minW / F, maxW / F) * F
        if to - (a + w) < minW then w = to - a end
        out[#out + 1] = { a, a + w }
        a = a + w
    end
    return out
end
City.Lots = lots

-- Cut a row's lots round the streets the subway lines run down. A lot a
-- street crosses keeps the parts either side of it; a part too narrow to be
-- a building (City.MIN_PIECE) is given to the street instead, so the street
-- never leaves a sliver standing. Returns each lot's pieces, in order.
City.MIN_PIECE = 256
local function cutLots(list, cuts)
    for _, c in ipairs(cuts) do
        for _, lot in ipairs(list) do
            if lot[1] < c.a1 and lot[2] > c.a0 then
                if lot[1] < c.a0 and c.a0 - lot[1] < City.MIN_PIECE then c.a0 = lot[1] end
                if lot[2] > c.a1 and lot[2] - c.a1 < City.MIN_PIECE then c.a1 = lot[2] end
            end
        end
    end
    local pieces = {}
    for i, lot in ipairs(list) do
        local segs = { { lot[1], lot[2] } }
        for _, c in ipairs(cuts) do
            local keep = {}
            for _, s in ipairs(segs) do
                if s[1] < c.a1 and s[2] > c.a0 then
                    if c.a0 > s[1] then keep[#keep + 1] = { s[1], c.a0 } end
                    if c.a1 < s[2] then keep[#keep + 1] = { c.a1, s[2] } end
                else
                    keep[#keep + 1] = s
                end
            end
            segs = keep
        end
        pieces[i] = segs
    end
    return pieces
end
City.CutLots = cutLots

-- The station house: the low building a line passes over where it crosses
-- the frontage. Tall enough to cover the park's wall, low enough to leave
-- the line's girders `STATION_CLEAR` of air over its roof.
City.STATION_CLEAR = 96
City.STATION_STYLES = { "stone", "brick", "tan", "red" }

-- `cuts`: the streets crossing this row ({ a0, a1, line, under }); with
-- `stations`, each street gets a station house on the wall line (the
-- frontage), without, it is left open (the back row).
function B:row(side, rowDef, rng, cuts, stations)
    local F = City.FLOOR
    local ground = self.def.ground
    local list = lots(rng, side.from, side.to, rowDef.minWidth, rowDef.maxWidth)
    local streets = {}
    for _, c in ipairs(cuts or {}) do streets[#streets + 1] = { a0 = c.a0, a1 = c.a1, line = c.line, under = c.under } end
    local pieces = cutLots(list, streets)
    -- the parts a street made: their own generator, so the seed's buildings
    -- elsewhere come out as they always have
    local extra = Rng((self.def.seed or 1) + 7 + #self.buildings)
    local built, plan = {}, {}
    for i, lot in ipairs(list) do
        local floors = rng.int(rowDef.minFloors, rowDef.maxFloors)
        local setback = (rowDef.offset or 0) + (rowDef.jitter and rng.int(0, rowDef.jitter / 16) * 16 or 0)
        local depth = rng.int(rowDef.minDepth / F, rowDef.maxDepth / F) * F
        local z1 = ground + floors * F
        local style = rowDef.styles[rng.int(1, #rowDef.styles)]
        local tint = 0.9 + rng.float() * 0.16

        -- A setback tower: narrower, set further back, rising from the roof.
        local tower
        if rowDef.towerChance and rng.chance(rowDef.towerChance) and (lot[2] - lot[1]) >= 3 * F then
            local tfloors = rng.int(rowDef.towerMin or 3, rowDef.towerMax or 8)
            local inA = F * rng.int(0, 1)
            local back = F * rng.int(1, 2)
            local tstyle = rng.chance(0.5) and style or rowDef.styles[rng.int(1, #rowDef.styles)]
            tower = { a0 = lot[1] + inA, a1 = lot[2] - inA, back = back, z1 = z1 + tfloors * F, style = tstyle }
        end

        local function piece(a0, a1)
            local bd = toBox(side, a0, a1, -(rowDef.inset or 0) + setback, depth + setback, rowDef.base or ground, z1)
            bd.style, bd.tint, bd.street = style, tint, rowDef.street ~= false
            bd.side, bd.lot = side.name, { a0, a1 }
            return bd
        end
        local segs = pieces[i]
        local towerPlaced = false
        for j, seg in ipairs(segs) do
            local bd = piece(seg[1], seg[2])
            built[#built + 1] = bd
            plan[#plan + 1] = { bd = bd, rng = j == 1 and rng or extra }
            if tower and not towerPlaced then
                local t0, t1 = math.max(tower.a0, seg[1]), math.min(tower.a1, seg[2])
                if t1 - t0 >= 3 * F then
                    local tb = toBox(side, t0, t1, -(rowDef.inset or 0) + setback + tower.back, depth + setback, z1, tower.z1)
                    tb.style, tb.tint, tb.street = tower.style, tint, false
                    tb.side, tb.lot = side.name, { t0, t1 }
                    bd.tower = tb
                    towerPlaced = true
                    -- the tower's draws are the lot's, wherever it now stands
                    plan[#plan + 1] = { bd = tb, rng = rng }
                end
            end
        end
        if #segs == 0 then
            -- the street took the whole lot
            plan[#plan + 1] = { bd = piece(lot[1], lot[2]), rng = rng, dry = true }
        end
        if tower and not towerPlaced then
            plan[#plan + 1] = { bd = piece(lot[1], lot[2]), rng = rng, dry = true }
        end
    end

    -- the station houses, under the lines, on the wall line
    if stations then
        for _, st in ipairs(streets) do
            local most = math.floor((st.under - City.STATION_CLEAR - ground) / F)
            local least = math.ceil(((self.def.wallTop or 528) - ground) / F)
            local floors = math.max(least, math.min(most, extra.int(4, 5)))
            local bd = toBox(side, st.a0, st.a1, -(rowDef.inset or 0), self.def.stationDepth or 512, ground, ground + floors * F)
            bd.style = City.STATION_STYLES[extra.int(1, #City.STATION_STYLES)]
            bd.tint, bd.street = 0.92 + extra.float() * 0.1, true
            bd.side, bd.lot, bd.station = side.name, { st.a0, st.a1 }, st.line
            built[#built + 1] = bd
            plan[#plan + 1] = { bd = bd, rng = extra }
        end
    end
    local ax = side.axis == "x" and 1 or 2
    table.sort(built, function(a, b) return a[ax] < b[ax] end)

    -- A side face is hidden up to the neighbour's roof when the neighbour sits
    -- flush beside it. Record that, so the hidden part is never drawn.
    for i, bd in ipairs(built) do
        bd.hidden = {}
        local function hide(nb, key)
            if not nb then return end
            local touching = math.abs(nb[ax + 3] - bd[ax]) < 1 or math.abs(nb[ax] - bd[ax + 3]) < 1
            if touching and math.abs((nb[side.axis == "x" and 2 or 1]) - (bd[side.axis == "x" and 2 or 1])) < 1 then
                bd.hidden[key] = nb[6]
            end
        end
        if side.axis == "x" then
            hide(built[i - 1], "-1,0") hide(built[i + 1], "1,0")
        else
            hide(built[i - 1], "0,-1") hide(built[i + 1], "0,1")
        end
    end
    -- the signs on this wall find their building before its windows are
    -- laid, and the shops take the street floor
    if self.wallSignsBySide and self.wallSignsBySide[side.name] then
        self:placeWallSigns(side, built, self.wallSignsBySide[side.name])
    end
    if stations and self.def.storefronts then self:storefronts(side, built) end
    for _, p in ipairs(plan) do self:building(p.bd, p.rng, p.dry) end
    return built
end

--------------------------------------------------------------------------
-- The skyline: free-standing towers further out, all around.
--------------------------------------------------------------------------
-- Does a box stand in a subway line's street: within STREET_HALF of its axis
-- (either side), anywhere past the park's wall along it?
City.STREET_HALF = 192 + 256
function B:inStreet(bx)
    local p = self.def.park
    for _, v in ipairs(self.def.viaducts or {}) do
        local h = City.STREET_HALF
        if v.axis == "y" then
            if bx[1] < v.at + h and bx[4] > v.at - h and (bx[2] < p[2] or bx[5] > p[5]) then return true end
        else
            if bx[2] < v.at + h and bx[5] > v.at - h and (bx[1] < p[1] or bx[4] > p[4]) then return true end
        end
    end
    return false
end

function B:skyline(sk, rng)
    local F = City.FLOOR
    local p = self.def.park
    local cx, cy = (p[1] + p[4]) / 2, (p[2] + p[5]) / 2
    local placed = {}
    local tries = 0
    while #placed < sk.count and tries < sk.count * 30 do
        tries = tries + 1
        local w = rng.int(sk.minWidth / F, sk.maxWidth / F) * F
        local d = rng.int(sk.minWidth / F, sk.maxWidth / F) * F
        local ang = rng.float() * math.pi * 2
        local r = sk.minDist + rng.float() * (sk.maxDist - sk.minDist)
        -- distance is from the park's EDGE, so the ring hugs the rectangle
        local hx, hy = (p[4] - p[1]) / 2, (p[5] - p[2]) / 2
        local x = cx + math.cos(ang) * (hx + r)
        local y = cy + math.sin(ang) * (hy + r)
        x = math.floor(x / F) * F
        y = math.floor(y / F) * F
        local bx = { x, y, self.def.ground, x + w, y + d, 0 }
        local ok = true
        for _, o in ipairs(placed) do
            if bx[1] < o[4] + F and bx[4] > o[1] - F and bx[2] < o[5] + F and bx[5] > o[2] - F then ok = false break end
        end
        -- never inside the inner rows
        local m = sk.clear
        if bx[1] < p[4] + m and bx[4] > p[1] - m and bx[2] < p[5] + m and bx[5] > p[2] - m then ok = false end
        -- never in a subway line's street: the tower is placed as it always
        -- was (so the ones after it are too), and built from no material
        local inStreet = ok and self:inStreet(bx)
        if ok then
            local floors = rng.int(sk.minFloors, sk.maxFloors)
            bx[6] = self.def.ground + floors * F
            bx.style = sk.styles[rng.int(1, #sk.styles)]
            bx.tint = 0.86 + rng.float() * 0.14
            bx.street = false
            bx.cornice = rng.chance(0.6)
            bx.side = "skyline"
            -- eight sectors round the park, for the client's culling
            local sector = math.floor(((math.atan2(y - cy, x - cx) + math.pi) / (2 * math.pi)) * 8) % 8
            self.group = "sky:" .. sector
            placed[#placed + 1] = bx
            self:building(bx, rng, inStreet)
            -- a crown on some: a smaller block and a mast
            if rng.chance(sk.crownChance or 0.4) then
                local i = F
                local cb = { bx[1] + i, bx[2] + i, bx[6], bx[4] - i, bx[5] - i, bx[6] + F * rng.int(2, 4) }
                if cb[4] > cb[1] and cb[5] > cb[2] then
                    cb.style, cb.tint, cb.street, cb.side = bx.style, bx.tint, false, "skyline"
                    self:building(cb, rng, inStreet)
                    local mx, my = (cb[1] + cb[4]) / 2, (cb[2] + cb[5]) / 2
                    local mast = rng.int(4, 9) * 64
                    if not inStreet then self:box(mx - 8, my - 8, cb[6], mx + 8, my + 8, cb[6] + mast, "steel", 0.8) end
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- An elevated subway viaduct: a steel through-truss, deck and two tracks,
-- crossing the park and running on out over the city to the horizon.
--
--   { axis = "y", at = 1400, from = -1792, to = 768, deck = 1000, reach = 11000 }
--
-- The line runs along `axis` at `at` on the other axis; `deck` is the top of
-- the deck; `from`/`to` are the park's walls. It does NOT end in a building:
-- where it crosses a wall it passes over a low station house standing in a
-- gap in the frontage (B:row), then on down an open street between the back
-- row and through the skyline, `reach` past the wall, beyond every building
-- in the city. A train comes in from out there and goes back out there, so
-- it is never seen to go into or come out of anything. Two tracks, one each
-- way (right-hand running), so a train leaving and the next one coming in
-- can both be on the line.
--
-- Train cars run on it (see cl_city.lua). Inside the park the deck, girders
-- and truss walls are solid; out over the city nothing can reach them.
--------------------------------------------------------------------------
City.Viaduct = {
    width = 384,      -- outside of the truss walls
    track = 96,       -- each track's centre, either side of the line's axis
    slab = 40,        -- deck thickness
    girder = 64,      -- plate girders under the deck edges
    truss = 224,      -- truss wall height above the deck
    rail = 6,         -- rail head above the deck
    gauge = 56,       -- rail centres
    pierEvery = 1024, -- the piers holding it up out over the city
}

-- A car is a slot `length` long on the timetable (cl_city.lua draws a model
-- in each). Here so the server and the tests know a train's length too.
City.TrainCar = City.TrainCar or { length = 650, gap = 14, lift = 104 }

-- How long a train of `cars` cars is, nose to tail.
function City.TrainLength(cars)
    local C = City.TrainCar
    return cars * C.length + (cars - 1) * C.gap
end

-- How far past each wall a line's structure runs: its trains' reach, a whole
-- train beyond that (a train starts with its nose at `reach`), and a span.
function City.LineExtent(v)
    return (v.reach or 0) + City.TrainLength(v.cars or 3) + 512
end

-- Which side of the line's axis a train going `dir` runs on: right-hand
-- running, so northbound (+y) on the east track, eastbound (+x) on the south.
function City.TrackOffset(l, dir)
    local k = (City.Viaduct.track or 0) * (dir > 0 and 1 or -1)
    if l.axis == "y" then return k end
    return -k
end

-- local frame helpers: a = along the line, c = across it
local function lineBox(v, a0, a1, c0, c1, z0, z1)
    if v.axis == "y" then return v.at + c0, a0, z0, v.at + c1, a1, z1 end
    return a0, v.at + c0, z0, a1, v.at + c1, z1
end

function B:viaduct(v, name)
    local V = City.Viaduct
    local hw = V.width / 2
    local ext = City.LineExtent(v)
    local a0, a1 = v.from - ext, v.to + ext
    local deck = v.deck
    local bot = deck - V.slab
    local gb = bot - V.girder

    -- deck slab: concrete edges, steel plate underneath
    local x0, y0, z0, x1, y1, z1 = lineBox(v, a0, a1, -hw, hw, bot, deck)
    self:box(x0, y0, z0, x1, y1, z1, { side = "concrete", top = "steel", bottom = "steel" }, 0.95)
    -- the plate girders, one under each edge
    for _, c in ipairs({ -hw, hw - 12 }) do
        x0, y0, z0, x1, y1, z1 = lineBox(v, a0, a1, c, c + 12, gb, bot)
        self:box(x0, y0, z0, x1, y1, z1, { side = "girder", bottom = "steel" }, 0.85)
    end
    -- cross beams under the deck every 256
    for a = a0 + 128, a1 - 64, 256 do
        x0, y0, z0, x1, y1, z1 = lineBox(v, a - 8, a + 8, -hw + 12, hw - 12, gb + 16, bot)
        self:box(x0, y0, z0, x1, y1, z1, "steel", 0.7)
    end
    -- rails: a pair for each track
    for _, t in ipairs({ -V.track, V.track }) do
        for _, c in ipairs({ t - V.gauge / 2, t + V.gauge / 2 }) do
            x0, y0, z0, x1, y1, z1 = lineBox(v, a0, a1, c - 2, c + 2, deck, deck + V.rail)
            self:box(x0, y0, z0, x1, y1, z1, { side = "steel", top = "steel" }, 1.1)
        end
    end
    -- truss walls: alpha-tested panels, both faces, so the train shows
    -- through the holes from below and from either side
    local tz = deck + V.truss
    for _, c in ipairs({ -hw, hw }) do
        local len = a1 - a0
        if v.axis == "y" then
            self:quad("truss", { v.at + c, a0, tz }, { 0, 1, 0 }, DOWN, len, V.truss, { 1, 0, 0 }, 0.9, 0, 0, false)
            self:quad("truss", { v.at + c, a1, tz }, { 0, -1, 0 }, DOWN, len, V.truss, { -1, 0, 0 }, 0.9, 0, 0, false)
        else
            self:quad("truss", { a1, v.at + c, tz }, { -1, 0, 0 }, DOWN, len, V.truss, { 0, 1, 0 }, 0.9, 0, 0, false)
            self:quad("truss", { a0, v.at + c, tz }, { 1, 0, 0 }, DOWN, len, V.truss, { 0, -1, 0 }, 0.9, 0, 0, false)
        end
        -- top chord
        local cc = c > 0 and c - 16 or c
        x0, y0, z0, x1, y1, z1 = lineBox(v, a0, a1, cc, cc + 16, tz, tz + 16)
        self:box(x0, y0, z0, x1, y1, z1, { side = "steel", top = "steel", bottom = "steel" }, 0.8)
    end
    -- top bracing across, one per panel
    for a = a0 + V.truss, a1 - 1, V.truss do
        x0, y0, z0, x1, y1, z1 = lineBox(v, a - 6, a + 6, -hw, hw, tz + 2, tz + 14)
        self:box(x0, y0, z0, x1, y1, z1, "steel", 0.75)
    end

    -- Out over the city it stands on piers in the street it runs down: a
    -- concrete column and a crosshead under the girders, every pierEvery,
    -- from past the station house to the far end. Nobody can reach them.
    local first = (self.def.stationDepth or 512) + 256
    for _, e in ipairs({ { v.from, -1 }, { v.to, 1 } }) do
        for d = first, ext - 256, V.pierEvery do
            local a = e[1] + e[2] * d
            x0, y0, z0, x1, y1, z1 = lineBox(v, a - 40, a + 40, -40, 40, self.def.ground, gb - 40)
            self:box(x0, y0, z0, x1, y1, z1, { side = "concrete" }, 0.9)
            x0, y0, z0, x1, y1, z1 = lineBox(v, a - 48, a + 48, -hw - 16, hw + 16, gb - 40, gb)
            self:box(x0, y0, z0, x1, y1, z1, { side = "concrete2", bottom = "concrete2" }, 0.85)
        end
    end

    -- Solid: deck + girders as one slab, and the truss walls, over the park.
    x0, y0, z0, x1, y1, z1 = lineBox(v, v.from, v.to, -hw, hw, gb, deck)
    self:solid(name, x0, y0, z0, x1, y1, z1)
    for _, c in ipairs({ -hw, hw - 8 }) do
        x0, y0, z0, x1, y1, z1 = lineBox(v, v.from, v.to, c, c + 8, deck, tz + 16)
        self:solid(name, x0, y0, z0, x1, y1, z1)
    end

    self.lines[#self.lines + 1] = {
        name = name, axis = v.axis, at = v.at, from = v.from, to = v.to, deck = deck,
        period = v.period or 45, offset = v.offset or 0, cars = v.cars or 3,
        speed = v.speed or 1100, runout = v.reach or 0, reach = v.reach or 0, extent = ext,
        label = v.label, color = v.color, ends = v.ends,
    }
end

--------------------------------------------------------------------------
-- Where a line goes. A line runs both ways over the park: +1 from its `from`
-- end to its `to` end, -1 back. `ends = { from = "...", to = "..." }` names the
-- terminus beyond each end, so a train's destination is the end it is heading
-- for, and the same direction of travel always goes to the same place: on the
-- train's front board, its rear board, and the station sign at either end.
--------------------------------------------------------------------------
local BOUND = { y = { [1] = "NORTHBOUND", [-1] = "SOUTHBOUND" },
                x = { [1] = "EASTBOUND", [-1] = "WESTBOUND" } }

-- The terminus a train going `dir` on line `l` is heading for.
function City.LineDest(l, dir)
    local e = l.ends or {}
    if dir > 0 then return e.to or "" end
    return e.from or ""
end

-- The compass way a train going `dir` travels ("NORTHBOUND", ...): +y is north
-- and +x east in the map's frame.
function City.LineBound(l, dir)
    return BOUND[l.axis][dir > 0 and 1 or -1]
end

-- A station sign's rows: one per direction, in a fixed order (+1 first), so
-- the sign at either end of a line reads exactly the same.
function City.TransitRows(l)
    return {
        { dir = 1, bound = City.LineBound(l, 1), dest = City.LineDest(l, 1) },
        { dir = -1, bound = City.LineBound(l, -1), dest = City.LineDest(l, -1) },
    }
end

-- The line a transit sign belongs to (its `metro` field names it).
function City.SignLine(layout, s)
    for _, l in ipairs(layout and layout.lines or {}) do
        if l.name == s.metro then return l end
    end
end

-- A pier: a concrete column from the park floor to the underside of a
-- viaduct, with a cap. Solid, because it stands where riders ride. The cap
-- is a crosshead reaching out under both girders of the line it carries.
function B:pier(p, name)
    local h = (p.size or 96) / 2
    local x, y = p.x, p.y
    local z0, z1 = self.def.ground, p.top
    local V = City.Viaduct
    local cx, cy = h + 24, h + 24
    for _, v in ipairs(self.def.viaducts or {}) do
        if v.deck - V.slab - V.girder == p.top then
            if v.axis == "y" and math.abs(v.at - x) < 1 then cx = V.width / 2 + 16 end
            if v.axis == "x" and math.abs(v.at - y) < 1 then cy = V.width / 2 + 16 end
        end
    end
    self:box(x - h, y - h, z0, x + h, y + h, z1 - 32, { side = "concrete", top = "concrete" }, 1)
    self:box(x - cx, y - cy, z1 - 32, x + cx, y + cy, z1, "concrete2", 0.95)
    -- a kerb plinth at the foot
    self:box(x - h - 8, y - h - 8, z0, x + h + 8, y + h + 8, z0 + 12, "concrete2", 0.8)
    self:solid(name, x - h - 8, y - h - 8, z0, x + h + 8, y + h + 8, z0 + 12)
    self:solid(name, x - h, y - h, z0 + 12, x + h, y + h, z1 - 32)
    self:solid(name, x - cx, y - cy, z1 - 32, x + cx, y + cy, z1)
    -- a steel post from this pier's viaduct up to one crossing above, if any
    if p.postFrom and p.postTo then
        self:box(x - 16, y - 16, p.postFrom, x + 16, y + 16, p.postTo, "steel", 0.8)
        self:solid(name, x - 16, y - 16, p.postFrom, x + 16, y + 16, p.postTo)
    end
end

--------------------------------------------------------------------------
-- Signs are things, not stickers.
--
-- Every sign is a board in a case. The face (the artwork, drawn by
-- cl_city.lua from a render target, frame included) is the case's OPEN
-- front: no other surface lies in its plane, so it can never z-fight, and
-- nothing behind it shows through. The case's sides, top and back are mesh.
-- A floodlit ad gets its lamps as real arms on the case's top edge.
--
-- Wall signs are PLACED, not just put: each one moves along its wall onto one
-- building (never across two, never over the roof line or the cornice), and
-- the bays of that facade behind it are laid as blank wall, so a sign never
-- covers a window (tests/test_signs.lua checks every sign against every
-- window). Not how a real street works; it reads better.
--------------------------------------------------------------------------
City.SignPanelPx = { ad = 360, transit = 200, street = 170, shop = 240 }
City.SIGN_BORDER = 28            -- panel px of frame round the board
City.SignBorder = { shop = 0 }   -- a shop front is the whole front: no frame
City.SIGN_RT = { ad = { 1024, 512 }, transit = { 1024, 256 }, street = { 1024, 256 }, shop = { 1024, 256 } }
City.SIGN_CASE = 18              -- a wall sign's case: wall to face
City.SIGN_BACK = 10              -- a free-standing sign's case behind its face
City.SIGN_LAMP = { arm = 46, rise = 28, n = 4 }
City.SIGN_MARGIN = 24            -- blank wall round a sign

function City.SignFloodlit(s)
    return (s.look or "ad") == "ad" and s.style ~= "tv" and s.style ~= "neon"
end

-- A sign's artwork in panel pixels and its face in world units:
--   pw, ph   the board, in panel px (what the style functions draw)
--   ow, oh   the board and its frame, in panel px (what the render target holds)
--   scale    world units per panel px
--   fw, fh   the whole face, board and frame, in world units
function City.SignFrame(s)
    local look = s.look or "ad"
    local px = City.SignPanelPx[look] or 360
    local scale = s.h / px
    local B = City.SignBorder[look] or City.SIGN_BORDER
    local pw = s.w / scale
    return { pw = pw, ph = px, ow = pw + 2 * B, oh = px + 2 * B, scale = scale, border = B,
             fw = s.w + 2 * B * scale, fh = s.h + 2 * B * scale, rt = City.SIGN_RT[look] or City.SIGN_RT.ad }
end

-- The viewer's right, looking at a face with normal n (pointing at them).
function City.SignRight(n) return { -n[2], n[1], 0 } end

-- Ads are BILLBOARDS, up high: each one goes to the top of its building's
-- facade, under the cornice, on a steel catwalk with its floodlights over it
-- -- never down among the windows of the lower floors or the shops. A
-- building too low to hold the board with its foot at BILLBOARD_MIN_FLOORS
-- floors up stands it on its roof instead (B:billboard, on legs).
City.BILLBOARD_MIN_FLOORS = 4          -- z 576 on a 64 floor: over the wall's top
City.CATWALK = { out = 40, deck = 12, drop = 20, rail = 30 }

function City.BillboardMinZ(def)
    return (def.ground or 0) + City.BILLBOARD_MIN_FLOORS * City.FLOOR
end

function B:placeWallSigns(side, built, list)
    local ax = side.axis == "x" and 1 or 2
    local lo_i = side.axis == "x" and 2 or 1
    local p = self.def.park
    local w0, w1 = side.axis == "x" and p[1] or p[2], side.axis == "x" and p[4] or p[5]
    local n = side.axis == "x" and { 0, -side.out, 0 } or { -side.out, 0, 0 }
    local minZ = City.BillboardMinZ(self.def)
    self.blanks = self.blanks or {}
    self.facadesTaken = self.facadesTaken or {}
    for _, sg in ipairs(list) do
        local a = sg.pos[ax]
        if sg.metro then
            self:hangStationSign(side, sg, n)
        else
        -- its building: the one under it, else the nearest that has the room
        -- (an ad keeps 300+ wide) and no other sign; never a station house,
        -- unless it is that station's own sign
        local isAd = (sg.look or "ad") == "ad"
        local want = math.min(City.SignFrame(sg).fw, 400) + 96
        local home, best
        for _, bd in ipairs(built) do
            local l0, l1 = math.max(bd[ax], w0), math.min(bd[ax + 3], w1)
            local under = bd[ax] <= a and bd[ax + 3] >= a
            local fits
            if sg.metro then fits = bd.station == sg.metro and under
            elseif bd.station then fits = false
            elseif isAd then fits = l1 - l0 >= want and not self.facadesTaken[bd]
            else fits = under end
            if fits then
                local d = (a < l0 and l0 - a) or (a > l1 and a - l1) or 0
                if not best or d < best then home, best = bd, d end
            end
        end
        if not home and isAd then
            -- no facade free for it on this wall: it goes up on a roof
            local bb = {}
            for k, v in pairs(sg) do bb[k] = v end
            bb.side, bb.at, bb.back, bb.pos, bb.normal = side.name, a, bb.back or 64, nil, nil
            sg.toRoof = bb
        end
        if home then
            local lo, hi = math.max(home[ax], w0) + 48, math.min(home[ax + 3], w1) - 48
            local F = City.SignFrame(sg)
            if F.fw > hi - lo then
                local k = (hi - lo) / F.fw
                sg.w, sg.h = sg.w * k, sg.h * k
                F = City.SignFrame(sg)
            end
            a = math.min(math.max(a, lo + F.fw / 2), hi - F.fw / 2)
            local lampH = City.SignFloodlit(sg) and City.SIGN_LAMP.rise + 12 or 0
            local billboard = (sg.look or "ad") == "ad"
            -- under the cornice (32) with a storey's breathing room; a
            -- billboard right up there, anything else no higher than asked
            local top = home[6] - 32 - 48 - lampH - F.fh / 2
            local z = billboard and top or math.min(sg.pos[3], top)
            if billboard and z - F.fh / 2 - City.CATWALK.drop < minZ then
                -- too low a building to carry it up high: onto a roof
                local bb = {}
                for k, v in pairs(sg) do bb[k] = v end
                bb.side, bb.at, bb.back, bb.pos, bb.normal = side.name, a, bb.back or 64, nil, nil
                sg.toRoof = bb
            else
                -- the facade it hangs on, and its face standing proud of it
                local wall = (side.out > 0) and home[lo_i] or home[lo_i + 3]
                local face = wall + (n[1] ~= 0 and n[1] or n[2]) * City.SIGN_CASE
                local pos = { 0, 0, z }
                pos[ax] = a
                pos[lo_i] = face
                sg.pos, sg.normal, sg.wall, sg.home = pos, n, wall, home
                sg.mount = billboard and "wall" or nil
                if billboard then
                    -- one board to a facade, and no rooftop board right over
                    -- it (a setback tower's roof, higher and further back, may)
                    self.facadesTaken[home] = true
                    self.roofsTaken = self.roofsTaken or {}
                    self.roofsTaken[home] = true
                end
                local m = City.SIGN_MARGIN
                local foot = billboard and City.CATWALK.drop + City.CATWALK.deck or 0
                self.blanks[#self.blanks + 1] = { n = n, plane = face, a0 = a - F.fw / 2 - m, a1 = a + F.fw / 2 + m,
                                                  z0 = z - F.fh / 2 - foot - m, z1 = z + F.fh / 2 + lampH + m }
            end
        end
        end
    end
end

-- A station sign hangs from the line it names, where the line comes over the
-- wall: across the street under the viaduct, on two rods from its girders,
-- facing the park, over the station house's roof -- as a real elevated
-- railway signs its bridges. Never on the track side of the girders.
City.STATION_SIGN = { gap = 20, rods = 0.42 }
function B:hangStationSign(side, sg, n)
    local V = City.Viaduct
    local ax = side.axis == "x" and 1 or 2
    local lo_i = side.axis == "x" and 2 or 1
    local v
    for _, x in ipairs(self.def.viaducts or {}) do if x.name == sg.metro then v = x end end
    if not v then return end
    local gb = v.deck - V.slab - V.girder
    -- as wide as the rods under the girders allow
    local F = City.SignFrame(sg)
    local want = (V.width - 12) / (2 * City.STATION_SIGN.rods)
    if F.fw > want then
        local k = want / F.fw
        sg.w, sg.h = sg.w * k, sg.h * k
        F = City.SignFrame(sg)
    end
    local inset = self.def.frontage and self.def.frontage.inset or 4
    local face = side.at - side.out * (inset + City.SIGN_CASE)
    local pos = { 0, 0, gb - City.STATION_SIGN.gap - F.fh / 2 }
    pos[ax] = v.at
    pos[lo_i] = face
    sg.pos, sg.normal, sg.hang, sg.rods = pos, n, gb, City.STATION_SIGN.rods
end

--------------------------------------------------------------------------
-- Storefronts. Down at street level a building does not go on being windows
-- to the ground: its street floor is shops. Every frontage building, over
-- the park's wall, gets false shop fronts across its whole width -- a face
-- painted with the shop's fascia and name, its display window and its door
-- (cl_city.lua, the "shop" look) -- between stone pilasters, under a string
-- course, with a striped awning where nothing stands in front of it. The
-- station house's front is the metro's entrance.
--
-- The facade behind them (the street floor and the one over it) is laid as
-- blank wall, like the wall behind any sign, so there is no window behind
-- a shop's own window. Not walk-in: the park's wall is right behind them.
--------------------------------------------------------------------------
City.SHOP = {
    h = 192,          -- the shop front, from the ground: the street floor and half the next
    fascia = 56,      -- the fascia band at its top (the name)
    case = 10,        -- the face stands this far out of the wall
    pilaster = 16,    -- between shops and at each end
    proud = 16,       -- the pilasters and string course stand this far out
    band = 12,        -- the string course over the shop fronts
    maxW = 560,       -- a building wider than this has several shops
    minW = 192,       -- narrower than this, no shop at all
    stationW = 800,   -- the metro entrance at most (its artwork's width)
    door = 48,        -- a door's width, for the hedges and trees to keep clear of
}

function B:storefronts(side, built)
    local sf = self.def.storefronts
    local S = City.SHOP
    local ax = side.axis == "x" and 1 or 2
    local lo_i = side.axis == "x" and 2 or 1
    local p = self.def.park
    local w0, w1 = side.axis == "x" and p[1] or p[2], side.axis == "x" and p[4] or p[5]
    local n = side.axis == "x" and { 0, -side.out, 0 } or { -side.out, 0, 0 }
    local nn = n[1] ~= 0 and n[1] or n[2]
    local r = City.SignRight(n)
    local ra = (ax == 1) and r[1] or r[2]      -- +1 when the viewer's right is +along
    local ground = self.def.ground
    local inset = self.def.frontage and self.def.frontage.inset or 4
    self.shops = self.shops or {}
    self.shopKeep = self.shopKeep or {}
    self.blanks = self.blanks or {}
    self.shopIndex = self.shopIndex or 0
    local list = sf.shops or {}
    for _, bd in ipairs(built) do
        local a0, a1 = math.max(bd[ax], w0), math.min(bd[ax + 3], w1)
        if bd.street and a1 - a0 >= S.minW then
            local style = City.Styles[bd.style] or City.Styles.brick
            local wall = (side.out > 0) and bd[lo_i] or bd[lo_i + 3]
            local face = wall + nn * S.case
            local P = S.pilaster
            local count = bd.station and 1 or math.max(1, math.ceil((a1 - a0 - P) / (S.maxW + P)))
            local w = (a1 - a0 - P * (count + 1)) / count
            local first = a0 + P
            if bd.station and w > S.stationW then
                first = (a0 + a1) / 2 - S.stationW / 2
                w = S.stationW
            end
            local was = self.group
            self.group = "front:" .. side.name
            for k = 1, count do
                local s0 = first + (k - 1) * (w + P)
                local c = s0 + w / 2
                local shop
                if bd.station then
                    shop = sf.station or { text = "METRO", kind = "metro" }
                else
                    self.shopIndex = self.shopIndex + 1
                    shop = list[(self.shopIndex - 1) % math.max(#list, 1) + 1] or { text = "SHOP", kind = "general" }
                end
                -- the door: left, middle or right of the front, by turns
                local doorAt = bd.station and 0.5 or ({ 0.18, 0.5, 0.82 })[self.shopIndex % 3 + 1]
                local doorA = c + ra * (doorAt - 0.5) * (w - 2 * S.door)
                local sg = {}
                for key, v in pairs(shop) do sg[key] = v end
                sg.look, sg.shop = "shop", true
                sg.station = bd.station
                sg.num = tostring(math.floor(math.abs(c) / 16) * 2 + 1)
                sg.doorAt, sg.doorA = doorAt, doorA
                local pos = { 0, 0, ground + S.h / 2 }
                pos[ax] = c
                pos[lo_i] = face
                sg.pos, sg.normal, sg.wall, sg.shopOf = pos, n, wall, bd
                sg.w, sg.h = w, S.h
                sg.side, sg.a0, sg.a1 = side.name, s0, s0 + w
                sg.caseMat = style.plain
                self.shops[#self.shops + 1] = sg
                self.shopKeep[#self.shopKeep + 1] = { side = side.name, a0 = s0 - P, a1 = s0 + w + P,
                                                      z0 = ground, z1 = ground + S.h + S.band }
                -- the pilaster on its left (and, after the last, its right)
                for _, pa in ipairs(k == count and { s0 - P, s0 + w } or { s0 - P }) do
                    self:wallBox(side, pa, pa + P, -inset - S.proud, -inset, ground, ground + S.h,
                        { side = style.plain, top = style.plain }, 0.92)
                end
            end
            -- the string course over them all, and the wall behind blank
            self:wallBox(side, a0, a1, -inset - S.proud - 2, -inset, ground + S.h, ground + S.h + S.band,
                { side = style.trim, top = style.plain, bottom = style.plain }, 0.9)
            -- (all of its front: the part round the corner, past the park's
            -- wall, is out of sight, and plain)
            self.blanks[#self.blanks + 1] = { n = n, plane = face, a0 = bd[ax], a1 = bd[ax + 3], z0 = ground, z1 = ground + S.h + S.band }
            self.group = was
        elseif bd.street then
            -- round the corner, wholly past the park's wall: out of sight, plain
            local wall = (side.out > 0) and bd[lo_i] or bd[lo_i + 3]
            self.blanks[#self.blanks + 1] = { n = n, plane = wall + nn * S.case, a0 = bd[ax], a1 = bd[ax + 3],
                                              z0 = ground, z1 = ground + S.h + S.band }
        end
    end
end

-- Awnings over the shop windows: striped canvas sloping out from under the
-- fascia, with a valance along its front edge. Only where nothing stands in
-- front: no tree or lamp in front of the shop (they would grow through it),
-- and no ramp against the wall (`noAwning`, measured from the ramps).
City.AWNING = { out = 28, drop = 20, valance = 10, stripe = 24 }
City.AwningColours = {
    red = { 0.62, 0.12, 0.1 }, green = { 0.12, 0.36, 0.2 }, blue = { 0.14, 0.24, 0.46 },
    gold = { 0.78, 0.56, 0.14 }, navy = { 0.08, 0.1, 0.24 }, brown = { 0.36, 0.2, 0.1 },
    cream = { 0.86, 0.8, 0.66 },
}
for name, c in pairs(City.AwningColours) do
    City.Materials["awn_" .. name] = { tex = "vgui/white", w = 128, h = 128, color = c }
end

function B:awnings(sf)
    local A, S = City.AWNING, City.SHOP
    local ground = self.def.ground
    local inset = self.def.frontage and self.def.frontage.inset or 4
    self.awningList = {}
    for _, sg in ipairs(self.shops or {}) do
        local Sd = self.sidesByName[sg.side]
        self.group = "front:" .. sg.side
        local clear = sg.awning ~= nil and not sg.station
        for _, na in ipairs(sf.noAwning or {}) do
            if na.side == sg.side and sg.a0 < na.to and sg.a1 > na.from then clear = false end
        end
        local d0 = -inset - S.case            -- the face
        local d1 = d0 - A.out                 -- the awning's front edge
        if clear then
            for _, pl in ipairs(self.props) do
                local along, out
                if Sd.axis == "x" then along, out = pl.x, (pl.y - Sd.at) * Sd.out
                else along, out = pl.y, (pl.x - Sd.at) * Sd.out end
                -- a trunk or post (14 round) reaching under the canvas
                local r = 14
                if along > sg.a0 - r - 2 and along < sg.a1 + r + 2 and out + r + 2 > d1 and out - r - 2 < d0 then clear = false end
            end
        end
        if clear then
            local zt = ground + S.h - S.fascia
            local zb = zt - A.drop
            local n = sg.normal
            local slope = math.sqrt(A.out * A.out + A.drop * A.drop)
            -- down the slope, and the canvas's outward-and-up normal
            local wv = { n[1] * A.out / slope, n[2] * A.out / slope, -A.drop / slope }
            local nv = { n[1] * A.drop / slope, n[2] * A.drop / slope, A.out / slope }
            local r = City.SignRight(n)
            local cols = { "awn_" .. sg.awning, sg.awning2 and ("awn_" .. sg.awning2) or "awn_cream" }
            -- stripes, from the viewer's left
            local left = (Sd.axis == "x") and (r[1] > 0 and sg.a0 or sg.a1) or (r[2] > 0 and sg.a0 or sg.a1)
            local w = sg.a1 - sg.a0
            local count = math.max(1, math.floor(w / A.stripe + 0.5))
            local sw = w / count
            for i = 0, count - 1 do
                local a = left + (r[1] + r[2]) * i * sw
                local x, y
                if Sd.axis == "x" then x, y = a, Sd.at + Sd.out * d0 else x, y = Sd.at + Sd.out * d0, a end
                self:quad(cols[i % 2 + 1], { x, y, zt }, r, wv, sw, slope, nv, 0.95, 0, 0, false)
                -- the valance hanging from the front edge
                local fx, fy = x + n[1] * A.out, y + n[2] * A.out
                self:quad(cols[i % 2 + 1], { fx, fy, zb }, r, DOWN, sw, A.valance, n, 0.85, 0, 0, false)
            end
            local x0, y0 = Sd.axis == "x" and sg.a0 or Sd.at + Sd.out * d1, Sd.axis == "x" and Sd.at + Sd.out * d1 or sg.a0
            local x1, y1 = Sd.axis == "x" and sg.a1 or Sd.at + Sd.out * d0, Sd.axis == "x" and Sd.at + Sd.out * d0 or sg.a1
            self.awningList[#self.awningList + 1] = { shop = sg, box = { math.min(x0, x1), math.min(y0, y1), zb - A.valance,
                math.max(x0, x1), math.max(y0, y1), zt } }
            sg.awned = true
        end
    end
    self.group = nil
end

-- An axis-aligned box with one face left open (the sign's face goes there).
function B:openBox(x0, y0, z0, x1, y1, z1, mats, open, tint)
    for _, sd in ipairs(sides(x0, y0, x1, y1, z1)) do
        if not (open and sd.n[1] == open[1] and sd.n[2] == open[2]) then
            self:quad(mats.side, sd.o, sd.u, DOWN, sd.len, z1 - z0, sd.n, tint, 0, 0)
        end
    end
    self:quad(mats.top or mats.side, { x0, y1, z1 }, { 1, 0, 0 }, { 0, -1, 0 }, x1 - x0, y1 - y0, { 0, 0, 1 }, tint)
    self:quad(mats.bottom or mats.side, { x0, y0, z0 }, { 1, 0, 0 }, { 0, 1, 0 }, x1 - x0, y1 - y0, { 0, 0, -1 }, tint)
end

-- The case behind a sign's face, its lamps and hangers. Sets s.face (the
-- face's centre), s.fw, s.fh and s.case (the case's box, for the tests).
function B:signCase(s)
    local F = City.SignFrame(s)
    local n = s.normal
    local r = City.SignRight(n)
    local c = s.pos
    if s.roof then c = { c[1] + n[1] * 0.5, c[2] + n[2] * 0.5, c[3] } end
    s.face, s.fw, s.fh = c, F.fw, F.fh
    local depth = s.wall and math.abs(((n[1] ~= 0) and c[1] or c[2]) - s.wall) or City.SIGN_BACK
    local back = { c[1] - n[1] * depth, c[2] - n[2] * depth }
    local hx, hy = math.abs(r[1]) * F.fw / 2, math.abs(r[2]) * F.fw / 2
    local x0, x1 = math.min(c[1], back[1]) - hx, math.max(c[1], back[1]) + hx
    local y0, y1 = math.min(c[2], back[2]) - hy, math.max(c[2], back[2]) + hy
    local z0, z1 = c[3] - F.fh / 2, c[3] + F.fh / 2
    -- the open side is the face; a wall sign's back is against the wall
    -- (a shop front's reveal is the building's own stone)
    self:openBox(x0, y0, z0, x1, y1, z1, { side = s.caseMat or "signcase" }, { n[1], n[2] }, 1)
    s.case = { x0, y0, z0, x1, y1, z1 }
    local function at(along, out, z) return { c[1] + r[1] * along + n[1] * out, c[2] + r[2] * along + n[2] * out, z } end
    local function bx(p, q, mats, tint)
        self:box(math.min(p[1], q[1]), math.min(p[2], q[2]), math.min(p[3], q[3]),
                 math.max(p[1], q[1]), math.max(p[2], q[2]), math.max(p[3], q[3]), mats, tint)
    end
    if City.SignFloodlit(s) then
        -- the floodlights: a post up from the case, an arm reaching out over
        -- the face, a lamp head with its lens facing down onto the board
        local L = City.SIGN_LAMP
        for i = 1, L.n do
            local a = -s.w / 2 + s.w * (i - 0.5) / L.n
            bx(at(a - 2, -depth * 0.5 - 2, z1), at(a + 2, -depth * 0.5 + 2, z1 + L.rise), "steel", 0.7)
            bx(at(a - 2, -depth * 0.5, z1 + L.rise - 4), at(a + 2, L.arm, z1 + L.rise), "steel", 0.7)
            bx(at(a - 14, L.arm - 6, z1 + L.rise - 12), at(a + 14, L.arm + 6, z1 + L.rise - 2),
               { side = "signcase", top = "signcase", bottom = "lamplens" }, 1)
        end
    end
    if s.mount == "wall" then
        -- a billboard's catwalk: a grating along the foot of the board,
        -- standing out from the wall on steel brackets, a railing along it
        local C = City.CATWALK
        local zc = z0 - C.drop
        bx(at(-s.fw / 2, -depth, zc - C.deck), at(s.fw / 2, C.out, zc), { side = "steel", top = "grate", bottom = "steel" }, 0.8)
        for _, f in ipairs({ -0.42, 0, 0.42 }) do
            local a = s.fw * f
            bx(at(a - 4, -depth, zc - C.deck - 40), at(a + 4, C.out * 0.6, zc - C.deck), "steel", 0.7)
        end
        local r0 = at(-s.fw / 2, C.out, zc + C.rail)
        self:quad("rail", r0, r, DOWN, s.fw, C.rail, n, 0.8, 0, 0, false)
        -- and the posts from the catwalk up to the board's foot
        for _, f in ipairs({ -0.42, 0, 0.42 }) do
            local a = s.fw * f
            bx(at(a - 3, -depth * 0.5 - 3, zc), at(a + 3, -depth * 0.5 + 3, z0), "steel", 0.7)
        end
        s.catwalk = { zc - C.deck, zc }
    end
    if s.hang then
        -- a station sign hangs from the viaduct's girders on two rods
        local spread = s.rods or 0.36
        for _, f in ipairs({ -spread, spread }) do
            bx(at(F.fw * f - 3, -depth * 0.5 - 3, z1), at(F.fw * f + 3, -depth * 0.5 + 3, s.hang), "steel", 0.7)
        end
    end
end

--------------------------------------------------------------------------
-- A rooftop billboard: a sign on steel legs, standing on whichever frontage
-- building is under it, set back from its front edge.
--
--   { side = "north", at = 1800, w = 1024, h = 320, back = 96, text = ... }
--
-- `at` is the position along the wall. The height comes from the building,
-- so a new seed never buries the sign or leaves it floating.
--------------------------------------------------------------------------
function B:billboard(bb)
    local side = self.sidesByName[bb.side]
    local row = self.rows[bb.side]
    if not side or not row then return end
    local ax = side.axis == "x" and 1 or 2
    local out = side.out
    -- how far out from the wall a box's front face is
    local function nearOf(bx)
        local lo, hi = bx[side.axis == "x" and 2 or 1], bx[side.axis == "x" and 5 or 4]
        return ((out > 0) and lo or hi) * out - side.at * out
    end
    -- The roof it stands on: the building under `at`, else the nearest one
    -- that will take it -- never a station house (the line runs over it), and
    -- never a roof another board already stands on. Over the park's wall.
    local p = self.def.park
    local w0, w1 = side.axis == "x" and p[1] or p[2], side.axis == "x" and p[4] or p[5]
    self.roofsTaken = self.roofsTaken or {}
    local cands = {}
    for _, bd in ipairs(row) do
        local top = bd.tower or bd
        local l0, l1 = math.max(top[ax], w0), math.min(top[ax + 3], w1)
        if not bd.station and not self.roofsTaken[top] and l1 - l0 >= 384 then
            local d = (bb.at < l0 and l0 - bb.at) or (bb.at > l1 and bb.at - l1) or 0
            cands[#cands + 1] = { top = top, d = d, lot = { l0, l1 } }
        end
    end
    table.sort(cands, function(a, b) return a.d < b.d end)
    local pick = cands[1]
    if not pick then return end
    self.roofsTaken[pick.top] = true
    -- on a setback tower, the sign goes up on the tower's roof
    local roof, setback, lot = pick.top[6], nearOf(pick.top), pick.lot
    -- the board stays on its own roof: a taller neighbour beside it would
    -- otherwise stand in front of the part that hangs over
    bb = setmetatable({}, { __index = bb })
    local room = lot[2] - lot[1] - 64
    if bb.w > room then bb.h = bb.h * room / bb.w bb.w = room end
    bb.at = math.min(math.max(bb.at, lot[1] + 32 + bb.w / 2), lot[2] - 32 - bb.w / 2)
    local front = side.at + out * (setback + (bb.back or 96))   -- the sign's face line
    local legH = bb.legs or 96
    local z0 = roof + legH
    local cz = z0 + bb.h / 2
    -- legs: three pairs of steel posts behind the panel, and a catwalk
    for _, f in ipairs({ -0.4, 0, 0.4 }) do
        local a = bb.at + f * bb.w
        for _, d in ipairs({ 8, 72 }) do
            local n0 = front + out * d
            local x0, y0, x1, y1
            if side.axis == "x" then x0, x1, y0, y1 = a - 8, a + 8, math.min(n0, n0 + out * 16), math.max(n0, n0 + out * 16)
            else y0, y1, x0, x1 = a - 8, a + 8, math.min(n0, n0 + out * 16), math.max(n0, n0 + out * 16) end
            self:box(x0, y0, roof, x1, y1, z0 + bb.h * 0.9, "steel", 0.75)
        end
    end
    local n0, n1 = front + out * 2, front + out * 90
    local lo, hi = math.min(n0, n1), math.max(n0, n1)
    if side.axis == "x" then
        self:box(bb.at - bb.w / 2, lo, z0 - 12, bb.at + bb.w / 2, hi, z0, { side = "steel", top = "grate", bottom = "steel" }, 0.8)
    else
        self:box(lo, bb.at - bb.w / 2, z0 - 12, hi, bb.at + bb.w / 2, z0, { side = "steel", top = "grate", bottom = "steel" }, 0.8)
    end
    local nrm = side.axis == "x" and { 0, -out, 0 } or { -out, 0, 0 }
    local pos = side.axis == "x" and { bb.at, front, cz } or { front, bb.at, cz }
    local sg = {}
    for k, v in pairs(getmetatable(bb).__index) do sg[k] = v end
    sg.w, sg.h, sg.at = bb.w, bb.h, bb.at
    sg.pos, sg.normal, sg.roof, sg.onRoof = pos, nrm, roof, pick.top
    sg.side, sg.mount, sg.toRoof = bb.side, "roof", nil
    self.signs[#self.signs + 1] = sg
end

--------------------------------------------------------------------------
-- Greenery: planting beds along the park's walls, roof gardens and terraces
-- on the frontage, balconies with planters, and ivy.
--
--   beds       { side, from, to, depth }: a kerbed bed of grass against the
--              wall, from `from` to `to` along it, `depth` into the park.
--              Shrubs along it, trees in it. SOLID (kerb and trunks), so a
--              bike stops at the kerb instead of riding through the leaves;
--              tests/test_city.lua keeps every one 40 units off every ramp.
--   roofs      chance a frontage roof gets a garden: a planter along its
--              front edge, shrubs in it, trees behind
--   terraces   true: the strip in front of a setback tower gets planted
--   balconies  chance a frontage building gets balconies on its upper floors
--   ivy        chance a facade bay over a bed gets climbing ivy, and a roof
--              garden hangs ivy over its cornice
--
-- Plants are MODELS, laid out here as plain numbers (layout.props) and drawn
-- by cl_city.lua from its render hook like the rest of the city: not
-- entities, so the physgun, the toolgun and cleanup cannot touch them, and the
-- engine never fades or culls them by distance. Its own generator (the map's
-- seed plus one), so adding greenery leaves every building where it was.
--------------------------------------------------------------------------
function B:plant(kind, x, y, z, yaw, scale)
    local P = City.Plants[kind]
    if not P then error("BMX city: no plant " .. tostring(kind), 2) end
    self.props[#self.props + 1] = { kind = kind, x = x, y = y, z = z, yaw = yaw or 0, scale = scale or 1,
                                    group = self.group or "misc" }
end

-- Things greenery must keep off: the signs on the walls and roofs, and the
-- lines passing over the station houses. { side, a0, a1, z0, z1 } in wall terms.
function B:keepOffs()
    local p, out = self.def.park, {}
    local function sideOf(n, pos)
        if n[2] < -0.5 and math.abs(pos[2] - p[5]) < 200 then return "north", pos[1] end
        if n[2] > 0.5 and math.abs(pos[2] - p[2]) < 200 then return "south", pos[1] end
        if n[1] > 0.5 and math.abs(pos[1] - p[1]) < 200 then return "west", pos[2] end
        if n[1] < -0.5 and math.abs(pos[1] - p[4]) < 200 then return "east", pos[2] end
    end
    for _, s in ipairs(self.signs) do
        local side, a = sideOf(s.normal, s.pos)
        if s.shop then
            -- a shop front stands behind the bed, trees, lamps and all (its
            -- door finds a gap between them: B:shopDoors)
        elseif s.roof then
            -- a rooftop billboard: keep its roof clear in front of the board
            side = nil
            for name, S in pairs(self.sidesByName) do
                local n = S.axis == "x" and { 0, -S.out, 0 } or { -S.out, 0, 0 }
                if math.abs(n[1] - s.normal[1]) < 0.01 and math.abs(n[2] - s.normal[2]) < 0.01 then
                    side, a = name, S.axis == "x" and s.pos[1] or s.pos[2]
                end
            end
            if side then out[#out + 1] = { side = side, a0 = a - s.w / 2 - 96, a1 = a + s.w / 2 + 96, z0 = s.roof - 1, z1 = s.pos[3] + s.h / 2 } end
        elseif side then
            out[#out + 1] = { side = side, a0 = a - s.w / 2 - 48, a1 = a + s.w / 2 + 48,
                              z0 = s.pos[3] - s.h / 2 - 48, z1 = s.pos[3] + s.h / 2 + 64 }
        end
    end
    local V = City.Viaduct
    for _, v in ipairs(self.def.viaducts or {}) do
        local ends = v.axis == "y" and { "south", "north" } or { "west", "east" }
        for _, side in ipairs(ends) do
            out[#out + 1] = { side = side, a0 = v.at - V.width / 2 - 64, a1 = v.at + V.width / 2 + 64,
                              z0 = v.deck - V.slab - V.girder - 96, z1 = v.deck + V.truss + 128 }
        end
    end
    return out
end

local function keptOff(list, side, a0, a1, z0, z1)
    for _, k in ipairs(list) do
        if k.side == side and a0 < k.a1 and a1 > k.a0 and z0 < k.z1 and z1 > k.z0 then return true end
    end
    return false
end

-- Wall frame for a side: (a, d) -> x, y, where a runs along the wall and d is
-- the distance OUT from the wall line (negative: into the park).
local function wallXY(S, a, d)
    if S.axis == "x" then return a, S.at + S.out * d end
    return S.at + S.out * d, a
end
-- The normal of a side's facades, pointing into the park.
local function inward(S)
    if S.axis == "x" then return { 0, -S.out, 0 } end
    return { -S.out, 0, 0 }
end
-- A quad standing on the wall frame: its top-left corner at (a, d, z), facing
-- the park, running `len` to the viewer's right.
function B:wallQuad(S, mat, a, d, z, len, hgt, tint)
    local n = inward(S)
    -- the viewer's right, looking at the wall from the park
    local u = { -n[2], n[1], 0 }
    local ua = S.axis == "x" and u[1] or u[2]      -- +1 if right is +a
    local x, y = wallXY(S, ua > 0 and a or a + len, d)
    self:quad(mat, { x, y, z }, u, DOWN, len, hgt, n, tint, 0, 0, false)
end

-- An axis-aligned box from wall-frame extents.
function B:wallBox(S, a0, a1, d0, d1, z0, z1, mats, tint)
    local x0, y0 = wallXY(S, a0, d0)
    local x1, y1 = wallXY(S, a1, d1)
    self:box(math.min(x0, x1), math.min(y0, y1), z0, math.max(x0, x1), math.max(y0, y1), z1, mats, tint)
    return math.min(x0, x1), math.min(y0, y1), z0, math.max(x0, x1), math.max(y0, y1), z1
end

-- A bush: three crossed cards of leaves, `w` across and `h` tall, standing
-- on (x, y, z). Mesh, not a model: hundreds cost nothing, and a card of the
-- ivy art reads as a full, leafy shrub from any side.
function B:bush(x, y, z, w, h, rot, tint, mat)
    mat = mat or City.LEAF_COLOURS[1 + math.floor((x * 7 + y * 13) / 64) % #City.LEAF_COLOURS]
    for i = 0, 2 do
        local a = rot + i * math.pi / 3
        local u = { math.cos(a), math.sin(a), 0 }
        local n = { -u[2], u[1], 0 }
        self:quad(mat, { x - u[1] * w / 2, y - u[2] * w / 2, z + h }, u, DOWN, w, h, n, tint or 0.95,
            (i * 37) % 128, 0, false)
    end
end

-- A clipped hedge from a0 to a1, centred `d` out from the wall: two long
-- leafy faces and bushes all along it, so it is full from any angle.
function B:hedge(S, rng, a0, a1, d, z, h, w)
    h, w = h or 56, w or 36
    if a1 - a0 < 24 then return end
    -- one colour per stretch of hedge, the way one shrub turns all at once
    local mat = rng.pick(City.LEAF_COLOURS)
    for _, off in ipairs({ -w / 2, w / 2 }) do
        self:wallQuad(S, mat, a0, d + off, z + h, a1 - a0, h, 0.92)
    end
    local a = a0 + 20
    while a < a1 - 16 do
        local x, y = wallXY(S, a, d + rng.int(-4, 4))
        if rng.chance(0.3) then mat = rng.pick(City.LEAF_COLOURS) end
        self:bush(x, y, z - 2, w + rng.int(8, 24), h + rng.int(0, 20), rng.float() * math.pi, 0.85 + rng.float() * 0.15, mat)
        a = a + rng.int(28, 44)
    end
end

-- A planting bed on the park floor, against the wall.
-- Put the door of every shop standing behind a bed (from a0 to a1 along wall
-- S) where no tree trunk or lamp post stands in front of it: of the places a
-- door can go in its front, the one furthest from any of them. Returns the
-- doors' positions along the wall, in order.
function B:shopDoors(S, a0, a1, front)
    local D = City.SHOP.door
    local gap = D / 2 + 8
    local out = {}
    for _, sg in ipairs(self.shops or {}) do
        if sg.side == S.name and not sg.station and sg.a0 < a1 and sg.a1 > a0 and not sg.doorSet then
            local best, bestD
            for k = 0, 12 do
                local f = 0.12 + 0.76 * k / 12
                local da = (sg.a0 + sg.a1) / 2 + (City.SignRight(sg.normal)[S.axis == "x" and 1 or 2]) * (f - 0.5) * (sg.a1 - sg.a0 - 2 * D)
                -- in the bed with room for its gap, or off the bed altogether
                if (da > a0 + gap and da < a1 - gap) or da < a0 - gap or da > a1 + gap then
                    -- room to the nearest trunk, post or bush in front of the shop
                    local near = math.huge
                    local function by(list, r)
                        for _, pl in ipairs(list) do
                            local along = S.axis == "x" and pl.x or pl.y
                            local out_ = S.axis == "x" and (pl.y - S.at) * S.out or (pl.x - S.at) * S.out
                            if out_ > front - 200 and out_ < front + 1 then near = math.min(near, math.abs(along - da) - (pl.r or r)) end
                        end
                    end
                    by(self.props, 14)
                    by(self.bushSpots or {}, 40)
                    if not bestD or near > bestD then best, bestD = { f = f, a = da }, near end
                end
            end
            if best then
                sg.doorAt, sg.doorA, sg.doorSet = best.f, best.a, true
                if best.a > a0 and best.a < a1 then out[#out + 1] = best.a end
            end
        end
    end
    table.sort(out)
    return out
end

function B:bed(S, bd, g, rng, keep, name)
    local z0 = self.def.ground
    local kerb = g.kerb or 20
    local depth = bd.depth
    local inset = self.def.frontage and self.def.frontage.inset or 4
    local dIn, dOut = -depth, -inset
    -- kerb: a concrete ring, and the bed's soil and grass inside it
    local t = 8
    self:wallBox(S, bd.from, bd.to, dIn, dIn + t, z0, z0 + kerb, { side = "concrete2", top = "concrete2" }, 0.95)
    self:wallBox(S, bd.from, bd.from + t, dIn + t, dOut, z0, z0 + kerb, { side = "concrete2", top = "concrete2" }, 0.95)
    self:wallBox(S, bd.to - t, bd.to, dIn + t, dOut, z0, z0 + kerb, { side = "concrete2", top = "concrete2" }, 0.95)
    local x0, y0 = wallXY(S, bd.from + t, dIn + t)
    local x1, y1 = wallXY(S, bd.to - t, dOut)
    self:quad("grass", { math.min(x0, x1), math.max(y0, y1), z0 + kerb - 4 }, { 1, 0, 0 }, { 0, -1, 0 },
        math.abs(x1 - x0), math.abs(y1 - y0), { 0, 0, 1 }, 0.9)
    -- the whole bed is solid to the kerb's height: ride up to it, not into it
    local b0x, b0y = wallXY(S, bd.from, dIn)
    local b1x, b1y = wallXY(S, bd.to, dOut)
    self:solid(name, math.min(b0x, b1x), math.min(b0y, b1y), z0, math.max(b0x, b1x), math.max(b0y, b1y), z0 + kerb)

    local soil = z0 + kerb - 4
    local mid = (dIn + dOut) / 2
    -- street lamps, evenly along the bed, their arms reaching over the park
    local lampAt = {}
    if g.lampEvery then
        local n = math.max(1, math.floor((bd.to - bd.from) / g.lampEvery + 0.5))
        local step = (bd.to - bd.from) / n
        local nrm = inward(S)
        local yaw = math.deg(math.atan2(nrm[2], nrm[1])) - 90
        for i = 1, n do
            local a = bd.from + step * (i - 0.5)
            -- never a pole in front of a sign: slide along the bed to clear
            -- it, or leave that lamp out
            local at
            for _, off in ipairs({ 0, 160, -160, 280, -280 }) do
                local b = a + off
                local crowded = false
                for _, la in ipairs(lampAt) do if math.abs(b - la) < 320 then crowded = true end end
                if not at and not crowded and b > bd.from + 32 and b < bd.to - 32 and not keptOff(keep, S.name, b - 24, b + 24, soil, soil + 460) then
                    at = b
                end
            end
            if at then
                a = at
                -- at the kerb, as a street's lamps stand: the shop fronts'
                -- awnings reach out over the bed behind them
                local x, y = wallXY(S, a, dIn + 18)
                self:plant("lamp", x, y, soil, yaw, 1)
                self:solid(name, x - 10, y - 10, z0 + kerb, x + 10, y + 10, z0 + 440)
                local L = City.LAMP
                self.lamps[#self.lamps + 1] = { x = x, y = y, z = soil,
                    head = { x + nrm[1] * L.reach, y + nrm[2] * L.reach, soil + L.height } }
                lampAt[#lampAt + 1] = a
            end
        end
    end
    local function nearLamp(a)
        for _, la in ipairs(lampAt) do if math.abs(a - la) < 128 then return true end end
        return false
    end
    local treeMin, treeMax = g.treeEvery and g.treeEvery[1] or 288, g.treeEvery and g.treeEvery[2] or 448
    local a = bd.from + rng.int(80, 160)
    local kinds = bd.trees or { "tree", "tree_small", "tree2", "tree_small", "poplar" }
    local k = rng.int(1, #kinds)
    while a < bd.to - 64 do
        local kind = kinds[k] k = k % #kinds + 1
        local P = City.Plants[kind]
        local sc = (kind == "poplar") and 0.55 + rng.float() * 0.1 or 0.75 + rng.float() * 0.25
        local h = P.h * sc
        if not keptOff(keep, S.name, a - P.r * sc * 0.6, a + P.r * sc * 0.6, soil, soil + h) and not nearLamp(a) then
            -- in the hedge line, clear of the awnings over the shop windows
            local x, y = wallXY(S, a, mid - 14)
            self:plant(kind, x, y, soil, rng.int(0, 359), sc)
            -- the trunk is solid too
            self:solid(name, x - 12, y - 12, z0 + kerb, x + 12, y + 12, z0 + kerb + math.min(160, h * 0.4))
        else
            -- something to see past: a low bush instead
            local x, y = wallXY(S, a, mid + 8)
            self:bush(x, y, soil, 72, 64, rng.float() * math.pi)
            self.bushSpots = self.bushSpots or {}
            self.bushSpots[#self.bushSpots + 1] = { x = x, y = y, r = 40 }
        end
        a = a + rng.int(treeMin / 16, treeMax / 16) * 16
    end
    -- the hedge along the front, with a gap and a paved path across the bed
    -- to every shop door behind it; each door is put between the trees and
    -- lamps first (B:shopDoors), so nothing grows in a doorway
    local runs, a0h = {}, bd.from + t + 4
    local doors = self:shopDoors(S, bd.from + t, bd.to - t, dOut)
    local gap = City.SHOP.door / 2 + 8
    -- (the hedge's bushes spill past its ends by up to 12)
    for _, da in ipairs(doors) do
        if da - gap - 12 > a0h then runs[#runs + 1] = { a0h, da - gap - 12 } end
        a0h = math.max(a0h, da + gap + 12)
        local px0, py0 = wallXY(S, da - gap + 4, dIn + t)
        local px1, py1 = wallXY(S, da + gap - 4, dOut)
        self:quad("path", { math.min(px0, px1), math.max(py0, py1), z0 + kerb - 3 }, { 1, 0, 0 }, { 0, -1, 0 },
            math.abs(px1 - px0), math.abs(py1 - py0), { 0, 0, 1 }, 0.9)
    end
    if bd.to - t - 4 > a0h then runs[#runs + 1] = { a0h, bd.to - t - 4 } end
    for _, run in ipairs(runs) do
        if run[2] - run[1] > 24 then self:hedge(S, rng, run[1], run[2], dIn + 30, soil, 52, 32) end
    end
    -- ivy climbing the wall behind the bed
    local F = City.FLOOR
    a = bd.from
    while a + F <= bd.to do
        local h = F * rng.int(1, 3)
        if rng.chance(g.ivy or 0.5) and not keptOff(keep, S.name, a, a + F, z0, z0 + h)
           and not keptOff(self.shopKeep or {}, S.name, a, a + F, z0, z0 + h) then
            self:wallQuad(S, "ivy_climb", a, -inset - 1.5, z0 + h, F, h, 0.95)
        end
        a = a + F
    end
end

-- A roof garden: a planter along the front edge of a roof (shrubs, ivy hanging
-- over the cornice), and trees behind it. `front` is how far out from the wall
-- the roof's front edge is; `room` how deep the planted strip may go.
function B:roofGarden(S, a0, a1, front, room, z, g, rng, keep, small)
    if a1 - a0 < 192 then return end
    -- a billboard (or the line) stands on part of it: plant the parts beside it
    for _, k in ipairs(keep) do
        if k.side == S.name and a0 < k.a1 and a1 > k.a0 and z < k.z1 and z + 560 > k.z0 then
            self:roofGarden(S, a0, k.a0, front, room, z, g, rng, keep, small)
            self:roofGarden(S, k.a1, a1, front, room, z, g, rng, keep, small)
            return
        end
    end
    local d0 = front + 16
    -- the planter: a low concrete trough, grass on top
    self:wallBox(S, a0 + 32, a1 - 32, d0, d0 + 48, z, z + 24, { side = "concrete2", top = "grass" }, 0.9)
    self:hedge(S, rng, a0 + 40, a1 - 40, d0 + 24, z + 22, 60, 36)
    -- trees behind it
    if room >= 96 then
        local kinds = small and { "sapling", "tree_small" } or { "tree2", "tree", "poplar", "tree_small", "tree2" }
        local a = a0 + rng.int(96, 192)
        while a < a1 - 96 do
            local kind = rng.pick(kinds)
            local P = City.Plants[kind]
            local sc = kind == "poplar" and 0.5 + rng.float() * 0.12 or 0.7 + rng.float() * 0.3
            -- close behind the planter, so the crowns show over the cornice
            local x, y = wallXY(S, a, d0 + math.min(room - 32, 80 + rng.int(0, 48)))
            self:plant(kind, x, y, z, rng.int(0, 359), sc)
            a = a + rng.int(10, 16) * 16
        end
    end
end

-- Hanging ivy over a cornice at z, from a0 to a1, in bays.
function B:ivyDrape(S, a0, a1, z, g, rng, keep)
    local F = City.FLOOR
    local inset = self.def.frontage and self.def.frontage.inset or 4
    local a = a0 + ((a1 - a0) % F) / 2
    while a + F <= a1 + 0.5 do
        local h = F * (rng.chance(0.4) and 2 or 1)
        if rng.chance(g.ivy or 0.5) and not keptOff(keep, S.name, a, a + F, z - 32 - h, z) then
            self:wallQuad(S, rng.chance(0.5) and "ivy_hang" or "ivy_hang2", a, -inset - 1.5, z - 32, F, h, 0.9)
        end
        a = a + F
    end
end

-- Balconies on the upper floors of a frontage building's park face: a slab,
-- a railing, and a planter with a shrub, ivy trailing over the edge.
function B:balconies(S, bd, g, rng, keep)
    local F = City.FLOOR
    local inset = self.def.frontage and self.def.frontage.inset or 4
    local ax = S.axis == "x" and 1 or 2
    local a0, a1 = bd[ax], bd[ax + 3]
    local len = a1 - a0
    local bays = math.floor(len / F)
    local margin = (len - bays * F) / 2
    local floors = math.floor((bd[6] - bd[3]) / F + 0.001)
    local every = rng.int(2, 3)
    local first = rng.int(4, 5)          -- floor 4 is z 576: over the wall top
    local proud = 32
    local d0, d1 = -inset - proud, -inset
    local phase = rng.int(0, every - 1)
    for f = first, floors - 2, 2 do
        local zb = bd[3] + f * F
        for i = 0, bays - 1 do
            if (i + phase) % every == 0 then
                local b0, b1 = a0 + margin + i * F + 12, a0 + margin + (i + 1) * F - 12
                if not keptOff(keep, S.name, b0, b1, zb - 64, zb + 96) then
                    -- slab
                    self:wallBox(S, b0, b1, d0, d1, zb - 8, zb, { side = "concrete2", top = "concrete2", bottom = "concrete2" }, 0.85)
                    -- railing: front and the two ends, see-through
                    self:wallQuad(S, "rail", b0, d0, zb + 36, b1 - b0, 36, 0.8)
                    -- planter along the railing, a shrub in it, ivy over the edge
                    self:wallBox(S, b0 + 6, b1 - 6, d0 + 2, d0 + 14, zb, zb + 14, { side = "concrete", top = "soil" }, 0.8)
                    self:hedge(S, rng, b0 + 10, b1 - 10, d0 + 8, zb + 12, 26 + rng.int(0, 12), 10)
                    if rng.chance(0.6) then
                        self:wallQuad(S, rng.chance(0.5) and "ivy_hang" or "ivy_hang2", b0 + 4, d0 - 0.5, zb, b1 - b0 - 8, 64 + rng.int(0, 2) * 32, 0.9)
                    end
                end
            end
        end
    end
end

function B:greenery(g)
    local rng = Rng((g.seed or self.def.seed or 1) + 1)
    local keep = self:keepOffs()
    local inset = self.def.frontage and self.def.frontage.inset or 4
    -- the beds on the park floor
    for i, bd in ipairs(g.beds or {}) do
        local S = self.sidesByName[bd.side]
        self.group = "green:bed:" .. bd.side .. i
        self:bed(S, bd, g, rng, keep, "bed" .. i)
    end
    -- the frontage: roof gardens, terraces, balconies, ivy over cornices
    for _, key in ipairs({ "north", "south", "west", "east" }) do
        local S = self.sidesByName[key]
        local row = self.rows and self.rows[key] or {}
        local ax = S.axis == "x" and 1 or 2
        self.group = "green:front:" .. key
        for _, bd in ipairs(row) do
            local a0, a1 = bd[ax], bd[ax + 3]
            -- trim the corner lots to the part over the park's wall
            local w0, w1 = S.axis == "x" and self.def.park[1] or self.def.park[2], S.axis == "x" and self.def.park[4] or self.def.park[5]
            local c0, c1 = math.max(a0, w0), math.min(a1, w1)
            if c1 - c0 > 128 then
                local tower = bd.tower
                if tower and g.terraces then
                    -- the strip in front of the tower is a terrace garden
                    local back = math.abs((S.axis == "x" and (S.out > 0 and tower[2] or tower[5]) or (S.out > 0 and tower[1] or tower[4])) - S.at) - (-inset)
                    self:roofGarden(S, c0, c1, -inset, back - 24, bd[6], g, rng, keep, back < 200)
                    self:ivyDrape(S, c0, c1, bd[6], g, rng, keep)
                    if rng.chance(g.roofs or 0.5) then
                        local tback = math.abs((S.axis == "x" and (S.out > 0 and tower[2] or tower[5]) or (S.out > 0 and tower[1] or tower[4])) - S.at)
                        local t0, t1 = math.max(tower[ax], w0), math.min(tower[ax + 3], w1)
                        self:roofGarden(S, t0, t1, tback, 320, tower[6], g, rng, keep, false)
                    end
                elseif rng.chance(g.roofs or 0.5) then
                    self:roofGarden(S, c0, c1, -inset, 320, bd[6], g, rng, keep, false)
                    self:ivyDrape(S, c0, c1, bd[6], g, rng, keep)
                end
                if rng.chance(g.balconies or 0.3) then self:balconies(S, bd, g, rng, keep) end
            end
        end
    end
    self.group = nil
end

--------------------------------------------------------------------------
-- The floor: the map's floor is one concrete slab from wall to wall. Laid
-- over it, a hair above (it is drawn, never collided): slab concrete where
-- riders ride, a band of brick paving along the walls, cobbled plazas round
-- the piers, a kerb line between, and fallen leaves.
--
-- It is lit here, per vertex: the afternoon's ambient light, the shadow the
-- wall on the sun's side throws across the floor (soft-edged, and only a
-- shade darker: the map bakes fill light into it), and a warm pool under
-- every street lamp. The overlay is an unlit mesh -- no engine light can
-- reach it -- so all of that is baked into it. tests/test_lighting.lua keeps
-- every vertex between too dark and blown out (a vertex colour clips at 1).
--------------------------------------------------------------------------

-- 1 in the open, fl.shadow (e.g. 0.85) deep in the sun-side wall's shadow.
function B:wallShadow(x, y, fl)
    local k = fl.shadow
    if not k or not fl.wallTop then return 1 end
    local p, s = self.def.park, self.sun
    local h = math.sqrt(s[1] * s[1] + s[2] * s[2])
    if h < 1e-6 or s[3] <= 0 then return 1 end
    -- how far the floor point is from the wall the sun is behind, along
    -- the ray toward the sun (in plan)
    local run
    if math.abs(s[1]) >= math.abs(s[2]) then
        run = (s[1] < 0 and (x - p[1]) or (p[4] - x)) / (math.abs(s[1]) / h)
    else
        run = (s[2] < 0 and (y - p[2]) or (p[5] - y)) / (math.abs(s[2]) / h)
    end
    local reach = (fl.wallTop - self.def.ground) * h / s[3]   -- the shadow's depth
    local soft = fl.shadowSoft or 160
    local t = (run - (reach - soft / 2)) / soft                -- 0 in shade .. 1 in sun
    if t <= 0 then return k elseif t >= 1 then return 1 end
    t = t * t * (3 - 2 * t)
    return k + (1 - k) * t
end

function B:lightAt(x, y, fl)
    local a = fl.ambient or { 0.72, 0.64, 0.56 }
    local sh = self:wallShadow(x, y, fl)
    local r, g, b = a[1] * sh, a[2] * sh, a[3] * sh
    local pool, warm = fl.lampRadius or 420, fl.lampColor or { 0.62, 0.42, 0.2 }
    -- where two lamps' pools overlap they brighten each other, but never past
    -- one lamp at full: 1 - (1-k1)(1-k2)..., so two close lamps (the signs
    -- push them along the beds) cannot clip the paving white
    local dark = 1
    for _, l in ipairs(self.lamps) do
        local dx, dy = x - l.head[1], y - l.head[2]
        local d2 = (dx * dx + dy * dy) / (pool * pool)
        if d2 < 1 then dark = dark * (1 - (1 - d2) * (1 - d2)) end
    end
    local k = 1 - dark
    return r + warm[1] * k, g + warm[2] * k, b + warm[3] * k
end

-- A floor quad, x0..x1 by y0..y1 at z, lit per vertex. Texture by world
-- position, so neighbouring cells tile seamlessly.
function B:floorQuad(mat, x0, y0, x1, y1, z, fl)
    local M = City.Materials[mat]
    local list = self.faces[mat]
    if not list then list = {} self.faces[mat] = list end
    local q = { x0, y1, z, x1, y1, z, x1, y0, z, x0, y0, z,
        x0 / M.w, -y1 / M.h, x1 / M.w, -y0 / M.h, 1, self.group or "misc" }
    local c = 19
    for _, v in ipairs({ { x0, y1 }, { x1, y1 }, { x1, y0 }, { x0, y0 } }) do
        local r, g, b = self:lightAt(v[1], v[2], fl)
        q[c], q[c + 1], q[c + 2] = r, g, b
        c = c + 3
    end
    list[#list + 1] = q
    self.quads = self.quads + 1
end

function B:floor(fl, rng)
    local p = self.def.park
    local z = self.def.ground + (fl.lift or 0.6)
    local C = fl.cell or 64
    local walk = fl.walk or 176
    local plazas = {}
    for _, pr in ipairs(self.def.piers or {}) do plazas[#plazas + 1] = { pr.x, pr.y, fl.plaza or 288 } end
    for _, pl in ipairs(fl.plazas or {}) do plazas[#plazas + 1] = pl end
    self.group = "floor"
    for x = p[1], p[4] - 1, C do
        for y = p[2], p[5] - 1, C do
            local x1, y1 = math.min(x + C, p[4]), math.min(y + C, p[5])
            local cx, cy = (x + x1) / 2, (y + y1) / 2
            local dWall = math.min(cx - p[1], p[4] - cx, cy - p[2], p[5] - cy)
            local mat = "slab"
            if dWall < walk then mat = "pave_brick" end
            for _, pl in ipairs(plazas) do
                local dx, dy = cx - pl[1], cy - pl[2]
                if dx * dx + dy * dy < pl[3] * pl[3] then mat = "pave_cobble" end
            end
            self:floorQuad(mat, x, y, x1, y1, z, fl)
        end
    end
    -- the kerb line round the riding area, where the paving meets the slabs
    local k0, k1 = walk - 6, walk + 6
    local z2 = z + 0.2
    self:floorQuad("kerbline", p[1] + k0, p[5] - k1, p[4] - k0, p[5] - k0, z2, fl)
    self:floorQuad("kerbline", p[1] + k0, p[2] + k0, p[4] - k0, p[2] + k1, z2, fl)
    self:floorQuad("kerbline", p[1] + k0, p[2] + k1, p[1] + k1, p[5] - k1, z2, fl)
    self:floorQuad("kerbline", p[4] - k1, p[2] + k1, p[4] - k0, p[5] - k1, z2, fl)

    -- fallen leaves: drifts under the trees and along the beds, a few blown
    -- out across the slabs
    local seeds = {}
    for _, pl in ipairs(self.props) do
        if pl.kind ~= "lamp" and pl.x > p[1] and pl.x < p[4] and pl.y > p[2] and pl.y < p[5] and pl.z < 200 then
            seeds[#seeds + 1] = pl
        end
    end
    local z3 = z + 0.4
    for i = 1, fl.litter or 160 do
        local x, y, spread
        if #seeds > 0 and rng.chance(0.75) then
            local s = seeds[rng.int(1, #seeds)]
            spread = 320
            x, y = s.x + (rng.float() * 2 - 1) * spread, s.y + (rng.float() * 2 - 1) * spread
        else
            x, y = p[1] + rng.float() * (p[4] - p[1]), p[2] + rng.float() * (p[5] - p[2])
        end
        local size = rng.int(48, 112)
        local key = rng.pick(City.LITTER)
        local M = City.Materials[key]
        local h = size / 2
        if x - h > p[1] and x + h < p[4] and y - h > p[2] and y + h < p[5] then
            local a = rng.float() * math.pi * 2
            local u = { math.cos(a), math.sin(a), 0 }
            local w = { math.sin(a), -math.cos(a), 0 }
            local o = { x - u[1] * h - w[1] * h, y - u[2] * h - w[2] * h, z3 }
            local list = self.faces[key]
            if not list then list = {} self.faces[key] = list end
            local q = { o[1], o[2], z3,
                o[1] + u[1] * size, o[2] + u[2] * size, z3,
                o[1] + (u[1] + w[1]) * size, o[2] + (u[2] + w[2]) * size, z3,
                o[1] + w[1] * size, o[2] + w[2] * size, z3,
                0, 0, 1, 1, 1, self.group }
            local c = 19
            for k = 0, 3 do
                local r, g, b = self:lightAt(q[k * 3 + 1], q[k * 3 + 2], fl)
                q[c], q[c + 1], q[c + 2] = r, g, b
                c = c + 3
            end
            list[#list + 1] = q
            self.quads = self.quads + 1
        end
    end
    self.group = nil
end

--------------------------------------------------------------------------
-- Build a map definition into a layout.
--------------------------------------------------------------------------
function City.Build(def)
    local b = newBuilder(def)
    local rng = Rng(def.seed or 1)
    local p = def.park

    -- The four walls, as sides. Corners belong to the north/south rows, which
    -- run past the ends by the frontage depth.
    local fr = def.frontage
    local over = fr.maxDepth + (fr.offset or 0)
    local S = {
        north = { name = "north", axis = "x", at = p[5], out = 1,  from = p[1] - over, to = p[4] + over },
        south = { name = "south", axis = "x", at = p[2], out = -1, from = p[1] - over, to = p[4] + over },
        west  = { name = "west",  axis = "y", at = p[1], out = -1, from = p[2], to = p[5] },
        east  = { name = "east",  axis = "y", at = p[4], out = 1,  from = p[2], to = p[5] },
    }
    b.sidesByName = S

    -- The streets the subway lines run down: where a line crosses a wall, a
    -- gap in the frontage (with a low station house in it, under the line)
    -- and in the back row, so it runs on out over the city instead of into
    -- a building. { side, a0, a1, line, under } in wall terms.
    local V = City.Viaduct
    local streets = {}
    for i, v in ipairs(def.viaducts or {}) do
        local half = V.width / 2 + (def.streetMargin or 128)
        local ends = v.axis == "y" and { "south", "north" } or { "west", "east" }
        for _, side in ipairs(ends) do
            streets[#streets + 1] = { side = side, a0 = v.at - half, a1 = v.at + half,
                                      line = v.name or ("line" .. i), under = v.deck - V.slab - V.girder }
        end
    end
    local function streetsOn(side)
        local out = {}
        for _, st in ipairs(streets) do if st.side == side then out[#out + 1] = st end end
        return out
    end
    b.streets = streets

    -- The signs, as copies (placing moves them; the definition stays as
    -- written). Wall signs go with their side's row, to be placed on a
    -- building before its windows are laid.
    local defSigns = {}
    b.wallSignsBySide = {}
    for _, sg in ipairs(def.signs or {}) do
        local c = {}
        for k, v in pairs(sg) do c[k] = v end
        c.pos = { sg.pos[1], sg.pos[2], sg.pos[3] }
        c.normal = { sg.normal[1], sg.normal[2], sg.normal[3] or 0 }
        defSigns[#defSigns + 1] = c
        for name, sd in pairs(S) do
            local nn = sd.axis == "x" and { 0, -sd.out } or { -sd.out, 0 }
            local plane = sd.axis == "x" and c.pos[2] or c.pos[1]
            if nn[1] == c.normal[1] and nn[2] == c.normal[2] and math.abs(plane - sd.at) < 200 then
                b.wallSignsBySide[name] = b.wallSignsBySide[name] or {}
                table.insert(b.wallSignsBySide[name], c)
            end
        end
    end

    b.rows = {}
    for _, key in ipairs({ "north", "south", "west", "east" }) do
        b.group = "front:" .. key
        b.rows[key] = b:row(S[key], fr, rng, streetsOn(key), true)
    end
    -- the second row: taller, further back, gaps between
    if def.backRow then
        for _, key in ipairs({ "north", "south", "west", "east" }) do
            local s = S[key]
            local s2 = { name = key .. "2", axis = s.axis, at = s.at, out = s.out,
                from = s.from - (s.axis == "y" and over or 0), to = s.to + (s.axis == "y" and over or 0) }
            b.group = "back:" .. key
            b:row(s2, def.backRow, rng, streetsOn(key))
        end
    end
    if def.skyline then b:skyline(def.skyline, rng) end

    for i, v in ipairs(def.viaducts or {}) do
        b.group = "via:" .. (v.name or ("line" .. i))
        b:viaduct(v, v.name or ("line" .. i))
    end
    b.group = "via:piers"
    for i, pr in ipairs(def.piers or {}) do b:pier(pr, pr.name or ("pier" .. i)) end

    -- (an ad its building is too low to hold high up goes up on a roof)
    for _, sg in ipairs(defSigns) do if not sg.toRoof then b.signs[#b.signs + 1] = sg end end
    b.group = "front:roof"
    for _, bb in ipairs(def.billboards or {}) do b:billboard(bb) end
    for _, sg in ipairs(defSigns) do if sg.toRoof then b:billboard(sg.toRoof) end end
    -- the shops' fronts, after every other sign
    for _, sg in ipairs(b.shops or {}) do b.signs[#b.signs + 1] = sg end
    -- every sign's case (and lamps, hangers), now that all are where they go
    for _, sg in ipairs(b.signs) do
        b.group = sg.group or (sg.roof and "front:roof" or "front:signs")
        b:signCase(sg)
    end

    -- last, so the rest of the city is laid out exactly as it was without it
    if def.greenery then b:greenery(def.greenery) end
    if def.floor then b:floor(def.floor, Rng((def.seed or 1) + 2)) end
    -- awnings last of all: only over a shop with no tree or lamp in front
    if def.storefronts then b:awnings(def.storefronts) end

    return {
        faces = b.faces, solids = b.solids, lines = b.lines, signs = b.signs,
        buildings = b.buildings, props = b.props, lamps = b.lamps, quads = b.quads, rows = b.rows, def = def,
        streets = b.streets, shops = b.shops or {}, awnings = b.awningList or {},
        mood = def.mood,
    }
end

-- The current map's definition, if the city has one for it.
function City.Def(map)
    return City.Maps[map or game.GetMap()]
end

-- Is the city switched on? Server convar bmx_city (replicated), default on.
function City.Enabled()
    local cv = GetConVar and GetConVar("bmx_city")
    if cv then return cv:GetBool() end
    return true
end

-- Built once per map per realm and cached.
function City.Layout()
    local map = game.GetMap()
    if City._layoutMap ~= map then
        local def = City.Def(map)
        City._layout = def and City.Build(def) or nil
        City._layoutMap = map
    end
    return City._layout
end

if SERVER then
    CreateConVar("bmx_city", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
        "BMX: build the city around the park on maps that have one (1/0). Takes effect on map change or bmx_city_rebuild.")
end
