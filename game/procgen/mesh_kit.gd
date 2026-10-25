class_name MeshKit
extends RefCounted
## Tiny hard-surface modelling kit on top of SurfaceTool. Every triangle is
## flat-shaded and auto-oriented outward from a hint point, so parts can be
## described by their shape alone. Vertex colour carries material masks
## (see shaders/hull.gdshader).

const HULL := Color(0, 0, 0, 0)
const PAINT := Color(1, 0, 0, 0)
const GLOW := Color(0, 1, 0, 0)
const DARK := Color(0, 0, 1, 0)
const HEAT := Color(0, 0, 1, 1)

var st := SurfaceTool.new()
var tris := 0


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


## Adds a triangle facing away from `inside` (a point inside the part).
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, inside: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - inside) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	st.set_color(col)
	st.set_normal(n)
	st.set_uv(Vector2(a.x + a.z, a.y))
	st.add_vertex(a)
	st.set_uv(Vector2(b.x + b.z, b.y))
	st.add_vertex(b)
	st.set_uv(Vector2(c.x + c.z, c.y))
	st.add_vertex(c)
	tris += 1


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, inside: Vector3) -> void:
	tri(a, b, c, col, inside)
	tri(a, c, d, col, inside)


## Lofts a cross-section profile through sections [z, half_w, half_h, y_off].
## `profile` is a closed loop of unit 2D points. `cols` optionally colours
## each segment (index by section).
func loft(sections: Array, profile: Array, x_off := 0.0, cols: Array = [], cap_start := true, cap_end := true) -> void:
	var rings: Array = []
	for s in sections:
		var ring := []
		for p in profile:
			ring.append(Vector3(x_off + p.x * s[1], s[3] + p.y * s[2], s[0]))
		rings.append(ring)
	for i in sections.size() - 1:
		var col: Color = cols[i] if i < cols.size() else HULL
		var inside := Vector3(x_off, (sections[i][3] + sections[i + 1][3]) * 0.5, (sections[i][0] + sections[i + 1][0]) * 0.5)
		for j in profile.size():
			var k := (j + 1) % profile.size()
			quad(rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j], col, inside)
	if cap_start:
		_cap(rings[0], Vector3(x_off, sections[0][3], sections[0][0] + 0.5), cols[0] if cols.size() > 0 else HULL)
	if cap_end:
		var last := sections.size() - 1
		_cap(rings[last], Vector3(x_off, sections[last][3], sections[last][0] - 0.5), cols[last - 1] if cols.size() >= last else HULL)


func _cap(ring: Array, inside: Vector3, col: Color) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	for j in ring.size():
		tri(c, ring[j], ring[(j + 1) % ring.size()], col, inside)


## Chamfered box. `bevel` cuts the 4 edges running along Z.
func box(center: Vector3, half: Vector3, col: Color, bevel := 0.0) -> void:
	var b := minf(bevel, minf(half.x, half.y) * 0.9)
	var prof := [
		Vector2(half.x, half.y - b), Vector2(half.x - b, half.y), Vector2(-half.x + b, half.y), Vector2(-half.x, half.y - b),
		Vector2(-half.x, -half.y + b), Vector2(-half.x + b, -half.y), Vector2(half.x - b, -half.y), Vector2(half.x, -half.y + b)]
	var sections := [[center.z - half.z, 1.0, 1.0, center.y], [center.z + half.z, 1.0, 1.0, center.y]]
	loft(sections, prof, center.x, [col])


## Tapered cylinder between two points.
func cylinder(a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color, caps := true) -> void:
	var axis := (b - a).normalized()
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var u := axis.cross(up).normalized()
	var v := axis.cross(u).normalized()
	var ra := []
	var rb := []
	for i in sides:
		var ang := TAU * float(i) / float(sides)
		var dir := u * cos(ang) + v * sin(ang)
		ra.append(a + dir * r0)
		rb.append(b + dir * r1)
	var mid := (a + b) * 0.5
	for i in sides:
		var j := (i + 1) % sides
		quad(ra[i], ra[j], rb[j], rb[i], col, mid)
	if caps:
		for i in sides:
			var j := (i + 1) % sides
			if r0 > 0.001:
				tri(a, ra[i], ra[j], col, a + axis)
			if r1 > 0.001:
				tri(b, rb[i], rb[j], col, b - axis)


## Flat wing slab between a root chord and a tip chord.
## root/tip: [x, z_front, z_back, y, thickness]
func wing(root: Array, tip: Array, col: Color, edge_col := HULL) -> void:
	var rf := Vector3(root[0], root[3], root[1])
	var rb := Vector3(root[0], root[3], root[2])
	var tf := Vector3(tip[0], tip[3], tip[1])
	var tb := Vector3(tip[0], tip[3], tip[2])
	var rt: float = root[4] * 0.5
	var tt: float = tip[4] * 0.5
	var up := Vector3.UP
	var center := (rf + rb + tf + tb) * 0.25
	# Diamond aerofoil: thickest at 40% chord.
	var rm := rf.lerp(rb, 0.4)
	var tm := tf.lerp(tb, 0.4)
	var top_r := rm + up * rt
	var top_t := tm + up * tt
	var bot_r := rm - up * rt
	var bot_t := tm - up * tt
	quad(rf, tf, top_t, top_r, edge_col, center)
	quad(top_r, top_t, tb, rb, col, center)
	quad(rf, tf, bot_t, bot_r, edge_col, center)
	quad(bot_r, bot_t, tb, rb, col, center)
	# Tip and root caps.
	tri(tf, top_t, tb, col, center)
	tri(tf, bot_t, tb, col, center)
	tri(rf, top_r, rb, col, center)
	tri(rf, bot_r, rb, col, center)


func ring(center: Vector3, axis: Vector3, r_out: float, r_in: float, depth: float, sides: int, col: Color) -> void:
	axis = axis.normalized()
	cylinder(center - axis * depth * 0.5, center + axis * depth * 0.5, r_out, r_out, sides, col, false)
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var u := axis.cross(up).normalized()
	var v := axis.cross(u).normalized()
	for side in [-1.0, 1.0]:
		var c: Vector3 = center + axis * depth * 0.5 * side
		for i in sides:
			var a0 := TAU * float(i) / sides
			var a1 := TAU * float(i + 1) / sides
			var d0 := u * cos(a0) + v * sin(a0)
			var d1 := u * cos(a1) + v * sin(a1)
			quad(c + d0 * r_in, c + d1 * r_in, c + d1 * r_out, c + d0 * r_out, col, c - axis * side)


func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	return st.commit(mesh)


static func profile_fuselage() -> Array:
	return [Vector2(1.0, 0.05), Vector2(0.82, 0.55), Vector2(0.38, 0.95), Vector2(-0.38, 0.95), Vector2(-0.82, 0.55),
		Vector2(-1.0, 0.05), Vector2(-0.85, -0.5), Vector2(-0.35, -0.82), Vector2(0.35, -0.82), Vector2(0.85, -0.5)]


static func profile_box() -> Array:
	return [Vector2(1.0, 0.3), Vector2(1.0, -0.45), Vector2(0.72, -1.0), Vector2(-0.72, -1.0), Vector2(-1.0, -0.45),
		Vector2(-1.0, 0.3), Vector2(-0.62, 1.0), Vector2(0.62, 1.0)]


static func profile_round(n: int) -> Array:
	var out := []
	for i in n:
		var a := TAU * float(i) / n
		out.append(Vector2(cos(a), sin(a)))
	return out


## Flat disc facing `normal` (used for glowing nozzle throats).
func disc(center: Vector3, normal: Vector3, r: float, sides: int, col: Color) -> void:
	normal = normal.normalized()
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var u := normal.cross(up).normalized()
	var v := normal.cross(u).normalized()
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		tri(center, center + (u * cos(a0) + v * sin(a0)) * r, center + (u * cos(a1) + v * sin(a1)) * r, col, center - normal)
