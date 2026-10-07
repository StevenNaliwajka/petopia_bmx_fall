#!/usr/bin/env bash
# Deploy this map addon to the test server, test-gmod, under the TEST name.
#
#   tools/deploy-test.sh [ref]        default: origin/main
#
# The test server runs the map as test_petopia_bmx_fall, never petopia_bmx_fall:
# the production servers (Petopia) run petopia_bmx_fall, and a player who has
# downloaded one server's copy must never be told by the other that their map
# "differs from the server's". So the BSP, its .nav and its thumbnail are
# renamed here, on the way in (the city is keyed by both names in
# sh_city_maps.lua). Then the addon dir is swapped (the old one kept as
# addons/.petopia_old for rollback) and the map changed to it -- players stay
# connected. The server's systemd drop-in (gmod.service.d/map.conf) names the
# same map, so a restart comes back on it too.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="${1:-origin/main}"
HOST="${TEST_GMOD_HOST:-root@test-gmod.naliwajka.com}"
NAME=petopia_bmx_fall
TEST=test_petopia_bmx_fall
cd "$ROOT"
git fetch -q origin
SHA="$(git rev-parse "$REF")"
git archive "$REF" lua maps addon.json | ssh "$HOST" "set -e
A=/opt/gmod/garrysmod/addons; GM=/opt/gmod/garrysmod
rm -rf \$A/.petopia_new; mkdir \$A/.petopia_new; tar -x -C \$A/.petopia_new
cd \$A/.petopia_new/maps
mv $NAME.bsp $TEST.bsp; mv $NAME.nav $TEST.nav; mv thumb/$NAME.png thumb/$TEST.png
echo $SHA > \$A/.petopia_new/.deployed-sha
chown -R gmod:gmod \$A/.petopia_new
rm -rf \$A/.petopia_old; mv \$A/petopia_bmx_fall \$A/.petopia_old; mv \$A/.petopia_new \$A/petopia_bmx_fall
rm -f \$GM/maps/$TEST.bsp.ztmp \$GM/maps/$NAME.bsp.ztmp
grep -q 'GMOD_MAP=$TEST' /etc/systemd/system/gmod.service.d/map.conf || echo 'map.conf does not name $TEST' >&2
echo deployed $SHA as $TEST"
if [ -n "${RCON_PASSWORD:-}" ]; then
  python3 -I - "$TEST" <<'PY' || true
import socket, struct, sys, os
s = socket.create_connection(("test-gmod.naliwajka.com", 27016), 10)
def send(i, t, b): b = b.encode() + b"\0\0"; s.sendall(struct.pack("<iii", len(b) + 8, i, t) + b)
send(1, 3, os.environ["RCON_PASSWORD"]); send(2, 2, "changelevel " + sys.argv[1]); print("changelevel", sys.argv[1])
PY
else
  echo "now: rcon changelevel $TEST (set RCON_PASSWORD to do it here)"
fi
