#!/usr/bin/env python3
"""Split a Meshy ship GLB into game-ready parts.

Meshy exports a ship as one mesh with no materials, but the guns, barrels and
engine nozzles are still separate pieces of geometry (islands that share no
vertices with the hull). This tool finds those islands, groups them into
hardpoints and engines, and writes:

  assets/ships/<id>/<id>.glb        named nodes: hull, canopy, turret_N_base,
                                    turret_N_barrel, engine_N
  assets/ships/<id>/<id>.ship.json  hardpoints, muzzles and engine positions

Vertex colours carry material masks for shaders/hull.gdshader:
  R = team paint, G = emissive, B = dark metal.

Usage: python3 tools/ship_import/meshy_split.py tools/ship_import/configs/silverwing.json
"""
import json
import struct
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]


# ---------------------------------------------------------------- GLB reading

def read_glb(path):
    data = Path(path).read_bytes()
    magic, _, _ = struct.unpack("<III", data[:12])
    if magic != 0x46546C67:
        raise ValueError(f"{path} is not a GLB file")
    json_len = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + json_len])
    bin_start = 20 + json_len + 8
    blob = data[bin_start:]

    def accessor(i):
        a = gltf["accessors"][i]
        bv = gltf["bufferViews"][a["bufferView"]]
        dtype = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a["componentType"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        offset = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", 0)
        item = np.dtype(dtype).itemsize * width
        if stride and stride != item:
            raw = np.frombuffer(blob, np.uint8, stride * (a["count"] - 1) + item, offset)
            rows = [raw[k * stride:k * stride + item].view(dtype) for k in range(a["count"])]
            return np.array(rows).reshape(-1, width)
        return np.frombuffer(blob, dtype, a["count"] * width, offset).reshape(-1, width)

    positions, indices = [], []
    base = 0
    for node in gltf.get("nodes", []):
        if "mesh" not in node:
            continue
        m = np.eye(4)
        if "matrix" in node:
            m = np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
        else:
            if "scale" in node:
                m = m @ np.diag(list(node["scale"]) + [1.0])
            if "translation" in node:
                m[:3, 3] += node["translation"]
        for prim in gltf["meshes"][node["mesh"]]["primitives"]:
            p = accessor(prim["attributes"]["POSITION"]).astype(np.float64)
            p = (np.c_[p, np.ones(len(p))] @ m.T)[:, :3]
            if "indices" in prim:
                idx = accessor(prim["indices"]).reshape(-1, 3).astype(np.int64)
            else:
                idx = np.arange(len(p)).reshape(-1, 3)
            positions.append(p)
            indices.append(idx + base)
            base += len(p)
    return np.concatenate(positions), np.concatenate(indices)


# ---------------------------------------------------------------- GLB writing

def write_glb(path, root_name, parts):
    """parts: list of (name, positions, normals, colors, indices)."""
    blob = bytearray()
    views, accessors, meshes, nodes = [], [], [], []

    def add(array, target, component, kind, minmax=False):
        while len(blob) % 4:
            blob.append(0)
        raw = np.ascontiguousarray(array).tobytes()
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw), "target": target})
        blob.extend(raw)
        acc = {"bufferView": len(views) - 1, "componentType": component, "count": len(array), "type": kind}
        if minmax:
            acc["min"] = array.min(0).tolist()
            acc["max"] = array.max(0).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    for name, pos, nrm, col, idx in parts:
        attrs = {
            "POSITION": add(pos.astype(np.float32), 34962, 5126, "VEC3", True),
            "NORMAL": add(nrm.astype(np.float32), 34962, 5126, "VEC3"),
            "COLOR_0": add(col.astype(np.float32), 34962, 5126, "VEC4"),
        }
        ind = add(idx.astype(np.uint32).ravel(), 34963, 5125, "SCALAR")
        meshes.append({"name": name, "primitives": [{"attributes": attrs, "indices": ind}]})
        nodes.append({"name": name, "mesh": len(meshes) - 1})
    nodes.append({"name": root_name, "children": list(range(len(parts)))})
    while len(blob) % 4:
        blob.append(0)
    gltf = {
        "asset": {"version": "2.0", "generator": "StarBattles meshy_split.py"},
        "scene": 0,
        "scenes": [{"nodes": [len(nodes) - 1]}],
        "nodes": nodes,
        "meshes": meshes,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js
    out += struct.pack("<II", len(blob), 0x004E4942) + bytes(blob)
    Path(path).write_bytes(out)


# ---------------------------------------------------------------- geometry

def weld(P, tol=1e-5):
    _, inv = np.unique(np.round(P / tol).astype(np.int64), axis=0, return_inverse=True)
    return inv.ravel()


def islands(P, I):
    """Label each triangle with the connected piece of geometry it belongs to."""
    w = weld(P)[I]
    parent = np.arange(w.max() + 1)

    def find(x):
        r = x
        while parent[r] != r:
            r = parent[r]
        while parent[x] != r:
            parent[x], x = r, parent[x]
        return r

    for a, b, c in w:
        ra, rb, rc = find(a), find(b), find(c)
        parent[rb] = ra
        parent[find(rc)] = ra
    roots = np.array([find(x) for x in w[:, 0]])
    _, labels = np.unique(roots, return_inverse=True)
    return labels


def face_normals(P, I):
    t = P[I]
    n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    area = np.linalg.norm(n, axis=1, keepdims=True)
    return n / np.maximum(area, 1e-20), area[:, 0]


def split_normals(P, I, crease_deg=40.0):
    """Unweld corners and give each one a normal smoothed only across soft edges,
    so panel edges stay crisp while curved parts stay smooth."""
    fn, area = face_normals(P, I)
    w = weld(P)[I]
    cos_limit = np.cos(np.radians(crease_deg))
    incident = {}
    for f, tri in enumerate(w):
        for v in tri:
            incident.setdefault(v, []).append(f)
    corners = I.ravel()
    normals = np.zeros((len(corners), 3))
    for k, (f, v) in enumerate(zip(np.repeat(np.arange(len(I)), 3), w.ravel())):
        faces = incident[v]
        n = fn[faces]
        keep = n @ fn[f] >= cos_limit
        s = (n[keep] * area[faces][keep, None]).sum(0)
        normals[k] = s / max(np.linalg.norm(s), 1e-20)
    return P[corners], normals, np.arange(len(corners)).reshape(-1, 3)


def cluster(boxes, gap):
    """Group islands whose bounding boxes come within `gap` of each other."""
    n = len(boxes)
    parent = list(range(n))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for a in range(n):
        for b in range(a + 1, n):
            lo = np.maximum(boxes[a][0], boxes[b][0])
            hi = np.minimum(boxes[a][1], boxes[b][1])
            if np.all(lo - hi <= gap):
                parent[find(b)] = find(a)
    groups = {}
    for k in range(n):
        groups.setdefault(find(k), []).append(k)
    return list(groups.values())


# ---------------------------------------------------------------- main

def main(config_path):
    cfg = json.loads(Path(config_path).read_text())
    ship_id = cfg["id"]
    P, I = read_glb(ROOT / cfg["source"])
    # Meshy leaves some zero-area triangles; they have no normal and render nothing.
    I = I[face_normals(P, I)[1] > 1e-12]

    # Re-orient into game space: metres, forward -Z, up +Y, centred.
    fwd = cfg.get("source_forward", "-x")
    sign = -1.0 if fwd[0] == "-" else 1.0
    axis = "xyz".index(fwd[1])
    if axis == 0:   # rotate about Y so the source forward axis becomes -Z
        P = np.c_[sign * P[:, 2], P[:, 1], -sign * P[:, 0]]
    elif axis == 2:
        P = np.c_[P[:, 0] * -sign, P[:, 1], P[:, 2] * -sign]
    lo, hi = P.min(0), P.max(0)
    scale = cfg["length_m"] / (hi[2] - lo[2])
    P = (P - (lo + hi) / 2) * scale

    labels = islands(P, I)
    count = labels.max() + 1
    hull_id = np.bincount(labels).argmax()
    info = []
    for k in range(count):
        verts = P[np.unique(I[labels == k])]
        c = verts.mean(0)
        ev, evec = np.linalg.eigh(np.cov((verts - c).T)) if len(verts) > 3 else (np.ones(3), np.eye(3))
        info.append({
            "min": verts.min(0), "max": verts.max(0), "center": c,
            "elong": float(np.sqrt(ev[2] / max(ev[1], 1e-12))),
            "axis": evec[:, 2], "tris": int((labels == k).sum()),
        })
    L = cfg["length_m"]

    # Barrels: long thin cylinders pointing along the ship's forward axis.
    def is_barrel(i):
        size = info[i]["max"] - info[i]["min"]
        return (abs(info[i]["axis"][2]) > 0.97 and info[i]["elong"] > 2.5
                and max(size[0], size[1]) < 0.02 * L and size[2] > 0.015 * L)

    # Engine glow plates: flat discs facing backwards, in the rear part of the ship.
    def is_exhaust(i):
        size = info[i]["max"] - info[i]["min"]
        return (size[2] < 0.004 * L and min(size[0], size[1]) > 0.02 * L
                and info[i]["center"][2] > 0.3 * L)

    others = [k for k in range(count) if k != hull_id]
    groups = cluster([(info[k]["min"], info[k]["max"]) for k in others], cfg.get("cluster_gap", 0.01) * L)
    groups = [[others[g] for g in grp] for grp in groups]

    part_of = np.full(count, "hull", dtype=object)
    hardpoints, engines = [], []
    weapons = cfg.get("weapons", [])

    gun_groups = [g for g in groups if sum(is_barrel(k) for k in g) >= 1 and np.mean([info[k]["center"][2] for k in g]) < 0.3 * L]
    gun_groups.sort(key=lambda g: (np.mean([info[k]["center"][0] for k in g])))
    for n, g in enumerate(gun_groups):
        barrels = [k for k in g if is_barrel(k)]
        # Everything lying on a barrel's line in front of the mount moves with the barrels.
        base_min = min(info[k]["min"][2] for k in g if k not in barrels and info[k]["tris"] > 0.3 * max(info[j]["tris"] for j in g))
        tips = []
        for b in barrels:
            tips.append(info[b]["min"][2])
        barrel_set = set(barrels)
        for k in g:
            c = info[k]["center"]
            on_line = any(np.hypot(*(c[:2] - info[b]["center"][:2])) < 0.01 * L for b in barrels)
            if on_line and c[2] < base_min + 0.005 * L:
                barrel_set.add(k)
        bases = [k for k in g if k not in barrel_set]
        for k in bases:
            part_of[k] = f"turret_{n}_base"
        for k in barrel_set:
            part_of[k] = f"turret_{n}_barrel"
        bmin = np.min([info[k]["min"] for k in bases], 0)
        bmax = np.max([info[k]["max"] for k in bases], 0)
        pivot = (bmin + bmax) / 2
        muzzles = []
        for b in barrels:
            front = [info[k] for k in barrel_set if np.hypot(*(info[k]["center"][:2] - info[b]["center"][:2])) < 0.01 * L]
            z = min(f["min"][2] for f in front)
            muzzles.append([float(info[b]["center"][0]), float(info[b]["center"][1]), float(z)])
        # Muzzles of a twin gun often sit on the same line; keep one per line.
        uniq = []
        for m in sorted(muzzles, key=lambda m: m[2]):
            if all(np.hypot(m[0] - u[0], m[1] - u[1]) > 0.004 * L for u in uniq):
                uniq.append(m)
        w = weapons[n] if n < len(weapons) else cfg.get("default_weapon", {})
        hardpoints.append({
            "name": f"turret_{n}",
            "pos": [round(float(v), 4) for v in pivot],
            "base_node": f"turret_{n}_base",
            "barrel_node": f"turret_{n}_barrel",
            "muzzle": [round(v, 4) for v in np.mean(uniq, 0)],
            "muzzles": [[round(v, 4) for v in m] for m in uniq],
            "weapon": w.get("weapon", "pulse_cannon"),
            "gimbal": w.get("gimbal", 8.0),
            "turret": w.get("turret", False),
        })

    engine_islands = [k for g in groups if g not in gun_groups for k in g if info[k]["center"][2] > 0.25 * L]
    plates = sorted([k for k in engine_islands if is_exhaust(k)], key=lambda k: info[k]["center"][0])
    for n, p in enumerate(plates):
        size = info[p]["max"] - info[p]["min"]
        engines.append({
            "node": f"engine_{n}",
            "pos": [round(float(v), 4) for v in info[p]["center"]],
            "radius": round(float(min(size[0], size[1]) / 2), 4),
        })
    for k in engine_islands:
        if plates:
            d = [np.hypot(*(info[k]["center"][:2] - info[p]["center"][:2])) for p in plates]
            if min(d) < 4.0 * engines[int(np.argmin(d))]["radius"]:
                part_of[k] = f"engine_{int(np.argmin(d))}"
    # Exhaust leaves at the back edge of each nozzle, not at the glow plate inside it.
    for n, e in enumerate(engines):
        mine = [k for k in range(count) if part_of[k] == e["node"]]
        e["pos"][2] = round(float(max(info[k]["max"][2] for k in mine)), 4)

    # Canopy: hull faces inside the configured box that face mostly upwards.
    fn, _ = face_normals(P, I)
    tri_part = part_of[labels].astype(object)
    canopy = cfg.get("canopy")
    if canopy:
        cen = P[I].mean(1)
        box_lo = np.array(canopy["min"]) * L
        box_hi = np.array(canopy["max"]) * L
        inside = np.all((cen >= box_lo) & (cen <= box_hi), axis=1) & (fn[:, 1] > canopy.get("min_up", 0.35))
        tri_part[(labels == hull_id) & inside] = "canopy"

    # Material masks.
    masks = cfg.get("masks", {})
    order = ["hull", "canopy"] + [h["base_node"] for h in hardpoints] + [h["barrel_node"] for h in hardpoints] + [e["node"] for e in engines]
    parts = []
    for name in order:
        sel = tri_part == name
        if not sel.any():
            continue
        sub = I[sel]
        used, local = np.unique(sub, return_inverse=True)
        pos, nrm, idx = split_normals(P[used], local.reshape(-1, 3), cfg.get("crease_deg", 40.0))
        kind = name.split("_")[2] if name.startswith("turret_") else name.split("_")[0]
        col = np.tile(np.array(masks.get(kind, [0, 0, 0, 1]), dtype=np.float64), (len(pos), 1))
        if name.startswith("engine_"):
            # Light the exhaust plates and the inside of the nozzles.
            e = engines[int(name.split("_")[1])]
            ep = np.array(e["pos"])
            behind = pos[:, 2] > ep[2] - 0.6 * e["radius"]
            near = np.hypot(pos[:, 0] - ep[0], pos[:, 1] - ep[1]) < 0.85 * e["radius"]
            col[behind & near, 1] = 1.0
        parts.append((name, pos, nrm, col, idx))

    out_dir = ROOT / "assets" / "ships" / ship_id
    out_dir.mkdir(parents=True, exist_ok=True)
    write_glb(out_dir / f"{ship_id}.glb", ship_id, parts)
    hull_nodes = ["hull"] + (["canopy"] if any(p[0] == "canopy" for p in parts) else [])
    radius = float(np.linalg.norm(P, axis=1).max())
    ship = {
        "id": ship_id,
        "radius": round(radius, 2),
        "hull_nodes": hull_nodes,
        "hardpoints": hardpoints,
        "engines": engines,
    }
    (out_dir / f"{ship_id}.ship.json").write_text(json.dumps(ship, indent=2) + "\n")

    print(f"{ship_id}: {len(I)} tris, {count} islands, scale {scale:.2f}")
    for name, pos, _, _, idx in parts:
        print(f"  {name:18s} {len(idx):6d} tris")
    print(f"  {len(hardpoints)} hardpoints, {len(engines)} engines, radius {radius:.2f} m")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
