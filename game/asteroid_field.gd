class_name AsteroidField
extends Node3D
## Destructible asteroid field. Each asteroid is a record (seed, radius,
## drift, spin) whose transform is a pure function of match time, so every
## peer agrees without streaming positions. The server owns hit points and
## decides fractures; peers rebuild fragments from the records it sends.

const VARIANTS := 10
const DRIFT_K := 0.12
const MIN_FRAGMENT := 3.5

var arena: Arena
var records: Dictionary = {}  # id -> record Dictionary
var next_id := 0
var total_tris := 0
var _variants: Array = []  # [{mesh, hull, radius}] per detail level
var _grid: Dictionary = {}
var _grid_timer := 0.0
var _decor: MultiMeshInstance3D

signal broken(id: int, pos: Vector3, radius: float)


## Builds the base meshes on worker threads. Await before populate().
func prepare_variants() -> void:
	var tasks := []
	var results := []
	results.resize(VARIANTS + 1)
	for i in VARIANTS + 1:
		var subdiv := 3 if i < 3 else 2
		if i == VARIANTS:
			subdiv = 1
		var seed := 9000 + i * 7919
		tasks.append(WorkerThreadPool.add_task(func(): results[i] = AsteroidMesh.generate(seed, subdiv)))
	for t in tasks:
		while not WorkerThreadPool.is_task_completed(t):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(t)
	for i in VARIANTS + 1:
		var d: Dictionary = results[i]
		_variants.append({"mesh": AsteroidMesh.to_mesh(d), "hull": d.hull, "radius": d.radius, "tris": d.tris})


func populate(seed: int, avoid: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var placed := 0
	var attempts := 0
	var target := 64
	while placed < target and attempts < 2000:
		attempts += 1
		var r: float = lerpf(14.0, 110.0, pow(rng.randf(), 3.2))
		var p := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1) * 0.45, rng.randf_range(-1, 1)) * Vector3(1700, 1000, 1500)
		if absf(p.x) > 1650 and absf(p.z) < 500:
			continue  # keep spawn lanes clear
		var ok := true
		for a in avoid:
			if p.distance_to(a[0]) < float(a[1]) + r + 40.0:
				ok = false
				break
		if ok:
			for rec in records.values():
				if p.distance_to(rec.p0) < rec.radius + r + 25.0:
					ok = false
					break
		if not ok:
			continue
		var variant := rng.randi() % VARIANTS
		_add_record({
			"id": next_id, "seed": rng.randi(), "variant": variant, "fragment": false,
			"radius": r, "p0": p, "vel": Vector3.ZERO, "t0": 0.0,
			"axis": Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(),
			"spin": rng.randf_range(0.01, 0.08) * (40.0 / r), "basis0": _rand_basis(rng),
			"hp": r * r * 1.4, "max_hp": r * r * 1.4, "hot": 0.0})
		next_id += 1
		placed += 1
	_build_decor(rng)
	_rebuild_grid()


func _rand_basis(rng: RandomNumberGenerator) -> Basis:
	return Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))


func _add_record(rec: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("asteroid", rec.id)
	var mi := MeshInstance3D.new()
	var shape := ConvexPolygonShape3D.new()
	var base_r: float
	if rec.fragment:
		var data := AsteroidMesh.generate(int(rec.seed), 2 if rec.radius > 10.0 else 1, true)
		mi.mesh = AsteroidMesh.to_mesh(data)
		shape.points = data.hull
		base_r = data.radius
		total_tris += int(data.tris)
		rec["tris"] = data.tris
	else:
		var v: Dictionary = _variants[rec.variant]
		mi.mesh = v.mesh
		shape.points = v.hull
		base_r = v.radius
		total_tris += int(v.tris)
		rec["tris"] = v.tris
	var s: float = rec.radius / base_r
	var pts := PackedVector3Array()
	for pt in shape.points:
		pts.append(pt * s)
	shape.points = pts
	mi.scale = Vector3.ONE * s
	mi.material_override = Mats.asteroid(int(rec.seed) % 3)
	mi.set_instance_shader_parameter("tint", float(int(rec.seed) % 7) / 7.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(mi)
	add_child(body)
	rec["body"] = body
	rec["mesh"] = mi
	records[rec.id] = rec
	_place(rec, arena.time if arena else 0.0)


func _place(rec: Dictionary, t: float) -> void:
	var dt: float = maxf(0.0, t - float(rec.t0))
	var drift: Vector3 = rec.vel * (1.0 - exp(-DRIFT_K * dt)) / DRIFT_K
	var b: Basis = rec.basis0 * Basis(rec.axis, float(rec.spin) * (t if not rec.fragment else dt))
	rec.body.global_transform = Transform3D(b, rec.p0 + drift)


func position_of(id: int) -> Vector3:
	var rec: Dictionary = records.get(id, {})
	return rec.body.global_position if not rec.is_empty() else Vector3.ZERO


func _process(delta: float) -> void:
	var t := arena.time if arena else 0.0
	for rec in records.values():
		_place(rec, t)
		if rec.hot > 0.0:
			rec.hot = maxf(0.0, rec.hot - delta / 7.0)
			rec.mesh.set_instance_shader_parameter("hot", rec.hot)
	_grid_timer -= delta
	if _grid_timer <= 0.0:
		_grid_timer = 0.5
		_rebuild_grid()


# --- Spatial queries ---------------------------------------------------------------

const CELL := 240.0


func _key(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))


func _rebuild_grid() -> void:
	_grid.clear()
	for rec in records.values():
		var c: Vector3 = rec.body.global_position
		var r: float = rec.radius
		var lo := _key(c - Vector3.ONE * r)
		var hi := _key(c + Vector3.ONE * r)
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var k := Vector3i(x, y, z)
					if not _grid.has(k):
						_grid[k] = []
					_grid[k].append(rec.id)


func nearby(p: Vector3, r: float) -> Array:
	var out := {}
	var lo := _key(p - Vector3.ONE * r)
	var hi := _key(p + Vector3.ONE * r)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				for id in _grid.get(Vector3i(x, y, z), []):
					out[id] = true
	return out.keys()


## Sphere vs asteroid (approximated as a slightly shrunk sphere).
func collide_sphere(p: Vector3, r: float) -> Dictionary:
	for id in nearby(p, r + 20.0):
		var rec: Dictionary = records.get(id, {})
		if rec.is_empty():
			continue
		var c: Vector3 = rec.body.global_position
		var rr: float = rec.radius * 0.8 + r
		var d := p.distance_to(c)
		if d < rr and d > 0.001:
			return {"id": id, "normal": (p - c) / d, "depth": rr - d}
	return {}


## Returns how far ahead along `dir` an asteroid blocks a sphere of radius r.
func probe(p: Vector3, dir: Vector3, length: float, r: float) -> Dictionary:
	var best := {}
	var best_t := length
	for id in nearby(p + dir * length * 0.5, length * 0.5 + r + 120.0):
		var rec: Dictionary = records.get(id, {})
		if rec.is_empty():
			continue
		var c: Vector3 = rec.body.global_position
		var rr: float = rec.radius + r
		var oc := c - p
		var t := oc.dot(dir)
		if t < 0.0 or t > best_t:
			continue
		var d2 := oc.length_squared() - t * t
		if d2 < rr * rr:
			best_t = t
			best = {"id": id, "t": t, "center": c, "radius": rec.radius}
	return best


# --- Damage & fractures ---------------------------------------------------------------

## Server only.
func damage(id: int, amount: float, pos: Vector3, dir: Vector3) -> void:
	var rec: Dictionary = records.get(id, {})
	if rec.is_empty():
		return
	rec.hp -= amount
	if rec.hp > 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var children := []
	var r: float = rec.radius
	var c: Vector3 = rec.body.global_position
	var cur_vel: Vector3 = rec.vel * exp(-DRIFT_K * maxf(0.0, arena.time - float(rec.t0)))
	if r * 0.45 >= MIN_FRAGMENT:
		var n := rng.randi_range(3, 5) if r > 25.0 else rng.randi_range(2, 4)
		for i in n:
			var cr := r * rng.randf_range(0.32, 0.55)
			if cr < MIN_FRAGMENT:
				continue
			var out := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var speed := rng.randf_range(5.0, 16.0) * clampf(30.0 / r, 0.4, 2.0)
			children.append({
				"id": next_id, "seed": rng.randi(), "variant": 0, "fragment": true, "radius": cr,
				"p0": c + out * r * 0.45, "vel": cur_vel + out * speed + dir * speed * 0.4, "t0": arena.time,
				"axis": Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(),
				"spin": rng.randf_range(0.1, 0.6) * (10.0 / cr), "basis0": _rand_basis(rng),
				"hp": cr * cr * 1.4, "max_hp": cr * cr * 1.4, "hot": 1.0})
			next_id += 1
	arena.ctl.broadcast_asteroid_break(id, pos, children)


## All peers: remove an asteroid and spawn its fragments.
func apply_break(id: int, impact: Vector3, children: Array) -> void:
	var rec: Dictionary = records.get(id, {})
	if rec.is_empty():
		return
	var c: Vector3 = rec.body.global_position
	var r: float = rec.radius
	total_tris -= int(rec.get("tris", 0))
	rec.body.queue_free()
	records.erase(id)
	for ch in children:
		next_id = maxi(next_id, int(ch.id) + 1)
		_add_record(ch)
	_rebuild_grid()
	FX.dust(arena, c, (impact - c).normalized() if impact != c else Vector3.UP, r * 0.35, 12)
	FX.sparks(arena, c, Vector3.ZERO, Color(1.0, 0.55, 0.2), int(clampf(r, 10, 60)), true)
	Sfx.play_at("rock_break", c, clampf(r / 20.0, 0.0, 6.0), clampf(30.0 / r, 0.5, 1.4), 2600.0)
	arena.explosion_shake(c, r * 0.5)
	broken.emit(id, c, r)


func rock_hit_fx(id: int, pos: Vector3, normal: Vector3) -> void:
	FX.sparks(arena, pos, normal, Color(1.0, 0.75, 0.45), 5)
	if randf() < 0.35:
		FX.dust(arena, pos, normal, 1.2, 3)


func get_state() -> Array:
	var out := []
	for rec in records.values():
		var cur: Dictionary = rec.duplicate()
		cur.erase("body")
		cur.erase("mesh")
		out.append(cur)
	return out


func apply_state(state: Array) -> void:
	for rec in records.values():
		rec.body.queue_free()
	records.clear()
	total_tris = 0
	for rec in state:
		next_id = maxi(next_id, int(rec.id) + 1)
		_add_record(rec)
	_rebuild_grid()


## Distant non-colliding rubble shell beyond the combat zone (one MultiMesh).
func _build_decor(rng: RandomNumberGenerator) -> void:
	var v: Dictionary = _variants[VARIANTS]
	var count: int = [160, 260, 360, 420][Settings.quality()]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = false
	mm.mesh = v.mesh
	mm.instance_count = count
	for i in count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.35, 0.35), rng.randf_range(-1, 1)).normalized()
		var dist := rng.randf_range(2900.0, 5200.0)
		var s := rng.randf_range(4.0, 26.0)
		mm.set_instance_transform(i, Transform3D(_rand_basis(rng).scaled(Vector3.ONE * s / v.radius), dir * dist))
	_decor = MultiMeshInstance3D.new()
	_decor.multimesh = mm
	_decor.material_override = Mats.asteroid(1)
	_decor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_decor)
	total_tris += count * int(v.tris)
