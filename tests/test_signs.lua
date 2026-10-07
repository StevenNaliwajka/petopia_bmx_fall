--[[--------------------------------------------------------------------------
    The city's signs, from the front (sh_city.lua B:placeWallSigns,
    B:signCase; cl_city.lua drawSigns).

    What went wrong before 2026-10-07, and what these keep from coming back:
      - a sign was a flat sticker 14 units off the wall, drawn through two
        translucent "light" washes that overlapped in stripes and let the
        facade's windows show through the board
      - signs straddled two buildings, ran up over a roof line, and covered
        windows (the bays behind a sign are now blank wall)
      - the floodlights were painted on the board, not things on its case
----------------------------------------------------------------------------]]

local F = require("lib.fixture")

local function city()
    local sv, world = F.server()
    local cl = F.client(world)
    local City = cl.env.BMX.City
    return City, City.Build(City.Maps.gm_skatepark), cl
end

-- the materials that have windows in them: every style's window and street
-- floor panels (shop fronts and doors are glass too); `plain` and `trim` don't
local function windowMats(City)
    local set = {}
    for _, st in pairs(City.Styles) do
        for _, m in ipairs(st.win) do set[m] = true end
        for _, m in ipairs(st.ground) do set[m] = true end
    end
    for _, st in pairs(City.Styles) do set[st.plain] = nil set[st.trim] = nil end
    return set
end

-- a quad's normal and axis-aligned bounds
local function quadInfo(q)
    local ax, ay, az = q[4] - q[1], q[5] - q[2], q[6] - q[3]
    local bx, by, bz = q[10] - q[1], q[11] - q[2], q[12] - q[3]
    -- B:quad lays TL, TR, BR, BL with `u` right and `w` down: the face's
    -- normal is w x u, the opposite of (TR-TL) x (BL-TL)
    local nx, ny, nz = -(ay * bz - az * by), -(az * bx - ax * bz), -(ax * by - ay * bx)
    local l = math.sqrt(nx * nx + ny * ny + nz * nz)
    local mn, mx = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for c = 0, 3 do
        for a = 1, 3 do
            local v = q[c * 3 + a]
            mn[a] = math.min(mn[a], v) mx[a] = math.max(mx[a], v)
        end
    end
    return { l > 0 and nx / l or 0, l > 0 and ny / l or 0, l > 0 and nz / l or 0 }, mn, mx
end

-- The sign's footprint on the wall plane, in (along, z), with its lamps:
-- { a0, a1, z0, z1 }, `ax` the world axis `along` runs on, `plane` the face
local function footprint(City, s)
    local n = s.normal
    local ax = n[1] ~= 0 and 2 or 1
    local c = s.face
    local top = c[3] + s.fh / 2
    if City.SignFloodlit(s) then top = top + City.SIGN_LAMP.rise end
    return { c[ax] - s.fw / 2, c[ax] + s.fw / 2, c[3] - s.fh / 2, top }, ax, (n[1] ~= 0) and c[1] or c[2]
end

-- every window quad that a sign covers or cuts: parallel to it and behind it
-- (up to SIGN_BLANK_DEPTH) with overlapping outlines, or crossing its case
local function overlaps(City, L)
    local wins = windowMats(City)
    local hits = {}
    for _, s in ipairs(L.signs) do
        local fp, ax, plane = footprint(City, s)
        local sn = s.normal[1] ~= 0 and s.normal[1] or s.normal[2]
        for mat in pairs(wins) do
            for _, q in ipairs(L.faces[mat] or {}) do
                local n, mn, mx = quadInfo(q)
                local inOutline = mn[ax] < fp[2] - 0.5 and mx[ax] > fp[1] + 0.5 and mn[3] < fp[4] - 0.5 and mx[3] > fp[3] + 0.5
                local behind = false
                if math.abs(n[1] - s.normal[1]) < 1e-6 and math.abs(n[2] - s.normal[2]) < 1e-6 and math.abs(n[3]) < 1e-6 then
                    local qp = (s.normal[1] ~= 0) and mn[1] or mn[2]
                    local gap = (plane - qp) * sn
                    behind = gap > -1 and gap < City.SIGN_BLANK_DEPTH
                end
                local b = s.case
                local cuts = b and mn[1] < b[4] and mx[1] > b[1] and mn[2] < b[5] and mx[2] > b[2] and mn[3] < b[6] and mx[3] > b[3]
                if (behind and inOutline) or cuts then hits[#hits + 1] = tostring(s.text or s.look) .. " over a " .. mat end
            end
        end
    end
    return hits
end

T.test("signs: no sign covers or cuts into a window, on any facade", function()
    local City, L = city()
    local hits = overlaps(City, L)
    T.eq(#hits, 0, "signs over windows: " .. table.concat(hits, "; ", 1, math.min(#hits, 6)))
    T.ok(#L.signs >= 15, "signs: " .. #L.signs)
end)

T.test("signs: the wall behind a sign is truly blank: every style's plain panel has no window", function()
    local City = city()
    local ok = {}
    for _, id in ipairs(City.WindowlessPanels) do ok["building_template/building_template" .. id] = true end
    for name, st in pairs(City.Styles) do
        local M = City.Materials[st.plain]
        T.ok(M and ok[M.tex], name .. "'s plain panel " .. tostring(M and M.tex) .. " is a windowless one")
    end
end)

T.test("signs: the window check has teeth (without the blank wall, signs cover windows)", function()
    local City = city()
    local B = City.Builder
    local was = B.blanked
    B.blanked = function() return false end
    local ok, L = pcall(City.Build, City.Maps.gm_skatepark)
    B.blanked = was
    T.ok(ok, "built without blanking")
    T.ok(#overlaps(City, L) > 5, "the same layout with windows behind its signs is caught")
end)

T.test("signs: each wall sign hangs on one building, inside the park, under its cornice", function()
    local City, L = city()
    local p = City.Maps.gm_skatepark.park
    local walls = 0
    for _, s in ipairs(L.signs) do
        if s.home then
            walls = walls + 1
            local fp, ax = footprint(City, s)
            local h = s.home
            T.ok(fp[1] >= h[ax] + 32 and fp[2] <= h[ax + 3] - 32, tostring(s.text or s.metro) .. " on one building, not across two")
            local w0, w1 = ax == 1 and p[1] or p[2], ax == 1 and p[4] or p[5]
            T.ok(fp[1] >= w0 and fp[2] <= w1, tostring(s.text or s.metro) .. " over the park's wall, where it can be seen")
            T.ok(fp[4] <= h[6] - 32 - 16, tostring(s.text or s.metro) .. " under the cornice (top " .. fp[4] .. ", roof " .. h[6] .. ")")
            T.ok(fp[3] >= City.Maps.gm_skatepark.ground + 100, tostring(s.text or s.metro) .. " clear of the ground")
            -- stands proud of its own facade by the case depth
            local wallPlane = s.wall
            local facePlane = s.normal[1] ~= 0 and s.face[1] or s.face[2]
            T.near(math.abs(facePlane - wallPlane), City.SIGN_CASE, 0.01, tostring(s.text or s.metro) .. " case depth")
        end
    end
    T.ok(walls >= 10, "wall signs placed: " .. walls)
end)

T.test("signs: the face is the open front of a case, nothing lies in its plane (no z-fighting)", function()
    local City, L = city()
    for _, s in ipairs(L.signs) do
        T.ok(s.face and s.fw and s.fh and s.case, tostring(s.text or s.metro) .. " has a face and a case")
        local fp, ax, plane = footprint(City, s)
        fp[4] = s.face[3] + s.fh / 2
        local nax = s.normal[1] ~= 0 and 1 or 2
        -- the case reaches the face plane and lies behind it
        local b = s.case
        local sn = s.normal[nax]
        local front = sn > 0 and b[nax + 3] or b[nax]
        local rear = sn > 0 and b[nax] or b[nax + 3]
        T.near(front, plane, 0.01, tostring(s.text or s.metro) .. " case meets the face")
        T.ok((plane - rear) * sn >= 8, tostring(s.text or s.metro) .. " case has depth behind the face")
        for mat, list in pairs(L.faces) do
            for _, q in ipairs(list) do
                local n, mn, mx = quadInfo(q)
                if math.abs(n[3]) < 1e-6 and math.abs(math.abs(n[nax]) - 1) < 1e-6 then
                    local qp = mn[nax]
                    if math.abs(qp - plane) < 1 and mn[ax] < fp[2] - 0.5 and mx[ax] > fp[1] + 0.5 and mn[3] < fp[4] - 0.5 and mx[3] > fp[3] + 0.5 then
                        T.ok(false, tostring(s.text or s.metro) .. ": a " .. mat .. " quad in the face's plane")
                    end
                end
            end
        end
    end
end)

T.test("signs: artwork fits its render target 1:1 and is fine enough to read", function()
    local City, L = city()
    for _, s in ipairs(L.signs) do
        local Fr = City.SignFrame(s)
        T.ok(Fr.ow <= Fr.rt[1] and Fr.oh <= Fr.rt[2], tostring(s.text or s.metro) .. " artwork " .. math.floor(Fr.ow) .. "x" .. Fr.oh
            .. " fits " .. Fr.rt[1] .. "x" .. Fr.rt[2] .. " without shrinking")
        T.ok(Fr.scale <= 0.8, tostring(s.text or s.metro) .. ": " .. Fr.scale .. " units a pixel")
        T.ok(s.w >= 300 or s.look ~= "ad", tostring(s.text or s.metro) .. " still big enough to read: " .. s.w)
    end
end)

T.test("signs: floodlit ads have real lamps over the face, lenses facing down", function()
    local City, L = city()
    local lenses = L.faces.lamplens or {}
    local flood = 0
    for _, s in ipairs(L.signs) do
        if City.SignFloodlit(s) then
            flood = flood + 1
            local n, found = s.normal, 0
            for _, q in ipairs(lenses) do
                local nq, mn, mx = quadInfo(q)
                local cx, cy, cz = (mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2, mn[3]
                local out = (cx - s.face[1]) * n[1] + (cy - s.face[2]) * n[2]
                local r = City.SignRight(n)
                local along = (cx - s.face[1]) * r[1] + (cy - s.face[2]) * r[2]
                if nq[3] < -0.99 and out > 10 and out < 80 and math.abs(along) < s.fw / 2
                   and cz > s.face[3] + s.fh / 2 and cz < s.face[3] + s.fh / 2 + 60 then
                    found = found + 1
                end
            end
            T.eq(found, City.SIGN_LAMP.n, tostring(s.text or s.metro) .. " lamps over its face")
        end
    end
    T.ok(flood >= 6, "floodlit ads: " .. flood)
end)

T.test("signs: lit by the scene through the face's own colour, never glowing, never washed out", function()
    local City, L = city()
    for _, s in ipairs(L.signs) do
        local top, bottom, tint = City.SignFaceLight(s, L)
        T.ok(top <= 1 and bottom <= 1, tostring(s.text or s.metro) .. " never brighter than its paint")
        T.ok(bottom >= 0.5, tostring(s.text or s.metro) .. " readable at its foot: " .. bottom)
        for _, c in ipairs(tint) do T.between(c, 0.8, 1, tostring(s.text or s.metro) .. " tint is gentle") end
        if (s.look or "ad") == "ad" and (s.style == "tv" or s.style == "neon") then
            T.ok(top == 1 and bottom == 1, tostring(s.text or s.metro) .. " is its own light")
        elseif City.SignFloodlit(s) then
            T.ok(top > bottom, tostring(s.text or s.metro) .. " brighter under its lamps")
        else
            T.ok(top >= bottom, tostring(s.text or s.metro) .. " lit from above")
        end
    end
end)

T.test("signs (client): painted once into a render target, drawn as one quad at the case's front", function()
    local City, L, cl = city()
    local env = cl.env
    local pushes, quads, painted, verts = 0, 0, {}, nil
    env.GetRenderTargetEx = function(name, w, h) return { GetName = function() return name end, w = w, h = h } end
    env.CreateMaterial = function(name, shader, params) return { name = name, params = params } end
    env.render.PushRenderTarget = function(rt) pushes = pushes + 1 painted[rt:GetName()] = (painted[rt:GetName()] or 0) + 1 end
    env.render.PopRenderTarget = function() end
    env.render.Clear = function() end
    env.render.SetMaterial = function() end
    env.cam.Start2D = function() end
    env.cam.End2D = function() end
    env.FrameNumber = function() return 1 end
    env.mesh = { Begin = function() quads = quads + 1 verts = {} end, End = function() end,
                 Position = function(v) verts[#verts + 1] = { v.x, v.y, v.z } end,
                 TexCoord = function() end, Color = function() end, AdvanceVertex = function() end }
    env.surface.SetMaterial = function() end
    env.surface.DrawTexturedRect = function() end
    env.surface.DrawPoly = function() end
    env.surface.DrawOutlinedRect = function() end
    env.draw.SimpleTextOutlined = env.draw.SimpleText
    env.draw.NoTexture = function() end
    -- GMod's string.Explode, which the shim lacks (plain separator only)
    local str = env.string or string
    str.Explode = str.Explode or function(sep, text)
        local out, i = {}, 1
        while true do
            local a, b = text:find(sep, i, true)
            if not a then out[#out + 1] = text:sub(i) return out end
            out[#out + 1] = text:sub(i, a - 1)
            i = b + 1
        end
    end
    env.Matrix = function() return { Translate = function() end, Scale = function() end, Rotate = function() end } end
    env.EyeAngles = function() return env.Angle(0, 0, 0) end
    env.render.GetViewSetup = function() return { fov = 100, aspect = 16 / 9 } end
    env.GetConVar("bmx_city_trains"):SetInt(0)
    env.GetConVar("bmx_city_plants"):SetInt(0)
    -- no product photos here (no 3D in the shim): the faces paint without
    City.AdPicture = function() return nil end
    local sign = L.signs[1]
    -- stand in front of the first sign and draw them all
    env.EyePos = function() return env.Vector(sign.face[1] + sign.normal[1] * 500, sign.face[2] + sign.normal[2] * 500, sign.face[3]) end
    City.meshes, City._layout = {}, L
    local errs = #cl.errors
    City.Draw(false, true, false)
    T.ok(pushes >= 1, "faces painted into render targets: " .. pushes)
    T.ok(quads >= 1, "faces drawn: " .. quads)
    T.eq(#cl.errors, errs, "no sign errored while painting: " .. table.concat(cl.errors, " | ", errs + 1))
    -- the first sign's quad sits exactly on its case's open front
    local want = City.SignCorners(sign)
    local seen = false
    City.Draw(false, true, false)
    for k, v in pairs(painted) do T.eq(v, 1, k .. " painted once, not every frame") end
    -- the last quad drawn belongs to some sign; check the first one by redrawing it alone
    local only = { signs = { sign }, mood = L.mood, lamps = L.lamps }
    City._layout = only
    City.Draw(false, true, false)
    for v = 1, 4 do
        if verts[v] then
            seen = true
            for a = 1, 3 do T.near(verts[v][a], want[v][a], 1e-6, "corner " .. v) end
        end
    end
    T.ok(seen, "the first sign was drawn from in front of it")
end)

T.test("signs: tools/city/export.lua writes every sign (station signs have no text, ads no colour)", function()
    local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "tests"
    local f = io.popen("lua5.1 " .. here .. "/../tools/city/export.lua gm_skatepark 2>&1")
    local out = f:read("*a")
    f:close()
    local City, L = city()
    T.ok(out:sub(1, 1) == "{" and out:find('"signs":%['), "export wrote JSON: " .. out:sub(1, 120))
    local n = 0
    for _ in out:match('"signs":(%b[])'):gmatch('"text":') do n = n + 1 end
    T.eq(n, #L.signs, "every sign exported")
end)

-- Everything of a line a sign must keep clear of, as boxes { name, {x0,y0,z0,x1,y1,z1} }:
-- its colliders, the whole viaduct (deck, girders, rails, truss, bracing), each
-- portal with its frame, and the volume every train model sweeps along it.
local function lineParts(City, L)
    local V = City.Viaduct
    local parts = {}
    local function lineBox(l, a0, a1, c0, c1, z0, z1)
        if l.axis == "y" then return { l.at + c0, a0, z0, l.at + c1, a1, z1 } end
        return { a0, l.at + c0, z0, a1, l.at + c1, z1 }
    end
    for _, so in ipairs(L.solids) do
        if so.name:find("^line") then
            for _, b in ipairs(so.boxes) do parts[#parts + 1] = { so.name .. " collider", b } end
        end
    end
    for _, l in ipairs(L.lines) do
        local hw = V.width / 2
        parts[#parts + 1] = { l.name .. " viaduct", lineBox(l, l.from, l.to, -hw, hw, l.deck - V.slab - V.girder, l.deck + V.truss + 16) }
        for _, M in ipairs(City.TrainModels or { { w = 136, h = 205, len = 650 } }) do
            local w = math.max(M.w, 1) / 2
            local reach = l.runout + l.cars * ((M.len or 650) + 14)
            parts[#parts + 1] = { l.name .. " train " .. tostring(M.model), lineBox(l, l.from - reach, l.to + reach, -w, w,
                l.deck + V.rail, l.deck + V.rail + M.h) }
        end
    end
    -- each portal: its frame pieces, and the opening they surround
    local ends = {}
    for _, p in ipairs(L.portals or {}) do
        parts[#parts + 1] = { p.line .. " portal frame", p.box }
        local k = p.line .. ":" .. math.floor((p.box[2] + p.box[5]) / 2 / 400) .. ":" .. math.floor((p.box[1] + p.box[4]) / 2 / 400)
        local u = ends[k]
        if not u then ends[k] = { p.box[1], p.box[2], p.box[3], p.box[4], p.box[5], p.box[6] }
        else for a = 1, 3 do u[a] = math.min(u[a], p.box[a]) u[a + 3] = math.max(u[a + 3], p.box[a + 3]) end end
    end
    for k, u in pairs(ends) do parts[#parts + 1] = { k .. " portal", u } end
    return parts
end

-- a station sign's whole volume: its case (face to wall) and, for a hung
-- sign, its hangers
local function signBox(s)
    local b = s.case
    return { b[1], b[2], b[3], b[4], b[5], math.max(b[6], s.hang or b[6]) }
end

City_SIGN_TRACK_MARGIN = 32

local function trackClashes(City, L)
    local parts = lineParts(City, L)
    local M = City_SIGN_TRACK_MARGIN
    local out = {}
    for _, s in ipairs(L.signs) do
        if s.look == "transit" or s.metro then
            local a = signBox(s)
            for _, p in ipairs(parts) do
                local b = p[2]
                if a[1] < b[4] + M and a[4] > b[1] - M and a[2] < b[5] + M and a[5] > b[2] - M and a[3] < b[6] + M and a[6] > b[3] - M then
                    out[#out + 1] = string.format("%s sign at (%.0f,%.0f,%.0f) within %d of %s", tostring(s.metro or s.text),
                        s.face[1], s.face[2], s.face[3], M, p[1])
                end
            end
        end
    end
    return out, parts
end

T.test("station signs: clear of the tracks, viaduct, portals and every train's path, by a margin", function()
    local City, L = city()
    local hits, parts = trackClashes(City, L)
    T.ok(#parts > 20, "parts to keep clear of: " .. #parts)
    T.ok(#L.portals >= 24, "every portal's frame is in the layout: " .. #L.portals)
    local n = 0
    for _, s in ipairs(L.signs) do if s.look == "transit" or s.metro then n = n + 1 end end
    T.ok(n >= 6, "station signs: " .. n)
    T.eq(#hits, 0, "signs clashing with a line: " .. table.concat(hits, "; "))
end)

T.test("station signs: each still reads as its line's, by its own portal", function()
    local City, L = city()
    for _, s in ipairs(L.signs) do
        if s.metro then
            local l
            for _, x in ipairs(L.lines) do if x.name == s.metro then l = x end end
            T.ok(l, s.metro .. " is a line")
            -- on the end wall the line runs into, near its portal
            local along = l.axis == "y" and s.face[2] or s.face[1]
            local across = l.axis == "y" and s.face[1] or s.face[2]
            T.ok(math.abs(along - l.from) < 40 or math.abs(along - l.to) < 40, s.metro .. " on an end wall")
            local dz = s.face[3] - l.deck
            T.ok(math.abs(across - l.at) + math.max(0, math.abs(dz) - 400) <= 700, s.metro .. " sign within sight of its portal")
        end
    end
end)
