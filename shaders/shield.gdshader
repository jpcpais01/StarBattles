// Ship energy shield. Invisible until struck: the impact point flares,
// hexagonal cells light up in a wave that races across the bubble (each
// cell with its own flicker and delay), a thin refractive-looking rim
// shimmers over the whole shell, and it all decays in under a second.
// While recharging, a faint lattice scans across the grazing edges.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.4, 0.8, 1.0);
uniform vec3 hit_pos = vec3(0.0, 0.0, -1.0);
uniform float hit_time = -10.0;
uniform float strength = 1.0;
uniform float regen = 0.0;

varying vec3 v_obj;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Distance to the hex cell edge (0 on the edge) and the cell id.
vec3 hexcell(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	vec4 c = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, hc.xy) : vec4(h.zw, hc.zw + 9.5);
	vec2 a = abs(c.xy);
	float edge = 0.5 - max(dot(a, s * 0.5), a.x);
	return vec3(edge, c.zw);
}

void vertex() {
	v_obj = normalize(VERTEX);
}

void fragment() {
	float t = TIME - hit_time;
	vec3 hp = normalize(hit_pos);
	float d = distance(v_obj, hp);
	// Equal-area-ish projection keeps cells similar in size over the shell.
	vec2 uv = vec2(atan(v_obj.x, v_obj.z) * 2.2, v_obj.y * 4.4) * 2.0;
	vec3 hx = hexcell(uv);
	float lattice = 1.0 - smoothstep(0.0, 0.06, hx.x);
	float rnd = hash2(hx.yz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	float a = 0.0;
	if (t < 1.4) {
		// Ripple front.
		float front = t * 2.6;
		float ring = exp(-pow((d - front) * 9.0, 2.0)) * exp(-t * 3.2);
		// Cells light as the front passes, each a little late, then die.
		float lag = d / 2.6 + rnd * 0.08;
		float cell_t = t - lag;
		float cell = step(0.0, cell_t) * exp(-max(cell_t, 0.0) * 7.0) * (0.5 + 0.5 * rnd);
		float flare = exp(-d * d * 60.0) * exp(-t * 12.0);
		float shell = fres * exp(-t * 4.0) * 0.35;
		a = ring * (0.35 + lattice * 0.9) + cell * (0.15 + lattice) * smoothstep(1.6, 0.2, d) * 0.6 + flare * 0.55 + shell;
		a *= strength;
	}
	// Recharge shimmer.
	float scan = smoothstep(0.1, 0.0, abs(fract(v_obj.y * 0.5 - TIME * 0.4) - 0.5));
	a += regen * fres * (0.12 + lattice * 0.35 + scan * lattice * 0.6) * (0.7 + 0.3 * rnd);
	vec3 c = mix(color, vec3(0.85, 0.95, 1.0), clamp(a * 0.4, 0.0, 0.6));
	ALBEDO = c * a * 0.75;
}
