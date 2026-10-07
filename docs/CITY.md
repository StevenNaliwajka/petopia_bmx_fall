# The city around the park

On maps that have one (today: `gm_skatepark`), the addon builds a city around
the park: buildings stand on every wall instead of bare brick, with shops on
their street floors and billboards up top, a second row and a skyline rise
behind them, and three elevated subway lines cross overhead, running on out
over the city, with trains running over them on a timetable.

Nothing in the map is edited. The city is drawn by the client
(`lua/petopia_bmx_fall/cl_city.lua`) from a layout that `lua/petopia_bmx_fall/sh_city.lua` builds out
of a per-map definition (`lua/petopia_bmx_fall/sh_city_maps.lua`). The parts riders can
touch (the viaducts and their piers) get colliders, `bmx_city_solid`
entities spawned by `lua/petopia_bmx_fall/sv_city.lua`. It uses only HL2/GMod content, so
there is nothing extra to download.

## How it fits around a sealed map

`gm_skatepark` is one box: brick walls to z 528, sky brushes above, ceiling
z 1720. The sky brushes are not drawn as geometry, so anything drawn beyond
them shows through. The frontage's facades stand 4 units inside the walls and
cover the brick from the floor up. The buildings' bodies and everything behind
them are out in the void, where nobody can reach, so they need no collision.
The engine never draws entities out there (no visleaf), which is why the city
is a render hook and not entities.

## Settings

| Convar | Realm | Default | |
|---|---|---|---|
| `bmx_city` | server, replicated | 1 | build the city on maps that have one |
| `bmx_city_draw` | client | 1 | draw it |
| `bmx_city_trains` | client | 1 | run the trains and their sound |
| `bmx_city_signs` | client | 1 | draw the signs |
| `bmx_city_plants` | client | 1 | draw the trees and street lamps |
| `bmx_city_mood` | client | 1 | the late-autumn sky, haze, colour grade and lamplight |
| `bmx_city_leaves` | client | 1 | leaves falling from the trees |

Commands: `bmx_city_info` (what this map's city has), `bmx_city_rebuild`
(admin; respawn the colliders after changing `bmx_city`), and
`bmx_city_rebuild_client`.

## Late autumn: greenery, floor, lamps and the hour

The park is dressed for a late fall afternoon (the map's `greenery`, `floor`
and `mood` tables).

- **Planting beds** stand against the walls in lanes measured clear of every
  ramp. Each has a concrete kerb, grass, a hedge, trees, ivy climbing the wall
  behind and street lamps. The bed and the tree trunks and lamp poles are
  solid (`bmx_city_solid`), so a bike stops at the kerb.
- **Trees** are HL2 models (`hl2_misc`/`garrysmod` VPKs only, so nobody needs
  HL2 mounted) wearing a crown of leaf cards in red, orange, gold and rust, the
  same leaves the hedges are made of. They sway in a west wind with gusts.
- **The frontage** has roof gardens (planters, trees over the cornice, ivy
  hanging down), planted terraces in front of setback towers, and balconies
  with planters on the upper floors.
- **The floor** is laid over the map's single concrete slab, a hair above it:
  slab concrete to ride on, brick paving along the walls, cobbles round the
  piers, a kerb line, and drifts of fallen leaves. The afternoon light and a
  warm pool under every lamp are baked into its vertices.
- **The mood** (`cl_city_mood.lua`) swaps the noon sky for HL2's golden
  `sky_day01_08` (turned so the glow sits in the west, where the map's sun
  is), adds a thin warm haze and a slight warm grade, glows at the lamp
  heads, dynamic lights from the nearest lamps (models only), and the odd leaf
  falling and settling.
- **Signs are boards in cases, lit, not glowing**: every sign's artwork
  (board and frame) is painted once into its own render target and drawn as
  the open front of a steel case (`B:signCase`), so nothing shares its plane
  and nothing shows through it. Its light is in the face's vertex colours:
  the light where it stands (`signLight`, brighter near a street lamp), and on
  a floodlit ad, its own lamps (real arms and lenses on the case) brightening
  the top. TV and neon boards are their own light.
- **Signs sit on blank wall**: each wall sign moves onto one building (never
  across two, never over the roof line), and the bays of the facade behind it
  are laid as that style's plain, windowless panel.
  `tests/test_signs.lua` checks every sign against every window.

## A city that makes sense

`tests/test_sense.lua` keeps all of this true.

- **No train goes into a building.** Where a line crosses a wall, the
  frontage has a gap and a low **station house** stands in it (4-5 floors,
  its roof well under the girders), with the line passing over its roof. The
  back row leaves an open street there, and no skyline tower stands in it.
  The viaduct runs on down that street, on piers every 1024, `reach` (11000)
  past the wall: beyond the last building of the city. A train sets off out
  there, crosses the park and goes back out there. Two tracks, right-hand
  running, so the train going out and the next one coming in can both be on
  the line (`City.TrainsAt`). The rumble fades out over the city
  (`City.TrainFade`), and the horn sounds as the nose comes in over the wall.
  Rows are cut round the streets without disturbing the seed: a lot the
  street takes is built "dry" (its draws taken, nothing built), so every
  other building is where it always was.
- **Station signs hang from their line**: across the street under the
  viaduct, on two rods from its girders, over the station house's roof,
  facing the park. The station house's street floor is the metro's entrance
  ("QUAHOG METRO", the line's roundels, stairs going up).
- **Ads are billboards, up high.** A wall ad goes to the top of its
  building's facade, under the cornice, on a steel catwalk with a railing and
  its floodlights over it; one to a facade. A building too low to carry it
  with its foot four floors up (z 576, over the park's wall) puts it on its
  roof on legs instead, one to a roof, never on a station house.
- **The street floor is shops, not windows all the way down.** Every
  frontage building's front, over the park's wall, is false shop fronts
  (`storefronts` in the map's table): a face painted with the fascia and the
  shop's name, a display window with what it sells (`cl_city.lua`
  SHOP_WINDOWS), a stall riser and a door with its number and an OPEN card,
  between stone pilasters and under a string course. The facade behind is
  plain (no window behind a shop window). Where nothing stands in front, a
  striped awning hangs under the fascia; none where a ramp stands against
  the wall (`noAwning`). Every door behind a planting bed has a gap in the
  hedge and a brick path across the bed, and is put where no tree, lamp or
  bush stands in front of it.
- **Lamps**: the street lamps stand at the kerb of the beds, the glow in the
  lamp head's lens (z 438 over the foot, 87 out along the arm, read off
  `lamppost03a_on`'s vertices; it used to hang a foot under the head).

Nothing here is an entity a player can touch: plants are drawn by the client
from the render hook (never faded or culled by distance, always at full
LOD), and the solid parts are `bmx_city_solid`, which the physgun, gravity
gun, toolgun and context menu all refuse.

## The map: petopia_bmx_fall

The city now belongs to the **petopia_bmx_fall** map (this repository), whose
BSP is our own compile (`mapsrc/build_vmf.py`, `tools/build-map.sh`): the same
play box, walls, sky ceiling and spawns as gm_skatepark, which the city was
measured against, with our own brush ramps at the same footprints. The city
table is still keyed by both names (`Maps.petopia_bmx_fall = Maps.gm_skatepark`),
so gm_skatepark keeps its city too.

`sv_city.lua` sends the map icon (`maps/thumb/petopia_bmx_fall.png`) to
everyone who joins (`resource.AddFile`). Clients download the map from the
server.

(Until 2026-10-07 the test server ran a renamed copy of gm_skatepark's BSP
under this name. That copy was somebody else's map and is gone; this BSP is
ours and can be published.)

## Changing the city

Everything is in the map's table in `sh_city_maps.lua`:

- `seed`: a different seed gives a different city with the same rules.
  The generator is private and seeded, so every realm builds the same one.
- `frontage`, `backRow`: lot widths, depths, floor counts, styles, setback
  towers. One floor is 128 units, one HL2 `building_template` panel.
- `skyline`: tower count, distance band, heights.
- `viaducts`: each line's axis, position, deck height, train period, offset,
  cars and speed, how far it runs on past each wall (`reach`), its number and
  colour (`label`, `color`), and `ends`: the terminus past each end (`to` is
  where trains going from -> to are headed, `from` the way back). A train's
  nose and tail boards and the station sign at each end (a `transit` sign
  with `metro = "<line name>"`) all read from `ends`, so one direction always
  goes to one place (`tests/test_trains.lua`). `piers` stand under the
  crossings; `stationDepth` is how deep the station houses are.
- `signs`: text panels on the facades (ads become billboards, see above).
- `billboards`: rooftop billboards.
- `storefronts`: the shops along the street floor, in order round the park,
  the metro entrance, and where no awning may go.

Styles (which panels go on the street floor, the floors above and the
cornice) and materials are at the top of `sh_city.lua`.

To look at a change without starting the game:

    lua5.1 tools/city/export.lua gm_skatepark > layout.json
    python3 tools/city/preview.py layout.json texdump view.png  100 -1500 130 35 -18

`texdump/` comes from `tools/city/texdump.py`, run on a GMod server.

`tests/test_city.lua` holds the rules a layout must keep, checked against
every ramp's measured footprint: solids clear of every ramp and spawn by 40
units, viaducts at least 400 over the tallest coping, lines that cross without
touching and stay under the sky ceiling, trains that come in from past the city
and go out past it. `tests/test_sense.lua` checks that no train or viaduct ever
passes through a building. Change the map's table and run `lua5.1 tests/run.lua`.

## Another map

Measure the map's play box, floor height and sun (the brush and entity lumps
of the BSP), add a table under its name, and put any piers in clear lanes. If
the map is not a sealed box, the frontage covers whatever is behind its walls.
