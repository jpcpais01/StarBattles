class_name ProjectileSystem
extends MultiMeshInstance3D
## All plasma bolts in one MultiMesh. Simulated on every peer for visuals;
## physics raycasts sweep each bolt per tick. Only the server turns hits
## into damage.

const MAX := 1024
const STRIDE := 16

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _shooter := PackedInt32Array()
var _team := PackedInt32Array()
var _color := PackedColorArray()
var _len := PackedFloat32Array()
var _size := PackedFloat32Array()
var _weapon: Array[String] = []
var _buffer := PackedFloat32Array()
var arena: Arena


func _ready() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = Mats.bolt_mesh()
	multimesh.instance_count = MAX
	multimesh.visible_instance_count = 0
	material_override = Mats.bolt()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	custom_aabb = AABB(Vector3.ONE * -6000.0, Vector3.ONE * 12000.0)
	_buffer.resize(MAX * STRIDE)


func count() -> int:
	return _pos.size()


func spawn(shooter_id: int, team: int, origin: Vector3, dir: Vector3, weapon_id: String, inherit: Vector3) -> void:
	if _pos.size() >= MAX:
		_remove(0)
	var w := ShipLibrary.weapon(weapon_id)
	_pos.append(origin)
	_vel.append(dir * float(w.speed) + inherit * 0.6)
	_life.append(float(w.range) / float(w.speed))
	_shooter.append(shooter_id)
	_team.append(team)
	var c: Color = w.color if team == 0 else w.color.lerp(Color(1.0, 0.45, 0.25), 0.75)
	_color.append(c)
	_len.append(0.0)
	_size.append(float(w.get("size", 1.0)))
	_weapon.append(weapon_id)


func _remove(i: int) -> void:
	var last := _pos.size() - 1
	_pos[i] = _pos[last]
	_vel[i] = _vel[last]
	_life[i] = _life[last]
	_shooter[i] = _shooter[last]
	_team[i] = _team[last]
	_color[i] = _color[last]
	_len[i] = _len[last]
	_size[i] = _size[last]
	_weapon[i] = _weapon[last]
	_pos.resize(last)
	_vel.resize(last)
	_life.resize(last)
	_shooter.resize(last)
	_team.resize(last)
	_color.resize(last)
	_len.resize(last)
	_size.resize(last)
	_weapon.resize(last)


func _physics_process(delta: float) -> void:
	if arena == null:
		return
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collide_with_areas = true
	q.collide_with_bodies = true
	q.collision_mask = 1 | 2
	var i := 0
	while i < _pos.size():
		_life[i] -= delta
		if _life[i] <= 0.0:
			_remove(i)
			continue
		var from := _pos[i]
		var to := from + _vel[i] * delta
		q.from = from
		q.to = to
		var shooter := arena.ship_by_id(_shooter[i])
		q.exclude = [shooter.hit_area.get_rid()] if shooter else []
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var col: Object = hit.collider
			var friendly := (col.has_meta("ship") and (col.get_meta("ship") as Ship).team == _team[i]) \
				or (col.has_meta("mteam") and int(col.get_meta("mteam")) == _team[i])
			if not friendly:
				arena.on_bolt_hit(_shooter[i], _weapon[i], hit, _vel[i].normalized(), _color[i], _team[i])
				_remove(i)
				continue
		_pos[i] = to
		_len[i] = minf(_len[i] + delta * 120.0, 1.0)
		i += 1


func _process(_delta: float) -> void:
	var n := _pos.size()
	multimesh.visible_instance_count = n
	if n == 0:
		return
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	for i in n:
		var v := _vel[i]
		var dir := v.normalized()
		var p := _pos[i]
		# Bolts get a little fatter far away so they stay readable.
		var dist := p.distance_to(cam_pos)
		var w := (0.55 + dist * 0.0012) * _size[i]
		var l := ((6.0 + dist * 0.006) * _len[i] + 1.0) * sqrt(_size[i])
		var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
		var b := Basis.looking_at(dir, up)
		var bx := b.x * w
		var by := b.y * w
		var bz := b.z * l
		var c := p - dir * l * 0.5
		var o := i * STRIDE
		_buffer[o] = bx.x; _buffer[o + 1] = by.x; _buffer[o + 2] = bz.x; _buffer[o + 3] = c.x
		_buffer[o + 4] = bx.y; _buffer[o + 5] = by.y; _buffer[o + 6] = bz.y; _buffer[o + 7] = c.y
		_buffer[o + 8] = bx.z; _buffer[o + 9] = by.z; _buffer[o + 10] = bz.z; _buffer[o + 11] = c.z
		var col := _color[i]
		_buffer[o + 12] = col.r; _buffer[o + 13] = col.g; _buffer[o + 14] = col.b; _buffer[o + 15] = 1.0
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), _buffer)
