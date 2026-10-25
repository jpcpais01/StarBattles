// Saturn: subtle latitudinal cloud bands with turbulent edges, the polar
// hexagon, limb darkening, a thin forward-scattering haze at the limb and
// the shadow the rings cast across the globe. Lit analytically from the
// global sun direction (unshaded so it never depends on scene lights).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled, depth_draw_opaque;

global uniform vec3 sun_dir;
uniform vec3 ring_normal = vec3(0.0, 1.0, 0.0);
uniform float ring_inner = 1.24;
uniform float ring_outer = 2.27;
uniform vec3 band_light : source_color = vec3(0.92, 0.84, 0.64);
uniform vec3 band_mid : source_color = vec3(0.82, 0.68, 0.45);
uniform vec3 band_dark : source_color = vec3(0.62, 0.48, 0.3);
uniform vec3 pole_color : source_color = vec3(0.45, 0.52, 0.55);
uniform float brightness = 1.6;

varying vec3 v_local;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Mirrors the ring density profile so shadows line up with the rings.
float ring_density(float r) {
	float d = 0.0;
	d += smoothstep(1.24, 1.26, r) * (1.0 - smoothstep(1.52, 1.53, r)) * 0.22;
	d += smoothstep(1.52, 1.54, r) * (1.0 - smoothstep(1.94, 1.95, r)) * 0.9;
	d += smoothstep(2.02, 2.03, r) * (1.0 - smoothstep(2.26, 2.27, r)) * 0.6;
	return d;
}

void vertex() {
	v_local = normalize(VERTEX);
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 L = normalize(sun_dir);
	vec3 V = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);

	float lat = v_local.y;
	float lon = atan(v_local.z, v_local.x);
	// Turbulent band coordinate: latitude warped by longitudinal noise.
	float warp = noise(vec3(lon * 3.0, lat * 18.0, 0.0)) * 0.025 + noise(vec3(lon * 9.0, lat * 50.0, 4.0)) * 0.008;
	float b = lat + warp;
	float bands = sin(b * 42.0) * 0.5 + 0.5;
	float fine = sin(b * 130.0 + noise(vec3(lon * 6.0, b * 80.0, 1.0)) * 2.0) * 0.5 + 0.5;
	vec3 col = mix(band_mid, band_light, bands);
	col = mix(col, band_dark, smoothstep(0.55, 1.0, fine) * 0.25);
	// Darker equatorial belts and the bluish north polar region + hexagon.
	col = mix(col, band_dark, smoothstep(0.25, 0.05, abs(lat - 0.18)) * 0.25);
	float hex_r = length(v_local.xz);
	float hex_a = atan(v_local.z, v_local.x);
	float hexagon = cos(3.14159 / 6.0) / cos(mod(hex_a, 1.0472) - 0.5236);
	float pole = smoothstep(0.82, 0.95, lat);
	col = mix(col, pole_color, pole * 0.7);
	col = mix(col, pole_color * 0.7, smoothstep(0.02, 0.0, abs(hex_r - 0.3 * hexagon)) * step(0.0, lat) * 0.6);
	col *= 0.92 + 0.16 * noise(v_local * 24.0);

	float ndl = dot(wn, L);
	float diffuse = smoothstep(-0.08, 0.35, ndl) * (0.25 + 0.75 * clamp(ndl, 0.0, 1.0));
	float ndv = clamp(dot(wn, V), 0.0, 1.0);
	float limb = pow(ndv, 0.35);

	// Ring shadow: march toward the sun and find where we cross the ring plane.
	vec3 center = NODE_POSITION_WORLD;
	float radius = length(MODEL_MATRIX[0].xyz);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rn = normalize((MODEL_MATRIX * vec4(ring_normal, 0.0)).xyz);
	float denom = dot(L, rn);
	float shadow = 1.0;
	if (abs(denom) > 0.0001) {
		float t = dot(center - wp, rn) / denom;
		if (t > 0.0) {
			float r = length(wp + L * t - center) / radius;
			shadow = 1.0 - ring_density(r) * 0.85;
		}
	}

	vec3 lit = col * diffuse * limb * shadow * brightness;
	// Thin haze glowing at the sunlit limb.
	float haze = pow(1.0 - ndv, 5.0) * smoothstep(-0.2, 0.4, ndl);
	lit += vec3(0.95, 0.8, 0.55) * haze * 0.35;
	// Faint ringshine on the night side.
	lit += col * 0.015 * (1.0 - diffuse);
	ALBEDO = lit;
}
