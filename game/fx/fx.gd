class_name FX
## Spawners for transient effects: sparks, impacts, explosions, debris,
## rail tracers and rock dust. Everything self-destructs; particle counts
## scale with the graphics quality setting.

const SH_SPARK := preload("res://shaders/spark.gdshader")
const SH_DUST := preload("res://shaders/dust.gdshader")
const FxNode := preload("res://game/fx/fx_node.gd")

static var _spark_pm: ParticleProcessMaterial
static var _ember_pm: ParticleProcessMaterial
static var _dust_pm: ParticleProcessMaterial
static var _spark_meshes: Dictionary = {}
static var _dust_mesh: QuadMesh
static var _debris_meshes: Array = []


static func _ok() -> bool:
	return not App.is_dedicated


static func _parent(arena: Node) -> Node3D:
	return arena.fx_root if arena and "fx_root" in arena else null


static func _spark_material() -> ParticleProcessMaterial:
	if _spark_pm == null:
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 0, 1)
		pm.spread = 55.0
		pm.initial_velocity_min = 30.0
		pm.initial_velocity_max = 110.0
		pm.damping_min = 40.0
		pm.damping_max = 90.0
		pm.gravity = Vector3.ZERO
		pm.scale_min = 0.5
		pm.scale_max = 1.3
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		ramp.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = ramp
		pm.color_ramp = gt
		_spark_pm = pm
		var ember := pm.duplicate() as ParticleProcessMaterial
		ember.spread = 180.0
		ember.initial_velocity_min = 20.0
		ember.initial_velocity_max = 70.0
		ember.damping_min = 8.0
		ember.damping_max = 20.0
		_ember_pm = ember
	return _spark_pm


static func _spark_mesh(color: Color) -> QuadMesh:
	var key := color.to_html(false)
	if not _spark_meshes.has(key):
		var q := QuadMesh.new()
		q.size = Vector2(0.12, 1.6)
		var sm := ShaderMaterial.new()
		sm.shader = SH_SPARK
		sm.set_shader_parameter("tint", color)
		q.material = sm
		_spark_meshes[key] = q
	return _spark_meshes[key]


static func sparks(arena: Node, pos: Vector3, normal: Vector3, color: Color, count := 10, big := false) -> void:
	if not _ok():
		return
	var parent := _parent(arena)
	if parent == null:
		return
	_spark_material()
	var p := GPUParticles3D.new()
	p.amount = maxi(2, int(count * Settings.fx_scale()))
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.7 if big else 0.45
	p.process_material = _ember_pm if big else _spark_pm
	p.draw_pass_1 = _spark_mesh(color)
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	parent.add_child(p)
	p.global_position = pos
	if normal.length_squared() > 0.001:
		var up := Vector3.UP if absf(normal.normalized().y) < 0.99 else Vector3.RIGHT
		p.global_basis = Basis.looking_at(-normal, up)
	p.emitting = true
	p.get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)
	_flash(parent, pos, color, 1.5 if not big else 4.0, 0.12)


static func _flash(parent: Node3D, pos: Vector3, color: Color, size: float, life: float) -> void:
	var f := FxNode.new()
	parent.add_child(f)
	f.global_position = pos
	f.add_glow(color, size, life, 4.0)


static func impact(arena: Node, pos: Vector3, normal: Vector3, color: Color, shield: bool) -> void:
	if not _ok():
		return
	sparks(arena, pos, normal, color.lerp(Color(0.6, 0.9, 1.0), 0.5) if shield else Color(1.0, 0.7, 0.4), 8)


static func explosion(arena: Node, pos: Vector3, size: float, color: Color, debris := true) -> void:
	if not _ok():
		return
	var parent := _parent(arena)
	if parent == null:
		return
	var f := FxNode.new()
	parent.add_child(f)
	f.global_position = pos
	f.explosion(size, color)
	sparks(arena, pos, Vector3.ZERO, Color(1.0, 0.75, 0.4), int(40 * size / 10.0), true)
	if debris:
		_debris(parent, pos, size)
	Sfx.play_at("explosion" if size > 6.0 else "explosion_small", pos, 2.0 if size > 6.0 else 0.0, randf_range(0.85, 1.1), 2400.0)
	if arena.has_method("explosion_shake"):
		arena.explosion_shake(pos, size)


static func _debris(parent: Node3D, pos: Vector3, size: float) -> void:
	if _debris_meshes.is_empty():
		for i in 3:
			var k := MeshKit.new()
			k.box(Vector3.ZERO, Vector3(randf_range(0.3, 0.9), randf_range(0.1, 0.3), randf_range(0.4, 1.2)), MeshKit.DARK if i == 0 else MeshKit.HULL, 0.08)
			_debris_meshes.append(k.commit())
	var n := int(randi_range(4, 7) * Settings.fx_scale())
	for i in n:
		var d := FxNode.new()
		parent.add_child(d)
		d.global_position = pos
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		d.debris(_debris_meshes[i % _debris_meshes.size()], dir * randf_range(25.0, 70.0) * (size / 10.0 + 0.5), size * 0.12)


static func rail_tracer(arena: Node, from: Vector3, to: Vector3, color: Color) -> void:
	if not _ok():
		return
	var parent := _parent(arena)
	if parent == null:
		return
	var f := FxNode.new()
	parent.add_child(f)
	f.global_position = from
	f.tracer(from, to, color)


static func _dust_material() -> void:
	if _dust_pm:
		return
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 70.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 14.0
	pm.damping_min = 2.0
	pm.damping_max = 5.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	_dust_pm = pm
	_dust_mesh = QuadMesh.new()
	_dust_mesh.size = Vector2(1, 1)
	var sm := ShaderMaterial.new()
	sm.shader = SH_DUST
	_dust_mesh.material = sm


static func dust(arena: Node, pos: Vector3, normal: Vector3, size: float, count := 8) -> void:
	if not _ok():
		return
	var parent := _parent(arena)
	if parent == null:
		return
	_dust_material()
	var p := GPUParticles3D.new()
	p.amount = maxi(2, int(count * Settings.fx_scale()))
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 2.5
	p.process_material = _dust_pm
	p.draw_pass_1 = _dust_mesh
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3.ONE * -size * 6.0, Vector3.ONE * size * 12.0)
	p.scale = Vector3.ONE * size
	parent.add_child(p)
	p.global_position = pos
	if normal.length_squared() > 0.001:
		var up := Vector3.UP if absf(normal.normalized().y) < 0.99 else Vector3.RIGHT
		p.global_basis = Basis.looking_at(-normal, up).scaled(Vector3.ONE * size)
	p.emitting = true
	p.get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)
