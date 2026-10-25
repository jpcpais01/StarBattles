// Alpha-blended missile smoke ribbon, lit by a fake sun term.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(0.7, 0.7, 0.72);

void fragment() {
	float across = 1.0 - abs(UV.y - 0.5) * 2.0;
	ALBEDO = color * COLOR.rgb;
	ALPHA = COLOR.a * pow(across, 1.2) * 0.55;
}
