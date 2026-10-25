#!/usr/bin/env python3
"""Turn a Meshy capital-ship GLB into a game-ready mothership.

Capital ships arrive like fighters (one mesh, hundreds of loose pieces, no
materials) but are used very differently: they are kilometres long, stay put,
carry dozens of turrets and break apart when destroyed. This tool:

  * re-orients and scales the model to game space (metres, -Z forward, +Y up),
  * sorts every loose piece into a hull section along the ship's length, so
    the game can tear the hull apart at those seams,
  * finds the engine bells at the stern and lights their insides,
  * paints vertex-colour masks per piece (team paint, dark greebles, glow),
  * snaps the configured turret, shield generator and reactor spots onto the
    hull surface with ray casts, and samples surface points for fires,
    secondary explosions and running lights.

Writes assets/ships/<id>/<id>.glb (nodes section_N and engine_N) and
assets/ships/<id>/<id>.capital.json.

Usage: python3 tools/ship_import/capital_split.py tools/ship_import/configs/iron_vanguard.json
"""
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from meshy_split import ROOT, face_normals, islands, read_glb, split_normals, write_glb  # noqa: E402


def orient(P, fwd):
    sign = -1.0 if fwd[0] == "-" else 1.0
    axis = "xyz".index(fwd[1])
    if axis == 0:
        return np.c_[sign * P[:, 2], P[:, 1], -sign * P[:, 0]]
    if axis == 2:
        return np.c_[P[:, 0] * -sign, P[:, 1], P[:, 2] * -sign]
    raise ValueError("source_forward must be along x or z")


def raycast(P, I, origin, direction):
    """Nearest hit of one ray against every triangle (Moller-Trumbore)."""
    t0, t1, t2 = P[I[:, 0]], P[I[:, 1]], P[I[:, 2]]
    e1, e2 = t1 - t0, t2 - t0
    h = np.cross(direction, e2)
    a = (e1 * h).sum(1)
    ok = np.abs(a) > 1e-9
    f = np.where(ok, 1.0 / np.where(ok, a, 1.0), 0.0)
    s = origin - t0
    u = f * (s * h).sum(1)
    q = np.cross(s, e1)
    v = f * (q * direction).sum(1)
    t = f * (e2 * q).sum(1)
    hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-4)
    if not hit.any():
        return None
    k = np.where(hit, t, np.inf).argmin()
    n = np.cross(e1[k], e2[k])
    n /= np.linalg.norm(n)
    if n @ direction > 0:
        n = -n
    return origin + direction * t[k], n, int(k)


FACES = {
    "top": np.array([0.0, 1.0, 0.0]),
    "bottom": np.array([0.0, -1.0, 0.0]),
    "left": np.array([-1.0, 0.0, 0.0]),
    "right": np.array([1.0, 0.0, 0.0]),
}


def main(config_path):
    cfg = json.loads(Path(config_path).read_text())
    ship_id = cfg["id"]
    rng = np.random.default_rng(cfg.get("seed", 7))
    P, I = read_glb(ROOT / cfg["source"])
    I = I[face_normals(P, I)[1] > 1e-12]
    P = orient(P, cfg.get("source_forward", "-x"))
    lo, hi = P.min(0), P.max(0)
    L = cfg["length_m"]
    scale = L / (hi[2] - lo[2])
    # Centre on the main body, not on stray antennas: use the bulk of the vertices.
    core = np.percentile(P, [5, 95], axis=0)
    centre = np.array([(lo[0] + hi[0]) / 2, (core[0][1] + core[1][1]) / 2, (lo[2] + hi[2]) / 2])
    P = (P - centre) * scale

    labels = islands(P, I)
    count = labels.max() + 1
    info = []
    for k in range(count):
        tri = labels == k
        verts = P[np.unique(I[tri])]
        info.append({"min": verts.min(0), "max": verts.max(0), "center": verts.mean(0), "tris": int(tri.sum())})

    # Engines: big round pieces whose back face sits at the stern.
    zmax = P[:, 2].max()
    bells = []
    for k in range(count):
        size = info[k]["max"] - info[k]["min"]
        if info[k]["max"][2] > zmax - 0.004 * L and min(size[0], size[1]) > 0.03 * L and abs(size[0] - size[1]) < 0.35 * max(size[0], size[1]):
            bells.append(k)
    bells.sort(key=lambda k: (round(info[k]["center"][1] / (0.05 * L)), info[k]["center"][0]))
    engines = []
    part_of = np.full(count, "", dtype=object)
    for n, k in enumerate(bells):
        size = info[k]["max"] - info[k]["min"]
        c = info[k]["center"]
        engines.append({"node": f"engine_{n}", "pos": [round(float(c[0]), 2), round(float(c[1]), 2), round(float(info[k]["max"][2]), 2)],
                        "radius": round(float(min(size[0], size[1]) * 0.5 * 0.82), 2)})
        part_of[k] = f"engine_{n}"

    # Hull sections: cut along the length at the configured fractions.
    cuts = sorted(cfg.get("section_cuts", []))
    for k in range(count):
        if part_of[k]:
            continue
        z = info[k]["center"][2] / L
        part_of[k] = f"section_{int(np.searchsorted(cuts, z))}"

    # Per-piece material masks: R = team paint, G = glow, B = dark metal, A = window density.
    masks = np.zeros((count, 4))
    big = np.percentile([i["tris"] for i in info], 70)
    for k in range(count):
        size = info[k]["max"] - info[k]["min"]
        if part_of[k].startswith("engine"):
            masks[k] = [0.0, 0.0, 0.85, 0.0]
        elif info[k]["tris"] < 30 or max(size) < 0.012 * L:
            masks[k] = [0.0, 0.0, 0.75, 0.0]  # greebles, antennas, pipes
        else:
            paint = 1.0 if rng.random() < cfg.get("paint_fraction", 0.22) else 0.0
            masks[k] = [paint, 0.0, 0.0, 1.0 if info[k]["tris"] >= big else 0.5]

    fn, area = face_normals(P, I)
    tri_part = part_of[labels]
    parts = []
    for name in sorted(set(tri_part), key=lambda s: (s.split("_")[0], int(s.split("_")[1]))):
        sel = tri_part == name
        sub = I[sel]
        used, local = np.unique(sub, return_inverse=True)
        pos, nrm, idx = split_normals(P[used], local.reshape(-1, 3), cfg.get("crease_deg", 38.0))
        # Colour per vertex from the piece it came from.
        owner = np.zeros(len(used), dtype=np.int64)
        owner[local.reshape(-1, 3).ravel()] = np.repeat(labels[sel], 3)
        corner_owner = np.zeros(len(pos), dtype=np.int64)
        corner_owner[idx.ravel()] = owner[local.reshape(-1, 3).ravel()]
        col = masks[corner_owner].copy()
        if name.startswith("engine_"):
            e = engines[int(name.split("_")[1])]
            ep = np.array(e["pos"])
            inside = (pos[:, 2] > ep[2] - 0.9 * e["radius"]) & (np.hypot(pos[:, 0] - ep[0], pos[:, 1] - ep[1]) < 0.92 * e["radius"])
            col[inside, 1] = 1.0
        parts.append((name, pos, nrm, col, idx))

    # Hardpoints snapped onto the hull with ray casts from outside.
    ext = np.abs(P).max(0)
    hardpoints = []
    for h in cfg["hardpoints"]:
        face = FACES[h["face"]]
        u = h["u"] * L  # along the length (z)
        if h["face"] in ("top", "bottom"):
            origin = np.array([h.get("v", 0.0) * ext[0] * 2, face[1] * ext[1] * 3, u])
        else:
            origin = np.array([face[0] * ext[0] * 3, h.get("v", 0.0) * ext[1] * 2, u])
        hit = raycast(P, I, origin, -face)
        if hit is None:
            print(f"  ! no hull under hardpoint {h}")
            continue
        p, n, _ = hit
        # Mount on the face's axis so turrets sit upright on sloped plating.
        up = (n * 0.35 + face * 0.65)
        up /= np.linalg.norm(up)
        hardpoints.append({"kind": h["kind"], "pos": [round(float(x), 2) for x in p], "up": [round(float(x), 3) for x in up]})

    # Surface samples (area weighted, outward facing) for fires and blasts.
    outward = (fn * (P[I].mean(1) - np.array([0, 0, 0]))).sum(1) > 0
    w = area * outward
    w = w / w.sum()
    picks = rng.choice(len(I), size=cfg.get("surface_points", 90), replace=False, p=w)
    surface = []
    for t in picks:
        a, b = rng.random(2)
        if a + b > 1:
            a, b = 1 - a, 1 - b
        tri = P[I[t]]
        p = tri[0] + (tri[1] - tri[0]) * a + (tri[2] - tri[0]) * b
        surface.append([round(float(x), 1) for x in p] + [round(float(x), 2) for x in fn[t]])

    # Running lights on the extremities: nose, tail, keel, tower tip, flanks.
    lights = []
    for axis, sgn in [(2, -1), (2, 1), (1, 1), (1, -1), (0, -1), (0, 1)]:
        k = (P[:, axis] * sgn).argmax()
        lights.append([round(float(x), 1) for x in P[k]])

    out_dir = ROOT / "assets" / "ships" / ship_id
    out_dir.mkdir(parents=True, exist_ok=True)
    write_glb(out_dir / f"{ship_id}.glb", ship_id, parts)
    spec = {
        "id": ship_id,
        "length": round(float(P[:, 2].max() - P[:, 2].min()), 1),
        "bounds_min": [round(float(x), 1) for x in P.min(0)],
        "bounds_max": [round(float(x), 1) for x in P.max(0)],
        "sections": [p[0] for p in parts if p[0].startswith("section_")],
        "section_cuts": [round(c * L, 1) for c in cuts],
        "engines": engines,
        "hardpoints": hardpoints,
        "surface": surface,
        "lights": lights,
    }
    (out_dir / f"{ship_id}.capital.json").write_text(json.dumps(spec, indent=1) + "\n")
    print(f"{ship_id}: {len(I)} tris, {count} pieces, scale {scale:.2f}, bounds {spec['bounds_min']} .. {spec['bounds_max']}")
    for name, pos, _, _, idx in parts:
        print(f"  {name:12s} {len(idx):6d} tris")
    print(f"  {len(engines)} engines, {len(hardpoints)} hardpoints, {len(surface)} surface points")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
