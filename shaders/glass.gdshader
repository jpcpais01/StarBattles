// Cockpit canopy: deep tinted glass with sharp specular, fresnel sheen and
// a faint interior HUD glow.
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.04, 0.08, 0.14);
uniform vec3 glow : source_color = vec3(0.35, 0.8, 1.0);

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = tint;
	METALLIC = 0.85;
	ROUGHNESS = 0.06;
	SPECULAR = 1.0;
	EMISSION = glow * (0.05 + f * 0.35);
}
