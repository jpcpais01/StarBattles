class_name WeaponBuilder
## Placeholder weapon models, built as three articulated parts so they can
## aim and recoil: base (fixed) -> turret (yaw) -> barrel (pitch + recoil).
## Returns {base, turret, barrel, muzzles: Array[Vector3] (barrel space),
## pivot: float (yaw pivot height)}.

static var _cache: Dictionary = {}


static func build(model: String) -> Dictionary:
	if _cache.has(model):
		return _cache[model]
	var out: Dictionary
	match model:
		"laser":
			out = _laser()
		"railgun":
			out = _railgun()
		"missile_pod":
			out = _missile_pod()
		_:
			out = _cannon()
	_cache[model] = out
	return out


static func _cannon() -> Dictionary:
	var base := MeshKit.new()
	base.cylinder(Vector3(0, -0.12, 0), Vector3(0, 0.05, 0), 0.32, 0.26, 8, MeshKit.DARK)
	var tur := MeshKit.new()
	tur.box(Vector3(0, 0.12, 0.05), Vector3(0.3, 0.16, 0.45), MeshKit.PAINT, 0.08)
	tur.box(Vector3(0, 0.29, 0.1), Vector3(0.12, 0.03, 0.25), MeshKit.GLOW)
	var bar := MeshKit.new()
	for s in [-1.0, 1.0]:
		var x: float = s * 0.13
		bar.cylinder(Vector3(x, 0, -0.2), Vector3(x, 0, -2.0), 0.075, 0.065, 8, MeshKit.HEAT)
		bar.cylinder(Vector3(x, 0, -1.9), Vector3(x, 0, -2.25), 0.11, 0.1, 8, MeshKit.DARK)
		for i in 3:
			bar.cylinder(Vector3(x, 0, -0.45 - i * 0.22), Vector3(x, 0, -0.55 - i * 0.22), 0.1, 0.1, 8, MeshKit.DARK, false)
	bar.box(Vector3(0, 0, 0.0), Vector3(0.24, 0.1, 0.25), MeshKit.HULL, 0.05)
	return {"base": base.commit(), "turret": tur.commit(), "barrel": bar.commit(),
		"muzzles": [Vector3(-0.13, 0, -2.3), Vector3(0.13, 0, -2.3)], "pivot": 0.14}


static func _laser() -> Dictionary:
	var base := MeshKit.new()
	base.cylinder(Vector3(0, -0.1, 0), Vector3(0, 0.04, 0), 0.26, 0.22, 8, MeshKit.DARK)
	var tur := MeshKit.new()
	tur.loft([[0.35, 0.18, 0.14, 0.12], [-0.25, 0.26, 0.2, 0.12], [-0.45, 0.2, 0.16, 0.12]], MeshKit.profile_round(8), 0.0, [MeshKit.PAINT, MeshKit.HULL])
	var bar := MeshKit.new()
	bar.cylinder(Vector3(0, 0, -0.3), Vector3(0, 0, -1.35), 0.11, 0.09, 10, MeshKit.HULL)
	bar.ring(Vector3(0, 0, -1.4), Vector3(0, 0, 1), 0.16, 0.07, 0.08, 10, MeshKit.GLOW)
	bar.ring(Vector3(0, 0, -0.75), Vector3(0, 0, 1), 0.14, 0.1, 0.06, 10, MeshKit.GLOW)
	for i in 3:
		var a := TAU * i / 3.0
		var off := Vector3(cos(a), sin(a), 0) * 0.17
		bar.cylinder(off + Vector3(0, 0, -0.9), off * 0.7 + Vector3(0, 0, -1.6), 0.03, 0.02, 5, MeshKit.DARK)
	return {"base": base.commit(), "turret": tur.commit(), "barrel": bar.commit(),
		"muzzles": [Vector3(0, 0, -1.55)], "pivot": 0.12}


static func _railgun() -> Dictionary:
	var base := MeshKit.new()
	base.cylinder(Vector3(0, -0.1, 0), Vector3(0, 0.1, 0), 0.75, 0.68, 12, MeshKit.DARK)
	var tur := MeshKit.new()
	tur.box(Vector3(0, 0.38, 0.25), Vector3(0.62, 0.3, 0.78), MeshKit.PAINT, 0.2)
	tur.box(Vector3(0, 0.72, 0.45), Vector3(0.3, 0.06, 0.4), MeshKit.DARK, 0.05)
	tur.box(Vector3(0.45, 0.4, 0.75), Vector3(0.05, 0.05, 0.3), MeshKit.GLOW)
	tur.box(Vector3(-0.45, 0.4, 0.75), Vector3(0.05, 0.05, 0.3), MeshKit.GLOW)
	var bar := MeshKit.new()
	for s in [-1.0, 1.0]:
		bar.box(Vector3(s * 0.16, 0, -1.7), Vector3(0.06, 0.15, 1.6), MeshKit.HEAT, 0.03)
	for i in 5:
		bar.ring(Vector3(0, 0, -0.6 - i * 0.55), Vector3(0, 0, 1), 0.34, 0.24, 0.12, 10, MeshKit.GLOW)
	bar.box(Vector3(0, 0, 0.1), Vector3(0.3, 0.22, 0.35), MeshKit.HULL, 0.08)
	return {"base": base.commit(), "turret": tur.commit(), "barrel": bar.commit(),
		"muzzles": [Vector3(0, 0, -3.4)], "pivot": 0.42}


static func _missile_pod() -> Dictionary:
	var base := MeshKit.new()
	base.box(Vector3(0, 0, 0.6), Vector3(0.45, 0.3, 0.9), MeshKit.PAINT, 0.12)
	var tur := MeshKit.new()
	tur.box(Vector3(0, 0, -0.05), Vector3(0.42, 0.28, 0.06), MeshKit.DARK)
	var bar := MeshKit.new()
	var muzzles := []
	for x in [-0.2, 0.2]:
		for y in [-0.12, 0.12]:
			bar.cylinder(Vector3(x, y, -0.1), Vector3(x, y, -0.4), 0.09, 0.09, 8, MeshKit.DARK, false)
			bar.cylinder(Vector3(x, y, -0.15), Vector3(x, y, -0.35), 0.055, 0.0, 6, MeshKit.GLOW)
			muzzles.append(Vector3(x, y, -0.45))
	return {"base": base.commit(), "turret": tur.commit(), "barrel": bar.commit(), "muzzles": muzzles, "pivot": 0.0}
