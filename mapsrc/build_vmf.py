#!/usr/bin/env python3
"""Generate mapsrc/petopia_bmx_fall.vmf: the BMX park, as brushes.

Deterministic (no randomness, no clock): the same script writes the same VMF.

THE GEOMETRY MATCHES gm_skatepark'S PLAY BOX ON PURPOSE. The city (lua in this
repo) was laid out against gm_skatepark's measured box, walls, sky ceiling,
spawns and ramp footprints. This map keeps those numbers so the city still
fits, but every brush here is our own: nothing is copied from that map.

    play box   x -256..3584, y -1792..768, floor top z 64
    walls      brick, 256 thick, up to z 528
    sky        toolsskybox from the wall tops up to a ceiling at z 1720
    ramps      RAMPS below: name, x0, y0, x1, y1, z top, and which way the high
               side faces. Footprints are gm_skatepark's ramps' measured
               WorldSpaceAABBs (gmod-bmx tests/test_city.lua).

Every brush is convex and its plane points are integers. Shared edges between
neighbouring wedges are computed once and rounded the same way, so the curves
close without gaps.
"""

import math
import os

FLOOR = 64
BOX = (-256, -1792, 3584, 768)       # x0, y0, x1, y1 inside the walls
WALL_TOP = 528
WALL_T = 256
CEIL = 1720
SKY_T = 16

MAT_FLOOR = "CONCRETE/CONCRETEFLOOR033A"
MAT_WALL = "BRICK/BRICKWALL031B"
MAT_RAMP = "WOOD/WOODFLOOR005A"      # ride surfaces
MAT_RAMP_SIDE = "WOOD/WOODWALL009A"  # the sides and backs of the ramps
MAT_BOX = "CONCRETE/CONCRETEWALL004A"  # funbox sides and top
MAT_METAL = "METAL/METALPIPE003A"    # coping and rails
MAT_SKY = "TOOLS/TOOLSSKYBOX"
MAT_NODRAW = "TOOLS/TOOLSNODRAW"
SKYNAME = "sky_day02_09"

# The light (see entities()). "r g b brightness".
SUN = "255 206 150 200"          # warm, low, moderate
SKY = "218 212 226 170"          # sky fill, a touch cool: lights the shade without greying the wood
LAMP = "255 186 112 260"         # the street lamps, as the city draws them
LAMP_HALF, LAMP_ZERO = 260, 640  # their falloff, units
# Fill in the west wall's shadow. The sunlit park floor and the city's sunlit
# east side throw light back into it; vrad can't (the facades are Lua
# meshes, the BSP only has the bare brick), so a row of soft lights high
# along the west wall stands in for that bounce. Without it the west eighth
# of the park, and the spine in its south-west corner most of all, sat in
# near-black shade.
FILL = "236 214 196 60"
FILL_HALF, FILL_ZERO = 420, 1100
FILL_AT = [(BOX[0] + 112, y, 440) for y in range(BOX[1] + 128, BOX[3], 384)]
EXPOSURE = (0.6, 1.1)            # HDR auto-exposure clamp
BLOOM = 0.15

# name, x0, y0, x1, y1, ztop, facing
#   quarterpipe: facing = the side the high (vertical) end is on
#   flatramp:    facing = the side the deck is on
#   spiner:      facing = "x" or "y", the axis the slopes run along
#   halfpipe:    facing = "x" or "y", the axis the transitions run along
RAMPS = [
    ("spiner2",      -221, -1785,  155, -1208, 179, "x"),
    ("flatramp",     -161,   481,  193,   767, 177, "+y"),
    ("quarterpipe3",  187,   475,  807,   774, 237, "+y"),
    ("halfpipe7",     324, -1037, 1515,  -468, 421, "x"),
    ("flatramp",      559, -1791,  913, -1505, 177, "-y"),
    ("funbox2",       572,  -259, 1118,   222, 150, None),
    ("quarterpipe3",  811,   475, 1431,   774, 237, "+y"),
    ("spiner2",      1386, -1703, 1963, -1327, 179, "y"),
    ("funbox2",      1855,  -290, 2401,   191, 150, None),
    ("flatramp",     2151, -1009, 2437,  -655, 177, "+y"),
    ("funbox2",      2398, -1776, 2944, -1295, 150, None),
    ("spiner2",      2437, -1082, 2812,  -505, 179, "x"),
    ("spiner2",      2805, -1082, 3180,  -505, 179, "x"),
    ("rail2",        2914,  -342, 3230,  -330, 139, None),
    ("flatramp",     2929,  -257, 3215,    97, 177, "+y"),
    ("flatramp",     2929,    95, 3215,   449, 177, "-y"),
    ("quarterpipe3", 3291, -1687, 3590, -1067, 237, "+x"),
]

SPAWNS = [(1008, -421), (2562, 0), (195, -764), (1707, -673), (3212, -814)]


# --------------------------------------------------------------------------
# Brushes
# --------------------------------------------------------------------------
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def rnd(p):
    return tuple(int(round(c)) for c in p)


class Brush:
    """A convex brush from its faces: each face a list of (at least 3) corner
    points and a material. Orientation is fixed against the centroid, so the
    caller never has to think about Hammer's winding."""

    def __init__(self, faces):
        self.faces = [([rnd(p) for p in pts], mat) for pts, mat in faces]

    def vmf(self, ids):
        pts = [p for f, _ in self.faces for p in f]
        c = tuple(sum(p[i] for p in pts) / len(pts) for i in range(3))
        out = ['solid\n{\n\t"id" "%d"\n' % ids.next()]
        for f, mat in self.faces:
            a, b, cc = pick3(f)
            n = cross(sub(a, b), sub(cc, b))          # VBSP: (p0-p1) x (p2-p1)
            if dot(n, sub(a, c)) < 0:
                a, cc = cc, a
                n = cross(sub(a, b), sub(cc, b))
            u, v = tex_axes(n)
            out.append('\tside\n\t{\n\t\t"id" "%d"\n\t\t"plane" "(%d %d %d) (%d %d %d) (%d %d %d)"\n'
                       '\t\t"material" "%s"\n\t\t"uaxis" "[%s 0] 0.25"\n\t\t"vaxis" "[%s 0] 0.25"\n'
                       '\t\t"rotation" "0"\n\t\t"lightmapscale" "%d"\n\t\t"smoothing_groups" "0"\n\t}\n'
                       % (ids.next(), *a, *b, *cc, mat, u, v, 32 if mat in (MAT_FLOOR, MAT_WALL) else 16))
        out.append('}\n')
        return "".join(out)


def pick3(f):
    """Three corners of a face that are not collinear (after rounding)."""
    n = len(f)
    best, score = None, -1
    for i in range(n):
        for j in range(i + 1, n):
            for k in range(j + 1, n):
                cr = cross(sub(f[j], f[i]), sub(f[k], f[i]))
                s = dot(cr, cr)
                if s > score:
                    best, score = (f[i], f[j], f[k]), s
    if score <= 0:
        raise ValueError("degenerate face %r" % (f,))
    return best


def tex_axes(n):
    ax = [abs(c) for c in n]
    if ax[2] >= ax[0] and ax[2] >= ax[1]:
        return "1 0 0", "0 -1 0"
    if ax[0] >= ax[1]:
        return "0 1 0", "0 0 -1"
    return "1 0 0", "0 0 -1"


def box(x0, y0, z0, x1, y1, z1, mat, top=None, bottom=None, sides=None):
    top = top or mat
    bottom = bottom or mat
    sides = sides or mat
    P = lambda x, y, z: (x, y, z)
    return Brush([
        ([P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1)], top),
        ([P(x0, y0, z0), P(x1, y0, z0), P(x1, y1, z0), P(x0, y1, z0)], bottom),
        ([P(x0, y0, z0), P(x0, y1, z0), P(x0, y1, z1), P(x0, y0, z1)], sides),
        ([P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z1), P(x1, y0, z1)], sides),
        ([P(x0, y0, z0), P(x1, y0, z0), P(x1, y0, z1), P(x0, y0, z1)], sides),
        ([P(x0, y1, z0), P(x1, y1, z0), P(x1, y1, z1), P(x0, y1, z1)], sides),
    ])


def prism(profile, place, w0, w1, mats):
    """Extrude a convex 2-D profile [(s, z), ...] (counter-clockwise or not)
    between w0 and w1. place(s, z, w) -> (x, y, z). mats(i) gives the
    material of the face on edge i, or "cap" for the two ends."""
    n = len(profile)
    faces = []
    for i in range(n):
        a, b = profile[i], profile[(i + 1) % n]
        faces.append(([place(a[0], a[1], w0), place(b[0], b[1], w0),
                       place(b[0], b[1], w1), place(a[0], a[1], w1)], mats(i)))
    faces.append(([place(s, z, w0) for s, z in profile], mats("cap")))
    faces.append(([place(s, z, w1) for s, z in profile], mats("cap")))
    return Brush(faces)


def frustum(x0, y0, x1, y1, z0, z1, inset, mat_top, mat_side):
    b = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)]
    t = [(x0 + inset, y0 + inset, z1), (x1 - inset, y0 + inset, z1),
         (x1 - inset, y1 - inset, z1), (x0 + inset, y1 - inset, z1)]
    faces = [(t, mat_top), (b, MAT_NODRAW)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append(([b[i], b[j], t[j], t[i]], mat_side))
    return Brush(faces)


OCT = [(4, 2), (2, 4), (-2, 4), (-4, 2), (-4, -2), (-2, -4), (2, -4), (4, -2)]


def octagon(r, cz, cs):
    """An 8-sided section about (cs, cz), flat on top: a pipe for grinding.
    Integer offsets from a rounded centre, so it survives rounding to the
    grid; r is the scale over a 4-unit octagon."""
    cs, cz, k = round(cs), round(cz), r / 4
    return [(cs + dx * k, cz + dz * k) for dx, dz in OCT]


# --------------------------------------------------------------------------
# A frame for each ramp: s runs from the low end to the high end, w across.
# --------------------------------------------------------------------------
def frame(x0, y0, x1, y1, facing):
    """Returns (length along s, w0, w1, place) for a ramp whose high side is
    toward `facing` (+x, -x, +y, -y)."""
    if facing == "+x":
        return x1 - x0, y0, y1, lambda s, z, w: (x0 + s, w, z)
    if facing == "-x":
        return x1 - x0, y0, y1, lambda s, z, w: (x1 - s, w, z)
    if facing == "+y":
        return y1 - y0, x0, x1, lambda s, z, w: (w, y0 + s, z)
    if facing == "-y":
        return y1 - y0, x0, x1, lambda s, z, w: (w, y1 - s, z)
    raise ValueError(facing)


def arc(run, rise, segs):
    """Points of a circular transition that leaves the floor flat and rises
    `rise` over `run`. (s, z) from (0, 0) to (run, rise)."""
    theta = 2 * math.atan2(rise, run)
    r = run / math.sin(theta)
    return [(r * math.sin(theta * i / segs), r * (1 - math.cos(theta * i / segs))) for i in range(segs + 1)]


def side_mats(top_edges):
    def m(i):
        if i == "cap":
            return MAT_RAMP_SIDE
        return MAT_RAMP if i in top_edges else MAT_RAMP_SIDE
    return m


def transition(out, place, s0, run, rise, w0, w1, segs=8, reverse=False):
    """A quarter-pipe curve as convex wedges from s0 (floor) to s0+run (lip).
    reverse: the curve rises toward smaller s (for the far side of a pipe)."""
    pts = arc(run, rise, segs)
    for i in range(segs):
        (sa, za), (sb, zb) = pts[i], pts[i + 1]
        if reverse:
            sa, sb = s0 - sa, s0 - sb
        else:
            sa, sb = s0 + sa, s0 + sb
        za, zb = FLOOR + za, FLOOR + zb
        if round(za) == FLOOR:
            prof = [(sa, FLOOR), (sb, FLOOR), (sb, zb)]
            top = {2}
        else:
            prof = [(sa, FLOOR), (sb, FLOOR), (sb, zb), (sa, za)]
            top = {2}
        out.append(prism(prof, place, w0, w1, side_mats(top)))


def coping(out, place, s, z, w0, w1):
    out.append(prism(octagon(4, z - 4, s), place, w0, w1, lambda i: MAT_METAL))


def quarterpipe(out, x0, y0, x1, y1, zt, facing, deck=64):
    L, w0, w1, place = frame(x0, y0, x1, y1, facing)
    rise = zt - FLOOR
    run = L - deck
    transition(out, place, 0, run, rise, w0, w1)
    out.append(prism([(run, FLOOR), (L, FLOOR), (L, zt), (run, zt)], place, w0, w1, side_mats({2})))
    coping(out, place, run, zt, w0, w1)


def halfpipe(out, x0, y0, x1, y1, zt, axis, deck=48):
    facing = "+x" if axis == "x" else "+y"
    L, w0, w1, place = frame(x0, y0, x1, y1, facing)
    rise = zt - FLOOR
    run = rise                                   # a full radius: vert at the top
    flat = L - 2 * deck - 2 * run
    assert flat > 64, "halfpipe too short for its height"
    # deck, curve down, flat, curve up, deck
    out.append(prism([(0, FLOOR), (deck, FLOOR), (deck, zt), (0, zt)], place, w0, w1, side_mats({2})))
    transition(out, place, deck + run, run, rise, w0, w1, reverse=True)
    # (the flat bottom is the park floor itself)
    transition(out, place, L - deck - run, run, rise, w0, w1)
    out.append(prism([(L - deck, FLOOR), (L, FLOOR), (L, zt), (L - deck, zt)], place, w0, w1, side_mats({2})))
    coping(out, place, deck, zt, w0, w1)
    coping(out, place, L - deck, zt, w0, w1)


def spine(out, x0, y0, x1, y1, zt, axis):
    facing = "+x" if axis == "x" else "+y"
    L, w0, w1, place = frame(x0, y0, x1, y1, facing)
    half = L / 2
    rise = zt - FLOOR
    transition(out, place, 0, half, rise, w0, w1)
    transition(out, place, L, half, rise, w0, w1, reverse=True)
    coping(out, place, half, zt, w0, w1)


def flatramp(out, x0, y0, x1, y1, zt, facing, slope=0.65):
    L, w0, w1, place = frame(x0, y0, x1, y1, facing)
    s1 = L * slope
    out.append(prism([(0, FLOOR), (s1, FLOOR), (s1, zt)], place, w0, w1, side_mats({2})))
    out.append(prism([(s1, FLOOR), (L, FLOOR), (L, zt), (s1, zt)], place, w0, w1, side_mats({2})))


def funbox(out, x0, y0, x1, y1, zt):
    out.append(frustum(x0, y0, x1, y1, FLOOR, zt, 128, MAT_BOX, MAT_RAMP))


def rail(out, x0, y0, x1, y1, zt):
    cy = (y0 + y1) / 2
    place = lambda s, z, w: (w, s, z)            # s = y, w = x
    out.append(prism(octagon(4, zt - 4, cy), place, x0, x1, lambda i: MAT_METAL))
    for px in (x0 + 24, x1 - 24):
        out.append(box(px - 3, cy - 3, FLOOR, px + 3, cy + 3, zt - 7, MAT_METAL))


def clamp(x0, y0, x1, y1):
    return max(x0, BOX[0]), max(y0, BOX[1]), min(x1, BOX[2]), min(y1, BOX[3])


def ramps():
    out = []
    for name, x0, y0, x1, y1, zt, f in RAMPS:
        x0, y0, x1, y1 = clamp(x0, y0, x1, y1)
        if name.startswith("quarterpipe"):
            quarterpipe(out, x0, y0, x1, y1, zt, f)
        elif name.startswith("halfpipe"):
            halfpipe(out, x0, y0, x1, y1, zt, f)
        elif name.startswith("spiner"):
            spine(out, x0, y0, x1, y1, zt, f)
        elif name.startswith("flatramp"):
            flatramp(out, x0, y0, x1, y1, zt, f)
        elif name.startswith("funbox"):
            funbox(out, x0, y0, x1, y1, zt)
        elif name.startswith("rail"):
            rail(out, x0, y0, x1, y1, zt)
        else:
            raise ValueError(name)
    return out


def shell():
    x0, y0, x1, y1 = BOX
    X0, Y0, X1, Y1 = x0 - WALL_T, y0 - WALL_T, x1 + WALL_T, y1 + WALL_T
    out = [box(X0, Y0, FLOOR - 64, X1, Y1, FLOOR, MAT_NODRAW, top=MAT_FLOOR)]
    walls = [(X0, Y0, x0, Y1), (x1, Y0, X1, Y1), (x0, Y0, x1, y0), (x0, y1, x1, Y1)]
    for a, b, c, d in walls:
        out.append(box(a, b, FLOOR, c, d, WALL_TOP, MAT_WALL))
        out.append(box(a, b, WALL_TOP, c, d, CEIL, MAT_SKY))
    out.append(box(X0, Y0, CEIL, X1, Y1, CEIL + SKY_T, MAT_SKY))
    return out


# --------------------------------------------------------------------------
# Entities
# --------------------------------------------------------------------------
def ent(ids, cls, connections=(), **kv):
    s = 'entity\n{\n\t"id" "%d"\n\t"classname" "%s"\n' % (ids.next(), cls)
    for k, v in kv.items():
        s += '\t"%s" "%s"\n' % (k, v)
    if connections:
        s += '\tconnections\n\t{\n'
        for out, target in connections:
            s += '\t\t"%s" "%s"\n' % (out, target)
        s += '\t}\n'
    return s + '}\n'


def lamps():
    """The city's street lamp heads, (x, y, z) each: mapsrc/city_lamps.txt,
    written by tools/city/lamps.lua from the city's own layout."""
    here = os.path.dirname(os.path.abspath(__file__))
    out = []
    with open(os.path.join(here, "city_lamps.txt")) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                out.append(tuple(int(v) for v in line.split()))
    return out


def entities(ids):
    out = []
    for i, (x, y) in enumerate(SPAWNS):
        out.append(ent(ids, "info_player_start", origin="%d %d %d" % (x, y, FLOOR + 8), angles="0 90 0"))
        out.append(ent(ids, "info_player_deathmatch", origin="%d %d %d" % (x, y, FLOOR + 8), angles="0 90 0"))
    # THE LIGHT. A low late-autumn sun in the west, light travelling +x (pitch
    # -28, yaw 0), behind a 464-unit wall: its shadow reaches ~870 units into
    # the park, over the whole west strip and every ramp in it. So:
    #   - the sun is warm and moderate (it was 400 and blew the lit slopes out)
    #   - the sky fill is cool and strong enough to light the shade: in the
    #     wall's shadow, and on every slope turned from the sun, you still see
    #     the wood (it was 70, which left the west eighth of the park black)
    #   - a row of soft lights high along the west wall stands in for the
    #     bounce into the wall's shadow that vrad can't compute (FILL above)
    #   - each of the city's street lamps is a real light here too, baked
    #     onto the ramps beneath it (mapsrc/city_lamps.txt, from the city)
    #   - the exposure is pinned, so HDR auto-exposure can't brighten the
    #     shade back into a washed-out frame
    # tests/test_lighting.lua holds every cell of the park between "too dark"
    # and "blown out".
    out.append(ent(ids, "light_environment", origin="1664 -512 1500", angles="0 0 0", pitch="-28",
                   _light=SUN, _ambient=SKY,
                   _lightHDR="-1 -1 -1 1", _ambientHDR="-1 -1 -1 1", _lightscaleHDR="1",
                   _AmbientScaleHDR="1", SunSpreadAngle="5"))
    for i, (x, y, z) in enumerate(lamps()):
        out.append(ent(ids, "light", origin="%d %d %d" % (x, y, z - 24), _light=LAMP,
                       _lightHDR="-1 -1 -1 1", _lightscaleHDR="1", style="0",
                       _fifty_percent_distance=str(LAMP_HALF), _zero_percent_distance=str(LAMP_ZERO)))
    for x, y, z in FILL_AT:
        out.append(ent(ids, "light", origin="%d %d %d" % (x, y, z), _light=FILL,
                       _lightHDR="-1 -1 -1 1", _lightscaleHDR="1", style="0",
                       _fifty_percent_distance=str(FILL_HALF), _zero_percent_distance=str(FILL_ZERO)))
    out.append(ent(ids, "env_fog_controller", origin="1664 -512 1400", fogenable="1",
                   fogcolor="150 118 92", fogcolor2="150 118 92", fogstart="3000", fogend="15000",
                   fogmaxdensity="0.45", fogdir="1 0 0", farz="-1", targetname="fog"))
    out.append(ent(ids, "shadow_control", origin="1664 -512 1300", angles="62 0 0", color="64 52 40",
                   distance="96"))
    out.append(ent(ids, "env_tonemap_controller", origin="1664 -512 1200", targetname="tonemap"))
    out.append(ent(ids, "logic_auto", origin="1664 -512 1100", spawnflags="0", connections=[
        ("OnMapSpawn", "tonemap,SetAutoExposureMin,%s,0,-1" % EXPOSURE[0]),
        ("OnMapSpawn", "tonemap,SetAutoExposureMax,%s,0,-1" % EXPOSURE[1]),
        ("OnMapSpawn", "tonemap,SetBloomScale,%s,0,-1" % BLOOM),
    ]))
    return out


class Ids:
    def __init__(self): self.n = 0
    def next(self):
        self.n += 1
        return self.n


def main():
    ids = Ids()
    parts = ['versioninfo\n{\n\t"editorversion" "400"\n\t"editorbuild" "0"\n\t"mapversion" "1"\n'
             '\t"formatversion" "100"\n\t"prefab" "0"\n}\n',
             'world\n{\n\t"id" "%d"\n\t"mapversion" "1"\n\t"classname" "worldspawn"\n'
             '\t"skyname" "%s"\n\t"detailmaterial" "detail/detailsprites"\n'
             '\t"detailvbsp" "detail.vbsp"\n\t"maxpropscreenwidth" "-1"\n' % (ids.next(), SKYNAME)]
    for b in shell() + ramps():
        parts.append(b.vmf(ids))
    parts.append('}\n')
    parts += entities(ids)
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "petopia_bmx_fall.vmf"), "w", newline="\n") as f:
        f.write("".join(parts))


if __name__ == "__main__":
    main()
