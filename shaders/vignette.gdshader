// Screen vignette + subtle left-side gradient for menu legibility.
shader_type canvas_item;

uniform float strength = 0.7;
uniform float left_shade = 0.55;

void fragment() {
	vec2 uv = UV - 0.5;
	float v = smoothstep(0.35, 0.95, length(uv * vec2(1.4, 1.0)));
	float l = smoothstep(0.75, 0.0, UV.x) * left_shade;
	float b = smoothstep(0.55, 1.0, UV.y) * 0.5;
	COLOR = vec4(0.0, 0.005, 0.015, clamp(v * strength + l + b, 0.0, 0.95));
}
