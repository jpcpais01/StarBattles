// Jupiter and the Galilean moons, ray-traced inside a low-poly proxy sphere.
// The proxy only bounds the body: every pixel intersects the true ellipsoid
// in object space, so limbs are perfectly round at any size, Jupiter keeps
// its real 6.5 % polar flattening, and the edge is anti-aliased analytically.
// Surface colour comes from NASA global maps (public domain) with
// procedural detail layered on top so close-ups stay sharp. Lit
// analytically from the global sun direction plus Jupitershine.
//   kind 0 Jupiter · 1 Europa · 2 Io · 3 Ganymede · 4 Callisto
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

global uniform vec3 sun_dir;
uniform int kind = 1;
uniform sampler2D surface_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Body radius inside the unit proxy (the proxy is slightly larger).
uniform float body_scale = 0.95;
uniform float lon_offset = 0.0;
uniform float brightness = 1.0;
// Direction (world) and strength of light reflected from Jupiter.
uniform vec3 jupiter_dir = vec3(0.0, 0.0, -1.0);
uniform float jupiter_shine = 0.0;
uniform vec3 tint_light : source_color = vec3(0.9, 0.88, 0.84);
uniform vec3 tint_dark : source_color = vec3(0.55, 0.38, 0.26);
uniform float detail = 1.0;

varying vec3 v_obj;
varying vec3 v_cam;
varying vec3 v_n0;
varying vec3 v_n1;
varying vec3 v_n2;

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

float fbm(vec3 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += a * noise(p);
		p = p * 2.07 + vec3(1.7, 9.2, 4.1);
		a *= 0.5;
	}
	return v;
}

// Sharp crests: thin bright/dark lines like Europa's lineae.
float ridged(vec3 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += a * pow(1.0 - abs(noise(p) * 2.0 - 1.0), 8.0);
		p = p * 2.3 + vec3(3.1, 1.3, 7.7);
		a *= 0.55;
	}
	return v;
}

// Equirectangular lookup without the mip seam where atan() wraps.
vec4 sample_map(vec3 n) {
	float lon = atan(n.z, n.x) / 6.2831853 + 0.5 + lon_offset;
	float lat = asin(clamp(n.y, -1.0, 1.0)) / 3.1415927;
	vec2 uv = vec2(lon, 0.5 - lat);
	vec2 uv2 = vec2(fract(lon + 0.5) - 0.5, uv.y);
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 dx2 = dFdx(uv2);
	vec2 dy2 = dFdy(uv2);
	if (dot(dx2, dx2) + dot(dy2, dy2) < dot(dx, dx) + dot(dy, dy)) {
		dx = dx2;
		dy = dy2;
	}
	return textureGrad(surface_map, uv, dx, dy);
}

void vertex() {
	v_obj = VERTEX;
	v_cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	mat3 nm = transpose(inverse(mat3(MODEL_MATRIX)));
	v_n0 = nm[0];
	v_n1 = nm[1];
	v_n2 = nm[2];
}

void fragment() {
	vec3 ro = v_cam;
	vec3 rd = normalize(v_obj - v_cam);
	float b = dot(ro, rd);
	float ro2 = dot(ro, ro);
	// Closest approach of the view ray to the centre, in body radii.
	float miss = sqrt(max(ro2 - b * b, 0.0)) / body_scale;
	float px = max(fwidth(miss), 1e-5);
	// Sub-pixel bodies keep a stable minimum footprint, dimmed so the
	// total light they send stays physically right.
	float r_eff = max(1.0, px * 1.6);
	float coverage = clamp((r_eff - miss) / px + 0.5, 0.0, 1.0);
	if (coverage <= 0.0) {
		discard;
	}
	float energy = 1.0 / (r_eff * r_eff);
	float m = min(miss / r_eff, 0.9999);
	// Hit point on the unit body: along the ray, or the limb point when the
	// ray only grazes (anti-aliasing fringe).
	float th = sqrt(max(1.0 - m * m, 0.0));
	vec3 c_pt = ro + rd * (-b);
	vec3 closest = c_pt / max(length(c_pt), 1e-6);
	vec3 n_obj = normalize(closest * m - rd * th);

	mat3 nm = mat3(v_n0, v_n1, v_n2);
	vec3 N = normalize(nm * n_obj);
	vec3 L = normalize(sun_dir);
	vec3 V = normalize(CAMERA_POSITION_WORLD - NODE_POSITION_WORLD);
	float ndl = dot(N, L);
	float ndv = max(dot(N, V), 0.0);

	vec3 col;
	float lit;
	if (kind == 0) {
		// --- Jupiter -------------------------------------------------
		// Small zonal shear and eddies on top of the map so the belts read
		// as moving cloud rather than a printed texture.
		float lat = n_obj.y;
		vec3 q = n_obj * 9.0;
		float eddy = fbm(q + vec3(0.0, 0.0, TIME * 0.002), 4) - 0.5;
		vec3 warped = normalize(n_obj + vec3(eddy * 0.018, 0.0, eddy * 0.018) * detail);
		col = sample_map(warped).rgb;
		// Voyager colours run hot: pull toward the softer Juno/Cassini palette.
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(luma), col, 0.78) * vec3(1.02, 0.97, 0.9);
		col *= 0.9 + 0.2 * fbm(n_obj * vec3(40.0, 160.0, 40.0), 3) * detail;
		// The map smears near the poles: blend into the bluish-grey polar hoods.
		float polar = smoothstep(0.72, 0.9, abs(lat));
		vec3 hood = vec3(0.45, 0.45, 0.47) * (0.85 + 0.3 * fbm(n_obj * 26.0, 3));
		col = mix(col, hood, polar);
		col *= 0.95;
		// Cloud tops: soft terminator through the atmosphere, Minnaert
		// limb darkening, faint forward-scattering haze along the limb.
		float d = smoothstep(-0.06, 0.25, ndl) * pow(max(ndl, 0.0), 0.15);
		float k = 0.82;
		lit = pow(max(ndl, 0.0), k) * pow(max(ndv, 0.02), k - 1.0) * 0.82;
		lit = mix(d * 0.4, lit, smoothstep(0.0, 0.2, ndl));
		vec3 haze = vec3(0.55, 0.62, 0.75) * pow(1.0 - ndv, 6.0) * smoothstep(-0.1, 0.3, ndl) * 0.25;
		col = col * lit + haze;
	} else {
		// --- Galilean moons ------------------------------------------
		vec4 s = sample_map(n_obj);
		float g = s.r;
		float h = 0.0;
		if (kind == 1) {
			// Europa: bright water ice crossed by rusty lineae; the map's
			// dark strokes become the reddish-brown ridges.
			float lines = smoothstep(0.42, 0.04, g);
			float fine = ridged(n_obj * 22.0, 3) * detail;
			float mott = fbm(n_obj * 6.0, 4);
			col = mix(tint_light, tint_light * vec3(0.93, 0.88, 0.8), mott);
			col = mix(col, tint_dark, clamp(lines * 0.55 + fine * 0.1 * (0.4 + mott), 0.0, 0.8));
			h = g;
		} else if (kind == 2) {
			// Io: sulphur yellows and the dark caldera spots straight from the map.
			col = pow(s.rgb, vec3(1.08)) * vec3(1.04, 1.0, 0.9);
			col *= 0.92 + 0.16 * fbm(n_obj * 60.0, 3) * detail;
			h = dot(s.rgb, vec3(0.33));
		} else {
			// Ganymede (grooved bright terrain over dark plains) and Callisto.
			float fine = fbm(n_obj * 70.0, 3) * detail;
			col = mix(tint_dark, tint_light, smoothstep(0.2, 0.85, g + (fine - 0.5) * 0.12));
			h = g + fine * 0.2;
		}
		// Relief from the map's brightness: shows near the terminator only,
		// like real low-sun photography.
		vec3 dpx = dFdx(n_obj);
		vec3 dpy = dFdy(n_obj);
		float dhx = dFdx(h);
		float dhy = dFdy(h);
		vec3 r1 = cross(dpy, n_obj);
		vec3 r2 = cross(n_obj, dpx);
		float det = dot(dpx, r1);
		vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
		vec3 nb = normalize(abs(det) * n_obj - grad * 0.0015);
		float ndl_b = dot(normalize(nm * nb), L);
		// Lommel-Seeliger / Lambert mix: regolith looks flat-lit, ice is more
		// Lambertian.
		float w = kind == 1 ? 0.35 : 0.6;
		float mu0 = max(ndl_b, 0.0);
		float ls = 2.0 * mu0 / (mu0 + max(ndv, 0.05));
		lit = mix(mu0, ls * 0.5, w) * smoothstep(-0.01, 0.04, ndl);
		// Jupitershine softly lights the night side.
		float js = max(dot(N, normalize(jupiter_dir)), 0.0) * jupiter_shine;
		col = col * (lit * 1.05 + js * vec3(1.0, 0.86, 0.68));
	}
	ALBEDO = col * brightness * energy;
	ALPHA = coverage;
}
