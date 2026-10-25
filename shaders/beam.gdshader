// Continuous laser beam on a unit cylinder stretched along -Z.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.35, 0.85);
instance uniform float intensity = 1.0;
instance uniform float beam_length = 100.0;

void fragment() {
	float edge = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float core = pow(edge, 6.0);
	float glow = pow(edge, 1.5);
	float flow = 0.75 + 0.25 * sin(UV.y * beam_length * 0.35 - TIME * 60.0);
	ALBEDO = (color * glow * 2.5 * flow + vec3(1.0) * core * 3.0) * intensity;
}
