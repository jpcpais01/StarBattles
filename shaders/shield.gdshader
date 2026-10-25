// Energy shield shell: invisible until hit, then a hex-patterned ripple
// expands from the impact point. Shows faintly while regenerating.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.4, 0.8, 1.0);
uniform vec3 hit_pos = vec3(0.0, 0.0, -1.0);
uniform float hit_time = -10.0;
uniform float strength = 1.0;
uniform float regen = 0.0;

varying vec3 v_obj;

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
	float t = TIME - hit_time;
	float d = distance(v_obj, normalize(hit_pos));
	float ring = smoothstep(0.25, 0.0, abs(d - t * 3.2)) * exp(-t * 3.0);
	float splash = exp(-d * 5.0) * exp(-t * 6.0) * 2.0;
	vec2 uv = vec2(atan(v_obj.x, v_obj.z) * 3.0, v_obj.y * 6.0);
	float h = 1.0 - smoothstep(0.0, 0.12, hex(uv * 1.6));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float a = (ring * (0.4 + h) + splash * (0.5 + h)) * strength + fres * regen * 0.25 * (0.5 + h);
	ALBEDO = color * a * 2.0;
}
