// Deep-space sky: two star layers with colour temperature, a Milky Way
// band with dust lanes, faint nebulae and the Sun with corona. The soft
// layers render in the half-res pass; stars and Sun stay full-res.
shader_type sky;
render_mode use_half_res_pass;

global uniform vec3 sun_dir;
uniform vec3 galactic_pole = vec3(0.35, 0.82, -0.45);
uniform float milky_way = 1.0;
uniform float star_brightness = 1.0;
uniform vec3 nebula_a : source_color = vec3(0.16, 0.26, 0.55);
uniform vec3 nebula_b : source_color = vec3(0.5, 0.18, 0.32);
uniform float nebula_strength = 1.0;
uniform float sun_energy = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 4.1);
		a *= 0.5;
	}
	return v;
}

vec3 star_layer(vec3 d, float scale, float density, float size) {
	vec3 p = d * scale;
	vec3 c = floor(p);
	float h = hash(c);
	if (h > density) {
		return vec3(0.0);
	}
	vec3 sp = c + vec3(hash(c + 1.31), hash(c + 2.77), hash(c + 5.13));
	float dist = length(p - sp);
	float b = exp(-dist * dist * size) * (0.4 + 2.2 * pow(hash(c + 9.7), 6.0));
	float temp = hash(c + 3.3);
	vec3 col = temp < 0.2 ? vec3(0.65, 0.78, 1.0) : (temp < 0.75 ? vec3(1.0, 0.98, 0.95) : vec3(1.0, 0.82, 0.6));
	return col * b;
}

vec3 galaxy(vec3 d) {
	float lat = dot(d, normalize(galactic_pole));
	float band = exp(-lat * lat * 14.0);
	float core = exp(-lat * lat * 60.0);
	float n = fbm(d * 3.2);
	float dust = smoothstep(0.42, 0.72, fbm(d * 7.0 + vec3(3.0)));
	vec3 col = mix(vec3(0.42, 0.5, 0.72), vec3(1.0, 0.86, 0.66), core);
	float glow = band * (0.35 + 0.65 * n) * (1.0 - dust * 0.85 * band);
	// Dense unresolved stars along the band.
	float grain = pow(noise(d * 260.0), 8.0) * band;
	vec3 g = col * glow * 0.075 + vec3(0.9, 0.9, 1.0) * grain * 0.25;
	float neb = fbm(d * 1.4 + vec3(5.0, 1.0, 2.0));
	float neb2 = fbm(d * 2.1 + vec3(-3.0, 7.0, 1.0));
	g += nebula_a * pow(smoothstep(0.45, 0.85, neb), 2.0) * 0.07 * nebula_strength;
	g += nebula_b * pow(smoothstep(0.5, 0.9, neb2), 2.0) * 0.05 * nebula_strength;
	return g * milky_way;
}

vec3 sun(vec3 d) {
	float c = dot(d, normalize(sun_dir));
	float disk = smoothstep(0.99990, 0.99994, c) * 80.0;
	float corona = pow(max(c, 0.0), 1600.0) * 6.0 + pow(max(c, 0.0), 180.0) * 0.6 + pow(max(c, 0.0), 12.0) * 0.04;
	return vec3(1.0, 0.95, 0.88) * (disk + corona) * sun_energy;
}

void sky() {
	vec3 d = EYEDIR;
	if (AT_CUBEMAP_PASS) {
		COLOR = galaxy(d) * 1.5 + sun(d) * 0.4;
	} else if (AT_HALF_RES_PASS) {
		COLOR = galaxy(d);
	} else {
		vec3 s = star_layer(d, 140.0, 0.03, 18.0) * 1.4 + star_layer(d, 320.0, 0.022, 16.0) * 0.5;
		COLOR = HALF_RES_COLOR.rgb + s * star_brightness + sun(d);
	}
}
