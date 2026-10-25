// Saturn's rings on an annulus in the planet's equatorial plane, radius in
// planet radii. Density profile follows the real D/C/B/A/F structure with
// the Cassini division and Encke gap, plus thousands of fine ringlets.
// Lit side vs. unlit side and forward scattering are handled separately,
// and the planet's shadow falls across them.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

global uniform vec3 sun_dir;
uniform float brightness = 1.5;

varying vec3 v_local;

float hash1(float x) { return fract(sin(x * 127.1) * 43758.5453); }
float vnoise(float x) {
	float i = floor(x); float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash1(i), hash1(i + 1.0), f);
}

float density(float r) {
	float d = 0.0;
	d += smoothstep(1.11, 1.12, r) * (1.0 - smoothstep(1.235, 1.24, r)) * 0.04;          // D
	d += smoothstep(1.239, 1.25, r) * (1.0 - smoothstep(1.52, 1.527, r)) * (0.16 + 0.08 * vnoise(r * 180.0)); // C
	d += smoothstep(1.525, 1.54, r) * (1.0 - smoothstep(1.945, 1.951, r)) * (0.72 + 0.26 * vnoise(r * 90.0)); // B
	d += smoothstep(1.951, 1.96, r) * (1.0 - smoothstep(2.02, 2.027, r)) * 0.05;         // Cassini division
	d += smoothstep(2.026, 2.035, r) * (1.0 - smoothstep(2.262, 2.269, r)) * (0.5 + 0.15 * vnoise(r * 120.0)); // A
	d *= 1.0 - (1.0 - smoothstep(0.0, 0.004, abs(r - 2.214))) * 0.95;                    // Encke gap
	d *= 1.0 - (1.0 - smoothstep(0.0, 0.0015, abs(r - 2.265))) * 0.9;                    // Keeler gap
	d += (1.0 - smoothstep(0.0, 0.004, abs(r - 2.326))) * 0.35;                          // F ring
	d *= 0.82 + 0.18 * vnoise(r * 1400.0) + 0.1 * (vnoise(r * 5200.0) - 0.5);
	return clamp(d, 0.0, 1.0);
}

vec3 ring_color(float r) {
	vec3 c_ring = vec3(0.55, 0.5, 0.45);
	vec3 b_ring = vec3(0.93, 0.85, 0.7);
	vec3 a_ring = vec3(0.78, 0.74, 0.68);
	vec3 col = mix(c_ring, b_ring, smoothstep(1.5, 1.6, r));
	col = mix(col, a_ring, smoothstep(1.97, 2.05, r));
	return col * (0.9 + 0.2 * vnoise(r * 300.0));
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float r = length(v_local.xz);
	float d = density(r);
	if (d < 0.003) {
		discard;
	}
	vec3 L = normalize(sun_dir);
	vec3 n = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 V = normalize(cam - wp);

	// Planet shadow.
	vec3 center = NODE_POSITION_WORLD;
	float radius = length(MODEL_MATRIX[0].xyz);
	vec3 oc = wp - center;
	float b = dot(oc, L);
	float c = dot(oc, oc) - radius * radius;
	float disc = b * b - c;
	float shadow = 1.0;
	if (disc > 0.0 && -b - sqrt(disc) > 0.0) {
		shadow = 0.04;
	}

	float sl = dot(L, n);
	float sv = dot(V, n);
	vec3 col = ring_color(r);
	float lit;
	if (sign(sl) == sign(sv)) {
		lit = 0.35 + 0.65 * abs(sl);
	} else {
		// Seen from the unlit face: light filters through sparse regions.
		float fwd = pow(max(dot(-V, L), 0.0), 3.0);
		lit = (d * (1.0 - d) * 1.8 + fwd * 0.6) * (0.4 + abs(sl));
	}
	ALBEDO = col * lit * shadow * brightness;
	ALPHA = d * 0.95;
}
