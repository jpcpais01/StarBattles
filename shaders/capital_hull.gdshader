// Capital-ship hull at kilometre scale. Same idea as hull.gdshader (object-
// space triplanar plating, vertex-colour material masks) with detail tiers
// sized for a 1.5 km ship: 30 m armour belts, 7.5 m plates, and rows of lit
// windows on the vertical walls that fade to an even glow far away.
// Damage adds scorch blotches and, near the end, glowing hull cracks.
//   COLOR: R = team paint, G = engine glow, B = dark metal, A = window density.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.56, 0.58, 0.62);
uniform vec3 paint_color : source_color = vec3(0.27, 0.72, 1.0);
uniform vec3 dark_color : source_color = vec3(0.07, 0.08, 0.1);
uniform vec3 glow_color : source_color = vec3(0.45, 0.85, 1.0);
uniform vec3 window_color : source_color = vec3(1.0, 0.86, 0.62);
uniform float glow_energy = 6.0;
uniform float window_energy = 3.2;
uniform float engine_power = 1.0;
uniform float damage = 0.0;
uniform float alert = 0.0;
uniform float lights_on = 1.0;

instance uniform float burn = 0.0;
instance uniform float flash = 0.0;

varying vec3 v_obj;
varying vec3 v_objn;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

float plate(vec2 uv, out float id) {
	uv.x += floor(uv.y) * 0.5;
	vec2 cell = floor(uv);
	id = hash3(vec3(cell, 7.0));
	vec2 g = abs(fract(uv) - 0.5);
	float e = max(g.x, g.y);
	float w = fwidth(uv.x) + fwidth(uv.y);
	return 1.0 - smoothstep(0.5 - 0.015 - w, 0.5, e);
}

// Triplanar plating at one scale: returns seam mask, writes plate id.
float plating(vec3 p, vec3 w, float s, out float pid) {
	float ix; float iy; float iz;
	float ex = plate(p.zy * s * vec2(1.0, 2.0), ix);
	float ey = plate(p.xz * s * vec2(2.0, 1.0), iy);
	float ez = plate(p.xy * s * vec2(2.0, 2.0), iz);
	pid = ix * w.x + iy * w.y + iz * w.z;
	return ex * w.x + ey * w.y + ez * w.z;
}

void vertex() {
	v_obj = VERTEX;
	v_objn = NORMAL;
}

void fragment() {
	vec3 n = normalize(v_objn);
	vec3 an = abs(n);
	vec3 w = pow(an, vec3(6.0));
	w /= (w.x + w.y + w.z);
	float big_id;
	float small_id;
	float big = plating(v_obj, w, 1.0 / 30.0, big_id);
	float small = plating(v_obj + 3.1, w, 1.0 / 7.5, small_id);
	float seams = mix(0.35, 1.0, big) * mix(0.72, 1.0, small);

	vec3 col = base_color * (0.8 + 0.22 * big_id + 0.1 * small_id);
	// Painted armour belts on some big plates as well as on painted pieces.
	float paint = max(COLOR.r, step(0.86, big_id) * (1.0 - COLOR.b));
	col = mix(col, paint_color * (0.8 + 0.2 * small_id), paint);
	col = mix(col, dark_color * (0.8 + 0.4 * small_id), COLOR.b);
	col *= seams;

	// Damage: scorch blotches spread as the hull weakens.
	float nz = noise3(v_obj / 38.0) * 0.65 + noise3(v_obj / 11.0) * 0.35;
	float scorch = smoothstep(1.0 - damage * 0.75, 1.05 - damage * 0.75, nz);
	col *= 1.0 - scorch * 0.7;
	col *= 1.0 - burn * 0.8;

	ALBEDO = col;
	METALLIC = mix(0.55, 0.2, paint) * (1.0 - COLOR.b * 0.3);
	ROUGHNESS = clamp(0.32 + 0.2 * small_id + (1.0 - big) * 0.3 + COLOR.b * 0.2 + scorch * 0.3 + burn * 0.3, 0.05, 1.0);
	SPECULAR = 0.5;

	// Windows: rows on walls, sparse lit cells; averaged out when tiny on screen.
	float wall = 1.0 - smoothstep(0.25, 0.45, an.y);
	vec2 wuv = (an.x > an.z ? v_obj.zy : v_obj.xy) * vec2(1.0 / 3.2, 1.0 / 2.4);
	vec2 cell = floor(wuv);
	vec2 f = fract(wuv);
	float row_on = step(0.55, hash3(vec3(floor(cell.y), floor(cell.x / 9.0), 3.0)));
	float lit = step(0.35, hash3(vec3(cell, 11.0))) * row_on;
	float shape = step(0.18, f.x) * step(f.x, 0.82) * step(0.3, f.y) * step(f.y, 0.7);
	float px = fwidth(wuv.x) + fwidth(wuv.y);
	float far_k = smoothstep(0.35, 1.2, px);
	float win = mix(lit * shape, 0.13, far_k) * wall * COLOR.a * big * (1.0 - COLOR.b) * (1.0 - paint * 0.7);
	vec3 wcol = mix(window_color, vec3(0.7, 0.85, 1.0), step(0.8, hash3(vec3(cell, 5.0))));
	float alive = lights_on * (1.0 - burn) * (1.0 - scorch);

	vec3 glow = mix(glow_color, vec3(1.0, 0.15, 0.08), alert * (0.55 + 0.45 * sin(TIME * 5.0)));
	EMISSION = glow * glow_energy * COLOR.g * engine_power;
	EMISSION += wcol * window_energy * win * alive;
	// Hot cracks open along plate seams as the hull fails.
	float crack = (1.0 - small) * smoothstep(0.55, 1.0, damage) * smoothstep(0.5, 0.8, nz) + burn * (1.0 - big) * 0.8;
	EMISSION += vec3(1.0, 0.38, 0.08) * crack * 6.0 * (0.75 + 0.25 * sin(TIME * 3.0 + nz * 20.0));
	EMISSION += vec3(1.0, 0.7, 0.5) * flash * 1.5;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION += paint_color * rim * 0.05;
}
