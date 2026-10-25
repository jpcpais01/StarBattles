// Expanding shock ring for explosions.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.7, 0.45);
instance uniform float life = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.08, 0.0, abs(r - 0.85)) + smoothstep(0.4, 0.0, abs(r - 0.8)) * 0.25;
	ALBEDO = color * ring * (1.0 - life) * (1.0 - life) * 3.0;
}
