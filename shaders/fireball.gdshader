// Explosion fireball billboard. Shaded as a puffy sphere: domain-warped
// turbulence defines the billowing silhouette, a blackbody ramp takes the
// core from white through yellow and orange to deep red, and as it cools
// the cloud turns to soot that is lit by the real sun direction (bright
// rim toward the sun, dark self-shadowed side). "life" runs 0 -> 1.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

global uniform vec3 sun_dir;
instance uniform float life = 0.0;
instance uniform float seed = 0.0;
uniform float energy = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.3, 7.1); a *= 0.5; }
	return v;
}

// Approximate blackbody colour for t in 0..1 (≈ 800 K .. 6500 K).
vec3 blackbody(float t) {
	vec3 c = vec3(1.0, 0.18, 0.02);
	c = mix(c, vec3(1.0, 0.45, 0.08), smoothstep(0.15, 0.45, t));
	c = mix(c, vec3(1.0, 0.78, 0.38), smoothstep(0.45, 0.75, t));
	c = mix(c, vec3(1.0, 0.96, 0.9), smoothstep(0.75, 1.0, t));
	return c;
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 uv = (UV - 0.5) * 2.0;
	float r = length(uv);
	vec2 sd = vec2(seed * 17.0, seed * 31.0);
	// Billowing: warp the domain, and let the cloud roll outward over time.
	vec2 w = vec2(fbm(uv * 2.2 + sd + life * 0.8), fbm(uv * 2.2 + sd.yx - life * 0.6)) - 0.5;
	float n = fbm(uv * 3.2 + w * 1.6 + sd - normalize(uv + 1e-4) * life * 1.2);
	float edge = 0.62 + (n - 0.5) * 0.9 + life * 0.12;
	float shape = 1.0 - smoothstep(edge - 0.2, edge, r);
	if (shape <= 0.002) {
		discard;
	}
	// Pseudo-sphere normal for lighting the soot.
	float z = sqrt(max(1.0 - min(r / max(edge, 0.05), 1.0), 0.0));
	vec3 nv = normalize(vec3(uv + w * 0.8, z * 1.3));
	vec3 l = normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz);
	float lit = clamp(dot(nv, l) * 0.6 + 0.45, 0.0, 1.0);
	// Temperature: hottest early and deep inside; cools from the edge in.
	float heat = clamp(0.95 - life * 3.2 + (1.0 - r) * 0.35 + (n - 0.5) * 0.9, 0.0, 1.0);
	float glow = smoothstep(0.05, 0.45, heat);
	vec3 soot = vec3(0.07, 0.065, 0.06) * (0.35 + 1.1 * lit) + vec3(0.6, 0.18, 0.03) * glow * 0.4;
	vec3 fire = blackbody(heat * 0.92) * (0.3 + heat * heat * 1.1) * energy;
	ALBEDO = mix(soot, fire, glow);
	float fade = 1.0 - smoothstep(0.5, 1.0, life);
	ALPHA = shape * fade * mix(0.85, 1.0, glow);
}
