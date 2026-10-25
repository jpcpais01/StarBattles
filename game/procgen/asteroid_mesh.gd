class_name AsteroidMesh
## Procedural asteroid geometry: a displaced icosphere with fbm lumps,
## impact craters and anisotropic squash. Fragments get flat fracture cuts
## (marked in vertex colour R so the shader can make them glow hot).
## generate() is pure data and safe to run on worker threads.

const PHI := 1.618033988749895


static func generate(seed: int, subdiv: int, fragment := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var verts := PackedVector3Array()
	var faces := PackedInt32Array()
	_icosphere(verts, faces, subdiv)

	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.9 if not fragment else 1.6
	var squash := Vector3(1.0, rng.randf_range(0.55, 0.95), rng.randf_range(0.6, 1.0))
	var craters := []
	for i in rng.randi_range(3, 7):
		craters.append([Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(),
			rng.randf_range(0.18, 0.5), rng.randf_range(0.05, 0.14)])
	var cuts := []
	if fragment:
		for i in rng.randi_range(1, 3):
			cuts.append([Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.35, 0.7)])

	var colors := PackedColorArray()
	colors.resize(verts.size())
	var max_r := 0.0
	for i in verts.size():
		var p := verts[i]
		var r := 1.0 + noise.get_noise_3dv(p * 1.1) * 0.32 + noise.get_noise_3dv(p * 3.7 + Vector3(9, 1, 3)) * 0.08
		for c in craters:
			var d := p.distance_to(c[0])
			var cr: float = c[1]
			if d < cr * 1.3:
				var k := d / cr
				if k < 1.0:
					r -= c[2] * (1.0 - k * k)
				else:
					r += c[2] * 0.35 * (1.0 - (k - 1.0) / 0.3)
		var v := p * r * squash
		var frac := 0.0
		for cut in cuts:
			var dist: float = v.dot(cut[0])
			if dist > cut[1]:
				v -= cut[0] * (dist - cut[1])
				frac = 1.0
		verts[i] = v
		colors[i] = Color(frac, 0, 0)
		max_r = maxf(max_r, v.length())

	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for f in range(0, faces.size(), 3):
		var a := verts[faces[f]]
		var b := verts[faces[f + 1]]
		var c := verts[faces[f + 2]]
		var n := (c - a).cross(b - a)
		normals[faces[f]] += n
		normals[faces[f + 1]] += n
		normals[faces[f + 2]] += n
	for i in normals.size():
		normals[i] = normals[i].normalized()

	var hull_points := PackedVector3Array()
	for i in mini(42, verts.size()):
		hull_points.append(verts[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = faces
	return {"arrays": arrays, "radius": max_r, "hull": hull_points, "tris": faces.size() / 3}


static func to_mesh(data: Dictionary) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data.arrays)
	return m


static func _icosphere(verts: PackedVector3Array, faces: PackedInt32Array, subdiv: int) -> void:
	var t := PHI
	for p in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append(p.normalized())
	var f := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	# Godot treats clockwise as front-facing, so flip the CCW reference list.
	for i in range(0, f.size(), 3):
		faces.append_array([f[i], f[i + 2], f[i + 1]])
	for level in subdiv:
		var cache := {}
		var nf := PackedInt32Array()
		for i in range(0, faces.size(), 3):
			var a := faces[i]
			var b := faces[i + 1]
			var c := faces[i + 2]
			var ab := _mid(verts, cache, a, b)
			var bc := _mid(verts, cache, b, c)
			var ca := _mid(verts, cache, c, a)
			nf.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		faces.clear()
		faces.append_array(nf)


static func _mid(verts: PackedVector3Array, cache: Dictionary, a: int, b: int) -> int:
	var key := mini(a, b) * 100000 + maxi(a, b)
	if cache.has(key):
		return cache[key]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	cache[key] = verts.size() - 1
	return verts.size() - 1
