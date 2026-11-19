// Shared trip globals and helpers. Values are driven by TripDirector.
global uniform float trip_intensity;
global uniform float trip_time;
global uniform float trip_grain;
global uniform float trip_breathe;
global uniform float trip_echo;
global uniform float trip_contour;
global uniform float trip_ribbons;
global uniform float trip_fold;
global uniform float trip_marble;
global uniform float trip_warp;
global uniform float trip_split;
global uniform float trip_sky;
global uniform float trip_hue;
global uniform float trip_eyes;
global uniform vec3 rider_pos;
global uniform vec3 travel_dir;
global uniform vec3 wave_origin;
global uniform float wave_time;
global uniform vec3 gate_wave_origin;
global uniform float gate_wave_time;
global uniform float gate_line_z;
global uniform float gate_line_glow;

vec3 hue_rgb(float h) {
	vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return k * k * (3.0 - 2.0 * k);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x),
		mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s;
}

// Escape-time Julia set banding (the paisley / spiral reference).
vec3 julia_bands(vec2 p, float t) {
	vec2 c = vec2(-0.745 + 0.02 * sin(t * 0.13), 0.112 + 0.02 * cos(t * 0.11));
	vec2 z = p;
	float n = 0.0;
	for (int i = 0; i < 28; i++) {
		z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
		if (dot(z, z) > 16.0) break;
		n += 1.0;
	}
	float sm = n - log2(max(log2(dot(z, z)), 1e-4)) + 4.0;
	vec3 col = hue_rgb(sm * 0.085 + t * 0.03 + trip_hue);
	float band = 0.5 + 0.5 * cos(sm * 2.6);
	return col * (0.55 + 0.45 * band) * step(n, 27.0) + vec3(0.05, 0.25, 0.22) * step(27.0, n);
}
