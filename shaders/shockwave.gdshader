// Explosion shock front: a thin, ragged ring of glowing ionised gas that
// races outward and fades, with a faint inner haze.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.7, 0.45);
instance uniform float life = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float rag = noise(vec2(a * 9.0, life * 4.0)) * 0.06 + noise(vec2(a * 31.0, 3.0)) * 0.03;
	float ring = exp(-pow((r - 0.86 - rag) * 28.0, 2.0));
	float haze = smoothstep(0.9, 0.2, r) * 0.12;
	float k = (1.0 - life);
	ALBEDO = color * (ring * (0.6 + 0.6 * noise(vec2(a * 14.0, 1.0))) + haze) * k * k * 1.6;
}
