class_name Trail3D
extends MeshInstance3D
## Camera-facing ribbon that follows a target node. Points are sampled by
## distance travelled and fade out by age, rebuilt into an ImmediateMesh.

@export var max_points := 24
@export var lifetime := 0.6
@export var width := 0.6
@export var min_step := 1.5
@export var width_curve := 1.0
var source: Node3D
var emitting := true
var color := Color.WHITE

var _points: Array = []  # [pos, age]
var _im := ImmediateMesh.new()


func _ready() -> void:
	mesh = _im
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	global_transform = Transform3D.IDENTITY
	extra_cull_margin = 200.0


func clear() -> void:
	_points.clear()
	_im.clear_surfaces()


func _process(delta: float) -> void:
	for p in _points:
		p[1] += delta
	while _points.size() > 0 and _points[_points.size() - 1][1] > lifetime:
		_points.pop_back()
	if emitting and is_instance_valid(source) and source.is_visible_in_tree():
		var pos := source.global_position
		if _points.is_empty() or _points[0][0].distance_to(pos) > min_step:
			_points.push_front([pos, 0.0])
			if _points.size() > max_points:
				_points.pop_back()
		else:
			_points[0][0] = pos
	_rebuild()


func _rebuild() -> void:
	_im.clear_surfaces()
	if _points.size() < 2 or material_override == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_pos := cam.global_position
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _points.size()
	for i in n:
		var p: Vector3 = _points[i][0]
		var nxt: Vector3 = _points[mini(i + 1, n - 1)][0]
		var prv: Vector3 = _points[maxi(i - 1, 0)][0]
		var dir := (prv - nxt)
		if dir.length_squared() < 0.0001:
			dir = Vector3.FORWARD
		var side := dir.cross(cam_pos - p).normalized()
		var life := 1.0 - clampf(_points[i][1] / lifetime, 0.0, 1.0)
		var w := width * lerpf(1.0, life, width_curve) * 0.5
		var c := Color(color.r, color.g, color.b, life * color.a)
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(float(i) / n, 0.0))
		_im.surface_add_vertex(p + side * w)
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(float(i) / n, 1.0))
		_im.surface_add_vertex(p - side * w)
	_im.surface_end()
