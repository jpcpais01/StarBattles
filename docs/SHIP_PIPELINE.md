# Ship pipeline

Ships are defined in `game/data/ship_library.gd`. Each entry lists flight stats,
**hardpoints** (where a separate, animated weapon model is mounted) and
**engines** (where the plume, glow and ion-trail VFX attach). Until real models
arrive, hulls are built procedurally by `game/procgen/hull_builder.gd`.

## Swapping in a Meshy model

1. Put the model at `assets/ships/<id>/<id>.glb`.
2. Set `"model": "res://assets/ships/<id>/<id>.glb"` on the ship entry.
3. Add `assets/ships/<id>/<id>.ship.json` next to it:

```json
{
  "radius": 7.5,
  "hardpoints": [
    {
      "pos": [-5.3, -0.2, -0.6],
      "weapon": "pulse_cannon",
      "gimbal": 7.0,
      "turret": false,
      "base_node": "GunL_Base",
      "barrel_node": "GunL_Barrel",
      "muzzles": [[-5.3, -0.2, -3.4]]
    }
  ],
  "engines": [ { "pos": [-1.2, 0.0, 6.1], "radius": 0.7 } ]
}
```

Coordinates are in the model's local space: forward is **-Z**, up is **+Y**,
1 unit = 1 metre. `base_node` / `barrel_node` are node names inside the GLB;
they are detached from the hull and re-parented under the weapon mount so they
yaw/pitch toward the aim point and recoil when firing. Without them the
procedural weapon models from `game/procgen/weapon_builder.gd` are used.
Nodes whose name starts with `canopy` get the glass material.

## Materials

Every hull part uses `shaders/hull.gdshader`: brushed metal with procedural panel
lines, grime and emissive strips. It is driven by vertex colour masks
(R = team paint, G = emissive, B = dark trim, A = engine heat) and can take an
optional low-res colour mask texture (`color_mask`) baked from Meshy's textured
export. Meshy's own 8k textures are not used (too soft up close).

## Untextured multi-piece GLBs

Meshy exports arrive as one mesh made of ~100 loose pieces.
`tools/ship_import/meshy_split.py` splits it by connected components, sorts the
pieces into hull, canopy, turret bases, barrels and engines, re-orients and
scales it to game space, writes vertex colour masks, and writes the GLB and the
`.ship.json` above. Each ship has a small config in `tools/ship_import/configs/`,
and the raw Meshy file stays in `assets_src/`. See `tools/ship_import/README.md`.
Budget: ~30k triangles per ship.
