// Procedural hard-surface hull: object-space triplanar panel lines with
// staggered plating, per-panel tint/roughness variation, brushed micro
// detail and edge wear. Vertex colour drives material regions:
//   R = team paint, G = emissive strips, B = dark metal, A = heat mask.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.6, 0.62, 0.66);
uniform vec3 paint_color : source_color = vec3(0.27, 0.72, 1.0);
uniform vec3 dark_color : source_color = vec3(0.09, 0.1, 0.12);
uniform vec3 glow_color : source_color = vec3(0.45, 0.85, 1.0);
uniform float glow_energy = 5.0;
uniform float panel_scale = 0.85;
uniform float metallic_base = 0.55;
uniform float wear = 0.4;
// Optional low-res colour guide (e.g. a 1k Meshy bake) multiplied in.
uniform sampler2D color_mask : source_color, hint_default_white, filter_linear_mipmap;
uniform float color_mask_strength = 0.0;

instance uniform float heat = 0.0;
instance uniform float flash = 0.0;
instance uniform float burn = 0.0;

varying vec3 v_obj;
varying vec3 v_objn;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// 1 inside a plate, ~0 on the seam. Soft width keeps it alias-free.
float plate(vec2 uv, out float id) {
	uv.x += floor(uv.y) * 0.5;
	vec2 cell = floor(uv);
	id = hash3(vec3(cell, 7.0));
	vec2 g = abs(fract(uv) - 0.5);
	float e = max(g.x, g.y);
	float w = fwidth(uv.x) + fwidth(uv.y);
	return 1.0 - smoothstep(0.5 - 0.02 - w, 0.5, e);
}

void vertex() {
	v_obj = VERTEX;
	v_objn = NORMAL;
}

void fragment() {
	vec3 n = abs(normalize(v_objn));
	vec3 w = pow(n, vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec3 p = v_obj * panel_scale;
	float idx; float idy; float idz;
	float ex = plate(p.zy * vec2(1.0, 2.2), idx);
	float ey = plate(p.xz * vec2(2.2, 1.0), idy);
	float ez = plate(p.xy * vec2(2.0, 2.0), idz);
	float edge = ex * w.x + ey * w.y + ez * w.z;
	float pid = idx * w.x + idy * w.y + idz * w.z;

	// Brushed streaks along the hull length.
	float brushed = hash3(floor(v_obj * vec3(3.0, 60.0, 0.6))) * 0.5 + hash3(floor(v_obj * vec3(1.5, 140.0, 0.3))) * 0.5;

	vec3 col = base_color * (0.86 + 0.24 * pid);
	col = mix(col, paint_color * (0.9 + 0.15 * pid), COLOR.r);
	col = mix(col, dark_color, COLOR.b);
	col *= mix(0.42, 1.0, edge);
	col *= 0.94 + 0.08 * brushed;
	if (color_mask_strength > 0.0) {
		col *= mix(vec3(1.0), texture(color_mask, UV).rgb * 1.6, color_mask_strength);
	}
	// Edge wear: brighter scuffs where plates meet on painted areas.
	float scuff = smoothstep(0.75, 1.0, hash3(floor(v_obj * 9.0))) * (1.0 - edge) * wear;
	col = mix(col, base_color * 1.25, scuff * COLOR.r);
	col *= 1.0 - burn * 0.75;

	ALBEDO = col;
	METALLIC = mix(metallic_base, 0.2, COLOR.r) * (1.0 - COLOR.b * 0.3);
	ROUGHNESS = clamp(0.3 + 0.25 * pid * wear + (1.0 - edge) * 0.35 + brushed * 0.08 + COLOR.b * 0.2 + burn * 0.3, 0.05, 1.0);
	SPECULAR = 0.55;
	vec3 hot = mix(vec3(1.0, 0.25, 0.05), vec3(1.0, 0.8, 0.5), heat * heat);
	EMISSION = glow_color * glow_energy * COLOR.g + hot * heat * heat * 7.0 * COLOR.a + vec3(1.0, 0.7, 0.5) * flash * 2.5;
	// Faint rim so silhouettes read against black space.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION += paint_color * rim * 0.06;
}
