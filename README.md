# petopia_bmx_fall

The BMX park map for Petopia's BMX mode: a walled street park on a late-autumn
afternoon. 17 ramps (quarter pipes, a halfpipe, spines, kickers, funboxes and a
grind rail), all built as world brushes, so bike grinds and the navmesh see them.

The play box, walls, sky ceiling, spawns and ramp footprints match the numbers
the BMX city was laid out against (x -256..3584, y -1792..768, floor z 64, brick
walls to z 528, sky to z 1720). Every brush is our own; no other map's content.

| Path | What |
|---|---|
| `mapsrc/build_vmf.py` | The map, as code: writes `mapsrc/petopia_bmx_fall.vmf` (deterministic, stdlib only). |
| `mapsrc/city_lamps.txt` | The city's street lamp heads (from `tools/city/lamps.lua`); each one is a baked light in the BSP. |
| `tools/build-map.sh` | VMF -> vbsp -> vvis -> vrad (`-both`, 2 threads) under wine -> `maps/petopia_bmx_fall.bsp`. `-final` for final-quality light. |
| `maps/petopia_bmx_fall.bsp` | The compiled map (base HL2/GMod materials only). |
| `maps/thumb/petopia_bmx_fall.png` | The map icon (Peter on his BMX against a fall sunset). |
| `lua/autorun/petopia_bmx_fall.lua` | The map's Lua: loads the city below. |
| `lua/petopia_bmx_fall/` | The city around the park: buildings, skyline, viaducts and trains, billboards, greenery, and the late-autumn mood (sky, haze, lamps, falling leaves). See [docs/CITY.md](docs/CITY.md). |
| `lua/entities/bmx_city_solid/` | The city's colliders (viaducts, piers, planting beds). |
| `tools/city/` | Offline preview of the city layout. |
| `tests/` | The city's tests, run on the BMX addon's offline harness. |
| `maps/petopia_bmx_fall.nav` | the navmesh: 360 areas, made by the BMX addon's `bmx_nav_build` (rebuild it after any change to the BSP) |

## Official server

**Petopia**, Peter Griffin's Garry's Mod server, is the official BMX server:

    connect gmod.naliwajka.com:27015

Paste that into the Garry's Mod console (~), or find "Petopia" in the server
browser. Type `/vote bmx` in chat to switch it to BMX.

Found a bug or have an idea? [Open an issue on GitHub](https://github.com/StevenNaliwajka/petopia_bmx_fall/issues).

## The three pieces

| Piece | Repository | What it is |
|---|---|---|
| **BMX** | gmod/gmod-bmx | The vehicle mod (Workshop 3814420080). |
| **BMX (Mode)** | gmod/gmod-bmx-mode | The gamemode: games, scores, the trick bot. |
| **petopia_bmx_fall** | gmod/petopia_bmx_fall (this) | The map: the BSP and its city. |

The map needs neither of the others to load; the city's settings show up in
Options > BMX when the BMX addon is installed. Install the whole repository as
a folder in `garrysmod/addons/` (it has `maps/` and `lua/`), and start with
`+map petopia_bmx_fall` (with `+gamemode bmx` for the full BMX server).

## SkateGM

[SkateGM](https://github.com/the-schwilliam/SkateGM) (Skate 3 in Garry's Mod)
builds its skater's collision from the BSP's brushes, not Source's physics.
Two things on this map are there for it:

- **The floor in pieces** (`mapsrc/build_vmf.py` `floor_cells`). Up to 1.0.1
  the floor was one brush; SkateGM dropped half its top as "hidden" and a
  skater in the park's north-east half fell straight through the floor
  (Workshop comment, 2026-10-13).
- **The city's colliders** (`lua/petopia_bmx_fall/cl_skategm.lua`). A
  `bmx_city_solid` is a stand-in model with boxes made at runtime, which
  SkateGM can't see; this hands each one's boxes to SkateGM through its add-on
  hooks, so planting beds, piers and lamp posts stop the skater too.

`tools/skategm/check.sh` measures it with SkateGM's own map loader (built
from its repository, no engine or game data needed): the map's top surface on
a grid, and the walls, against the collision SkateGM's engine gets.

Known, not ours to fix in the map: SkateGM drops the top wedge of each
transition beside its coping (the coping's flat top is level with it), and it
builds faces from vbsp's bevel planes too, which can crack a funbox's sloped
corner. Both are in SkateGM's own map loader.

## Tests

    lua5.1 tests/run.lua

The city's tests on the BMX addon's offline harness, which this finds at
`$BMX_ADDON`, else `../gmod-bmx`, else `tests/.addon`. `tests/test_lighting.lua`
reads the compiled BSP's lightmaps and fails on any part of the park left dark
or blown out; `lua5.1 tests/bsplight.lua maps/petopia_bmx_fall.bsp` prints
that light as a map of the park.

## Rebuilding

    tools/build-map.sh          # ~40 s
    tools/build-map.sh -final

Needs wine, python3 and the map SDK at `~/sdk/gmod-mapsdk` (override with
`GMOD_MAPSDK`). How that SDK is assembled from anonymous steamcmd downloads plus
SlimBSP's compilers is written at the top of `tools/build-map.sh`.

To change a ramp, edit `RAMPS` in `mapsrc/build_vmf.py` and rebuild; commit the
VMF and the BSP together. The floor is cut into pieces along every ramp's
footprint (`floor_cells`), never one brush: SkateGM drops a big floor face it
takes for hidden (see SkateGM below), and `tests/test_skategm.lua` fails if
any floor or wall face would go. The light (sun, sky fill, the west-wall fill row,
lamps, exposure) is at the top of the same file. If the city's lamps move, run
`lua5.1 tools/city/lamps.lua > mapsrc/city_lamps.txt` and rebuild.
