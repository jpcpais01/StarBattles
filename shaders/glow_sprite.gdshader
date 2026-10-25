// Camera-facing additive glow (engine cores, muzzle flashes, impacts).
// Physically shaped falloff: a tight inverse-square core plus a wide soft
// halo, with faint diffraction spikes on the brightest flashes.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.4, 0.8, 1.0);
uniform float energy = 3.0;
uniform float softness = 2.2;
uniform float spikes = 0.0;
instance uniform float intensity = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = length(p);
	float fade = 1.0 - smoothstep(0.7, 1.0, d);
	float halo = pow(clamp(1.0 - d, 0.0, 1.0), softness);
	float core = 0.012 / (d * d + 0.012) * fade;
	float sp = spikes * fade * (exp(-abs(p.x) * 60.0) + exp(-abs(p.y) * 60.0)) * pow(clamp(1.0 - d, 0.0, 1.0), 1.5);
	ALBEDO = (color * halo * 0.55 + mix(color, vec3(1.0), 0.7) * (core * 0.5 + sp)) * energy * intensity * 0.5;
}
