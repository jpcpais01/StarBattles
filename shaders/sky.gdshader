// Deep space as the eye sees it past Jupiter: true black, scattered with
// crisp pin-point stars. Each star is sized to the screen pixel (so it
// stays a sharp dot at any resolution or FOV) and carries a subtle colour
// temperature; faint stars thicken along the galactic plane. The Sun is a
// tiny, blinding disc with a tight glare (bloom does the rest).
// The reflection/radiance cubemap only sees black space and the Sun.
shader_type sky;

global uniform vec3 sun_dir;
uniform vec3 galactic_pole = vec3(0.35, 0.82, -0.45);
uniform float star_brightness = 1.0;
uniform float sun_energy = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 star_layer(vec3 d, float scale, float density, float gain) {
	vec3 p = d * scale;
	vec3 c = floor(p);
	float h = hash(c);
	if (h > density) {
		return vec3(0.0);
	}
	// Star position kept off the cell walls, then projected onto the sphere
	// so it is a true point on the sky.
	vec3 sp = normalize(c + 0.2 + 0.6 * vec3(hash(c + 1.31), hash(c + 2.77), hash(c + 5.13))) * scale;
	float dist = length(p - sp);
	// One screen pixel in cell units: stars are 1-2 px dots, never blobs.
	float px = max(length(fwidth(p)), 1e-4);
	float r = px * 0.55;
	float core = exp(-(dist * dist) / (r * r));
	// Steep magnitude distribution: a few bright stars, many faint ones.
	float mag = hash(c + 9.7);
	float b = (0.12 + 0.55 * mag * mag + 2.4 * pow(mag, 14.0)) * gain;
	float temp = hash(c + 3.3);
	vec3 col = temp < 0.18 ? vec3(0.78, 0.86, 1.0) : (temp < 0.8 ? vec3(1.0, 0.99, 0.97) : vec3(1.0, 0.88, 0.74));
	return col * core * b;
}

vec3 sun(vec3 d) {
	vec3 s = normalize(sun_dir);
	float a = length(d - s);
	// Disc ~0.15 deg (a little larger than the true 0.05 so it holds a pixel).
	float disc = 1.0 - smoothstep(0.0022, 0.0028, a);
	float c = max(dot(d, s), 0.0);
	float glare = exp(-a * 260.0) * 1.6 + exp(-a * 38.0) * 0.12 + pow(c, 24.0) * 0.012;
	return vec3(1.0, 0.97, 0.92) * (disc * 40.0 + glare) * sun_energy;
}

void sky() {
	vec3 d = EYEDIR;
	if (AT_CUBEMAP_PASS) {
		COLOR = sun(d) * 0.5;
	} else {
		float lat = dot(d, normalize(galactic_pole));
		float band = exp(-lat * lat * 10.0);
		vec3 s = star_layer(d, 70.0, 0.02, 1.5);
		s += star_layer(d, 170.0, 0.007 + 0.016 * band, 0.75);
		s += star_layer(d, 380.0, 0.002 + 0.012 * band, 0.4);
		COLOR = s * star_brightness + sun(d);
	}
}
