class_name HullBuilder
## Procedural placeholder hulls until the real Meshy models arrive. Each
## returns {"hull": ArrayMesh, "glass": ArrayMesh}. Forward is -Z.

static var _cache: Dictionary = {}


static func build(kind: String) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var out: Dictionary
	match kind:
		"wraith":
			out = _wraith()
		"bastion":
			out = _bastion()
		"carrier":
			out = _carrier()
		_:
			out = _vanguard()
	_cache[kind] = out
	return out


static func _vanguard() -> Dictionary:
	var k := MeshKit.new()
	var P := MeshKit.PAINT
	var H := MeshKit.HULL
	var D := MeshKit.DARK
	var prof := MeshKit.profile_fuselage()
	k.loft([
		[-7.2, 0.06, 0.05, 0.0], [-5.6, 0.5, 0.42, 0.05], [-3.6, 0.95, 0.72, 0.12],
		[-1.0, 1.25, 0.92, 0.18], [2.0, 1.45, 0.9, 0.15], [4.4, 1.55, 0.85, 0.1], [6.0, 1.45, 0.75, 0.05]],
		prof, 0.0, [P, H, H, H, H, D])
	# Dorsal spine and intakes.
	k.box(Vector3(0, 0.95, 2.4), Vector3(0.35, 0.22, 2.4), H, 0.12)
	k.box(Vector3(-1.45, -0.15, -0.6), Vector3(0.28, 0.4, 1.0), D, 0.1)
	k.box(Vector3(1.45, -0.15, -0.6), Vector3(0.28, 0.4, 1.0), D, 0.1)
	# Swept wings with wingtip gun pods.
	for s in [-1.0, 1.0]:
		k.wing([s * 1.2, -1.4, 3.4, -0.1, 0.38], [s * 5.15, 0.9, 2.6, -0.18, 0.16], H, P)
		k.cylinder(Vector3(s * 5.35, -0.15, -0.6), Vector3(s * 5.35, -0.15, 2.9), 0.34, 0.26, 8, P)
		k.cylinder(Vector3(s * 5.35, -0.15, 2.9), Vector3(s * 5.35, -0.15, 3.3), 0.26, 0.12, 8, D)
		# Engine nacelles.
		k.cylinder(Vector3(s * 1.25, 0.05, 2.6), Vector3(s * 1.25, 0.05, 5.9), 0.92, 0.84, 12, H)
		k.ring(Vector3(s * 1.25, 0.05, 6.0), Vector3(0, 0, 1), 0.84, 0.6, 0.3, 12, D)
		k.disc(Vector3(s * 1.25, 0.05, 6.15), Vector3(0, 0, 1), 0.62, 12, MeshKit.GLOW)
		# Canted tail fins.
		var base := Vector3(s * 0.85, 0.75, 3.4)
		var top := Vector3(s * 1.6, 2.4, 5.2)
		k.quad(base, base + Vector3(0, 0, 2.6), top + Vector3(0, 0, 0.8), top, P, Vector3(s * 0.4, 0.7, 4.6))
		k.quad(base + Vector3(s * 0.12, 0, 0), base + Vector3(s * 0.12, 0, 2.6), top + Vector3(s * 0.08, 0, 0.8), top + Vector3(s * 0.08, 0, 0), P, Vector3(s * 2.2, 1.2, 4.6))
		# Running lights.
		k.box(Vector3(s * 1.05, 0.55, -2.2), Vector3(0.04, 0.05, 0.9), MeshKit.GLOW)
		k.box(Vector3(s * 4.9, -0.12, 2.2), Vector3(0.1, 0.04, 0.3), MeshKit.GLOW)
	var hull := k.commit()
	var g := MeshKit.new()
	g.loft([[-4.6, 0.05, 0.05, 0.62], [-3.5, 0.48, 0.34, 0.8], [-2.2, 0.6, 0.45, 0.9], [-0.8, 0.45, 0.32, 0.86]],
		MeshKit.profile_round(10), 0.0, [], true, true)
	return {"hull": hull, "glass": g.commit(), "tris": k.tris + g.tris}


static func _wraith() -> Dictionary:
	var k := MeshKit.new()
	var P := MeshKit.PAINT
	var H := MeshKit.HULL
	var D := MeshKit.DARK
	var prof := MeshKit.profile_fuselage()
	k.loft([
		[-6.8, 0.04, 0.03, 0.0], [-4.6, 0.42, 0.28, 0.0], [-2.0, 0.78, 0.5, 0.05], [1.0, 1.0, 0.62, 0.1],
		[3.4, 1.2, 0.75, 0.1], [5.0, 1.18, 0.8, 0.1], [5.4, 1.0, 0.72, 0.1]],
		prof, 0.0, [P, P, H, H, H, D])
	k.ring(Vector3(0, 0.1, 5.4), Vector3(0, 0, 1), 1.05, 0.85, 0.35, 14, D)
	k.disc(Vector3(0, 0.1, 5.6), Vector3(0, 0, 1), 0.86, 14, MeshKit.GLOW)
	for s in [-1.0, 1.0]:
		# Forward-swept blades.
		k.wing([s * 0.8, 1.2, 4.6, 0.0, 0.22], [s * 5.0, -1.2, 0.2, 0.25, 0.08], H, P)
		k.quad(Vector3(s * 4.9, 0.25, -1.1), Vector3(s * 4.9, 0.25, 0.2), Vector3(s * 5.1, -1.3, 0.6), Vector3(s * 5.1, -1.0, -0.4), P, Vector3(s * 4.4, 0.0, -0.3))
		k.quad(Vector3(s * 4.98, 0.25, -1.1), Vector3(s * 4.98, 0.25, 0.2), Vector3(s * 5.18, -1.3, 0.6), Vector3(s * 5.18, -1.0, -0.4), P, Vector3(s * 5.6, 0.0, -0.3))
		# Side boosters.
		k.cylinder(Vector3(s * 1.55, -0.05, 2.4), Vector3(s * 1.55, -0.05, 4.6), 0.5, 0.48, 10, H)
		k.ring(Vector3(s * 1.55, -0.05, 4.62), Vector3(0, 0, 1), 0.48, 0.32, 0.14, 10, D)
		k.disc(Vector3(s * 1.55, -0.05, 4.7), Vector3(0, 0, 1), 0.34, 10, MeshKit.GLOW)
		# Chin laser fairings.
		k.box(Vector3(s * 0.95, -0.45, -2.6), Vector3(0.22, 0.2, 1.0), D, 0.08)
		k.box(Vector3(s * 0.62, 0.32, -1.0), Vector3(0.03, 0.04, 1.4), MeshKit.GLOW)
	# Dorsal fin.
	k.quad(Vector3(0, 0.7, 2.0), Vector3(0, 0.7, 4.8), Vector3(0, 2.1, 5.4), Vector3(0, 1.9, 4.0), P, Vector3(-0.1, 1.2, 4.0))
	k.quad(Vector3(0.06, 0.7, 2.0), Vector3(0.06, 0.7, 4.8), Vector3(0.06, 2.1, 5.4), Vector3(0.06, 1.9, 4.0), P, Vector3(0.3, 1.2, 4.0))
	var hull := k.commit()
	var g := MeshKit.new()
	g.loft([[-3.4, 0.04, 0.04, 0.35], [-2.4, 0.4, 0.22, 0.5], [-0.8, 0.48, 0.3, 0.58], [0.6, 0.3, 0.2, 0.55]],
		MeshKit.profile_round(10))
	return {"hull": hull, "glass": g.commit(), "tris": k.tris + g.tris}


static func _bastion() -> Dictionary:
	var k := MeshKit.new()
	var P := MeshKit.PAINT
	var H := MeshKit.HULL
	var D := MeshKit.DARK
	var prof := MeshKit.profile_box()
	k.loft([
		[-9.2, 0.9, 0.5, -0.2], [-7.4, 2.2, 1.2, 0.0], [-4.0, 3.0, 1.7, 0.1], [0.0, 3.3, 1.9, 0.15],
		[4.0, 3.4, 1.9, 0.1], [6.6, 3.2, 1.8, 0.0], [7.0, 3.0, 1.6, -0.2]],
		prof, 0.0, [P, H, H, H, H, D])
	# Turret plinth and armour plates.
	k.box(Vector3(0, 1.85, -1.6), Vector3(1.3, 0.25, 1.4), D, 0.3)
	k.box(Vector3(0, 1.9, 2.6), Vector3(2.0, 0.22, 2.2), H, 0.2)
	k.box(Vector3(0, -1.85, 0.5), Vector3(2.4, 0.2, 4.0), D, 0.2)
	for s in [-1.0, 1.0]:
		k.box(Vector3(s * 2.9, 0.9, 0.0), Vector3(0.5, 0.6, 3.5), P, 0.25)
		# Sponsons with missile racks.
		k.wing([s * 3.0, -1.0, 3.5, 0.2, 0.6], [s * 6.0, -0.6, 3.0, 0.3, 0.5], H, P)
		k.box(Vector3(s * 6.4, 0.3, 2.2), Vector3(0.75, 0.7, 2.6), H, 0.25)
		k.box(Vector3(s * 4.6, -0.4, -2.2), Vector3(0.6, 0.5, 1.6), D, 0.15)
		# Engine block.
		for y in [0.6, -1.3]:
			k.cylinder(Vector3(s * 2.6, y, 6.0), Vector3(s * 2.6, y, 8.5), 1.15, 1.1, 12, H)
			k.ring(Vector3(s * 2.6, y, 8.6), Vector3(0, 0, 1), 1.1, 0.82, 0.3, 12, D)
			k.disc(Vector3(s * 2.6, y, 8.7), Vector3(0, 0, 1), 0.85, 12, MeshKit.GLOW)
		k.box(Vector3(s * 3.35, 0.2, -5.0), Vector3(0.05, 0.08, 1.6), MeshKit.GLOW)
		k.box(Vector3(s * 6.4, 1.05, 0.5), Vector3(0.5, 0.05, 0.08), MeshKit.GLOW)
	var hull := k.commit()
	var g := MeshKit.new()
	g.box(Vector3(0, 1.05, -6.4), Vector3(1.1, 0.25, 0.9), MeshKit.HULL, 0.2)
	return {"hull": hull, "glass": g.commit(), "tris": k.tris + g.tris}


## Team capital ship that anchors each spawn. Built at unit scale; the
## arena scales it up ~30x.
static func _carrier() -> Dictionary:
	var k := MeshKit.new()
	var P := MeshKit.PAINT
	var H := MeshKit.HULL
	var D := MeshKit.DARK
	k.loft([
		[-12.0, 0.6, 0.4, 0.0], [-10.0, 1.6, 0.9, 0.0], [-4.0, 2.2, 1.2, 0.1], [3.0, 2.4, 1.3, 0.1], [9.0, 2.2, 1.4, 0.0], [10.0, 2.0, 1.2, 0.0]],
		MeshKit.profile_box(), 0.0, [P, H, H, H, D])
	k.box(Vector3(0, 1.8, 4.0), Vector3(0.7, 0.9, 1.8), H, 0.2)
	k.box(Vector3(0, 2.9, 4.4), Vector3(0.9, 0.25, 0.8), D, 0.1)
	k.box(Vector3(0, 0.0, -2.0), Vector3(2.3, 0.35, 3.0), D, 0.2)
	for s in [-1.0, 1.0]:
		k.box(Vector3(s * 2.6, 0.0, 1.0), Vector3(0.5, 0.9, 6.5), H, 0.3)
		k.box(Vector3(s * 2.9, 0.0, -3.0), Vector3(0.12, 0.35, 1.8), MeshKit.GLOW)
		k.cylinder(Vector3(s * 1.3, 0.0, 9.4), Vector3(s * 1.3, 0.0, 11.0), 0.9, 0.8, 12, D)
		k.disc(Vector3(s * 1.3, 0.0, 11.05), Vector3(0, 0, 1), 0.7, 12, MeshKit.GLOW)
		for i in 6:
			k.box(Vector3(s * 2.25, 1.1, -7.0 + i * 2.6), Vector3(0.05, 0.04, 0.6), MeshKit.GLOW)
	return {"hull": k.commit(), "glass": null, "tris": k.tris}
