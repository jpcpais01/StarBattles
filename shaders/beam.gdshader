// Energy beam / rail tracer on a unit cylinder stretched along -Z.
// A thin white-hot filament wrapped in an ionised sheath: the sheath
// ripples with a travelling helix and frays out as the beam fades.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.35, 0.85);
instance uniform float intensity = 1.0;
instance uniform float beam_length = 100.0;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float edge = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float core = pow(edge, 10.0);
	float sheath = pow(edge, 2.2);
	float z = -v_obj.z * beam_length;
	float ang = atan(v_obj.y, v_obj.x);
	float helix = 0.5 + 0.5 * sin(ang * 2.0 + z * 0.25 - TIME * 40.0);
	float flow = 0.7 + 0.3 * sin(z * 0.11 - TIME * 55.0);
	// Fray: patchy sheath as the beam weakens.
	float fray = mix(1.0, smoothstep(0.2, 0.8, helix), clamp(1.0 - intensity, 0.0, 1.0));
	vec3 c = color * sheath * (0.6 + 0.6 * helix) * flow * fray * 1.6 + vec3(1.0) * core * 1.8;
	// Soften the very start so it grows out of the muzzle.
	c *= smoothstep(0.0, 3.0, z);
	ALBEDO = c * intensity;
}
