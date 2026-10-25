// Soft lit dust puff for rock impacts, billboarded by the particle system.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

global uniform vec3 sun_dir;
uniform vec3 color : source_color = vec3(0.42, 0.38, 0.34);

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv) * 2.0;
	float puff = pow(clamp(1.0 - d, 0.0, 1.0), 1.6);
	float lit = 0.45 + 0.55 * clamp(dot(normalize(vec3(uv.x, -uv.y, 0.5)), normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz)), 0.0, 1.0);
	ALBEDO = color * COLOR.rgb * lit;
	ALPHA = puff * COLOR.a * 0.7;
}
