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
//! Env: STEP (grid, u), TOP (start the downward scan here), FULL=1 (print every
//! row), SK8_SMOOTH (0/1/2), SK8_OFF / SK8_ON (SkateGM's own stage switches),
//! PROBE=x,y (the engine triangles at one spot), UNDER=x,y;... (engine ground
//! below z 100 there: anything inside a ramp?).
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
    let (tris, rails, st) = scene.build_input(centre);
    println!("engine input around {:?}: {} triangles, {} rails, region half {}", centre.to_array(), tris.len(), rails.len(), st.half);
    let tris: Vec<[Vec3; 3]> = tris.iter().map(|t| t.map(|v| Vec3::from_array(coords::from_skate(v)))).collect();
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
    let ok = holes + low + wall_miss_total == 0;
    println!("{}", if ok { "RESULT: SkateGM collision covers the park" } else { "RESULT: HOLES in SkateGM's collision" });
    std::process::exit(if ok { 0 } else { 1 });
}
