--[[--------------------------------------------------------------------------
    lua/petopia_bmx_fall/sh_city_maps.lua

    The city, per map. One table per map name; sh_city.lua builds it. To give
    another map a city, measure its play box and add an entry -- nothing else
    changes.

    THE NUMBERS FOR gm_skatepark ARE MEASURED FROM ITS BSP, not eyeballed
    (2026-10-07, from the brush and entity lumps):

        play box     x -256..3584, y -1792..768, floor z 64
        brick wall   to z 528 on all four sides, 256 thick
        sky brushes  above the wall, ceiling at z 1720
        sun          light_environment pitch -28, yaw 0: light travels +x, so
                     the sun sits low in the WEST and the east row's fronts
                     catch it

    Every ramp in the map was measured too (each one's WorldSpaceAABB on the
    running server, in tests/test_city.lua; NOT the models' vertices, which
    studiomdl stores turned 90 degrees from entity space -- the first layout
    was checked against those and put a pier on the halfpipe): the piers stand in the lanes between
    them, the viaducts pass 500+ units above the tallest coping, and nothing
    the city adds touches the floor anywhere else.
----------------------------------------------------------------------------]]

BMX = BMX or {}
BMX.City = BMX.City or {}
BMX.City.Maps = BMX.City.Maps or {}

local ALL_OLD = { "brick", "white", "grey", "ped", "yellow", "ochre", "tan", "red", "stone", "dark", "cream" }

BMX.City.Maps.gm_skatepark = {
    seed = 20261007,

    -- x0, y0, z0, x1, y1, z1: the inside of the box. Faces are only built if
    -- some point in here can see them.
    park = { -256, -1792, 64, 3584, 768, 1720 },
    ground = 64,
    sunPitch = 28, sunYaw = 180,

    -- The buildings standing on the wall. Their facades stand `inset` inside
    -- it, so they cover the brick from the floor up; their bodies go out into
    -- the void. 5 to 13 floors: z 704 to 1728, the low ones well clear of the
    -- sky ceiling, the tall ones rising past it.
    frontage = {
        inset = 4,
        minWidth = 384, maxWidth = 768,
        minDepth = 512, maxDepth = 896,
        minFloors = 5, maxFloors = 13,
        jitter = 0,
        styles = ALL_OLD,
        towerChance = 0.35, towerMin = 3, towerMax = 9,
    },

    -- Taller blocks behind, seen over the frontage's roofs.
    backRow = {
        offset = 1280, inset = 0, street = false,
        minWidth = 512, maxWidth = 1024,
        minDepth = 512, maxDepth = 1024,
        minFloors = 12, maxFloors = 24,
        jitter = 512,
        styles = { "office", "glass", "cream", "dark", "stone", "grey", "white" },
        towerChance = 0.4, towerMin = 4, towerMax = 12,
    },

    -- Free-standing towers further out, all the way round: the skyline.
    skyline = {
        count = 44,
        minDist = 3200, maxDist = 9000,  -- from the park's edge
        clear = 3000,                    -- never inside the inner rows
        minWidth = 512, maxWidth = 1280,
        minFloors = 20, maxFloors = 58,
        styles = { "glass", "office", "glass", "dark", "cream", "stone" },
        crownChance = 0.5,
    },

    -- The subway. Two lines cross the park north-south on the low level; one
    -- crosses east-west above them, over both. The low decks at z 1000 sit
    -- 517 above the halfpipe's coping (z 483), the tallest thing in the park.
    -- Truss tops 1224; the high line's girders bottom out at 1296; its truss
    -- top at 1624 stays under the sky ceiling at 1720.
    --
    -- No line ends in a building. Where a line crosses a wall it passes over
    -- a low station house standing in a gap in the frontage, then runs on
    -- down an open street through the back row and the skyline, `reach`
    -- (11000) past the wall: beyond the furthest tower, in the haze. Its
    -- trains come in from out there and go back out there, on two tracks,
    -- one each way.
    viaducts = {
        -- Slow enough to watch: 600 units/s (about 30 mph) puts a train over
        -- the park for 7-8 seconds, and one comes along on some line every
        -- 10 seconds or so, each way in turn.
        -- Each line runs both ways: `ends` names the terminus past each end
        -- (`to` is where +1 trains go, `from` where -1 trains go), and the
        -- trains' boards and the station signs all read from it.
        { name = "line1", axis = "y", at = 1685, from = -1792, to = 768, deck = 1000,
          period = 24, offset = 0, cars = 3, speed = 600, reach = 11000,
          label = "1", color = { 220, 40, 40 }, ends = { to = "SPOONER ST", from = "QUAHOG HARBOR" } },
        { name = "line2", axis = "y", at = 2665, from = -1792, to = 768, deck = 1000,
          period = 29, offset = 9, cars = 4, speed = 600, reach = 11000,
          label = "2", color = { 30, 120, 220 }, ends = { to = "TOY FACTORY", from = "JAMES WOODS HIGH" } },
        { name = "line3", axis = "x", at = -300, from = -256, to = 3584, deck = 1400,
          period = 35, offset = 17, cars = 4, speed = 700, reach = 11000,
          label = "3", color = { 30, 160, 70 }, ends = { to = "DOWNTOWN", from = "PAWTUCKET BREWERY" } },
    },
    -- the station houses under the lines: this deep, from the wall out
    stationDepth = 512,
    wallTop = 528,

    -- Piers under the crossings, in clear lanes (tests/test_city.lua proves
    -- the clearance against every ramp). Each carries the low line on its cap
    -- and a steel post up to the high line.
    --   (1685, -300): the lane between the halfpipe (x <= 1515) and the funbox
    --                 (x >= 1855), north of the spine (y <= -1327)
    --   (2665, -300): between the funbox (x <= 2401) and the rail (x >= 2914),
    --                 north of the spines (y <= -505)
    piers = {
        { name = "pier1", x = 1685, y = -300, size = 96, top = 1000 - 40 - 64,
          postFrom = 1000 + 224 + 16, postTo = 1400 - 40 - 64 },
        { name = "pier2", x = 2665, y = -300, size = 96, top = 1000 - 40 - 64,
          postFrom = 1000 + 224 + 16, postTo = 1400 - 40 - 64 },
    },

    -- The signs: billboard ads for Quahog, Rhode Island, the Family Guy town
    -- (Petopia is Peter's nation, founded in his back yard), selling the
    -- show's places and things; station signs for the metro; green street
    -- signs. Family friendly: the town's businesses and gags, nothing edgier.
    --
    -- Every ad has a `style` (cl_city.lua: comic, classic, minimal, tv, sale,
    -- split, neon) so no two neighbours look alike, and a `pic`: the product,
    -- photographed from base-game models (the Peter Griffin player model is
    -- the server's, so a slot with him always lists a fallback).
    -- pos is the panel's centre on the face; normal points at the park.
    signs = {
        -- north wall
        { look = "ad", style = "classic", text = "THE DRUNKEN CLAM", sub = "Quahog's finest clam chowder",
          burst = "SERVING SINCE 1983", fine = "Now 40% clam. The other 60% is a family secret.",
          bg = { 243, 232, 206 }, fg = { 120, 28, 28 }, band = { 28, 46, 86 },
          pic = { { model = "models/props_junk/garbage_takeoutcarton001a.mdl", ang = { 0, -25, 0 } },
                  { model = "models/props_junk/garbage_coffeemug001a.mdl", at = { -3, 10, -2 }, ang = { 0, 200, 0 } } },
          picPitch = 14, picBg = { 120, 80, 50 },
          pos = { 1000, 758, 640 }, normal = { 0, -1, 0 }, w = 640, h = 260 },
        { look = "ad", style = "sale", text = "QUAHOG MALL", sub = "Now with a SECOND escalator!", price = "50% OFF",
          fine = "*Escalator may be stairs.", bg = { 255, 236, 60 }, bg2 = { 255, 214, 0 }, fg = { 220, 20, 30 },
          pic = { { model = "models/props_junk/shoe001a.mdl", ang = { 0, -30, 0 } },
                  { model = "models/props_c17/briefcase001a.mdl", at = { -14, 18, 0 }, ang = { 0, 20, 0 } } },
          picPitch = 18, picBg = { 90, 70, 40 },
          pos = { 2112, 758, 660 }, normal = { 0, -1, 0 }, w = 620, h = 250 },
        { look = "street", text = "SPOONER ST", sub = "31",
          pos = { 2200, 762, 340 }, normal = { 0, -1, 0 }, w = 320, h = 72 },
        -- the metro: a station sign on the front of each station house, over
        -- its entrance, under the line (`metro` names the line). Both of a
        -- line's signs read the same, one row per direction: NORTHBOUND ->
        -- where northbound trains go, and so on.
        { look = "transit", metro = "line1", sub = "Quahog Metro",
          pos = { 1685, 758, 420 }, normal = { 0, -1, 0 }, w = 640, h = 150 },
        { look = "transit", metro = "line1", sub = "Quahog Metro",
          pos = { 1685, -1782, 420 }, normal = { 0, 1, 0 }, w = 640, h = 150 },
        { look = "transit", metro = "line2", sub = "Quahog Metro",
          pos = { 2665, 758, 420 }, normal = { 0, -1, 0 }, w = 640, h = 150 },
        { look = "transit", metro = "line2", sub = "Quahog Metro",
          pos = { 2665, -1782, 420 }, normal = { 0, 1, 0 }, w = 640, h = 150 },
        { look = "transit", metro = "line3", sub = "Quahog Metro",
          pos = { -246, -300, 420 }, normal = { 1, 0, 0 }, w = 640, h = 150 },
        { look = "transit", metro = "line3", sub = "Quahog Metro",
          pos = { 3574, -300, 420 }, normal = { -1, 0, 0 }, w = 640, h = 150 },
        -- west wall
        { look = "ad", style = "minimal", text = "Goldman's", sub = "Feeling sick? Try feeling better.",
          fine = "Mort Goldman, pharmacist. Not a doctor.", burst = "PHARMACY", bg = { 22, 40, 34 }, band = { 0, 210, 140 },
          pic = { { model = "models/items/healthkit.mdl", ang = { 0, 20, 0 } },
                  { model = "models/healthvial.mdl", at = { 8, 16, 0 }, ang = { 0, -10, 0 } },
                  { model = "models/healthvial.mdl", at = { 8, -16, 0 }, ang = { 0, 15, 0 } } },
          picPitch = 18, picBg = { 40, 70, 60 },
          pos = { -248, 448, 440 }, normal = { 1, 0, 0 }, w = 600, h = 230 },
        { look = "ad", style = "neon", text = "CLEVELAND'S DELI", sub = "Sandwiches so good you'll say \"Oh, that's nice\"",
          fine = "OPEN LATE  *  NO BATHTUBS ON THE 2ND FLOOR", fg = { 255, 170, 40 }, band = { 60, 230, 255 },
          pic = { { model = "models/food/burger.mdl", ang = { 0, -20, 0 } }, { model = "models/food/hotdog.mdl", at = { 0, 12, -2 }, ang = { 0, 30, 0 } } },
          picPitch = 22, picBg = { 60, 40, 30 },
          pos = { -248, -1350, 620 }, normal = { 1, 0, 0 }, w = 620, h = 240 },
        { look = "street", text = "SPOONER ST", sub = "",
          pos = { -250, -1000, 340 }, normal = { 1, 0, 0 }, w = 320, h = 72 },
        -- east wall
        { look = "ad", style = "tv", text = "QUAHOG 5 NEWS", sub = "Local man rides bike. Film at 11.", burst = "LIVE",
          fine = "TOM TUCKER: USUALLY RIGHT, ALWAYS CONFIDENT", bg = { 30, 50, 110 }, bg2 = { 8, 12, 40 }, band = { 14, 40, 120 },
          pic = { { model = "models/props_c17/tv_monitor01.mdl", ang = { 0, -28, 0 } } }, picPitch = 10, picBg = { 30, 40, 80 },
          pos = { 3570, -1300, 640 }, normal = { -1, 0, 0 }, w = 640, h = 280 },
        { look = "ad", style = "classic", text = "FASTER THAN THE SPEED OF LOVE", sub = "The novel by Brian Griffin",
          burst = "NOW IN THE BARGAIN BIN", fine = "\"I have read it.\" -- Brian Griffin",
          bg = { 236, 228, 214 }, fg = { 40, 40, 60 }, band = { 150, 30, 40 },
          pic = { { model = "models/props_lab/binderredlabel.mdl", ang = { 0, -30, 0 } },
                  { model = "models/props_lab/bindergreen.mdl", at = { -4, 14, 0 }, ang = { 0, -10, 0 } } },
          picPitch = 16, picBg = { 90, 70, 60 },
          pos = { 3570, -40, 600 }, normal = { -1, 0, 0 }, w = 640, h = 260 },
        -- south wall
        { look = "ad", style = "comic", text = "HAPPY-GO-LUCKY TOYS", sub = "So safe, we tested them on Peter!", burst = "NEW\nTOYS!",
          fine = "*Batteries, instructions and happiness sold separately.",
          bg = { 255, 150, 220 }, bg2 = { 170, 60, 255 }, fg = { 255, 255, 80 }, band = { 60, 20, 120 }, burstColor = { 255, 120, 0 },
          pic = { { model = "models/maxofs2d/companion_doll.mdl", ang = { 0, -20, 0 } },
                  { model = "models/props_c17/doll01.mdl", at = { 2, 15, 0 }, ang = { 0, -35, 0 } },
                  { model = "models/maxofs2d/balloon_classic.mdl", at = { -6, -13, 12 } } },
          picPitch = 8, picBg = { 110, 60, 120 },
          pos = { 2200, -1784, 620 }, normal = { 0, 1, 0 }, w = 680, h = 260 },
        { look = "ad", style = "split", text = "SPOONER ST BMX", sub = "Brakes sold separately. Hehehehehe.", burst = "Peter rides one!",
          fine = "Helmets strongly recommended. Ask Peter why.", bg = { 255, 110, 30 }, bg2 = { 20, 110, 200 },
          pic = { { model = "models/props_junk/bicycle01a.mdl", ang = { 0, 75, 0 } },
                  { model = { "models/petaly/peter_griffin/petergriffin.mdl", "models/props_lab/huladoll.mdl" }, at = { -10, -38, -22 }, ang = { 0, -15, 0 }, scale = 0.8, seq = "idle_all_01" } },
          picPitch = 6, picBg = { 40, 90, 120 },
          pos = { 400, -1784, 640 }, normal = { 0, 1, 0 }, w = 640, h = 250 },
        { look = "ad", style = "neon", text = "THE DRUNKEN CLAM", sub = "Live music Fridays  *  Clam chowder all night",
          fine = "21+ AFTER 9  *  ASK HORACE ABOUT THE SPECIALS", fg = { 255, 70, 90 }, band = { 255, 200, 60 },
          pic = { { model = "models/props_junk/garbage_takeoutcarton001a.mdl", ang = { 0, 25, 0 } } }, picPitch = 12, picBg = { 50, 30, 40 },
          pos = { 1250, -1784, 640 }, normal = { 0, 1, 0 }, w = 560, h = 220 },
    },

    -- Rooftop billboards, standing on whatever frontage building is there.
    billboards = {
        { look = "ad", style = "split", side = "north", at = 1150, w = 1280, h = 480, back = 64,
          text = "VISIT PETORIA", sub = "The world's smallest nation! (It's a back yard.)", burst = "No passport needed!",
          fine = "Customs: please wipe your feet and do not pet the dog.", bg = { 30, 150, 230 }, bg2 = { 250, 200, 30 },
          pic = { { model = { "models/petaly/peter_griffin/petergriffin.mdl", "models/props_lab/huladoll.mdl" }, ang = { 0, -20, 0 }, seq = "idle_all_01" } },
          picPitch = 6, picBg = { 60, 110, 160 } },
        { look = "ad", style = "classic", side = "east", at = 200, w = 1024, h = 400, back = 64,
          text = "WELCOME TO QUAHOG", sub = "Come for the clams. Stay for the chicken fights.", burst = "EST. 1635",
          fine = "Pop. 75,000 and one very large chicken.", bg = { 240, 230, 205 }, fg = { 30, 70, 140 }, band = { 160, 30, 30 },
          pic = { { model = "models/props_canal/boat001a.mdl", ang = { 0, 60, 0 } } }, picPitch = 28, picBg = { 60, 90, 120 } },
        { look = "ad", style = "comic", side = "south", at = 2900, w = 960, h = 370, back = 64,
          text = "JAMES WOODS HIGH", sub = "Home of the Fighting Clams. Go... Clams?", burst = "GO\nTEAM!",
          fine = "*Bust of our founder. Resemblance to James Woods not guaranteed.",
          bg = { 255, 90, 90 }, bg2 = { 150, 10, 40 }, fg = { 255, 255, 255 }, band = { 60, 0, 20 }, burstColor = { 255, 210, 0 },
          pic = { { model = "models/props_combine/breenbust.mdl", ang = { 0, -22, 0 } } }, picPitch = 6, picBg = { 90, 40, 45 } },
    },

    -- Every ramp in the park: its footprint, read off the running server
    -- (each one's WorldSpaceAABB, gm_skatepark, 2026-10-07; tests/test_city.lua
    -- holds the same list as its truth). name, x0, y0, x1, y1, z0, z1.
    ramps = {
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
    },

    -- The street floor is shops (sh_city.lua, B:storefronts): false shop
    -- fronts on every frontage building, over the park's wall, in this order
    -- round the park (north, south, west, east; each wall west to east or
    -- south to north). Only where nothing of the park's stands in front: a
    -- stretch of wall with a ramp within 200 of it stays plain wall (no
    -- shop anyone could see or get to), and so does a station house's, under
    -- its line. Quahog's own: the town's shops and the family's, nothing
    -- edgier. `kind` picks what is in the window (cl_city.lua SHOP_WINDOWS);
    -- `awning` its colour (City.AwningColours), stripes with `awning2` or cream.
    storefronts = {
        shops = {
            { text = "GOLDMAN'S PHARMACY", kind = "pharmacy", bg = { 22, 70, 54 }, fg = { 240, 240, 228 }, awning = "green" },
            { text = "SPOONER ST BIKES", kind = "bikes", bg = { 196, 78, 22 }, fg = { 255, 255, 255 }, awning = "navy" },
            { text = "QUAHOG BAKERY", kind = "bakery", bg = { 240, 226, 196 }, fg = { 120, 60, 30 }, awning = "brown" },
            { text = "BRIAN'S BOOKS", kind = "books", bg = { 30, 40, 70 }, fg = { 232, 204, 128 }, awning = "red" },
            { text = "CLEVELAND'S DELI", kind = "deli", bg = { 150, 30, 30 }, fg = { 255, 240, 200 }, awning = "gold" },
            { text = "QUAHOG FLOWERS", kind = "flowers", bg = { 245, 230, 235 }, fg = { 170, 40, 90 }, awning = "green", awning2 = "gold" },
            { text = "PAWTUCKET RECORDS", kind = "records", bg = { 20, 20, 24 }, fg = { 255, 200, 60 }, awning = "red" },
            { text = "HAPPY-GO-LUCKY TOYS", kind = "toys", bg = { 255, 150, 220 }, fg = { 80, 20, 120 }, awning = "blue", awning2 = "gold" },
            { text = "THE CLAM SHACK", kind = "diner", bg = { 30, 110, 150 }, fg = { 255, 255, 255 }, awning = "red" },
            { text = "QUAHOG HARDWARE", kind = "hardware", bg = { 200, 40, 30 }, fg = { 255, 255, 255 }, awning = "navy" },
            { text = "MEG'S CUPCAKES", kind = "bakery", bg = { 255, 214, 226 }, fg = { 150, 40, 80 }, awning = "red" },
            { text = "QUAHOG BARBERS", kind = "barber", bg = { 240, 240, 240 }, fg = { 30, 50, 120 }, awning = "blue" },
            { text = "SUDS LAUNDROMAT", kind = "laundry", bg = { 60, 150, 200 }, fg = { 255, 255, 255 }, awning = "navy" },
            { text = "PEWTERSCHMIDT SAVINGS", kind = "bank", bg = { 28, 30, 40 }, fg = { 220, 186, 100 } },
            { text = "QUAHOG COFFEE CO.", kind = "coffee", bg = { 70, 44, 30 }, fg = { 240, 220, 190 }, awning = "brown", awning2 = "cream" },
            { text = "BIG PETE'S PIZZA", kind = "pizza", bg = { 30, 110, 50 }, fg = { 255, 255, 255 }, awning = "red", awning2 = "cream" },
            { text = "PETORIA GIFTS", kind = "souvenir", bg = { 30, 150, 230 }, fg = { 255, 230, 60 }, awning = "gold" },
            { text = "QUAHOG CANDY", kind = "candy", bg = { 255, 240, 120 }, fg = { 220, 30, 90 }, awning = "red" },
            { text = "LOIS'S PIANO LESSONS", kind = "music", bg = { 60, 30, 60 }, fg = { 245, 225, 240 }, awning = "navy" },
            { text = "QUAHOG POST OFFICE", kind = "post", bg = { 24, 50, 110 }, fg = { 255, 255, 255 }, awning = "blue" },
        },
    },

    -- The bike rental: the BMX addon's free vending machines (bmx_rental), so
    -- nobody needs the console or the Q menu to get a bike. Three in a row
    -- beside the spawn nearest the middle of the park, (1707, -673), facing it
    -- across open floor (yaw 180: their faces look west). x 1990 keeps their
    -- backs 140+ off the flat ramp (x >= 2151), the row sits between the
    -- spine (y <= -1327) and the funbox (y >= -290), and the bikes they hand
    -- out appear between the machines and the spawn (sv_city.lua places
    -- them; tests/test_rental.lua proves the clearances).
    rental = {
        { x = 1990, y = -770, yaw = 180 },
        { x = 1990, y = -700, yaw = 180 },
        { x = 1990, y = -630, yaw = 180 },
    },

    -- Greenery (sh_city.lua, B:greenery). The beds stand on the park floor
    -- against the wall, each in a lane measured clear of every ramp by 40+
    -- units (tests/test_city.lua checks it against the live footprints):
    --   north  x 1480..3584: east of the quarterpipes (x <= 1431)
    --   south  four gaps between the spine, flat ramps, funbox and the
    --          quarterpipe in the corner
    --   west   y -1160..440: between the spine (y <= -1208) and the flat
    --          ramp (y >= 481)
    --   east   y -1020..672: north of the quarterpipe (y <= -1067)
    greenery = {
        kerb = 20,
        treeEvery = { 224, 352 },
        beds = {
            { side = "north", from = 1480, to = 3584, depth = 88 },
            { side = "south", from = 200, to = 515, depth = 88 },
            { side = "south", from = 960, to = 1340, depth = 88 },
            { side = "south", from = 2010, to = 2350, depth = 88 },
            { side = "south", from = 2990, to = 3250, depth = 88 },
            { side = "west", from = -1160, to = 440, depth = 88 },
            { side = "east", from = -1020, to = 672, depth = 88 },
        },
        roofs = 0.8,
        terraces = true,
        balconies = 0.45,
        ivy = 0.55,
        -- a street lamp every ~560 along each bed, arm over the park
        lampEvery = 560,
    },

    -- The park's floor, laid over the map's bare concrete: slabs to ride on,
    -- brick paving along the walls, cobbles round the piers, a kerb line,
    -- leaves. Lit per vertex: ambient afternoon light, the west wall's
    -- shadow (wallTop, shadow: as dark as the open floor times this), and
    -- the lamps' pools. Kept under 1 everywhere (a vertex colour clips, and
    -- clipped pools read as blown-out white); tests/test_lighting.lua.
    floor = {
        cell = 64, walk = 176, lift = 0.6, plaza = 288,
        litter = 240,
        ambient = { 0.62, 0.55, 0.47 },
        wallTop = 528, shadow = 0.85, shadowSoft = 192,
        lampRadius = 420, lampColor = { 0.34, 0.23, 0.1 },
    },

    -- A late autumn afternoon (cl_city_mood.lua): the sun low in the west
    -- behind heavy cloud. `light` warms every surface of the city; the sky is
    -- HL2's golden-hour sky, dimmed; the haze is thin and far.
    -- The grade adds contrast and keeps the colour (it used to desaturate
    -- and lift, which with the bright unlit city read as washed out).
    mood = {
        light = { 0.92, 0.79, 0.65 },
        sky = "skybox/sky_day01_08", skyTint = { 0.8, 0.72, 0.66 }, skyYaw = 180,
        fog = { start = 3000, finish = 15000, density = 0.5, color = { 120, 92, 74 } },
        grade = { brightness = -0.05, contrast = 1.14, colour = 1.02, mulr = 0.08, mulg = 0.02, addr = 0.01, addg = 0.002 },
        lampColor = { 255, 186, 112 }, lampBrightness = 1.3, lampSize = 560,
        leafEvery = 0.22,
        -- the signs are lit, not glowing: this much of full brightness in
        -- the open, more within reach of a street lamp
        signLight = 0.66, signLampLight = 0.3, signLampRadius = 560, signShadow = { 26, 15, 10 },
    },
}

-- The same park, renamed for its autumn edition: the server runs a copy of
-- gm_skatepark's BSP as petopia_bmx_fall (docs/CITY.md, "The map").
-- petopia_bmx_fall is gm_skatepark's layout with its own changes to the ramps
-- (mapsrc/build_vmf.py RAMPS): rail2 is gone (a low pipe on the east side
-- instead), a flip kicker stands west of the halfpipe, and three ramps moved
-- north off the south wall's planting beds. The shop fronts read this list (a
-- ramp by a wall gets plain wall behind it), so it is the map's own, not
-- gm_skatepark's.
local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end
local fall = copy(BMX.City.Maps.gm_skatepark)
local moved = {
    -- name, x0 (which one), new y0, new y1
    { "flatramp", 559, -1541, -1255 },
    { "spiner2", 1386, -1423, -1047 },
    { "funbox2", 2398, -1516, -1095 },
}
local ramps = {}
for _, r in ipairs(fall.ramps) do
    if r[1] ~= "rail2" then
        for _, m in ipairs(moved) do
            if r[1] == m[1] and r[2] == m[2] then r[3], r[5] = m[3], m[4] end
        end
        ramps[#ramps + 1] = r
    end
end
ramps[#ramps + 1] = { "kicker", -40, -560, 152, -150, 64, 254 }
ramps[#ramps + 1] = { "pipe", 3288, -300, 3292, 20, 64, 82 }
fall.ramps = ramps
-- The far south bed (x 2990..3250) is the one a bike comes at past funbox 3
-- with a quarter pipe at its end: at 20 u its kerb clipped the front wheel of
-- a hop meant to land on its edge. Its kerb is 14 u.
for _, bd in ipairs(fall.greenery.beds) do
    if bd.side == "south" and bd.from == 2990 then bd.kerb = 14 end
end
BMX.City.Maps.petopia_bmx_fall = fall
-- The test server (test-gmod) runs the same BSP under its own name, so a
-- player's downloaded copy of one never clashes with the other's ("your map
-- differs from the server's"): tools/deploy-test.sh renames it on the way in.
BMX.City.Maps.test_petopia_bmx_fall = fall
