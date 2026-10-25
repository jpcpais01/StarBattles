// Camera-facing additive glow (engine cores, muzzle flashes, impacts).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.4, 0.8, 1.0);
uniform float energy = 3.0;
uniform float softness = 2.2;
instance uniform float intensity = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float g = pow(clamp(1.0 - d, 0.0, 1.0), softness);
	float core = pow(clamp(1.0 - d * 2.2, 0.0, 1.0), 3.0);
	ALBEDO = (color * g + vec3(1.0) * core * 0.8) * energy * intensity;
}
