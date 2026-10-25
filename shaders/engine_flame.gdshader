// Engine exhaust plume on a cone pointing down +Z (UV.y = 0 at nozzle).
// Scrolling turbulence, white-hot core, shock diamonds when boosting.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.35, 0.75, 1.0);
instance uniform float thrust = 0.5;
instance uniform float boost = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float along = UV.y;
	float around = UV.x;
	float n = noise(vec2(around * 12.0, along * 6.0 - TIME * 14.0)) * 0.6 + noise(vec2(around * 30.0, along * 14.0 - TIME * 30.0)) * 0.4;
	float edge = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float core = pow(edge, 2.5);
	float fade = pow(1.0 - along, 1.6 + (1.0 - thrust) * 2.0);
	float diamonds = boost * pow(0.5 + 0.5 * cos(along * 38.0 - TIME * 6.0), 6.0) * (1.0 - along);
	vec3 hot = mix(color, vec3(1.0), core * 0.8);
	float intensity = (0.25 + 0.75 * thrust + boost * 0.8) * fade * (0.55 + 0.45 * n) * (0.25 + core);
	ALBEDO = hot * intensity * 3.5 + vec3(1.0) * diamonds * 2.5;
}
