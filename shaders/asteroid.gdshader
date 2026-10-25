// Rocky asteroid: triplanar fbm albedo and bump, crater pocking, mineral
// glints, and a glowing fracture rim right after it splits.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 rock_a : source_color = vec3(0.32, 0.29, 0.27);
uniform vec3 rock_b : source_color = vec3(0.17, 0.155, 0.15);
uniform vec3 rock_c : source_color = vec3(0.45, 0.4, 0.34);
uniform float scale = 0.08;
uniform float bump = 0.55;
instance uniform float hot = 0.0;
instance uniform float tint = 0.0;

varying vec3 v_obj;
varying vec3 v_objn;

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
float fbm(vec3 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.1 + 3.1; a *= 0.5; }
	return v;
}

void vertex() {
	v_obj = VERTEX;
	v_objn = NORMAL;
}

void fragment() {
	vec3 p = v_obj * scale;
	float h = fbm(p * 4.0);
	float hf = fbm(p * 16.0);
	// Bump from the fbm gradient (object space), rotated into view space.
	float e = 0.05;
	vec3 grad = vec3(fbm((p + vec3(e, 0, 0)) * 16.0) - hf, fbm((p + vec3(0, e, 0)) * 16.0) - hf, fbm((p + vec3(0, 0, e)) * 16.0) - hf) / e;
	vec3 on = normalize(v_objn - grad * bump * 0.08);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(on, 0.0)).xyz);

	vec3 col = mix(rock_b, rock_a, smoothstep(0.3, 0.7, h));
	col = mix(col, rock_c, smoothstep(0.62, 0.8, hf) * 0.6);
	col *= 0.75 + 0.5 * hf;
	col = mix(col, col * vec3(1.15, 0.95, 0.8), tint);
	float glint = step(0.985, hash(floor(v_obj * 2.5))) * 0.6;
	ALBEDO = col;
	ROUGHNESS = 0.82 - glint * 0.5;
	METALLIC = glint * 0.5;
	SPECULAR = 0.35;
	// Fresh fracture faces glow and cool down.
	float crack = smoothstep(0.55, 0.75, hf) * hot;
	EMISSION = vec3(1.0, 0.42, 0.12) * crack * 5.0 + vec3(1.0, 0.6, 0.3) * hot * hot * 0.5;
}
