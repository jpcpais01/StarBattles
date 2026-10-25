// Ribbon trail. Vertex colour alpha fades the tail; UV.y spans the width.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.4, 0.8, 1.0);
uniform float energy = 1.6;

void fragment() {
	float across = 1.0 - abs(UV.y - 0.5) * 2.0;
	float a = COLOR.a * pow(across, 1.5);
	// Fade out the stretch that passes right by the chase camera.
	a *= smoothstep(6.0, 48.0, length(VERTEX));
	ALBEDO = color * COLOR.rgb * a * energy;
}
