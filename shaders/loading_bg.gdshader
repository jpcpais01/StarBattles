// Boot/loading backdrop: drifting nebula, twinkling stars and a ringed
// gas giant rising in the corner, all analytic in one cheap pass.
shader_type canvas_item;

uniform vec2 resolution = vec2(1920.0, 1080.0);
uniform float reveal = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + 1.7; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 uv = UV;
	float aspect = resolution.x / resolution.y;
	vec2 p = vec2(uv.x * aspect, uv.y);
	float t = TIME * 0.015;
	vec3 col = vec3(0.008, 0.012, 0.025);
	// Nebula.
	float n = fbm(p * 2.2 + vec2(t, -t * 0.6));
	float n2 = fbm(p * 4.0 - vec2(t * 1.3, t * 0.4) + n);
	col += vec3(0.08, 0.14, 0.32) * pow(n2, 2.5) * 1.1;
	col += vec3(0.28, 0.08, 0.18) * pow(fbm(p * 1.6 + vec2(4.0, t)), 3.0) * 0.8;
	// Stars.
	for (int l = 0; l < 2; l++) {
		float sc = l == 0 ? 90.0 : 220.0;
		vec2 g = p * sc;
		vec2 id = floor(g);
		vec2 f = fract(g) - 0.5;
		float h = hash(id + float(l) * 17.0);
		if (h > 0.93) {
			vec2 o = vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5;
			float d = length(f - o * 0.6);
			float tw = 0.6 + 0.4 * sin(TIME * (1.0 + h * 4.0) + h * 30.0);
			col += vec3(0.9, 0.95, 1.0) * smoothstep(0.12, 0.0, d) * tw * (l == 0 ? 1.0 : 0.5);
		}
	}
	// Ringed planet, bottom right.
	vec2 c = vec2(aspect * 0.82, 1.02 - 0.04 * sin(TIME * 0.1));
	float R = 0.42;
	vec2 d = p - c;
	float r = length(d);
	vec3 L = normalize(vec3(-0.8, -0.35, 0.5));
	if (r < R) {
		vec3 nrm = vec3(d / R, sqrt(1.0 - (r / R) * (r / R)));
		float lit = clamp(dot(nrm, L), 0.0, 1.0);
		float bands = 0.5 + 0.5 * sin(nrm.y * 26.0 + noise(nrm.xy * 6.0) * 1.5);
		vec3 pc = mix(vec3(0.75, 0.6, 0.38), vec3(0.95, 0.85, 0.62), bands);
		col = pc * (lit * 0.95 + 0.02) * pow(nrm.z, 0.3);
	}
	// Rings: tilted ellipse band in front/behind.
	vec2 rd = d;
	rd = vec2(rd.x * cos(-0.35) - rd.y * sin(-0.35), rd.x * sin(-0.35) + rd.y * cos(-0.35));
	float er = length(vec2(rd.x, rd.y * 4.2));
	float band = smoothstep(0.55, 0.57, er) * (1.0 - smoothstep(0.92, 0.95, er));
	band *= 0.55 + 0.45 * noise(vec2(er * 80.0, 0.0));
	band *= 1.0 - smoothstep(0.76, 0.77, er) * (1.0 - smoothstep(0.785, 0.795, er));
	bool front = rd.y > 0.0 || r > R;
	if (band > 0.0 && front) {
		col = mix(col, vec3(0.85, 0.76, 0.6) * 0.9, band * 0.85);
	}
	// Vignette and reveal fade.
	float v = smoothstep(1.3, 0.3, length((uv - 0.5) * vec2(aspect, 1.0)));
	col *= mix(0.55, 1.0, v);
	COLOR = vec4(col * reveal, 1.0);
}
