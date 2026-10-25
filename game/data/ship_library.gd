class_name ShipLibrary
## Ship and weapon definitions. Ships list hardpoints (where a separate,
## animated weapon model is mounted) and engine nozzles (where engine VFX
## attach). Placeholder hulls come from HullBuilder; a Meshy model can
## replace one by setting "model" — see docs/SHIP_PIPELINE.md.

const SHIPS := {
	"vanguard": {
		"name": "VANGUARD",
		"role": "Multirole Fighter",
		"desc": "Dependable twin-cannon fighter with a belly missile pod. Holds its own anywhere.",
		"builder": "vanguard",
		"model": "",
		"hull": 1000.0, "shield": 500.0, "shield_regen": 55.0, "shield_delay": 3.2,
		"speed": 115.0, "boost_speed": 225.0, "min_speed": 25.0, "accel": 1.6,
		"pitch_rate": 1.55, "yaw_rate": 1.15, "roll_rate": 2.6, "agility": 4.5,
		"boost_energy": 100.0, "boost_drain": 30.0, "boost_regen": 16.0,
		"radius": 7.0, "camera_dist": 22.0, "camera_height": 5.5,
		"engine_color": Color(0.35, 0.75, 1.0),
		"stats": {"speed": 0.62, "armor": 0.6, "agility": 0.62, "firepower": 0.65},
		"hardpoints": [
			{"pos": Vector3(-5.35, -0.15, -0.6), "weapon": "pulse_cannon", "gimbal": 7.0, "scale": 1.0},
			{"pos": Vector3(5.35, -0.15, -0.6), "weapon": "pulse_cannon", "gimbal": 7.0, "scale": 1.0},
			{"pos": Vector3(0.0, -1.25, -0.4), "weapon": "missile_pod", "gimbal": 0.0, "scale": 1.0},
		],
		"engines": [
			{"pos": Vector3(-1.25, 0.05, 6.15), "radius": 0.72},
			{"pos": Vector3(1.25, 0.05, 6.15), "radius": 0.72},
		],
	},
	"wraith": {
		"name": "WRAITH",
		"role": "Interceptor",
		"desc": "A blade of a ship. Twin beam lasers, a seeker pod and a monstrous reactor — fast, nimble, fragile.",
		"builder": "wraith",
		"model": "",
		"hull": 700.0, "shield": 450.0, "shield_regen": 70.0, "shield_delay": 2.6,
		"speed": 140.0, "boost_speed": 270.0, "min_speed": 35.0, "accel": 2.1,
		"pitch_rate": 1.95, "yaw_rate": 1.45, "roll_rate": 3.4, "agility": 6.0,
		"boost_energy": 110.0, "boost_drain": 26.0, "boost_regen": 20.0,
		"radius": 6.0, "camera_dist": 19.0, "camera_height": 4.5,
		"engine_color": Color(0.72, 0.45, 1.0),
		"stats": {"speed": 0.9, "armor": 0.35, "agility": 0.92, "firepower": 0.55},
		"hardpoints": [
			{"pos": Vector3(-0.95, -0.55, -3.4), "weapon": "laser", "gimbal": 5.0, "scale": 0.9},
			{"pos": Vector3(0.95, -0.55, -3.4), "weapon": "laser", "gimbal": 5.0, "scale": 0.9},
			{"pos": Vector3(0.0, -0.62, 1.0), "weapon": "missile_pod", "gimbal": 0.0, "scale": 0.8},
		],
		"engines": [
			{"pos": Vector3(0.0, 0.1, 5.6), "radius": 1.05},
			{"pos": Vector3(-1.55, -0.05, 4.7), "radius": 0.42},
			{"pos": Vector3(1.55, -0.05, 4.7), "radius": 0.42},
		],
	},
	"bastion": {
		"name": "BASTION",
		"role": "Heavy Gunship",
		"desc": "Armoured brawler with a dorsal railgun turret, heavy cannons and dual missile racks.",
		"builder": "bastion",
		"model": "",
		"hull": 1700.0, "shield": 750.0, "shield_regen": 45.0, "shield_delay": 4.0,
		"speed": 92.0, "boost_speed": 175.0, "min_speed": 15.0, "accel": 1.2,
		"pitch_rate": 1.05, "yaw_rate": 0.85, "roll_rate": 1.7, "agility": 3.2,
		"boost_energy": 90.0, "boost_drain": 32.0, "boost_regen": 14.0,
		"radius": 10.0, "camera_dist": 30.0, "camera_height": 8.0,
		"engine_color": Color(1.0, 0.62, 0.3),
		"stats": {"speed": 0.38, "armor": 0.95, "agility": 0.3, "firepower": 0.95},
		"hardpoints": [
			{"pos": Vector3(0.0, 2.05, -1.6), "weapon": "railgun", "gimbal": 28.0, "scale": 1.15, "turret": true},
			{"pos": Vector3(-4.6, -0.4, -3.2), "weapon": "pulse_cannon", "gimbal": 9.0, "scale": 1.25},
			{"pos": Vector3(4.6, -0.4, -3.2), "weapon": "pulse_cannon", "gimbal": 9.0, "scale": 1.25},
			{"pos": Vector3(-6.4, 0.3, 1.2), "weapon": "missile_pod", "gimbal": 0.0, "scale": 1.1},
			{"pos": Vector3(6.4, 0.3, 1.2), "weapon": "missile_pod", "gimbal": 0.0, "scale": 1.1},
		],
		"engines": [
			{"pos": Vector3(-2.6, 0.6, 8.7), "radius": 0.95},
			{"pos": Vector3(2.6, 0.6, 8.7), "radius": 0.95},
			{"pos": Vector3(-2.6, -1.3, 8.7), "radius": 0.95},
			{"pos": Vector3(2.6, -1.3, 8.7), "radius": 0.95},
		],
	},
	"silverwing": {
		"name": "SILVERWING",
		"role": "Strike Fighter",
		"desc": "Swept-wing striker with twin-barrel cannons on each wingtip and a belly seeker pod. Wide, stable gun platform with a triple-nozzle drive.",
		"builder": "vanguard",
		"model": "res://assets/ships/silverwing/silverwing.glb",
		"hull": 900.0, "shield": 520.0, "shield_regen": 60.0, "shield_delay": 3.0,
		"speed": 125.0, "boost_speed": 245.0, "min_speed": 30.0, "accel": 1.8,
		"pitch_rate": 1.7, "yaw_rate": 1.25, "roll_rate": 2.9, "agility": 5.2,
		"boost_energy": 105.0, "boost_drain": 28.0, "boost_regen": 18.0,
		"radius": 8.4, "camera_dist": 24.0, "camera_height": 5.5,
		"engine_color": Color(0.4, 0.82, 1.0),
		"stats": {"speed": 0.74, "armor": 0.5, "agility": 0.72, "firepower": 0.7},
		## Hardpoints and engines come from silverwing.ship.json (made by
		## tools/ship_import); these are only used if the model is missing.
		"hardpoints": [
			{"pos": Vector3(-7.49, -0.41, 1.65), "weapon": "pulse_cannon", "gimbal": 8.0, "scale": 1.0},
			{"pos": Vector3(7.5, -0.41, 1.7), "weapon": "pulse_cannon", "gimbal": 8.0, "scale": 1.0},
			{"pos": Vector3(0.0, -0.82, 0.3), "weapon": "missile_pod", "gimbal": 0.0, "scale": 0.95},
		],
		"engines": [
			{"pos": Vector3(-1.37, 0.1, 7.93), "radius": 0.33},
			{"pos": Vector3(0.03, 0.24, 7.64), "radius": 0.32},
			{"pos": Vector3(1.41, 0.1, 7.93), "radius": 0.32},
		],
	},
}

const SHIP_ORDER := ["vanguard", "silverwing", "wraith", "bastion"]

## type: projectile | beam | rail | missile.
## group: 0 = primary trigger, 1 = secondary trigger.
const WEAPONS := {
	"pulse_cannon": {
		"name": "Pulse Cannon", "type": "projectile", "group": 0, "model": "cannon",
		"rof": 7.0, "damage": 22.0, "speed": 1050.0, "range": 1250.0, "spread": 0.18,
		"heat": 0.055, "cool": 0.42, "vs_shield": 0.9, "vs_hull": 1.15,
		"color": Color(0.45, 0.85, 1.0), "sound": "pulse",
	},
	"laser": {
		"name": "Beam Laser", "type": "beam", "group": 0, "model": "laser",
		"dps": 105.0, "range": 850.0, "heat_rate": 0.26, "cool": 0.38,
		"vs_shield": 1.35, "vs_hull": 0.85,
		"color": Color(1.0, 0.35, 0.85), "sound": "beam",
	},
	"railgun": {
		"name": "Railgun", "type": "rail", "group": 0, "model": "railgun",
		"charge": 0.75, "reload": 2.4, "damage": 210.0, "range": 2400.0,
		"heat": 0.0, "cool": 1.0, "vs_shield": 0.8, "vs_hull": 1.3,
		"color": Color(0.6, 0.95, 1.0), "sound": "rail",
	},
	"missile_pod": {
		"name": "Seeker Missiles", "type": "missile", "group": 1, "model": "missile_pod",
		"reload": 6.0, "salvo": 2, "damage": 165.0, "splash": 28.0, "speed": 300.0,
		"turn": 2.6, "lock_time": 1.1, "lock_range": 1300.0, "lock_cone": 14.0, "life": 7.0,
		"vs_shield": 0.85, "vs_hull": 1.2,
		"color": Color(1.0, 0.6, 0.3), "sound": "missile",
	},
	# Mothership batteries (Siege). Not mountable on fighters.
	"capital_flak": {
		"name": "Flak Battery", "type": "projectile", "group": 0, "model": "cannon",
		"damage": 18.0, "speed": 1150.0, "range": 1750.0, "spread": 0.7, "size": 1.7,
		"vs_shield": 1.0, "vs_hull": 1.0,
		"color": Color(0.55, 0.88, 1.0), "sound": "flak",
	},
	"capital_cannon": {
		"name": "Heavy Cannon", "type": "projectile", "group": 0, "model": "cannon",
		"damage": 130.0, "speed": 760.0, "range": 2800.0, "spread": 0.2, "size": 4.0,
		"vs_shield": 1.1, "vs_hull": 1.0,
		"color": Color(0.4, 0.7, 1.0), "sound": "cannon",
	},
}


static func ship(id: String) -> Dictionary:
	return SHIPS.get(id, SHIPS.vanguard)


static func weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, WEAPONS.pulse_cannon)


static func primary_projectile_speed(ship_id: String) -> float:
	for hp in ship(ship_id).hardpoints:
		var w := weapon(hp.weapon)
		if w.type == "projectile":
			return w.speed
	return 0.0
