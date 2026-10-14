#!/usr/bin/env bash
# SkateGM's view of the map: builds tools/skategm/petopia_check.rs against
# SkateGM's own map loader (github.com/the-schwilliam/SkateGM, gm_skategm, no
# engine and no Skate 3 data needed) and runs it on the BSP.
#
#   tools/skategm/check.sh [map.bsp] [petopia_check args...]
#
# Needs git and a Rust toolchain >= 1.85 (rustup). SkateGM is cloned once into
# $SKATEGM_DIR (default ~/.cache/skategm) at $SKATEGM_REF.
#
# What 1.0.2 gives with SkateGM 9.0 (ea59a34): walls 0 through; floor 371 spots
# with no ground, every one beside a coping (SkateGM's hidden-face step takes the
# top wedge of a transition whose coping's flat top is level with it). With
# SK8_OFF=hidden: 6, along funbox 2's west corners (SkateGM builds faces from
# vbsp's bevel planes too). 1.0.1 gave 12,275: half the floor.
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
exec "${CARGO_TARGET_DIR:-$DIR/gm_skategm/target}/release/examples/petopia_check" "$MAP" "$@"
