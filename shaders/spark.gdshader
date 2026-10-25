// Particle sparks/embers: additive streaks with a white-hot head, cooling
// along the colour ramp as the particle ages.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float energy = 2.4;
uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float along = 1.0 - abs(UV.y - 0.5) * 2.0;
	float body = pow(across, 3.0) * pow(along, 0.8);
	float head = pow(across, 6.0) * smoothstep(0.55, 0.0, UV.y);
	vec3 c = COLOR.rgb * tint;
	ALBEDO = (c * body + mix(c, vec3(1.0), 0.7) * head) * energy * COLOR.a;
}
