// Icy/rocky moon with procedural craters, or a hazy atmosphere (Titan).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

global uniform vec3 sun_dir;
uniform vec3 albedo : source_color = vec3(0.8, 0.8, 0.82);
uniform vec3 albedo_dark : source_color = vec3(0.5, 0.5, 0.52);
uniform float crater_scale = 6.0;
uniform float haze = 0.0;
uniform vec3 haze_color : source_color = vec3(0.95, 0.65, 0.3);
uniform float seed = 1.0;

varying vec3 v_local;

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

float craters(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float best = 1.0;
	float rim = 0.0;
	for (int x = -1; x <= 1; x++)
	for (int y = -1; y <= 1; y++)
	for (int z = -1; z <= 1; z++) {
		vec3 o = vec3(float(x), float(y), float(z));
		vec3 h = hash3(i + o + seed);
		float d = length(o + h - f);
		float size = 0.25 + 0.35 * h.x;
		float k = d / size;
		best = min(best, k);
		rim += smoothstep(0.75, 1.0, k) * (1.0 - smoothstep(1.0, 1.3, k)) * 0.5;
	}
	return clamp(1.0 - smoothstep(0.0, 1.0, best), 0.0, 1.0) * 0.6 - rim * 0.3;
}

void vertex() {
	v_local = normalize(VERTEX);
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 V = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float cr = craters(v_local * crater_scale) + craters(v_local * crater_scale * 2.7) * 0.5;
	vec3 col = mix(albedo, albedo_dark, clamp(cr, 0.0, 1.0));
	float ndl = dot(wn, normalize(sun_dir));
	float lit = smoothstep(-0.03, 0.2, ndl) * clamp(ndl * 0.85 + 0.15, 0.0, 1.0);
	vec3 c = mix(col, haze_color, haze) * lit;
	float rim = pow(1.0 - clamp(dot(wn, V), 0.0, 1.0), 3.0);
	c += haze_color * rim * haze * smoothstep(-0.4, 0.3, ndl) * 0.8;
	ALBEDO = c * 1.4;
}
