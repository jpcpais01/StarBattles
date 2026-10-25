// Asteroid regolith. Dark carbonaceous rock (asteroids are about as dark
// as charcoal, so it reads mostly through sunlit relief): impact craters
// with raised rims at two scales, boulder-strewn fbm terrain, lighter
// fresh-ejecta patches and darker space-weathered plains. Relief comes
// from a height field turned into per-pixel normals with screen-space
// derivatives (no extra noise taps), so it stays cheap on phones.
// A glowing fracture rim shows right after a rock splits.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 rock_a : source_color = vec3(0.32, 0.29, 0.27);
uniform vec3 rock_b : source_color = vec3(0.17, 0.155, 0.15);
uniform vec3 rock_c : source_color = vec3(0.45, 0.4, 0.34);
uniform float scale = 3.0;
uniform float bump = 1.0;
instance uniform float hot = 0.0;
instance uniform float tint = 0.0;

varying vec3 v_obj;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
vec3 hash3(vec3 p) {
	return vec3(hash(p), hash(p + 17.31), hash(p + 41.77));
}
float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.13 + 3.1; a *= 0.5; }
	return v;
}

// Crater field: nearest feature point in a 2x2x2 neighbourhood. Returns
// height (bowl + rim) in x and "freshness" in y.
vec2 craters(vec3 p) {
	vec3 b = floor(p - 0.5);
	float bowl = 0.0;
	float rim = 0.0;
	float fresh = 0.0;
	for (int i = 0; i < 8; i++) {
		vec3 c = b + vec3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1));
		vec3 r = hash3(c);
		if (r.z < 0.35) {
			continue;
		}
		float rad = 0.25 + 0.3 * r.x;
		float d = length(p - (c + r)) / rad;
		bowl = min(bowl, min(d * d - 1.0, 0.0) * 0.6);
		rim += exp(-pow((d - 1.0) * 4.0, 2.0)) * 0.3;
		fresh = max(fresh, step(0.85, r.y) * smoothstep(2.4, 0.8, d));
	}
	float h = bowl + rim;
	return vec2(h, fresh);
}

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	vec3 p = v_obj * scale;
	float terrain = fbm(p * 3.0);
	float grit = noise(p * 40.0);
	vec2 c1 = craters(p * 2.2);
	vec2 c2 = craters(p * 7.0 + 11.0);
	float h = terrain * 1.4 + c1.x * 0.9 + c2.x * 0.35 + grit * 0.06;

	// Height -> normal (Mikkelsen's surface-gradient bump).
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * bump * 0.06 * length(MODEL_MATRIX[0].xyz));

	vec3 col = mix(rock_b, rock_a, smoothstep(0.3, 0.75, terrain));
	col = mix(col, rock_c, smoothstep(0.62, 0.85, fbm(p * 9.0 + 5.0)) * 0.5);
	// Crater floors collect dark fines; fresh craters expose bright rock.
	col *= 0.85 + 0.3 * clamp(c1.x + 0.5, 0.0, 1.0);
	col = mix(col, rock_c * 1.35, max(c1.y, c2.y * 0.6) * 0.45);
	col *= 0.85 + 0.3 * grit;
	col = mix(col, col * vec3(1.12, 0.96, 0.82), tint);
	float glint = step(0.992, hash(floor(v_obj * 3.0))) * 0.5;
	ALBEDO = col;
	ROUGHNESS = 0.9 - glint * 0.5;
	METALLIC = glint * 0.6;
	SPECULAR = 0.3;
	float crack = smoothstep(0.55, 0.75, terrain + grit * 0.2) * hot;
	EMISSION = vec3(1.0, 0.42, 0.12) * crack * 3.0 + vec3(1.0, 0.6, 0.3) * hot * hot * 0.3;
}
