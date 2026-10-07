--[[--------------------------------------------------------------------------
    The subway: its routes, the trains running them, the rumble that rides
    them, and where each one says it is going (cl_city.lua, sh_city.lua,
    sh_city_maps.lua).

    What went wrong, and is checked here:
      - no train was ever drawn: the car model was asked for through
        util.IsValidModel, which a client answers "no" for anything not yet
        precached, while the wheels' rumble played on its own anyway
      - the station signs at both portals of a line named one place, whichever
        way the train went
----------------------------------------------------------------------------]]

local F = require("lib.fixture")

local function layout()
    local sv, world = F.server()
    local cl = F.client(world)
    local City = cl.env.BMX.City
    return City, City.Build(City.Maps.gm_skatepark), cl, world
end

-- A client with the city built and the trains on, stub meshes, recorded
-- sounds. `models` says which files exist ("all", "base" = no content_hl2,
-- "none"); util.IsValidModel always says no, as it does on a real client
-- before a precache.
local function trainClient(models)
    local sv, world = F.server()
    local cl = F.client(world)
    local env = cl.env
    env.game.GetMap = function() return "gm_skatepark" end
    env.Mesh = function() local m = {} function m:Draw() end function m:Destroy() end return m end
    env.MATERIAL_QUADS = 4
    env.CreateMaterial = function(name, shader, params) return { name = name, params = params } end
    env.mesh = { Begin = function() end, Position = function() end, TexCoord = function() end,
                 Color = function() end, AdvanceVertex = function() end, End = function() end }
    env.SysTime = function() return 0 end
    env.render.SetMaterial = function() end
    env.render.GetViewSetup = function() return { fov = 100, aspect = 16 / 9 } end
    env.render.SuppressEngineLighting = function() end
    env.render.ResetModelLighting = function() end
    env.render.SetModelLighting = function() end
    env.GetConVar("bmx_city_signs"):SetInt(0)
    env.GetConVar("bmx_city_plants"):SetInt(0)
    env.GetConVar("bmx_city_trains"):SetInt(1)
    env.util.IsValidModel = function() return false end
    local outro = "models/props_trainstation/train_outro_car01.mdl"
    env.file.Exists = function(path)
        if models == "none" then return false end
        if models == "base" and path == outro then return false end
        return path:find("^models/") ~= nil
    end
    -- sound: one recorded channel per PlayFile, played at once
    local S = { channels = {}, horns = {} }
    env.sound = {
        PlayFile = function(path, flags, cb)
            local ch = { path = path, flags = flags, playing = false, stopped = false, vol = nil }
            function ch:IsValid() return not self.stopped end
            function ch:EnableLooping(b) self.loop = b end
            function ch:Set3DFadeDistance() end
            function ch:SetVolume(v) self.vol = v end
            function ch:SetPos(p) self.pos = p end
            function ch:Play() self.playing = true end
            function ch:Stop() self.playing = false self.stopped = true end
            S.channels[#S.channels + 1] = ch
            cb(ch)
        end,
        Play = function(path, pos) S.horns[#S.horns + 1] = { path = path, pos = pos } end,
    }
    env.EyePos = function() return env.Vector(1700, -500, 120) end
    env.EyeAngles = function() return env.Angle(-30, 90, 0) end
    local City = env.BMX.City
    City.ClientClear()
    T.ok(City.ClientBuild(), "built")
    local function frame(t)
        world.time = t
        cl.drawnCS = {}
        env.hook.Run("PostDrawOpaqueRenderables", false, true, false)
        return cl.drawnCS
    end
    local function live()
        local out = {}
        for _, ch in ipairs(S.channels) do if ch.playing then out[#out + 1] = ch end end
        return out
    end
    return City, City._layout, frame, S, live, env
end

-- a time when line `l` has a train halfway across the park
local function midRun(City, l)
    local len = l.to - l.from
    local train = l.cars * City.TrainCar.length + (l.cars - 1) * City.TrainCar.gap
    return l.offset + (l.runout + (len + train) / 2) / l.speed
end

-- which line a recorded car belongs to: the one whose axis it sits on
local function carsOn(City, L, l, drawn)
    local out = {}
    for _, d in ipairs(drawn) do
        local on = (l.axis == "y") and math.abs(d.pos.x - l.at) < 1 or math.abs(d.pos.y - l.at) < 1
        if on and math.abs(d.pos.z - (l.deck + City.Viaduct.rail)) < 150 then out[#out + 1] = d end
    end
    return out
end

T.test("routes: every line spans the park wall to wall, with a named terminus past each end and a sign at each portal", function()
    local City, L = layout()
    local p = City.Maps.gm_skatepark.park
    T.eq(#L.lines, 3, "three lines")
    for _, l in ipairs(L.lines) do
        T.ok(l.axis == "x" or l.axis == "y", l.name .. " axis")
        T.ok(l.to > l.from, l.name .. " runs from low to high")
        if l.axis == "y" then
            T.eq(l.from, p[2], l.name .. " starts at the south wall") T.eq(l.to, p[5], l.name .. " ends at the north wall")
        else
            T.eq(l.from, p[1], l.name .. " starts at the west wall") T.eq(l.to, p[4], l.name .. " ends at the east wall")
        end
        T.ok(l.speed > 0 and l.period > 0 and l.cars >= 1, l.name .. " timetable")
        T.ok(l.ends and l.ends.to and l.ends.to ~= "" and l.ends.from and l.ends.from ~= "", l.name .. " names both termini")
        T.ok(l.ends.to ~= l.ends.from, l.name .. " goes two different places")
        T.ok(l.label and l.label ~= "" and l.color, l.name .. " has a number and a colour")
        -- a station sign at each portal, on that end's wall, facing the park
        local atEnd = { [l.from] = 0, [l.to] = 0 }
        for _, s in ipairs(L.signs) do
            if s.look == "transit" and s.metro == l.name then
                T.ok(City.SignLine(L, s) == l, "sign resolves to " .. l.name)
                local along = (l.axis == "y") and s.pos[2] or s.pos[1]
                local across = (l.axis == "y") and s.pos[1] or s.pos[2]
                local inward = (l.axis == "y") and s.normal[2] or s.normal[1]
                local e = math.abs(along - l.from) < 20 and l.from or (math.abs(along - l.to) < 20 and l.to or nil)
                T.ok(e ~= nil, l.name .. " sign on an end wall, at " .. along)
                if e then
                    atEnd[e] = atEnd[e] + 1
                    T.ok(inward == (e == l.from and 1 or -1), l.name .. " sign faces the park")
                end
                T.ok(math.abs(across - l.at) <= 500, l.name .. " sign by its portal")
            end
        end
        T.eq(atEnd[l.from], 1, l.name .. " one sign at the " .. l.from .. " end")
        T.eq(atEnd[l.to], 1, l.name .. " one sign at the " .. l.to .. " end")
    end
    -- no transit sign left that names no line
    for _, s in ipairs(L.signs) do
        if s.look == "transit" then T.ok(City.SignLine(L, s) ~= nil, "transit sign " .. tostring(s.metro) .. " has a line") end
    end
end)

T.test("trains advance: every second the cars move speed units the way the train is going", function()
    local City, L = layout()
    for _, l in ipairs(L.lines) do
        for cycle = 0, 1 do
            local t0 = midRun(City, l) + cycle * l.period
            local a = City.TrainAt(l, t0)
            T.ok(a and a.cycle == cycle, l.name .. " running at " .. t0)
            local last = a
            for k = 1, 5 do
                local t = t0 + k * 0.5
                local b = City.TrainAt(l, t)
                T.ok(b, l.name .. " still running")
                T.near(b.head - last.head, l.speed * 0.5, 1e-6, l.name .. " head moved")
                for i = 1, l.cars do
                    local x0, y0 = City.CarPos(l, last, i)
                    local x1, y1 = City.CarPos(l, b, i)
                    local moved = (l.axis == "y") and (y1 - y0) or (x1 - x0)
                    T.near(moved, b.dir * l.speed * 0.5, 1e-6, l.name .. " car " .. i .. " moved along")
                    T.near((l.axis == "y") and x1 or y1, l.at, 1e-9, l.name .. " car on its track")
                end
                last = b
            end
        end
    end
end)

T.test("trains are drawn on the client, and move, even though util.IsValidModel says no", function()
    local City, L, frame = trainClient("all")
    for _, l in ipairs(L.lines) do
        local t = midRun(City, l)
        local d0 = carsOn(City, L, l, frame(t))
        T.eq(#d0, l.cars, l.name .. " draws its " .. l.cars .. " cars")
        T.eq(d0[1] and d0[1].model, "models/props_trainstation/train_outro_car01.mdl", l.name .. " car model")
        local st = City.TrainAt(l, t)
        local d1 = carsOn(City, L, l, frame(t + 1))
        T.eq(#d1, l.cars, l.name .. " still there a second later")
        for i = 1, math.min(#d0, #d1) do
            local moved = (l.axis == "y") and (d1[i].pos.y - d0[i].pos.y) or (d1[i].pos.x - d0[i].pos.x)
            T.near(moved, st.dir * l.speed, 1e-6, l.name .. " car " .. i .. " moved a second's run")
        end
        -- after the run, before the next: nothing on the line
        local gone = l.offset + City.TrainAt(l, l.offset + 0.01).run + 0.5
        T.eq(#carsOn(City, L, l, frame(gone)), 0, l.name .. " empty between trains")
    end
end)

T.test("without the HL2 train car, the base-game coach runs instead, floor on the rails", function()
    local City, L, frame = trainClient("base")
    local l = L.lines[1]
    local drawn = carsOn(City, L, l, frame(midRun(City, l)))
    T.eq(#drawn, l.cars, "cars drawn")
    local M = City.TrainModels[2]
    T.eq(drawn[1] and drawn[1].model, M.model, "fallback model")
    T.near(drawn[1].pos.z, l.deck + City.Viaduct.rail + M.lift, 1e-6, "fallback floor on the rails")
end)

T.test("every train model fits the truss and its slot on the timetable", function()
    local City = layout()
    local V = City.Viaduct
    for _, M in ipairs(City.TrainModels) do
        T.ok(M.w < V.width - 2 * 16, M.model .. " width " .. M.w .. " inside the chords")
        T.ok(V.rail + M.h < V.truss, M.model .. " roof " .. M.h .. " under the top bracing")
        T.ok(M.len <= City.TrainCar.length + City.TrainCar.gap / 2, M.model .. " length " .. M.len .. " fits its slot")
    end
end)

T.test("the rumble rides the train: heard where the train is, loud over the park, silent in the portals", function()
    local City, L = layout()
    for _, l in ipairs(L.lines) do
        local first = City.TrainAt(l, l.offset)
        T.near(City.TrainSoundAt(l, first).vol, 0, 1e-9, l.name .. " silent at the start, deep in the portal")
        local run = first.run
        local loud = 0
        for ph = 0, run, 0.1 do
            local st = City.TrainAt(l, l.offset + ph)
            local snd = City.TrainSoundAt(l, st)
            -- on the track, at the train
            local along = (l.axis == "y") and snd.y or snd.x
            local across = (l.axis == "y") and snd.x or snd.y
            T.near(across, l.at, 1e-9, l.name .. " sound on the track")
            local hx = (l.axis == "y") and select(2, City.CarPos(l, st, 1)) or City.CarPos(l, st, 1)
            local tx = (l.axis == "y") and select(2, City.CarPos(l, st, l.cars)) or City.CarPos(l, st, l.cars)
            local lo, hi = math.min(hx, tx) - City.TrainCar.length, math.max(hx, tx) + City.TrainCar.length
            T.ok(along >= lo - 1e-6 and along <= hi + 1e-6, l.name .. " sound within the train")
            if snd.vol > 0 then
                T.ok(along >= l.from - City.TrainFade and along <= l.to + City.TrainFade, l.name .. " heard only near the park")
            end
            -- loud exactly when part of the train is out over the park
            local head, tail = st.head, st.head - st.train
            local out = head >= 0 and tail <= (l.to - l.from)
            if out then T.near(snd.vol, 1, 1e-9, l.name .. " full while out") loud = loud + 1 end
            if head < -City.TrainFade or tail > (l.to - l.from) + City.TrainFade then
                T.near(snd.vol, 0, 1e-9, l.name .. " silent while hidden")
            end
        end
        T.ok(loud > 0, l.name .. " heard over the park")
        local last = City.TrainAt(l, l.offset + run - 0.01)
        T.near(City.TrainSoundAt(l, last).vol, 0, 1e-9, l.name .. " silent as the run ends")
        T.eq(City.TrainSoundAt(l, nil), nil, "no train, no sound")
    end
end)

T.test("on the client the rumble starts with the train, follows it, and stops when it goes", function()
    local City, L, frame, S, live = trainClient("all")
    local l = L.lines[1]
    -- line1 alone: before line2/line3 start (offsets 9 and 17)
    T.eq(#live(), 0, "silence before any train")
    frame(1.4)                          -- the nose just out of the portal: the horn
    local st0 = City.TrainAt(l, 2)
    T.ok(st0, "line1 running at t=2")
    frame(2)
    local chs = live()
    T.eq(#chs, 1, "one channel playing")
    local ch = chs[1]
    T.eq(ch.path, City.TrainSound, "the wheels")
    T.ok(ch.loop, "looping")
    local want = City.TrainSoundAt(l, st0)
    T.near(ch.pos.y, want.y, 1e-6, "at the train") T.near(ch.pos.x, l.at, 1e-6, "on the track")
    T.near(ch.vol, want.vol, 1e-9, "as loud as the train says")
    local y0 = ch.pos.y
    frame(4)
    T.ok(ch.playing, "still playing")
    T.ok((ch.pos.y - y0) * st0.dir > 0, "moved with the train")
    T.near(ch.pos.y, City.TrainSoundAt(l, City.TrainAt(l, 4)).y, 1e-6, "still at the train")
    -- the run ends (line1 run is ~5.3 + ~3.3 s): stopped, nothing playing for it
    local gone = City.TrainAt(l, 0.01).run + 0.5
    T.ok(City.TrainAt(l, gone) == nil, "line1 done")
    frame(gone)
    T.ok(not ch.playing and ch.stopped, "stopped when the train went in")
    -- the horn sounded once, near the portal mouth, and only once
    local horns = 0
    for _, h in ipairs(S.horns) do if math.abs(h.pos.x - l.at) < 1 then horns = horns + 1 end end
    T.eq(horns, 1, "one horn for line1's run")
end)

T.test("no car model on this client: no train, and no rumble playing on its own", function()
    local City, L, frame, S, live = trainClient("none")
    local l = L.lines[1]
    T.eq(#carsOn(City, L, l, frame(midRun(City, l))), 0, "nothing drawn")
    T.eq(#live(), 0, "nothing heard")
    T.eq(#S.horns, 0, "no horn")
end)

T.test("a joiner mid-run hears no horn for a train already over the park", function()
    local City, L = layout()
    for _, l in ipairs(L.lines) do
        local st = City.TrainAt(l, midRun(City, l))
        T.ok(not City.TrainHornDue(l, st), l.name .. " no horn halfway")
        local nose = City.TrainAt(l, l.offset + l.runout / l.speed)
        T.ok(City.TrainHornDue(l, nose), l.name .. " horn as the nose comes out")
    end
end)

T.test("directions: the same way always goes to the same place, on both ends of the train and both portals' signs", function()
    local City, L = layout()
    for _, l in ipairs(L.lines) do
        -- the signs at the two portals read the same rows, in the same order
        local signs = {}
        for _, s in ipairs(L.signs) do if s.metro == l.name then signs[#signs + 1] = City.TransitRows(City.SignLine(L, s)) end end
        T.eq(#signs, 2, l.name .. " two signs")
        for i = 1, 2 do
            T.eq(signs[1][i].dest, signs[2][i].dest, l.name .. " row " .. i .. " destination on both signs")
            T.eq(signs[1][i].bound, signs[2][i].bound, l.name .. " row " .. i .. " direction on both signs")
            T.eq(signs[1][i].dir, signs[2][i].dir, l.name .. " row " .. i .. " way on both signs")
        end
        T.ok(signs[1][1].dest ~= signs[1][2].dest, l.name .. " the two ways go to different places")
        local rowFor = {}
        for _, r in ipairs(signs[1]) do rowFor[r.dir] = r end
        -- each run: front and rear boards say the same, and agree with the signs
        for cycle = 0, 3 do
            local st = City.TrainAt(l, midRun(City, l) + cycle * l.period)
            local b = City.TrainBoards(l, st)
            T.eq(#b, 2, l.name .. " a board at each end")
            T.eq(b[1].dest, b[2].dest, l.name .. " nose and tail say the same")
            T.eq(b[1].dest, rowFor[st.dir].dest, l.name .. " the train agrees with the signs")
            T.eq(b[1].label, l.label, l.name .. " board shows the line")
            -- the destination is the end it is heading for, and the compass way is right
            local later = City.TrainAt(l, midRun(City, l) + cycle * l.period + 1)
            local x0, y0 = City.CarPos(l, st, 1)
            local x1, y1 = City.CarPos(l, later, 1)
            local step = (l.axis == "y") and (y1 - y0) or (x1 - x0)
            T.eq(b[1].dest, step > 0 and l.ends.to or l.ends.from, l.name .. " heads for the end it names")
            local want = (l.axis == "y") and (step > 0 and "NORTHBOUND" or "SOUTHBOUND") or (step > 0 and "EASTBOUND" or "WESTBOUND")
            T.eq(rowFor[st.dir].bound, want, l.name .. " compass way")
            -- the nose board is ahead of the lead car facing forward, the tail behind the last facing back
            local nose, tail = b[1], b[2]
            T.ok(nose.front and not tail.front, l.name .. " nose then tail")
            local na = (l.axis == "y") and nose.y or nose.x
            local ta = (l.axis == "y") and tail.y or tail.x
            local la = (l.axis == "y") and y0 or x0
            local nn = (l.axis == "y") and nose.ny or nose.nx
            local tn = (l.axis == "y") and tail.ny or tail.nx
            T.ok((na - la) * st.dir > 0 and nn * st.dir > 0, l.name .. " nose board ahead, facing ahead")
            T.ok((la - ta) * st.dir > 0 and tn * st.dir < 0, l.name .. " tail board behind, facing back")
        end
    end
end)

T.test("the station signs draw both ways, the same on both portals; the trains draw their boards", function()
    local City, L, frame, S, live, env = trainClient("all")
    env.GetConVar("bmx_city_signs"):SetInt(1)
    env.GetConVar("bmx_city_trains"):SetInt(0)      -- the signs alone first
    env.cam.Start3D2D = function() end
    env.cam.End3D2D = function() end
    env.surface.DrawPoly = function() end
    env.surface.DrawOutlinedRect = function() end
    env.surface.SetMaterial = function() end
    env.surface.DrawTexturedRect = function() end
    env.draw.NoTexture = function() end
    env.Material = function() return {} end
    -- read what a transit sign draws, one sign at a time
    local texts = {}
    local realTexts = env.draw.SimpleText
    for _, l in ipairs(L.lines) do
        local got = {}
        for _, s in ipairs(L.signs) do
            if s.metro == l.name then
                local list = {}
                env.draw.SimpleText = function(t) list[#list + 1] = tostring(t) end
                -- stand in front of this sign and draw only it
                local keep = L.signs
                L.signs = { s }
                env.EyePos = function() return env.Vector(s.pos[1] + s.normal[1] * 500, s.pos[2] + s.normal[2] * 500, s.pos[3]) end
                frame(1000.5)
                L.signs = keep
                got[#got + 1] = table.concat(list, "|")
            end
        end
        T.eq(#got, 2, l.name .. " two signs drawn")
        T.eq(got[1], got[2], l.name .. " both signs read: " .. tostring(got[1]))
        for _, r in ipairs(City.TransitRows(l)) do
            T.ok(got[1]:find(r.dest, 1, true) and got[1]:find(r.bound, 1, true), l.name .. " sign shows " .. r.bound .. " " .. r.dest)
        end
        texts[l.name] = got[1]
    end
    env.draw.SimpleText = realTexts
    env.GetConVar("bmx_city_trains"):SetInt(1)
    -- a train on screen: its boards were laid out with its destination
    local l = L.lines[1]
    env.EyePos = function() return env.Vector(1700, -500, 120) end
    frame(midRun(City, l))
    local n = 0
    for _, b in ipairs(City._trainBoards) do
        if b.label == l.label then n = n + 1 T.eq(b.dest, City.LineDest(l, City.TrainAt(l, midRun(City, l)).dir), "board destination") end
    end
    T.eq(n, 2, "line1's two boards")
end)
