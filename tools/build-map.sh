#!/usr/bin/env bash
# Build maps/petopia_bmx_fall.bsp from mapsrc/build_vmf.py, on Linux, under wine.
#
#   tools/build-map.sh           normal quality (vvis full, vrad default)
#   tools/build-map.sh -final    vrad -final (slower, smoother light)
#
# THE TOOLCHAIN (SDK=${GMOD_MAPSDK:-$HOME/sdk/gmod-mapsdk}) is assembled once, by hand:
#
#   $SDK/bin         the Source SDK 2013 runtime DLLs (tier0, vstdlib, filesystem_stdio,
#                    vphysics, materialsystem, shaderapiempty, vrad_dll, vvis_dll, ...)
#                    from the ANONYMOUS "Source SDK Base 2013 Dedicated Server":
#                      steamcmd +@sSteamCmdForcePlatformType windows \
#                        +force_install_dir /tmp/sdkds +login anonymous +app_update 244310 +quit
#                      -> copy /tmp/sdkds/bin (without x64/) to $SDK/bin
#                    plus vbsp.exe, vvis.exe, vrad.exe from SlimBSP v0.9.2
#                    (github.com/AusHick/SlimBSP/releases, slimbsp.7z), copied over them.
#   $SDK/garrysmod   gameinfo.txt, garrysmod_*.vpk, detail.vbsp, lights.rad, steam.inf
#   $SDK/sourceengine hl2_textures_*.vpk, hl2_misc_*.vpk, resource/, scripts/
#   $SDK/platform    platform/
#                    all three from the ANONYMOUS Windows Garry's Mod Dedicated Server:
#                      steamcmd +@sSteamCmdForcePlatformType windows \
#                        +force_install_dir /tmp/gmodwin +login anonymous +app_update 4020 +quit
#                    (run steamcmd as the user that owns its install, or app_update fails
#                    with "Missing file permissions").
#
#   GMod's own bin/ DLLs do NOT work with these vbsp/vvis/vrad (different tier0 and
#   filesystem interfaces); they are kept aside in $SDK/bin_gmod and unused. The tier0
#   shim in $SDK/shim was an experiment for that and is NOT needed.
#
# Needs wine (32-bit support) and python3. Other sessions share this box: vrad runs on
# two threads.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="${GMOD_MAPSDK:-$HOME/sdk/gmod-mapsdk}"
NAME=petopia_bmx_fall
FINAL=""
[ "${1:-}" = "-final" ] && FINAL="-final"

export WINEPREFIX="${WINEPREFIX:-$HOME/sdk/wineprefix}" WINEDEBUG=-all
winpath() { echo "Z:${1//\//\\}"; }

for f in vbsp.exe vvis.exe vrad.exe tier0.dll vrad_dll.dll vvis_dll.dll; do
  [ -f "$SDK/bin/$f" ] || { echo "missing $SDK/bin/$f -- see the header of this script" >&2; exit 2; }
done

python3 "$ROOT/mapsrc/build_vmf.py"

WORK="$ROOT/mapsrc/.build"; rm -rf "$WORK"; mkdir -p "$WORK"   # wine may not see a private /tmp
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/mapsrc/$NAME.vmf" "$WORK/"
GAME="$(winpath "$SDK/garrysmod")"
MAP="$(winpath "$WORK/$NAME")"
LOG="$ROOT/mapsrc/build.log"
: > "$LOG"

run() {  # tool, args...: run from bin/ so it finds its DLLs; output to the log and the screen
  echo "== $*" | tee -a "$LOG"
  (cd "$SDK/bin" && wine "$@" 2>&1) | tr -d '\r' | tee -a "$LOG"
}

run vbsp.exe -game "$GAME" "$MAP.vmf"
if grep -q -i 'leaked' "$LOG"; then echo "vbsp: MAP LEAKED, stopping" >&2; exit 1; fi
[ -f "$WORK/$NAME.bsp" ] || { echo "vbsp wrote no bsp" >&2; exit 1; }
run vvis.exe -game "$GAME" "$MAP"
run vrad.exe -game "$GAME" -both -threads 2 $FINAL "$MAP"

mkdir -p "$ROOT/maps"
cp "$WORK/$NAME.bsp" "$ROOT/maps/$NAME.bsp"
echo "built maps/$NAME.bsp ($(stat -c %s "$ROOT/maps/$NAME.bsp") bytes); log in mapsrc/build.log"
