// Warm low-sun sky. At depth the upper sky grows aurora ribbons and a
// slowly turning fractal mandala around the sun.
shader_type sky;

#include "res://shaders/trip_common.gdshaderinc"

uniform vec3 zenith : source_color = vec3(0.16, 0.33, 0.68);
uniform vec3 horizon : source_color = vec3(0.78, 0.84, 0.93);
uniform vec3 sunset : source_color = vec3(1.0, 0.72, 0.48);
uniform float cloud_cover = 0.45;
uniform vec3 ground_col : source_color = vec3(0.72, 0.78, 0.92);
uniform vec3 sun_col : source_color = vec3(1.0, 0.86, 0.62);
uniform float reduced = 0.0;

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 sd = LIGHT0_DIRECTION;
	float sa = max(dot(d, sd), 0.0);
	// Rayleigh-ish gradient, warmer toward the low sun, with horizon haze.
	vec3 col = mix(horizon, zenith, pow(smoothstep(-0.02, 0.6, h), 0.6));
	col = mix(col, sunset, pow(sa, 4.0) * smoothstep(0.35, 0.0, h) * 0.6);
	col = mix(col, ground_col, smoothstep(0.0, -0.25, h));
	// Drifting clouds, lit from the sun side.
	if (h > 0.01) {
		vec2 cp = d.xz / (h + 0.12) * 1.6 + vec2(TIME * 0.004, TIME * 0.002);
		float c = fbm(cp) * 0.7 + fbm(cp * 3.0) * 0.3;
		float cover = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.3, c) * smoothstep(0.01, 0.15, h);
		vec3 ccol = mix(vec3(0.72, 0.76, 0.84), vec3(1.0, 0.96, 0.9), pow(sa, 3.0) * 0.6 + 0.4);
		col = mix(col, ccol, cover * 0.85);
	}
	col += sun_col * (pow(sa, 900.0) * 6.0 + pow(sa, 40.0) * 0.4 + pow(sa, 6.0) * 0.12);
	if (!AT_CUBEMAP_PASS && trip_sky > 0.001 && h > -0.05) {
		float k = trip_sky * (1.0 - reduced * 0.6);
		vec2 p = d.xz / max(h + 0.35, 0.05);
		float band = sin(p.x * 1.4 + sin(p.y * 0.8 + trip_time * 0.15) * 2.0 + trip_time * 0.2);
		vec3 aur = hue_rgb(p.x * 0.05 + p.y * 0.04 + trip_time * 0.03 + trip_hue);
		col = mix(col, aur, smoothstep(0.3, 1.0, band) * k * 0.55 * smoothstep(0.0, 0.3, h));
		// Mandala around the sun: angular symmetry + Julia bands.
		vec3 t1 = normalize(cross(sd, vec3(0.0, 1.0, 0.0)));
		vec3 t2 = cross(t1, sd);
		vec2 q = vec2(dot(d, t1), dot(d, t2)) / max(dot(d, sd), 0.1);
		float ang = atan(q.y, q.x) + trip_time * 0.05;
		float seg = 6.2831 / 8.0;
		ang = abs(mod(ang, seg) - seg * 0.5);
		vec2 m = vec2(cos(ang), sin(ang)) * length(q) * 1.4;
		vec3 jul = julia_bands(m, trip_time);
		float rad = smoothstep(1.4, 0.2, length(q)) * step(0.0, dot(d, sd));
		col = mix(col, jul, rad * smoothstep(0.55, 1.0, trip_intensity) * k * 0.7);
	}
	COLOR = col;
}
