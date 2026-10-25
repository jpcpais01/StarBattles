// Explosion fireball billboard: animated fbm with temperature gradient
// from white-hot through orange to smoke. "life" goes 0 -> 1.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

instance uniform float life = 0.0;
instance uniform float seed = 0.0;
uniform float energy = 6.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.07; a *= 0.5; }
	return v;
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv) * 2.0;
	float n = fbm(uv * 4.0 + vec2(seed * 13.0, seed * 7.0) + life * 1.5);
	float shape = 1.0 - smoothstep(0.35 + n * 0.5, 0.75 + n * 0.4, r);
	float temp = clamp(1.0 - life * 1.6 + (1.0 - r) * 0.4 + n * 0.3, 0.0, 1.0);
	vec3 smoke = vec3(0.09, 0.085, 0.08);
	vec3 fire = mix(vec3(0.9, 0.18, 0.03), vec3(1.0, 0.65, 0.2), smoothstep(0.3, 0.7, temp));
	fire = mix(fire, vec3(1.0, 0.95, 0.85), smoothstep(0.8, 1.0, temp));
	float glow = smoothstep(0.25, 0.6, temp);
	vec3 c = mix(smoke, fire * energy, glow);
	ALBEDO = c;
	ALPHA = shape * (1.0 - smoothstep(0.55, 1.0, life)) * (0.6 + 0.4 * glow);
}
