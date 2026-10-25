// Plasma bolt, one instance per shot in a MultiMesh. Each instance is a
// single quad rebuilt in the vertex shader as a camera-facing capsule
// stretched along the bolt's screen-space motion, so a bolt seen nose-on
// is a round, blinding point and one seen side-on a long streak, with no
// crossed-quad seams. White-hot head, coloured plasma sheath, a tail that
// cools and thins behind it.
// Instance transform: basis.x/y = width, basis.z = -dir * length, origin = centre.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform float energy = 1.0;

varying vec2 v_q;
varying float v_ratio;

void vertex() {
	vec3 centre = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	vec3 axis = (VIEW_MATRIX * vec4(MODEL_MATRIX[2].xyz, 0.0)).xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 vd = normalize(centre);
	vec3 ap = axis - vd * dot(axis, vd);
	float alen = length(ap);
	// Projected axis points from head to tail.
	vec3 along = alen > 1e-4 ? ap / alen : normalize(cross(vd, vec3(0.0, 1.0, 0.0)));
	vec3 side = normalize(cross(vd, along));
	float half_w = w * 1.15;
	float half_len = alen * 0.5 + half_w;
	vec2 local = VERTEX.xy * 2.0;
	VERTEX = centre + side * local.x * half_w + along * local.y * half_len;
	NORMAL = -vd;
	v_ratio = half_len / half_w;
	v_q = vec2(local.x, local.y * v_ratio);
}

void fragment() {
	float seg = max(v_ratio - 1.0, 0.0);
	// Distance to the bolt's spine, in half-widths.
	float d = length(vec2(v_q.x, max(abs(v_q.y) - seg, 0.0)));
	// 0 at the tail tip, 1 at the head (-y is the head).
	float h = clamp((-v_q.y + v_ratio) / (2.0 * v_ratio), 0.0, 1.0);
	float sheath = exp(-d * d * 3.2) * (0.18 + 0.82 * pow(h, 1.6));
	float core = exp(-d * d * 22.0) * smoothstep(0.15, 0.85, h);
	float head = exp(-length(vec2(v_q.x, v_q.y + seg)) * 3.0) * 0.6;
	vec3 hot = mix(COLOR.rgb, vec3(1.0), 0.65);
	ALBEDO = (COLOR.rgb * sheath * 1.25 + hot * (core * 1.9 + head)) * energy * COLOR.a;
}
