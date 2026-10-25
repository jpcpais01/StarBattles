// Holographic capture sphere: fresnel shell with a scrolling hex grid,
// latitude scan lines and a fill wave showing capture progress.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.8, 0.85, 0.95);
uniform vec3 capture_color : source_color = vec3(0.27, 0.72, 1.0);
uniform float progress = 0.0;
uniform float contested = 0.0;

varying vec3 v_local;

float hex(vec2 p) {
	p.x *= 1.1547;
	p.y += mod(floor(p.x), 2.0) * 0.5;
	p = abs(fract(p) - 0.5);
	return abs(max(p.x * 1.5 + p.y, p.y * 2.0) - 1.0);
}

void vertex() {
	v_local = normalize(VERTEX);
}

void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	vec2 uv = vec2(atan(v_local.x, v_local.z) * 4.0, v_local.y * 8.0);
	float grid = 1.0 - smoothstep(0.0, 0.08, hex(uv * 1.3 + vec2(TIME * 0.05, 0.0)));
	float scan = pow(0.5 + 0.5 * sin(v_local.y * 40.0 - TIME * 2.0), 18.0);
	float fill_h = progress * 2.0 - 1.0;
	float filled = step(v_local.y, fill_h);
	float wave = smoothstep(0.04, 0.0, abs(v_local.y - fill_h)) * step(0.01, progress) * step(progress, 0.99);
	vec3 c = mix(color, capture_color, filled);
	float pulse = 1.0 + contested * (0.5 + 0.5 * sin(TIME * 10.0));
	float a = (fres * 0.55 + grid * fres * 0.6 + scan * 0.12 + wave * 1.5) * pulse;
	ALBEDO = c * a * 0.9;
}
