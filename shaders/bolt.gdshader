// Plasma bolt drawn through a MultiMesh: elongated cross quads, colour
// from the per-instance colour, white-hot centre line.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float energy = 6.0;

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float along = 1.0 - abs(UV.y - 0.5) * 2.0;
	float body = pow(across, 2.0) * pow(along, 0.6);
	float core = pow(across, 8.0) * pow(along, 1.5);
	ALBEDO = (COLOR.rgb * body + vec3(1.0) * core * 0.9) * energy * COLOR.a;
}
