// Missile exhaust ribbon: hot glowing gas at the nozzle that cools into
// billowing grey smoke. The smoke is lit by the sun with a forward-
// scattering lobe (it glows when you look toward the sun through it) and
// broken up by world-anchored turbulence so it never looks like a strip.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

global uniform vec3 sun_dir;
uniform vec3 color : source_color = vec3(0.62, 0.62, 0.64);
uniform vec3 hot_color : source_color = vec3(1.0, 0.55, 0.2);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float across = 1.0 - abs(UV.y - 0.5) * 2.0;
	float age = UV.x;
	float n = noise(wp * 0.35 + vec3(0.0, TIME * 0.4, 0.0)) * 0.65 + noise(wp * 1.1 - vec3(TIME * 0.3)) * 0.35;
	float body = smoothstep(0.0, 0.55 + 0.3 * n, across) * (0.55 + 0.75 * n);
	vec3 to_frag = normalize(wp - CAMERA_POSITION_WORLD);
	float fwd = pow(max(dot(to_frag, normalize(sun_dir)), 0.0), 6.0);
	vec3 smoke = color * COLOR.rgb * (0.45 + 0.35 * n + 1.1 * fwd);
	float heat = exp(-age * 14.0);
	ALBEDO = mix(smoke, hot_color * 2.2, heat);
	ALPHA = clamp(COLOR.a * body * mix(0.5, 0.9, heat), 0.0, 1.0);
}
