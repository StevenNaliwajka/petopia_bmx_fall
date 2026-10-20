//! petopia_check <map.bsp> [x0 y0 x1 y1]
//! Does the collision SkateGM hands its engine cover the map wherever the map
//! itself is solid? Built against SkateGM's own map loader and scene builder
//! (its gm_skategm crate, without the engine): tools/skategm/check.sh.
//!
//! Floors: on a grid (STEP, 16 u), the map's top surface from its own BSP tree
//! against the highest upward-facing engine triangle there ('X' none, 'v' over
//! 16 u too low, 'r' on a coping/pipe SkateGM made a grind rail, '/' a steep
//! face an engine triangle runs along). Walls: horizontal rays into each wall
//! of the box must meet an engine triangle facing them.
//!
//! Surfaces: every brush face minus what other brushes cover (the map as a
//! player meets it), against the engine triangles lying on it; a piece none
//! covers is missing, unless SkateGM's own ledge ramps or curves stand over it
//! (or anything within 13 u in front, as a ramp's toe stands over the floor).
//!
//! Env: STEP (grid, u), TOP (start the downward scan here), FULL=1 (print every
//! row), SK8_SMOOTH (0/1/2), SK8_OFF / SK8_ON (SkateGM's own stage switches),
//! PROBE=x,y (the engine triangles at one spot; PROBEZ=z around that height),
//! UNDER=x,y;... (engine ground below z 100 there: anything inside a ramp?),
//! PATCHES=file (cl_skategm_patches.lua: fed to SkateGM as entities, the way
//! cl_skategm.lua feeds them; none = without), GEN=file (write that file first:
//! every steep surface with a piece missing under any smoothing preset, whole),
//! GAPS=n (list n), RAILS=1 (list the rails).
use glam::Vec3;
use gmcl_skategm_win64::{cleanup, coords, scene::Scene, world};
use std::collections::HashMap;

fn ray_tri(o: Vec3, d: Vec3, t: &[Vec3; 3]) -> Option<f32> {
    let (e1, e2) = (t[1] - t[0], t[2] - t[0]);
    let p = d.cross(e2);
    let det = e1.dot(p);
    if det.abs() < 1e-8 {
        return None;
    }
    let inv = 1.0 / det;
    let s = o - t[0];
    let u = s.dot(p) * inv;
    if !(-1e-4..=1.0 + 1e-4).contains(&u) {
        return None;
    }
    let q = s.cross(e1);
    let v = d.dot(q) * inv;
    if v < -1e-4 || u + v > 1.0 + 1e-4 {
        return None;
    }
    let t = e2.dot(q) * inv;
    (t >= 0.0).then_some(t)
}

/// Distance from p to triangle t (closest point, Ericson's method).
fn point_tri(p: Vec3, t: &[Vec3; 3]) -> f32 {
    let (a, b, c) = (t[0], t[1], t[2]);
    let (ab, ac, ap) = (b - a, c - a, p - a);
    let (d1, d2) = (ab.dot(ap), ac.dot(ap));
    if d1 <= 0.0 && d2 <= 0.0 { return (p - a).length(); }
    let bp = p - b;
    let (d3, d4) = (ab.dot(bp), ac.dot(bp));
    if d3 >= 0.0 && d4 <= d3 { return (p - b).length(); }
    let vc = d1 * d4 - d3 * d2;
    if vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0 { return (p - (a + ab * (d1 / (d1 - d3)))).length(); }
    let cp = p - c;
    let (d5, d6) = (ab.dot(cp), ac.dot(cp));
    if d6 >= 0.0 && d5 <= d6 { return (p - c).length(); }
    let vb = d5 * d2 - d1 * d6;
    if vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0 { return (p - (a + ac * (d2 / (d2 - d6)))).length(); }
    let va = d3 * d6 - d5 * d4;
    if va <= 0.0 && (d4 - d3) >= 0.0 && (d5 - d6) >= 0.0 {
        return (p - (b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))))).length();
    }
    let denom = 1.0 / (va + vb + vc);
    (p - (a + ab * (vb * denom) + ac * (vc * denom))).length()
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let bytes = std::fs::read(&a[1]).expect("map");
    let num = |i: usize, d: f32| a.get(i).and_then(|s| s.parse().ok()).unwrap_or(d);
    let (x0, y0, x1, y1) = (num(2, -256.0), num(3, -1792.0), num(4, 3584.0), num(5, 768.0));
    let bsp = vbsp::Bsp::read(&bytes).expect("vbsp");
    let leaves = world::leaves_in_order(&bytes).expect("leaves");
    let solid = cleanup::WorldSolid::new(&bsp, &leaves, 0x1 | 0x2 | 0x8 | 0x10000);
    let w = world::from_bsp_with(&bytes, std::env::var("SK8_SMOOTH").ok().and_then(|v| v.parse().ok()).unwrap_or(1)).expect("SkateGM could not read the map");
    println!("SkateGM: {}", w.summary);
    let mut scene = Scene::new(w);
    scene.background_layer = false;
    let centre = Vec3::new((x0 + x1) / 2.0, (y0 + y1) / 2.0, 64.0);
    // the map's own surfaces: every face of every solid brush, minus what other
    // brushes cover (what Source collides with, and what a skater must find)
    let brushes = world_brushes(&bsp, &leaves);
    let (surfaces, face_of) = open_surfaces(&brushes, &solid);
    println!("the map: {} solid brushes, {} open surface pieces", brushes.len(), surfaces.len());
    // GEN=file: the patches SkateGM needs, written as cl_skategm.lua reads
    // them (each a piece of the map's own surface its collision is missing)
    let mut patch_file = std::env::var("PATCHES").ok().filter(|p| p != "none");
    if let Ok(out) = std::env::var("GEN") {
        // under each of SkateGM's smoothing presets (its "collision style"
        // setting), then together: what one leaves out and another does not is
        // still a patch, so one set serves them all
        let mut by_surface: std::collections::BTreeMap<usize, Vec<Poly>> = std::collections::BTreeMap::new();
        for smooth in [0u32, 1, 2] {
            let w = world::from_bsp_with(&bytes, smooth).expect("SkateGM could not read the map");
            let mut sc = Scene::new(w);
            sc.background_layer = false;
            let (raw, _, _, raw_tags) = sc.build_tagged(centre);
            let raw: Vec<[Vec3; 3]> = raw.iter().map(|t| t.map(|v| Vec3::from_array(coords::from_skate(v)))).collect();
            let (holes, _) = missing(&surfaces, &raw, &raw_tags);
            let mut n = 0;
            for (si, pieces) in holes {
                let have = by_surface.entry(si).or_default();
                for p in pieces {
                    // (only what the presets before did not already give)
                    let mut left = vec![p];
                    for h in have.iter() {
                        let m = normal(h);
                        let edges: Vec<[f32; 4]> = (0..h.len()).map(|k| {
                            let (a, b) = (h[k], h[(k + 1) % h.len()]);
                            let e = (b - a).cross(m).normalize_or_zero();
                            [e.x, e.y, e.z, e.dot(a)]
                        }).collect();
                        left = left.into_iter().flat_map(|q| outside(q, &edges)).collect();
                    }
                    for q in left.into_iter().filter(|q| area(q) >= 0.5 && width(q) >= 0.25) {
                        have.push(q);
                        n += 1;
                    }
                }
            }
            println!("smoothing {smooth}: {n} pieces more");
        }
        // Each surface with a piece missing goes WHOLE (what SkateGM keeps of it
        // too: its own triangles there and the patch agree), and only a steep
        // one. SkateGM finds an entity's grind rails from that entity's own
        // triangles alone, so a walkable patch's every edge, with no ground of
        // its own past it, became a rail across the slope it mends (funbox 2:
        // five of them); a steep face is never a rail's top.
        // (a face other brushes cut into several open pieces goes as all of
        // them, if any has a piece missing)
        let mut faces_hit = std::collections::BTreeSet::new();
        let mut holes: Vec<(usize, Vec<Poly>)> = Vec::new();
        for (si, v) in by_surface.into_iter().filter(|(_, v)| !v.is_empty()) {
            let n = normal(&surfaces[si]);
            if n.z > 0.65 {
                let c = surfaces[si].iter().copied().sum::<Vec3>() / surfaces[si].len() as f32;
                println!("left out, walkable: {} pieces ({:.0} sq u) of the surface at ({:.0} {:.0} {:.0})",
                    v.len(), v.iter().map(|p| area(p)).sum::<f32>(), c.x, c.y, c.z);
                continue;
            }
            faces_hit.insert(face_of[si]);
        }
        // (but no sliver under 0.5 u across: where a face meets a coping's top,
        // the open test lifts a hair of it out over the coping, and SkateGM's
        // weld folds two of those into a ridge it takes for a rail)
        for face in faces_hit {
            let pieces: Vec<Poly> = (0..surfaces.len()).filter(|&k| face_of[k] == face && width(&surfaces[k]) >= 0.5 && area(&surfaces[k]) >= 1.0)
                .map(|k| surfaces[k].clone()).collect();
            let first = (0..surfaces.len()).find(|&k| face_of[k] == face).unwrap_or(0);
            holes.push((first, pieces));
        }
        write_patches(&out, &holes);
        println!("wrote {} patches to {out}", holes.len());
        patch_file = Some(out);
    }
    if let Some(p) = &patch_file {
        let patches = read_patches(p);
        // as cl_skategm.lua hands them over: each a mesh of its own (DefineModel
        // mode 1, wound as given), all of them near the skater (SetEntities)
        let mut placed = Vec::new();
        for (name, soup) in &patches {
            scene.define_shape(name.clone(), vec![soup.clone()], true);
            placed.push(world::Placed { model: name.clone(), origin: Vec3::ZERO, angles: [0.0; 3] });
        }
        scene.set_dynamic(placed);
        println!("patches: {} fed to SkateGM as entities, from {p}", patches.len());
    }
    let (tris, rails, st, tags) = scene.build_tagged(centre);
    println!("engine input around {:?}: {} triangles, {} rails, region half {}", centre.to_array(), tris.len(), rails.len(), st.half);
    let tris: Vec<[Vec3; 3]> = tris.iter().map(|t| t.map(|v| Vec3::from_array(coords::from_skate(v)))).collect();
    if std::env::var("RAILS").is_ok() {
        for r in &rails {
            let (a, b) = (coords::from_skate(r[0]), coords::from_skate(r[r.len() - 1]));
            println!("rail ({:.0} {:.0} {:.0}) - ({:.0} {:.0} {:.0}), {} points", a[0], a[1], a[2], b[0], b[1], b[2], r.len());
        }
    }
    // copings and pipes become grind rails (the engine grinds those; their
    // triangles go): a spot on one is not a hole
    let rails: Vec<Vec<Vec3>> = rails.iter().map(|r| r.iter().map(|v| Vec3::from_array(coords::from_skate(*v))).collect()).collect();
    let on_rail = |p: Vec3| {
        rails.iter().any(|r| r.windows(2).any(|w| {
            let (a, b) = (w[0], w[1]);
            let ab = b - a;
            let t = ((p - a).dot(ab) / ab.length_squared().max(1e-6)).clamp(0.0, 1.0);
            let q = a + ab * t;
            (q - p).truncate().length() <= 10.0 && (q.z - p.z).abs() <= 12.0
        }))
    };

    // upward-facing triangles, bucketed 64 u
    const CELL: f32 = 64.0;
    let mut up: HashMap<(i32, i32), Vec<usize>> = HashMap::new();
    for (i, t) in tris.iter().enumerate() {
        let n = (t[1] - t[0]).cross(t[2] - t[0]);
        if n.length_squared() < 1e-9 || n.normalize().z <= 0.2 {
            continue;
        }
        let lo = t[0].min(t[1]).min(t[2]);
        let hi = t[0].max(t[1]).max(t[2]);
        for cx in (lo.x / CELL).floor() as i32..=(hi.x / CELL).floor() as i32 {
            for cy in (lo.y / CELL).floor() as i32..=(hi.y / CELL).floor() as i32 {
                up.entry((cx, cy)).or_default().push(i);
            }
        }
    }
    let ground = |x: f32, y: f32, top: f32| -> Option<f32> {
        let o = Vec3::new(x, y, top);
        let d = Vec3::new(0.0, 0.0, -1.0);
        let mut best: Option<f32> = None;
        for &i in up.get(&((x / CELL).floor() as i32, (y / CELL).floor() as i32))? {
            if let Some(t) = ray_tri(o, d, &tris[i]) {
                let z = top - t;
                if best.map_or(true, |b| z > b) {
                    best = Some(z);
                }
            }
        }
        best
    };

    // (UNDER=x,y;x,y...: the highest engine ground below 100 u there - is there
    // anything inside a ramp, under its surface?)
    if let Ok(list) = std::env::var("UNDER") {
        for xy in list.split(';') {
            let v: Vec<f32> = xy.split(',').filter_map(|s| s.parse().ok()).collect();
            println!("under ({}, {}): ground below z 100 = {:?}", v[0], v[1], ground(v[0], v[1], 100.0));
        }
        return;
    }
    // (PROBE=x,y: what is there, then stop)
    if let Ok(pr) = std::env::var("PROBE") {
        let v: Vec<f32> = pr.split(',').filter_map(|s| s.parse().ok()).collect();
        let (px, py) = (v[0], v[1]);
        let mut z = 1700.0;
        while z > 0.0 && !solid.solid(Vec3::new(px, py, z)) { z -= 0.25; }
        // (PROBEZ=z: look around that height instead of the map's top there)
        if let Some(pz) = std::env::var("PROBEZ").ok().and_then(|v| v.parse::<f32>().ok()) { z = pz; }
        println!("probe ({px}, {py}): map top z {z}");
        for (i, t) in tris.iter().enumerate() {
            let lo = t[0].min(t[1]).min(t[2]);
            let hi = t[0].max(t[1]).max(t[2]);
            if lo.x - 6.0 <= px && px <= hi.x + 6.0 && lo.y - 6.0 <= py && py <= hi.y + 6.0 && lo.z - 30.0 <= z && z <= hi.z + 30.0 {
                let n = (t[1] - t[0]).cross(t[2] - t[0]).normalize_or_zero();
                let hit = ray_tri(Vec3::new(px, py, z + 16.0), Vec3::new(0.0, 0.0, -1.0), t).map(|d| z + 16.0 - d);
                println!("  tri {i}: n ({:.2} {:.2} {:.2}) hit below {:?}  {:?}", n.x, n.y, n.z, hit, t.map(|v| (v.x.round(), v.y.round(), (v.z * 10.0).round() / 10.0)));
            }
        }
        return;
    }
    // floors
    let top_at = |x: f32, y: f32| -> f32 {
        // the map's own top surface here, from 1700 down
        let mut z: f32 = std::env::var("TOP").ok().and_then(|v| v.parse().ok()).unwrap_or(1700.0);
        while z > 0.0 && !solid.solid(Vec3::new(x, y, z)) {
            z -= 1.0;
        }
        z
    };
    let step: f32 = std::env::var("STEP").ok().and_then(|v| v.parse().ok()).unwrap_or(16.0);
    let (mut checked, mut holes, mut low, mut steep) = (0, 0, 0, 0);
    let mut rows = Vec::new();
    let mut y = y1 - step / 2.0;
    while y > y0 {
        let mut row = String::new();
        let mut x = x0 + step / 2.0;
        while x < x1 {
            let z = top_at(x, y);
            // the map's slope here: over ~78 degrees (the check's "upward" limit)
            // is a wall to ride up, not ground to stand on
            let slope = [(2.0, 0.0), (-2.0, 0.0), (0.0, 2.0), (0.0, -2.0)]
                .iter()
                .map(|(dx, dy)| (top_at(x + dx, y + dy) - z).abs() / 2.0)
                .fold(0.0f32, f32::max);
            let c = if z <= 0.0 {
                ' '
            } else if on_rail(Vec3::new(x, y, z)) {
                'r'
            } else if slope > 4.5 && ground(x, y, z + 16.0).map_or(true, |g| g < z - 16.0) {
                // steep: covered only if an engine triangle runs within 3 u of it
                let p = Vec3::new(x, y, z);
                if tris.iter().any(|t| point_tri(p, t) <= 3.0) {
                    steep += 1;
                    '/'
                } else {
                    holes += 1;
                    'X'
                }
            } else {
                checked += 1;
                match ground(x, y, z + 16.0) {
                    None => { holes += 1; 'X' }
                    Some(g) if g < z - 16.0 => { low += 1; 'v' }
                    Some(_) => '.',
                }
            };
            row.push(c);
            x += step;
        }
        rows.push((y, row));
        y -= step;
    }
    println!("floor: {checked} spots checked, {holes} with no ground under them (X), {low} with ground over 16 u too low (v); {steep} steep faces over 78 degrees (/, not ground)");
    if holes + low > 0 {
        println!("top-down, every {step} u (x {x0}..{x1} left to right):");
        for (y, row) in rows.iter().step_by(std::env::var("FULL").map(|_| 1).unwrap_or(2)) {
            let r: String = row.chars().step_by(std::env::var("FULL").map(|_| 1).unwrap_or(2)).collect();
            println!("{y:7.0} {r}");
        }
    }

    // walls: rays into each wall of the box, from 24 u in front
    let walls: [(&str, Vec3, Vec3, f32, f32); 4] = [
        ("west", Vec3::new(x0, 0.0, 0.0), Vec3::new(-1.0, 0.0, 0.0), y0, y1),
        ("east", Vec3::new(x1, 0.0, 0.0), Vec3::new(1.0, 0.0, 0.0), y0, y1),
        ("south", Vec3::new(0.0, y0, 0.0), Vec3::new(0.0, -1.0, 0.0), x0, x1),
        ("north", Vec3::new(0.0, y1, 0.0), Vec3::new(0.0, 1.0, 0.0), x0, x1),
    ];
    let mut wall_miss_total = 0;
    for (name, plane, dir, s0, s1) in walls {
        let (mut rays, mut miss) = (0, 0);
        let mut missed_at = Vec::new();
        let mut s = s0 + 16.0;
        while s < s1 - 8.0 {
            for z in [72.0, 120.0, 200.0, 300.0, 420.0, 520.0] {
                let on = if dir.x != 0.0 { Vec3::new(plane.x, s, z) } else { Vec3::new(s, plane.y, z) };
                let start = on - dir * 24.0;
                // only where the wall is the first thing there (not behind a ramp)
                if (0..=22).any(|k| solid.solid(on - dir * (2.0 + k as f32))) || !solid.solid(on + dir * 2.0) {
                    continue;
                }
                rays += 1;
                let hit = tris.iter().any(|t| {
                    let n = (t[1] - t[0]).cross(t[2] - t[0]);
                    n.dot(dir) < 0.0 && ray_tri(start, dir, t).is_some_and(|d| d <= 26.0)
                });
                if !hit {
                    miss += 1;
                    missed_at.push((s, z));
                }
            }
            s += 32.0;
        }
        wall_miss_total += miss;
        println!("{name} wall: {rays} rays, {miss} went through");
        for (s, z) in missed_at.iter().take(12) {
            println!("    through at {s} (along), z {z}");
        }
    }

    // surfaces: every open piece of the map's surface, against the engine's
    // triangles lying on it; what none covers, with nothing of SkateGM's own
    // (a ledge ramp, a curve) standing just in front of it, is a hole
    let (gaps, replaced) = missing(&surfaces, &tris, &tags);
    let gaps: Vec<Poly> = gaps.into_iter().flat_map(|(_, g)| g).collect();
    let gap_area: f32 = gaps.iter().map(|g| area(g)).sum();
    println!("surfaces: {} open pieces, {} pieces missing ({:.0} sq u), {} replaced by SkateGM's own ramps and curves",
        surfaces.len(), gaps.len(), gap_area, replaced);
    for g in gaps.iter().take(std::env::var("GAPS").ok().and_then(|v| v.parse().ok()).unwrap_or(40)) {
        let c = g.iter().copied().sum::<Vec3>() / g.len() as f32;
        let n = normal(g);
        let (lo, hi) = bounds(g);
        println!("    missing {:.0} sq u at ({:.0} {:.0} {:.0}), facing ({:.2} {:.2} {:.2}), x {:.1}..{:.1} y {:.1}..{:.1} z {:.1}..{:.1}",
            area(g), c.x, c.y, c.z, n.x, n.y, n.z, lo.x, hi.x, lo.y, hi.y, lo.z, hi.z);
    }
    let ok = holes + low + wall_miss_total + gaps.len() == 0;
    println!("{}", if ok { "RESULT: SkateGM collision covers the park" } else { "RESULT: HOLES in SkateGM's collision" });
    std::process::exit(if ok { 0 } else { 1 });
}

type Poly = Vec<Vec3>;

/// The world's solid brushes (the world model's tree), each as its planes
/// ([normal, dist], inside n.p <= dist) without vbsp's bevel sides: those are
/// for Source's hull traces, not faces (near-duplicates of real sides).
fn world_brushes(bsp: &vbsp::Bsp, leaves: &[world::LeafBrushes]) -> Vec<Vec<[f32; 4]>> {
    const PLAYER_SOLID: u32 = 0x1 | 0x2 | 0x8 | 0x10000;
    let mut set = std::collections::BTreeSet::new();
    let mut stack = vec![bsp.models.first().map_or(0, |m| m.head_node)];
    while let Some(n) = stack.pop() {
        if n >= 0 {
            if let Some(node) = bsp.nodes.get(n as usize) {
                stack.push(node.children[0]);
                stack.push(node.children[1]);
            }
        } else if let Some(leaf) = leaves.get((-1 - n) as usize) {
            for lb in bsp.leaf_brushes.iter().skip(leaf.first).take(leaf.count) {
                set.insert(lb.brush as usize);
            }
        }
    }
    set.into_iter()
        .filter_map(|i| {
            let b = bsp.brushes.get(i)?;
            if b.flags.bits() & PLAYER_SOLID == 0 {
                return None;
            }
            let planes: Vec<[f32; 4]> = bsp.brush_sides.iter().skip(b.brush_side as usize).take(b.num_brush_sides as usize)
                .filter(|s| s.bevel == 0)
                .filter_map(|s| bsp.planes.get(s.plane as usize))
                .map(|p| [p.normal.x, p.normal.y, p.normal.z, p.dist])
                .collect();
            (planes.len() >= 4).then_some(planes)
        })
        .collect()
}

fn normal(p: &Poly) -> Vec3 {
    let mut n = Vec3::ZERO;
    for i in 1..p.len().saturating_sub(1) {
        n += (p[i] - p[0]).cross(p[i + 1] - p[0]);
    }
    n.normalize_or_zero()
}

fn area(p: &Poly) -> f32 {
    let mut n = Vec3::ZERO;
    for i in 1..p.len().saturating_sub(1) {
        n += (p[i] - p[0]).cross(p[i + 1] - p[0]);
    }
    n.length() * 0.5
}

/// Narrowest width of a convex polygon: twice its area over its longest edge
/// (a sliver along a seam has next to none).
fn width(p: &Poly) -> f32 {
    let long = (0..p.len()).map(|i| (p[(i + 1) % p.len()] - p[i]).length()).fold(0.0f32, f32::max);
    if long <= 0.0 { 0.0 } else { 2.0 * area(p) / long }
}

fn tidy(p: Poly) -> Poly {
    let mut out: Poly = Vec::with_capacity(p.len());
    for v in p {
        if out.last().map_or(true, |l: &Vec3| l.distance(v) > 1e-4) {
            out.push(v);
        }
    }
    while out.len() > 1 && out[0].distance(out[out.len() - 1]) <= 1e-4 {
        out.pop();
    }
    if out.len() < 3 || area(&out) < 1e-4 { Vec::new() } else { out }
}

/// A convex polygon split by a plane: (the part with n.p >= d, the part with n.p <= d).
fn split(p: &Poly, pl: &[f32; 4]) -> (Poly, Poly) {
    let n = Vec3::new(pl[0], pl[1], pl[2]);
    let d: Vec<f32> = p.iter().map(|v| { let s = n.dot(*v) - pl[3]; if s.abs() < 1e-4 { 0.0 } else { s } }).collect();
    let (mut front, mut back) = (Vec::new(), Vec::new());
    for i in 0..p.len() {
        let j = (i + 1) % p.len();
        if d[i] >= 0.0 { front.push(p[i]); }
        if d[i] <= 0.0 { back.push(p[i]); }
        if (d[i] > 0.0 && d[j] < 0.0) || (d[i] < 0.0 && d[j] > 0.0) {
            let q = p[i] + (p[j] - p[i]) * (d[i] / (d[i] - d[j]));
            front.push(q);
            back.push(q);
        }
    }
    (tidy(front), tidy(back))
}

/// The parts of convex polygon `p` outside the convex solid `planes`.
fn outside(p: Poly, planes: &[[f32; 4]]) -> Vec<Poly> {
    let mut out = Vec::new();
    let mut rest = p;
    for pl in planes {
        let (f, b) = split(&rest, pl);
        if !f.is_empty() { out.push(f); }
        if b.is_empty() { return out; }
        rest = b;
    }
    out
}

fn bounds(p: &[Vec3]) -> (Vec3, Vec3) {
    p.iter().fold((Vec3::splat(f32::MAX), Vec3::splat(f32::MIN)), |(a, b), v| (a.min(*v), b.max(*v)))
}

/// Every brush face, minus the parts other brushes cover (judged a hair in
/// front of it, so a face pressed against another brush counts as covered):
/// the map's surface as a player meets it (and not the shell's outside, which
/// faces the void). Faces looking down are left out (a skater never stands on
/// an underside; SkateGM drops low ones on purpose).
fn open_surfaces(brushes: &[Vec<[f32; 4]>], solid: &cleanup::WorldSolid) -> (Vec<Poly>, Vec<usize>) {
    const LIFT: f32 = 0.25;
    let faces: Vec<Vec<Poly>> = brushes.iter().map(|b| world::brush_faces(b)).collect();
    let boxes: Vec<(Vec3, Vec3)> = faces.iter().map(|f| bounds(&f.iter().flatten().copied().collect::<Vec<_>>())).collect();
    let (mut out, mut face_of) = (Vec::new(), Vec::new());
    let mut face_id = 0;
    for (i, fs) in faces.iter().enumerate() {
        for f in fs {
            face_id += 1;
            let n = normal(f);
            if f.len() < 3 || n.z < -0.3 {
                continue;
            }
            let mut pieces: Vec<Poly> = vec![f.iter().map(|v| *v + n * LIFT).collect()];
            let (lo, hi) = bounds(&pieces[0]);
            for (j, other) in brushes.iter().enumerate() {
                if j == i || pieces.is_empty() {
                    continue;
                }
                let (blo, bhi) = boxes[j];
                if bhi.x < lo.x - 0.1 || blo.x > hi.x + 0.1 || bhi.y < lo.y - 0.1 || blo.y > hi.y + 0.1 || bhi.z < lo.z - 0.1 || blo.z > hi.z + 0.1 {
                    continue;
                }
                pieces = pieces.into_iter().flat_map(|p| outside(p, other)).collect();
            }
            // (and open per the BSP tree: outside the shell is solid there)
            for p in pieces.into_iter()
                .filter(|p| !solid.solid(p.iter().copied().sum::<Vec3>() / p.len() as f32))
                .map(|p| p.into_iter().map(|v| v - n * LIFT).collect::<Poly>())
                .filter(|p| area(p) > 0.01) {
                out.push(p);
                face_of.push(face_id);
            }
        }
    }
    (out, face_of)
}

/// The engine's triangles bucketed on a 64 u grid (x, y).
struct Grid<'a> {
    tris: &'a [[Vec3; 3]],
    cells: HashMap<(i32, i32), Vec<u32>>,
}

impl<'a> Grid<'a> {
    const CELL: f32 = 64.0;
    fn new(tris: &'a [[Vec3; 3]]) -> Self {
        let mut cells: HashMap<(i32, i32), Vec<u32>> = HashMap::new();
        for (i, t) in tris.iter().enumerate() {
            let (lo, hi) = bounds(t);
            for x in (lo.x / Self::CELL).floor() as i32..=(hi.x / Self::CELL).floor() as i32 {
                for y in (lo.y / Self::CELL).floor() as i32..=(hi.y / Self::CELL).floor() as i32 {
                    cells.entry((x, y)).or_default().push(i as u32);
                }
            }
        }
        Grid { tris, cells }
    }
    /// The triangles whose cells meet the box lo..hi (x, y), each once (indices).
    fn near_idx(&self, lo: Vec3, hi: Vec3) -> Vec<usize> {
        let mut seen = std::collections::HashSet::new();
        let mut out = Vec::new();
        for x in (lo.x / Self::CELL).floor() as i32..=(hi.x / Self::CELL).floor() as i32 {
            for y in (lo.y / Self::CELL).floor() as i32..=(hi.y / Self::CELL).floor() as i32 {
                for &i in self.cells.get(&(x, y)).map(|v| v.as_slice()).unwrap_or(&[]) {
                    if seen.insert(i) {
                        out.push(i as usize);
                    }
                }
            }
        }
        out
    }
    fn near(&self, lo: Vec3, hi: Vec3) -> Vec<&'a [Vec3; 3]> {
        self.near_idx(lo, hi).into_iter().map(|i| &self.tris[i]).collect()
    }
}

/// Does an engine triangle facing the same way as `d` lie within `reach` in
/// front of `o` along `d` (and, if `only` is given, one with a tag in it)? It
/// stands between the surface and a skater coming at it: a ramp's toe over the
/// floor under it, SkateGM's ledge ramp over a riser.
fn shielded(o: Vec3, d: Vec3, reach: f32, grid: &Grid, tags: &[u8], only: Option<&[u8]>) -> bool {
    let end = o + d * reach;
    grid.near_idx(o.min(end), o.max(end)).into_iter().any(|i| {
        let t = &grid.tris[i];
        let n = (t[1] - t[0]).cross(t[2] - t[0]);
        only.map_or(true, |o| o.contains(tags.get(i).unwrap_or(&0)))
            && n.dot(d) > 0.0 && ray_tri(o, d, t).is_some_and(|s| s <= reach)
    })
}

/// The open surface no engine triangle covers: each piece minus the engine
/// triangles lying on it (same way up, within 0.1 u of its plane). Slivers
/// under 0.5 u across (welded seams) are not holes, nor steep ones under 3 u
/// tall (lips at a ramp's foot). A piece shielded all over
/// by what stands just in front of it is replaced, not missing: anything within
/// 13 u (a ramp's toe over the floor under it), or SkateGM's own ledge ramps
/// and curves within 40 u (they run out that far over a riser they replace),
/// or above a steep piece (a crack SkateGM roofs over, the walls under it gone).
/// Returns (missing pieces by the surface they belong to, how many were replaced).
fn missing(surfaces: &[Poly], tris: &[[Vec3; 3]], tags: &[u8]) -> (Vec<(usize, Vec<Poly>)>, usize) {
    let grid = Grid::new(tris);
    let ours: &[u8] = &[world::TAG_STEP_RAMP, world::TAG_CURVE];
    let mut holes = Vec::new();
    let mut replaced = 0;
    for (si, s) in surfaces.iter().enumerate() {
        let mut found = Vec::new();
        let n = normal(s);
        let d = n.dot(s[0]);
        let (lo, hi) = bounds(s);
        let mut left = vec![s.clone()];
        for t in grid.near(lo, hi) {
            if left.is_empty() {
                break;
            }
            let m = (t[1] - t[0]).cross(t[2] - t[0]).normalize_or_zero();
            if m.dot(n) < 0.999 || (n.dot(t[0]) - d).abs() > 0.1 {
                continue;
            }
            let (tlo, thi) = bounds(t);
            if thi.x < lo.x || tlo.x > hi.x || thi.y < lo.y || tlo.y > hi.y || thi.z < lo.z - 0.2 || tlo.z > hi.z + 0.2 {
                continue;
            }
            let edges: Vec<[f32; 4]> = (0..3).map(|k| {
                let (a, b) = (t[k], t[(k + 1) % 3]);
                let e = (b - a).cross(m).normalize_or_zero();
                [e.x, e.y, e.z, e.dot(a)]
            }).collect();
            left = left.into_iter().flat_map(|p| outside(p, &edges)).collect();
        }
        for p in left {
            if area(&p) < 1.0 || width(&p) < 0.5 {
                continue;
            }
            // (a steep piece under 3 u tall is a lip, not a way through: a board
            // and its wheels stand 4 u)
            let (plo, phi) = bounds(&p);
            if n.z.abs() < 0.7 && phi.z - plo.z <= 3.0 {
                continue;
            }
            let c = p.iter().copied().sum::<Vec3>() / p.len() as f32;
            let probes: Vec<Vec3> = std::iter::once(c).chain(p.iter().map(|v| c + (*v - c) * 0.8)).collect();
            // (from just behind the surface: a ramp's toe meets the floor at
            // nothing, and starts a hair above it)
            // (or, for a steep piece, roofed over by SkateGM's own: it spans a
            // crack too narrow to ride - the 4 u between the north quarter pipes -
            // with a ledge ramp at the top, and takes the walls under it out)
            let steep = n.z.abs() < 0.7;
            if probes.iter().all(|q| shielded(*q - n * 0.1, n, 13.1, &grid, tags, None)
                || shielded(*q - n * 0.1, n, 40.1, &grid, tags, Some(ours))
                || (steep && shielded(*q + n * 0.5, Vec3::Z, 200.0, &grid, tags, Some(ours)))) {
                replaced += 1;
            } else {
                found.push(p);
            }
        }
        if !found.is_empty() {
            holes.push((si, found));
        }
    }
    (holes, replaced)
}

/// The patches as lua/petopia_bmx_fall/cl_skategm_patches.lua: one line each,
/// its middle then its triangles (map units, wound so they face out of the
/// surface they belong to).
fn write_patches(path: &str, holes: &[(usize, Vec<Poly>)]) {
    let mut s = String::new();
    s.push_str("--[[--------------------------------------------------------------------------\n");
    s.push_str("    lua/petopia_bmx_fall/cl_skategm_patches.lua -- GENERATED, do not edit:\n");
    s.push_str("        GEN=lua/petopia_bmx_fall/cl_skategm_patches.lua tools/skategm/check.sh\n\n");
    s.push_str("    The pieces of the map's own surface that SkateGM's collision leaves out,\n");
    s.push_str("    found with SkateGM's own map loader on maps/petopia_bmx_fall.bsp; handed\n");
    s.push_str("    to it by cl_skategm.lua. One line for each surface with pieces missing:\n");
    s.push_str("    the middle of its box (x, y, z), then its triangles (x, y, z a corner),\n");
    s.push_str("    wound to face out of the surface.\n");
    s.push_str("----------------------------------------------------------------------------]]\n\n");
    s.push_str("PetopiaBMXFall = PetopiaBMXFall or {}\n");
    s.push_str("PetopiaBMXFall.SkateGMPatches = {\n");
    for (_, pieces) in holes {
        let all: Vec<Vec3> = pieces.iter().flatten().copied().collect();
        let (lo, hi) = bounds(&all);
        let c = (lo + hi) * 0.5;
        let mut nums = vec![c.x, c.y, c.z];
        for h in pieces {
            for i in 1..h.len() - 1 {
                for v in [h[0], h[i], h[i + 1]] {
                    nums.extend([v.x, v.y, v.z]);
                }
            }
        }
        let txt: Vec<String> = nums.iter().map(|x| { let r = (*x as f64 * 10000.0).round() / 10000.0; if r == 0.0 { "0".to_string() } else { format!("{r}") } }).collect();
        s.push_str(&format!("    {{ {} }},\n", txt.join(", ")));
    }
    s.push_str("}\n");
    std::fs::write(path, s).expect("write patches");
}

/// Back from that file: ("petopia_bmx_fall:surface/<n>", triangle soup), named
/// as cl_skategm.lua names them.
fn read_patches(path: &str) -> Vec<(String, Vec<Vec3>)> {
    let text = std::fs::read_to_string(path).expect("patches file");
    let mut out = Vec::new();
    for line in text.lines() {
        let l = line.trim();
        if !l.starts_with('{') {
            continue;
        }
        let nums: Vec<f32> = l.trim_matches(|c| c == '{' || c == '}' || c == ',' || c == ' ')
            .split(',').filter_map(|x| x.trim().parse().ok()).collect();
        if nums.len() < 12 || (nums.len() - 3) % 9 != 0 {
            continue;
        }
        let soup: Vec<Vec3> = nums[3..].chunks_exact(3).map(|c| Vec3::new(c[0], c[1], c[2])).collect();
        out.push((format!("petopia_bmx_fall:surface/{}", out.len() + 1), soup));
    }
    out
}
