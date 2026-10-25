// Thin emissive ring on a torus: dashed segments that chase around it,
// brightest where the ring is seen edge-on.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.4, 0.8, 1.0);
uniform float energy = 1.0;
uniform float dashes = 48.0;
uniform float speed = 0.05;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float a = atan(v_obj.z, v_obj.x) / 6.2831853;
	float d = fract(a * dashes - TIME * speed * dashes);
	float dash = smoothstep(0.0, 0.08, d) * smoothstep(0.75, 0.6, d);
	float pulse = 0.5 + 0.5 * sin(a * 6.2831853 * 2.0 - TIME * 1.5);
	float edge = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = color * energy * (0.35 + 0.65 * dash) * (0.5 + 0.5 * pulse) * (0.4 + edge);
}
