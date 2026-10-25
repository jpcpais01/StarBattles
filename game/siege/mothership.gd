class_name Mothership
extends Node3D
## The IRON VANGUARD: a 1.5 km carrier built from the imported Meshy model
## (see tools/ship_import/capital_split.py). Owns the hull sections and
## their colliders, engines, running lights, the shield bubble and every
## destructible part, plus all of its set pieces: breach fires, the shield
## collapse, the reactor reveal, the break-up and the warp-out.
## Purely presentational and physical; the rules live in SiegeRules.

const MODEL := "res://assets/ships/iron_vanguard/iron_vanguard.glb"
const SPEC := "res://assets/ships/iron_vanguard/iron_vanguard.capital.json"
const DISPLAY_NAME := "IRON VANGUARD"
## Physics layer used only by the hull, so probes can ignore everything else.
const HULL_LAYER := 4

const SH_HULL := preload("res://shaders/capital_hull.gdshader")
const SH_SHIELD := preload("res://shaders/capital_shield.gdshader")

var arena: Arena
var team := 0
var spec: Dictionary = {}
var hull_mat: ShaderMaterial
var sections: Array[Node3D] = []
var section_meshes: Array[MeshInstance3D] = []
var bodies: Array[StaticBody3D] = []
var parts: Array[MothershipPart] = []
var engines: Array[EngineFX] = []
var surface: Array = []  # [local pos, local normal]
var half_extents := Vector3(250, 360, 760)
var shield_mi: MeshInstance3D
var shield_mat: ShaderMaterial
var shield_up := true
var destroyed := false
var warped := false

var _blinkers: Array = []  # [mesh, phase, period]
var _fires: Array[Node3D] = []
var _hit_slot := 0
var _hits := PackedVector4Array()
var _t := 0.0
var _engine_power := 1.0
var _breakup: Array = []  # [section, velocity, spin]
var _sphere := SphereShape3D.new()
var _shape_q := PhysicsShapeQueryParameters3D.new()
var _ray_q := PhysicsRayQueryParameters3D.new()
var _secondary_t := 3.0
var _damage := 0.0


func setup(a: Arena, t: int, xform: Transform3D) -> void:
	arena = a
	team = t
	name = "Mothership"
	global_transform = xform
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	spec = parsed if parsed is Dictionary else {}
	var bmin := _v3(spec.get("bounds_min", [-250, -350, -750]))
	var bmax := _v3(spec.get("bounds_max", [250, 350, 750]))
	half_extents = (bmax - bmin) * 0.5
	for s in spec.get("surface", []):
		surface.append([Vector3(s[0], s[1], s[2]), Vector3(s[3], s[4], s[5])])
	hull_mat = ShaderMaterial.new()
	hull_mat.shader = SH_HULL
	hull_mat.set_shader_parameter("paint_color", App.team_color(t) * Color(0.82, 0.82, 0.82))
	hull_mat.set_shader_parameter("glow_color", App.team_color(t).lerp(Color.WHITE, 0.25))
	_build_hull()
	_build_engines()
	_build_parts()
	if not App.is_dedicated:
		_build_lights()
		_build_shield()
	_sphere.radius = 8.0
	_shape_q.shape = _sphere
	_shape_q.collision_mask = HULL_LAYER
	_shape_q.collide_with_areas = false
	_ray_q.collision_mask = HULL_LAYER
	_ray_q.collide_with_areas = false


static func _v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _build_hull() -> void:
	var root: Node3D = (load(MODEL) as PackedScene).instantiate()
	var by_name := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		by_name[str(mi.name)] = mi
	var names: Array = spec.get("sections", [])
	for i in names.size():
		var holder := Node3D.new()
		holder.name = "Section_%d" % i
		add_child(holder)
		sections.append(holder)
		var mi: MeshInstance3D = by_name.get(names[i])
		if mi == null:
			continue
		_adopt(mi, holder)
		section_meshes.append(mi)
	# Engine bells ride with the stern section.
	for e in spec.get("engines", []):
		var mi: MeshInstance3D = by_name.get(str(e.node))
		if mi and not sections.is_empty():
			_adopt(mi, sections[sections.size() - 1])
			section_meshes.append(mi)
	root.queue_free()


func _adopt(mi: MeshInstance3D, holder: Node3D) -> void:
	mi.get_parent().remove_child(mi)
	mi.owner = null
	mi.transform = Transform3D.IDENTITY
	mi.material_override = hull_mat
	holder.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1 | HULL_LAYER
	body.collision_mask = 0
	body.set_meta("mship", true)
	body.set_meta("mteam", team)
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	body.add_child(cs)
	holder.add_child(body)
	bodies.append(body)


func _build_engines() -> void:
	if App.is_dedicated:
		return
	var col := App.team_color(team).lerp(Color.WHITE, 0.3)
	for e in spec.get("engines", []):
		var fx := EngineFX.new()
		sections[sections.size() - 1].add_child(fx)
		fx.setup(_v3(e.pos) + Vector3(0, 0, 4), float(e.radius), col, false)
		fx.thrust = 0.3
		engines.append(fx)
	var light := OmniLight3D.new()
	light.light_color = col
	light.omni_range = 520.0
	light.light_energy = 3.0
	light.position = Vector3(0, -30, half_extents.z + 120.0)
	sections[sections.size() - 1].add_child(light)


func _build_parts() -> void:
	var i := 0
	for h in spec.get("hardpoints", []):
		var p := MothershipPart.new()
		_section_for(_v3(h.pos)).add_child(p)
		p.setup(i, str(h.kind), team, _v3(h.pos), _v3(h.up), hull_mat)
		parts.append(p)
		i += 1


func _build_lights() -> void:
	# Blinking navigation beacons on the extremities and every turret.
	var spots: Array = []
	for l in spec.get("lights", []):
		spots.append(_v3(l))
	for p in parts:
		if p.is_turret():
			spots.append(p.position + p.up_local * p.radius * 0.9)
	for i in spots.size():
		var col := Color(1.0, 0.25, 0.2) if i % 3 == 0 else (Color(0.3, 1.0, 0.5) if i % 3 == 1 else Color(1, 1, 1))
		var g := MeshInstance3D.new()
		g.mesh = Mats.quad()
		g.material_override = Mats.glow(col, 4.0, 2.4)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.position = spots[i]
		g.scale = Vector3.ONE * (26.0 if i < 6 else 12.0)
		_section_for(spots[i]).add_child(g)
		_blinkers.append([g, randf() * 3.0, randf_range(1.6, 3.2)])
	# Soft floodlights so the hull reads on its shadow side.
	for z in [-0.3, 0.25]:
		var fl := OmniLight3D.new()
		fl.light_color = Color(0.75, 0.85, 1.0)
		fl.omni_range = 600.0
		fl.light_energy = 1.2
		fl.position = Vector3(0, half_extents.y * 0.9, z * half_extents.z * 2.0)
		add_child(fl)


func _build_shield() -> void:
	shield_mat = ShaderMaterial.new()
	shield_mat.shader = SH_SHIELD
	shield_mat.set_shader_parameter("color", App.team_color(team).lerp(Color(0.6, 0.9, 1.0), 0.4))
	_hits.resize(6)
	for i in 6:
		_hits[i] = Vector4(0, 0, 1, -100.0)
	shield_mat.set_shader_parameter("hits", _hits)
	shield_mi = MeshInstance3D.new()
	shield_mi.mesh = Mats.sphere(64, 32)
	shield_mi.material_override = shield_mat
	shield_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield_mi.scale = shield_scale()
	shield_mi.extra_cull_margin = 200.0
	add_child(shield_mi)


func shield_scale() -> Vector3:
	return Vector3(half_extents.x * 1.45, half_extents.y * 0.95, half_extents.z * 1.14)


func _section_for(local: Vector3) -> Node3D:
	var cuts: Array = spec.get("section_cuts", [])
	var i := 0
	while i < cuts.size() and local.z > float(cuts[i]):
		i += 1
	return sections[mini(i, sections.size() - 1)]


# --- Queries ----------------------------------------------------------------------

func center() -> Vector3:
	return global_position


## Rough "is this point anywhere near the ship" test in local space.
func near_hull(p: Vector3, margin: float) -> bool:
	var l := global_transform.affine_inverse() * p
	var e := half_extents + Vector3.ONE * margin
	return absf(l.x) < e.x and absf(l.y) < e.y and absf(l.z) < e.z


## Distance along `dir` to the hull, for avoidance. Empty if clear.
func probe(p: Vector3, dir: Vector3, length: float) -> Dictionary:
	if destroyed or not near_hull(p, length + 50.0):
		return {}
	_ray_q.from = p
	_ray_q.to = p + dir * length
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray_q)
	if hit.is_empty():
		return {}
	return {"t": p.distance_to(hit.position), "point": hit.position, "normal": hit.normal}


## Sphere vs hull: pushes ships out of the plating.
func collide_sphere(p: Vector3, r: float) -> Dictionary:
	if destroyed or not near_hull(p, r + 10.0):
		return {}
	_sphere.radius = r
	_shape_q.transform = Transform3D(Basis.IDENTITY, p)
	var info := get_world_3d().direct_space_state.get_rest_info(_shape_q)
	if info.is_empty():
		return {}
	var n: Vector3 = info.normal
	if n.length_squared() < 0.01:
		n = (p - global_position).normalized()
	var depth := r - (p - Vector3(info.point)).dot(n)
	if depth <= 0.0:
		return {}
	return {"normal": n, "depth": minf(depth, r * 2.0)}


## Closest outward surface sample to a world point (for fires and FX).
func surface_near(world: Vector3) -> Array:
	var l := global_transform.affine_inverse() * world
	var best: Array = surface[0] if not surface.is_empty() else [Vector3.ZERO, Vector3.UP]
	var bd := INF
	for s in surface:
		var d: float = (s[0] as Vector3).distance_squared_to(l)
		if d < bd:
			bd = d
			best = s
	return best


func world_point(s: Array) -> Vector3:
	return global_transform * (s[0] as Vector3)


func world_normal(s: Array) -> Vector3:
	return (global_basis * (s[1] as Vector3)).normalized()


# --- Reactions ----------------------------------------------------------------------

## Ripple on the bubble where a shot was stopped (all peers).
func shield_hit(world_pos: Vector3) -> void:
	if shield_mi == null or not shield_up:
		return
	var local := shield_mi.global_transform.affine_inverse() * world_pos
	_hits[_hit_slot] = Vector4(local.x, local.y, local.z, float(Time.get_ticks_msec()) / 1000.0)
	_hit_slot = (_hit_slot + 1) % 6
	shield_mat.set_shader_parameter("hits", _hits)


func set_strain(k: float) -> void:
	if shield_mat:
		shield_mat.set_shader_parameter("strain", k)


func set_damage(k: float) -> void:
	_damage = k
	hull_mat.set_shader_parameter("damage", k)


func set_alert(on: bool) -> void:
	hull_mat.set_shader_parameter("alert", 1.0 if on else 0.0)


func collapse_shield(animated: bool) -> void:
	if not shield_up:
		return
	shield_up = false
	if shield_mi == null:
		return
	if not animated:
		shield_mi.visible = false
		return
	var tw := create_tween()
	tw.tween_method(func(v: float): shield_mat.set_shader_parameter("strain", v), 0.0, 1.0, 1.2)
	tw.tween_method(func(v: float):
		shield_mat.set_shader_parameter("collapse", v)
		shield_mat.set_shader_parameter("power", 1.0 + v * 4.0), 0.0, 1.0, 1.6)
	tw.tween_callback(func(): shield_mi.visible = false)
	for i in 8:
		var s: Array = surface[randi() % surface.size()] if not surface.is_empty() else [Vector3.ZERO, Vector3.UP]
		var p := world_point(s) + world_normal(s) * 80.0
		get_tree().create_timer(1.2 + i * 0.12).timeout.connect(func(): FX.sparks(arena, p, Vector3.ZERO, Color(0.5, 0.85, 1.0), 40, true))
	Sfx.play("shield_down", 2.0)


func restore_shield() -> void:
	shield_up = true
	if shield_mi:
		shield_mi.visible = true
		shield_mat.set_shader_parameter("collapse", 0.0)
		shield_mat.set_shader_parameter("power", 1.0)
		shield_mat.set_shader_parameter("strain", 0.0)


## A part blew up: fireball, debris and a fire that keeps burning.
func part_destroyed(p: MothershipPart, quiet := false) -> void:
	p.destroy()
	if App.is_dedicated:
		return
	var pos := p.aim_center()
	if not quiet:
		FX.explosion(arena, pos, p.radius * 1.3, Color(1.0, 0.55, 0.25))
		FX.explosion(arena, pos + p.global_basis.y * p.radius * 0.8, p.radius * 0.8, Color(1.0, 0.7, 0.4), false)
		Sfx.play_at("explosion", pos, 6.0, 0.6, 5000.0)
	add_fire(p.global_position + p.global_basis.y * p.radius * 0.3, p.global_basis.y, p.radius * 0.9)


func add_fire(world: Vector3, normal: Vector3, size: float) -> void:
	if App.is_dedicated or _fires.size() > 24:
		return
	var f := preload("res://game/siege/hull_fire.gd").new()
	_section_for(global_transform.affine_inverse() * world).add_child(f)
	f.global_position = world
	f.setup(normal, size)
	_fires.append(f)


## Armour fractured: a breach blows open somewhere on the hull.
func breach(rng_seed: int, big := false) -> void:
	if surface.is_empty() or App.is_dedicated:
		return
	var s: Array = surface[rng_seed % surface.size()]
	var p := world_point(s)
	var n := world_normal(s)
	FX.explosion(arena, p + n * 10.0, 60.0 if big else 35.0, Color(1.0, 0.5, 0.2))
	Sfx.play_at("explosion", p, 6.0 if big else 2.0, 0.55, 5000.0)
	add_fire(p, n, 50.0 if big else 34.0)


func reveal_core(core: MothershipPart, animated: bool) -> void:
	core.set_exposed(true)
	set_alert(true)
	if animated and not App.is_dedicated:
		var pos := core.aim_center()
		FX.explosion(arena, pos, 110.0, Color(1.0, 0.6, 0.3))
		Sfx.play_at("explosion", pos, 8.0, 0.45, 6000.0)
		Sfx.play("alarm", -2.0, 0.7)


# --- Set pieces ---------------------------------------------------------------------

## The reactor goes: chain explosions race along the hull, the sections tear
## apart and drift, and finally the core detonates (all peers).
func play_destruction(core_world: Vector3) -> void:
	if destroyed:
		return
	destroyed = true
	set_alert(true)
	for b in bodies:
		b.collision_layer = 0
	for p in parts:
		if p.alive:
			p.destroy()
	if shield_mi:
		shield_mi.visible = false
	if App.is_dedicated:
		return
	App.flash(Color(1.0, 0.9, 0.75), 0.6)
	FX.explosion(arena, core_world, 160.0, Color(1.0, 0.6, 0.25))
	Sfx.play("boom_huge", 4.0, 1.0)
	arena.camera_shake(1.0)
	var order := surface.duplicate()
	var local_core := global_transform.affine_inverse() * core_world
	order.sort_custom(func(a, b): return (a[0] as Vector3).distance_squared_to(local_core) < (b[0] as Vector3).distance_squared_to(local_core))
	var n := order.size()
	for i in n:
		var s: Array = order[i]
		var delay := 0.25 + 5.0 * float(i) / float(n) + randf() * 0.3
		get_tree().create_timer(delay).timeout.connect(func():
			if not is_inside_tree():
				return
			var p := world_point(s)
			FX.explosion(arena, p + world_normal(s) * 12.0, randf_range(30.0, 70.0), Color(1.0, 0.5, 0.2), i % 3 == 0)
			if i % 4 == 0:
				Sfx.play_at("explosion", p, 6.0, randf_range(0.4, 0.7), 8000.0))
	# Engines gutter out.
	var tw := create_tween()
	tw.tween_method(func(v: float):
		_engine_power = v
		for e in engines:
			e.thrust = v * 0.3
			e.visible = v > 0.05, 1.0, 0.0, 2.5)
	get_tree().create_timer(2.2).timeout.connect(_break_apart.bind(local_core))
	get_tree().create_timer(6.2).timeout.connect(func():
		if not is_inside_tree():
			return
		App.flash(Color(1.0, 0.95, 0.85), 1.4)
		FX.explosion(arena, core_world, 340.0, Color(1.0, 0.7, 0.35))
		FX.explosion(arena, core_world + Vector3(0, 120, 0), 220.0, Color(1.0, 0.5, 0.2), false)
		Sfx.play("boom_huge", 6.0, 0.7)
		arena.camera_shake(1.0)
		for f in _fires:
			if is_instance_valid(f):
				f.scale_up(1.8))


func _break_apart(local_core: Vector3) -> void:
	if not is_inside_tree():
		return
	for s in sections:
		var c := Vector3(0, 0, 0)
		for ch in s.get_children():
			if ch is MeshInstance3D:
				c = (ch as MeshInstance3D).get_aabb().get_center()
				break
		var away := c - local_core
		away.y *= 0.4
		var vel := away.normalized() * randf_range(10.0, 22.0) + Vector3(randf_range(-4, 4), randf_range(-6, 6), randf_range(-4, 4))
		var spin := Vector3(randf_range(-0.05, 0.05), randf_range(-0.03, 0.03), randf_range(-0.06, 0.06))
		_breakup.append([s, vel, spin, c])
	for mi in section_meshes:
		var t := create_tween()
		t.tween_method(func(v: float): mi.set_instance_shader_parameter("burn", v), 0.0, 0.85, 7.0)
	hull_mat.set_shader_parameter("lights_on", 0.0)


## Defenders held: spool the drives and jump out in a flash.
func play_warp() -> void:
	if destroyed or warped:
		return
	warped = true
	if App.is_dedicated:
		return
	# Colliders can't take the warp stretch (Jolt only scales them uniformly),
	# and nothing needs them once the carrier is leaving.
	for b in bodies:
		b.queue_free()
	bodies.clear()
	for p in parts:
		if p.hit_area:
			p.hit_area.queue_free()
			p.hit_area = null
	for e in engines:
		e.thrust = 1.0
	var tw := create_tween()
	tw.tween_method(func(v: float):
		for e in engines:
			e.boost = v, 0.0, 1.0, 2.6)
	tw.tween_callback(func():
		Sfx.play("warp", 2.0)
		App.flash(Color(0.7, 0.9, 1.0), 0.5))
	var fwd := -global_basis.z
	var start := global_position
	tw.tween_property(self, "scale", Vector3(0.6, 0.6, 7.0), 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "global_position", start + fwd * 26000.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		visible = false
		FX.explosion(arena, start + fwd * 900.0, 120.0, Color(0.5, 0.85, 1.0), false))


func _process(delta: float) -> void:
	_t += delta
	for b in _blinkers:
		var on := fmod(_t + float(b[1]), float(b[2])) < 0.18
		(b[0] as MeshInstance3D).visible = on and not destroyed
	if not destroyed:
		var idle := 0.26 + 0.05 * sin(_t * 0.7)
		for e in engines:
			if not warped:
				e.thrust = idle
		hull_mat.set_shader_parameter("engine_power", 0.7 + 0.3 * sin(_t * 0.7))
		# Cosmetic secondary blasts once the armour is badly hurt.
		if _damage > 0.35 and not App.is_dedicated:
			_secondary_t -= delta
			if _secondary_t <= 0.0:
				_secondary_t = randf_range(1.0, 3.5) / _damage
				var s: Array = surface[randi() % surface.size()] if not surface.is_empty() else [Vector3.ZERO, Vector3.UP]
				FX.explosion(arena, world_point(s) + world_normal(s) * 6.0, randf_range(14.0, 28.0), Color(1.0, 0.55, 0.25), false)
	# Torn-off sections tumble about their own middle while drifting apart.
	for b in _breakup:
		var s: Node3D = b[0]
		var pc := s.transform * (b[3] as Vector3)
		var r := Transform3D(Basis.from_euler((b[2] as Vector3) * delta), Vector3.ZERO)
		s.transform = Transform3D(Basis.IDENTITY, pc) * r * Transform3D(Basis.IDENTITY, -pc) * s.transform
		s.position += (b[1] as Vector3) * delta
