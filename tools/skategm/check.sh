#!/usr/bin/env bash
# SkateGM's view of the map: builds tools/skategm/petopia_check.rs against
# SkateGM's own map loader (github.com/the-schwilliam/SkateGM, gm_skategm, no
# engine and no Skate 3 data needed) and runs it on the BSP.
#
#   tools/skategm/check.sh [map.bsp] [petopia_check args...]
#   GEN=lua/petopia_bmx_fall/cl_skategm_patches.lua tools/skategm/check.sh
#                               ...writes the surface patches first (after a
#                               BSP change, or a SkateGM that reads maps anew)
#
# Needs git and a Rust toolchain >= 1.85 (rustup). SkateGM is cloned once into
# $SKATEGM_DIR (default ~/.cache/skategm) at $SKATEGM_REF. The patches
# cl_skategm.lua hands SkateGM (lua/petopia_bmx_fall/cl_skategm_patches.lua)
# are fed to it as the game does; PATCHES=none checks the map without them.
#
# Three checks against the collision SkateGM's engine gets: the map's top
# surface on a 16 u grid of the park; rays into the walls; and every open piece
# of every brush face (what other brushes do not cover) against the engine
# triangles lying on it -- missing unless SkateGM's own ledge ramps or curves
# stand over it. TOP=600 starts the grid's scan under the sky (quicker).
#
# 1.0.4 with SkateGM 9.0 (ea59a34), at smoothing 0, 1 and 2: 0 spots with no
# ground, 0 pieces of surface missing, 0 rays through the walls, 74 grind rails
# (1.0.3: 73; the new one is funbox 2's north foot, a rail SkateGM finds along
# every side of funboxes 1 and 3 too). 1.0.3 was missing funbox 2's west slope,
# cracked along its corner (SkateGM builds faces from vbsp's bevel planes too,
# and every funbox has some a hair off its slopes): 6 spots, 823 sq u. A slope
# one can stand on can't be patched (SkateGM finds an entity's rails from its
# own triangles, so every edge of the patch was a rail); 1.0.4 moves that
# slope's top edge 1 u out instead (build_vmf.py funbox()). Without the
# patches: 371 spots with no ground, 365 of them beside a coping (SkateGM's
# hidden-face step takes the top wedge of a transition whose coping's flat top
# is level with it), and 85 pieces of surface missing (217,929 sq u): those
# tops (the halfpipe's 62 u of vert), the funbox, the flat ramp's side over the
# north-west quarter pipe. 1.0.1 gave 12,275 spots: half the floor.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAP="${1:-$ROOT/maps/petopia_bmx_fall.bsp}"; shift || true
DIR="${SKATEGM_DIR:-$HOME/.cache/skategm}"
REF="${SKATEGM_REF:-ea59a34}"
if [ ! -d "$DIR/.git" ]; then git clone -q https://github.com/the-schwilliam/SkateGM.git "$DIR"; fi
git -C "$DIR" fetch -q origin || true
git -C "$DIR" checkout -q "$REF"
cp "$ROOT/tools/skategm/petopia_check.rs" "$DIR/gm_skategm/examples/petopia_check.rs"
(cd "$DIR/gm_skategm" && cargo build -q --release --no-default-features --example petopia_check)
export PATCHES="${PATCHES:-$ROOT/lua/petopia_bmx_fall/cl_skategm_patches.lua}"
exec "${CARGO_TARGET_DIR:-$DIR/gm_skategm/target}/release/examples/petopia_check" "$MAP" "$@"
