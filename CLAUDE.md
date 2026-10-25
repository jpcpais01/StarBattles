# Star Battles — notes for contributors

Godot 4.7 (GDScript only), Mobile renderer (Vulkan), Jolt physics. Android is the
main target; every build also ships a single-file Windows .exe.

## Layout

- `autoload/` — global services: `App` (scene routing, palette, build info),
  `Settings`, `Sfx` (all audio is synthesised at boot), `Firebase` (REST auth +
  Firestore), `Profile`, `Net` (ENet sessions, LAN + Firestore lobby list),
  `Updater` (GitHub releases → in-game download/install).
- `game/` — the battle: `arena.gd` builds the scene; `match_controller.gd` owns
  rules, bots, respawns and netcode; `ship.gd`, `weapon_mount.gd`,
  `engine_fx.gd`, `asteroid_field.gd`, `projectiles.gd`; `procgen/` builds
  placeholder hulls, weapons and asteroids; `env/space_env.gd` is Saturn + sky.
  `siege/` is Mothership Siege: `siege_rules.gd` (stages, tickets, turret AI,
  server-authoritative damage), `mothership.gd` (the carrier and its set
  pieces) and `mothership_part.gd` (turrets, shield generators, reactor).
- `ui/` — `kit/` shared widgets and theme, `boot/` loading screen, `menu/` home
  screen and pages, `hud/` in-battle HUD.
- `shaders/` — all materials are custom shaders (no textures).

## Netcode in one paragraph

Each ship's owner simulates its own flight (bots are owned by the server) and
streams 40-byte snapshots; others interpolate 100 ms in the past. The server is
authoritative for damage, kills, captures, respawns and asteroid fractures.
Projectiles are simulated on every peer for visuals; only the server applies
hits. Asteroid motion is a pure function of match time.

## Rules

- **Patch notes:** every merge to main adds a player-facing entry to
  `data/patch_notes.json`. Entries are grouped by the hour they shipped
  (`"time": "YYYY-MM-DD · HH:00 UTC"`), newest group first, at most 5 entries
  per group. Write for players, not developers.
- Releases are cut by CI on every push to main (`.github/workflows/build.yml`),
  version `0.1.<run number>`.
- Keep the arena under ~100k environment triangles and ships ~30k.
- Don't run render/perf benchmarks in CI containers; logic checks are fine:
  `godot --headless --script tools/check_scripts.gd` and
  `godot --headless -- --autotest=20` (boots, plays a bot match, prints a report).
  Add `--mode=siege` (and `--team=0` to defend) for a siege match, and
  `--fixed-fps 60` before `--` to run a long match faster than real time.
  Add `--join=127.0.0.1` with a `--server` instance running to test netcode.
- `--server` on the command line runs a dedicated, headless host.
