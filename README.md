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
| `tools/build-map.sh` | VMF -> vbsp -> vvis -> vrad (`-both`, 2 threads) under wine -> `maps/petopia_bmx_fall.bsp`. `-final` for final-quality light. |
| `maps/petopia_bmx_fall.bsp` | The compiled map (base HL2/GMod materials only). |

## Rebuilding

    tools/build-map.sh          # ~40 s
    tools/build-map.sh -final

Needs wine, python3 and the map SDK at `~/sdk/gmod-mapsdk` (override with
`GMOD_MAPSDK`). How that SDK is assembled from anonymous steamcmd downloads plus
SlimBSP's compilers is written at the top of `tools/build-map.sh`.

To change a ramp, edit `RAMPS` in `mapsrc/build_vmf.py` and rebuild; commit the
VMF and the BSP together.
