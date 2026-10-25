// Home tile backdrop: rounded rect with a diagonal gradient, soft moving
// sheen and a glowing rim when focused.
shader_type canvas_item;

uniform vec4 color_a : source_color = vec4(0.1, 0.2, 0.4, 1.0);
uniform vec4 color_b : source_color = vec4(0.02, 0.04, 0.08, 1.0);
uniform vec4 rim : source_color = vec4(0.42, 0.82, 1.0, 1.0);
uniform float focus = 0.0;
uniform vec2 rect_size = vec2(300.0, 300.0);
uniform float radius = 22.0;

float rounded(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	float d = rounded(p, rect_size * 0.5, radius);
	float inside = 1.0 - smoothstep(-1.0, 0.5, d);
	float g = clamp(UV.x * 0.4 + (1.0 - UV.y) * 0.6, 0.0, 1.0);
	vec3 col = mix(color_b.rgb, color_a.rgb, g * (0.65 + focus * 0.35));
	float sheen = smoothstep(0.08, 0.0, abs(UV.x + UV.y * 0.6 - fract(TIME * 0.12) * 2.4 + 0.3)) * 0.12 * focus;
	col += sheen;
	col += vec3(1.0) * pow(1.0 - UV.y, 6.0) * 0.06;
	float edge = smoothstep(2.5, 0.0, abs(d + 1.0));
	col = mix(col, rim.rgb, edge * (0.18 + focus * 0.8));
	COLOR = vec4(col, inside * (0.82 + focus * 0.18));
}
