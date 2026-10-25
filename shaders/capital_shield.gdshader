// The mothership's shield bubble: a faint hex lattice that shimmers at
// grazing angles, lights up in ripples where shots splash against it (six
// ripple slots, newest overwrites oldest) and stutters apart as it collapses.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.35, 0.75, 1.0);
uniform vec4 hits[6];
uniform float power = 1.0;
uniform float collapse = 0.0;
uniform float strain = 0.0;

varying vec3 v_obj;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hex(vec2 p) {
	p.x *= 1.1547;
	p.y += mod(floor(p.x), 2.0) * 0.5;
	p = abs(fract(p) - 0.5);
	return abs(max(p.x * 1.5 + p.y, p.y * 2.0) - 1.0);
}

void vertex() {
	v_obj = normalize(VERTEX);
}

void fragment() {
	vec2 uv = vec2(atan(v_obj.x, v_obj.z) * 9.0, v_obj.y * 16.0);
	float lattice = 1.0 - smoothstep(0.0, 0.09, hex(uv));
	vec2 cell = floor(uv * vec2(1.1547, 1.0));
	float flick = hash2(cell + floor(TIME * 9.0));
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	float a = fres * (0.05 + 0.08 * lattice) * (1.0 + strain * 2.0 * step(0.7, flick));
	// Slow sweeping scan band.
	float band = smoothstep(0.06, 0.0, abs(fract(v_obj.y * 0.5 + TIME * 0.05) - 0.5) - 0.44);
	a += band * lattice * 0.05;
	for (int i = 0; i < 6; i++) {
		float t = TIME - hits[i].w;
		if (t < 0.0 || t > 2.5) {
			continue;
		}
		float d = distance(v_obj, normalize(hits[i].xyz));
		float ring = smoothstep(0.08, 0.0, abs(d - t * 0.35)) * exp(-t * 2.2);
		float splash = exp(-d * 18.0) * exp(-t * 5.0) * 2.5;
		a += (ring * (0.3 + lattice) + splash * (0.4 + lattice)) * 0.9;
	}
	// Collapse: cells drop out at random, the survivors flare.
	float gone = step(hash2(cell * 1.37), collapse);
	a *= (1.0 - gone) * (1.0 + collapse * 3.0 * step(0.5, flick));
	ALBEDO = color * a * power * 2.0;
}
