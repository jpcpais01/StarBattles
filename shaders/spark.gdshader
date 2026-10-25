// Particle sparks/embers: additive, coloured by the particle colour ramp.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float energy = 5.0;
uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float along = 1.0 - abs(UV.y - 0.5) * 2.0;
	ALBEDO = COLOR.rgb * tint * pow(across, 2.0) * pow(along, 0.7) * energy * COLOR.a;
}
