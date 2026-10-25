// Capture field around a relay station: a faint sensor bubble drawn as a
// fine latitude/longitude graticule that only shows at grazing angles
// (like a soap film), a slow sweep that circles it, and the capture
// progress as luminous "fill" rising from the bottom with a rippling
// meniscus. Contested zones flicker with interference. Seen from inside,
// everything drops to a whisper so it never blocks the fight.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.8, 0.85, 0.95);
uniform vec3 capture_color : source_color = vec3(0.27, 0.72, 1.0);
uniform float progress = 0.0;
uniform float contested = 0.0;

varying vec3 v_local;

float aa_line(float x, float w) {
	float f = abs(fract(x) - 0.5);
	float fw = fwidth(x);
	return 1.0 - smoothstep(w * fw, (w + 1.5) * fw, 0.5 - f);
}

void vertex() {
	v_local = normalize(VERTEX);
}

void fragment() {
	float radius = length(MODEL_MATRIX[0].xyz);
	float inside = step(distance(CAMERA_POSITION_WORLD, NODE_POSITION_WORLD), radius);
	float ndv = abs(dot(NORMAL, VIEW));
	float fres = pow(1.0 - ndv, 3.0);
	float lon = atan(v_local.x, v_local.z) / 6.2831853 + TIME * 0.004;
	float lat = asin(clamp(v_local.y, -1.0, 1.0)) / 3.1415927;
	float grid = max(aa_line(lon * 24.0, 0.4), aa_line(lat * 12.0, 0.4));
	float sweep_a = fract(lon - TIME * 0.05);
	float sweep = exp(-sweep_a * 18.0) * 0.8 + exp(-(1.0 - sweep_a) * 120.0);

	float fill_h = progress * 2.0 - 1.0 + step(0.995, progress) * 0.2;
	float wave = sin(lon * 6.2831853 * 6.0 + TIME * 2.0) * 0.015 + sin(lon * 6.2831853 * 11.0 - TIME * 3.1) * 0.008;
	float level = v_local.y - fill_h - wave;
	float filled = 1.0 - smoothstep(-0.005, 0.005, level);
	float active = step(0.005, progress) * step(progress, 0.995);
	float meniscus = exp(-pow(level * 70.0, 2.0)) * active;
	vec3 c = mix(color, capture_color, filled);

	float flick = contested * (0.5 + 0.5 * sin(TIME * 23.0 + v_local.y * 40.0)) * step(0.5, fract(TIME * 3.0 + lon * 4.0));
	float a = fres * 0.16 + grid * (0.012 + fres * 0.22) + sweep * grid * 0.3 * fres + filled * (0.03 + fres * 0.3) + meniscus * 1.1;
	a *= 1.0 + flick * 1.2;
	a *= mix(1.0, 0.18, inside);
	ALBEDO = c * a;
}
