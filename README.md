# Star Battles

10 v 10 starfighter combat high above Europa, in the shadow of Jupiter. Capture the three relay
stations or out-gun the enemy fleet; AI wingmen fill every empty seat.

**Download:** grab the latest APK (Android) or EXE (Windows) from
[Releases](https://github.com/jpcpais01/StarBattles/releases/latest). The game
also updates itself from inside the menu.

- Godot 4.7, GDScript, Mobile (Vulkan) renderer
- Online multiplayer (LAN discovery, public battle list, direct IP)
- Firebase accounts and cloud saves — see [docs/FIREBASE.md](docs/FIREBASE.md)
- Ship model pipeline — see [docs/SHIP_PIPELINE.md](docs/SHIP_PIPELINE.md)

### Controls

Keyboard & mouse: mouse steers, W/S throttle, A/D roll, Q/E strafe, Shift boost,
left click fire, right click missiles, F next target, C look back, Tab scores.
Gamepad and touch are supported too.

### Hosting

Host from the Multiplayer page. For internet play forward UDP port 24850. A
dedicated server runs with `StarBattles.exe --headless -- --server`.
