# Ship import (Meshy to game)

Meshy exports a ship as one mesh, but its guns, barrels and engine nozzles are
still separate pieces of geometry. `meshy_split.py` finds those pieces and
turns them into named nodes the game can animate.

```
python3 tools/ship_import/meshy_split.py tools/ship_import/configs/<id>.json
```

Needs Python 3 and numpy. Output:

- `assets/ships/<id>/<id>.glb`: nodes `hull`, `canopy`, `turret_N_base`,
  `turret_N_barrel` and `engine_N`, in metres, facing -Z with +Y up and
  centred on the origin.
- `assets/ships/<id>/<id>.ship.json`: hardpoint pivots, muzzles (`muzzle` is
  the average, and `muzzles` has one entry per barrel for twin guns), the
  weapon for each hardpoint, and engine exhaust points.

## How parts are found

| Part | Rule |
|---|---|
| Hull | the largest connected piece |
| Barrel | a long, thin cylinder pointing forward, plus anything on its line in front of the mount (muzzle, breech, bracket) |
| Turret base | everything else in the same cluster as a barrel |
| Engine | flat discs facing backwards in the rear part of the ship (the exhaust plates), plus nearby nozzle parts |
| Canopy | upward-facing hull triangles inside the config's `canopy` box (fractions of ship length) |

## Config

| Key | Meaning |
|---|---|
| `source` | raw Meshy GLB, kept in `assets_src/` (Godot ignores that folder) |
| `source_forward` | which way the nose points in the raw file, for example `-x` |
| `length_m` | ship length in metres |
| `weapons` | weapon, gimbal and turret settings per hardpoint, ordered from left to right |
| `canopy` | box (fractions of length, in game axes) where the cockpit glass sits |
| `masks` | vertex colour per part kind: R = team paint, G = glow, B = dark metal |

Engine nozzle interiors and exhaust plates get G = 1 automatically, so they
glow with the engine.
