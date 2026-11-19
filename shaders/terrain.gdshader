// Faceted snow. Every trip effect on the ground lives here, masked so that
// the area around the rider (and directly ahead) stays readable.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

#include "res://shaders/trip_common.gdshaderinc"

uniform vec3 snow_color : source_color = vec3(0.95, 0.965, 1.0);
uniform vec3 shadow_tint : source_color = vec3(0.62, 0.7, 0.98);
uniform float reduced = 0.0;
// Recent track polyline: xyz = (x, z, birth time). Updated by Tracks.
uniform vec3 track_pts[24];
uniform int track_count = 0;

varying vec3 wpos;
varying float d_rider;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	d_rider = length(wpos.xz - rider_pos.xz);
	// Distant terrain slowly breathes/undulates; ground near the rider never moves.
	float far = smoothstep(70.0, 190.0, d_rider) * (1.0 - reduced);
	float swell = sin(wpos.x * 0.028 + trip_time * 0.55) * sin(wpos.z * 0.021 - trip_time * 0.37);
	swell += 0.5 * sin(length(wpos.xz - rider_pos.xz) * 0.05 - trip_time * 0.9);
	float disp = swell * trip_warp * far * 7.0;
	VERTEX.y += disp;
	wpos.y += disp;
}

float seg_dist(vec2 p, vec2 a, vec2 b, out float t) {
	vec2 ab = b - a;
	t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
	return length(p - (a + ab * t));
}

void fragment() {
	vec3 alb = snow_color * COLOR.rgb;
	vec3 emi = vec3(0.0);
	float near_keep = smoothstep(7.0, 26.0, d_rider);    // 0 near rider -> 1 far
	float far_only = smoothstep(35.0, 90.0, d_rider);
	float mid_field = smoothstep(14.0, 60.0, d_rider);

	// --- Onset: snow grain flowing against the direction of travel.
	vec2 flow = wpos.xz * 2.2 + travel_dir.xz * trip_time * 1.6;
	float grain = vnoise(flow) * vnoise(flow * 2.7 + 3.0);
	float sparkle = step(0.93, hash12(floor(wpos.xz * 6.0)));
	alb *= 1.0 - 0.06 * grain;
	emi += sparkle * 0.06 * vec3(1.0);
	emi += hue_rgb(grain + trip_time * 0.05) * grain * trip_grain * 0.35;

	// --- Track echo + contour lines blooming out of the rider's tracks.
	float dmin = 1e4;
	float age = 99.0;
	for (int i = 0; i < 23; i++) {
		if (i + 1 >= track_count) break;
		float t;
		float d = seg_dist(wpos.xz, track_pts[i].xy, track_pts[i + 1].xy, t);
		if (d < dmin) {
			dmin = d;
			age = trip_time - mix(track_pts[i].z, track_pts[i + 1].z, t);
		}
	}
	if (dmin < 60.0) {
		float echo = exp(-dmin * 1.1) * exp(-age * 0.45) * trip_echo;
		emi += hue_rgb(age * 0.2 + trip_hue) * echo * 1.4;
		float rings = 0.5 + 0.5 * cos(dmin * 1.7 - trip_time * 2.3);
		float line = smoothstep(0.86, 1.0, rings);
		float bloom = smoothstep(0.0, 4.0, age) * exp(-dmin * 0.07) * trip_contour;
		emi += hue_rgb(dmin * 0.045 - trip_time * 0.07 + trip_hue) * line * bloom * 0.9;
	}

	// --- Topographic contours of the mountain itself (distance only).
	float topo = abs(fract(wpos.y / 3.2 - trip_time * 0.05) - 0.5);
	float topo_line = smoothstep(0.08, 0.0, topo) * trip_contour * far_only;
	emi += hue_rgb(wpos.y * 0.02 + trip_hue) * topo_line * 0.7;

	// --- Liquid marbling + Julia-set paisley in the far field and edges.
	float edge = smoothstep(0.3, 0.75, abs(SCREEN_UV.x - 0.5) * 2.0) + smoothstep(0.35, 0.0, SCREEN_UV.y);
	float mask = clamp(max(mid_field * 0.85, edge * near_keep), 0.0, 1.0) * trip_marble;
	if (mask > 0.01) {
		vec2 q = wpos.xz * 0.012;
		vec2 w = vec2(fbm(q + trip_time * 0.03), fbm(q + 7.3 - trip_time * 0.025));
		float liquid = fbm(q * 1.4 + w * 2.6 + trip_time * 0.02);
		vec3 marble = hue_rgb(liquid * 2.2 + trip_hue);
		marble = mix(marble, vec3(1.0), smoothstep(0.48, 0.5, fract(liquid * 6.0)) * 0.6);
		vec2 jp = (wpos.xz - rider_pos.xz) * 0.006;
		jp = vec2(jp.x * cos(trip_time * 0.03) - jp.y * sin(trip_time * 0.03), jp.x * sin(trip_time * 0.03) + jp.y * cos(trip_time * 0.03));
		vec3 jul = julia_bands(jp, trip_time);
		vec3 trip_col = mix(marble, jul, smoothstep(0.55, 0.9, trip_intensity) * far_only);
		alb = mix(alb, trip_col * 0.85, mask * 0.8);
		emi += trip_col * mask * 0.12;
	}

	// --- Waves: landed flips (wave_*) and blinker crossings (gate_wave_*).
	float wt = trip_time - wave_time;
	if (wt > 0.0 && wt < 4.0) {
		vec2 rel = wpos.xz - wave_origin.xz;
		float r = length(rel);
		float front = wt * 32.0;
		float band = exp(-pow((r - front) / 2.2, 2.0));
		float downhill = smoothstep(-0.3, 0.4, dot(normalize(rel + 1e-4), normalize(travel_dir.xz)));
		emi += hue_rgb(r * 0.02 + trip_hue) * band * downhill * (1.0 - wt / 4.0) * (0.6 + trip_intensity);
	}
	float gt = trip_time - gate_wave_time;
	if (gt > 0.0 && gt < 5.0) {
		vec2 rel = wpos.xz - gate_wave_origin.xz;
		float r = length(rel);
		float sum = 0.0;
		for (int k = 0; k < 4; k++) {
			float front = (gt - float(k) * 0.25) * 38.0;
			sum += exp(-pow((r - front) / 1.4, 2.0)) * step(0.0, front);
		}
		float ahead = smoothstep(-0.2, 0.5, dot(normalize(rel + 1e-4), normalize(travel_dir.xz)));
		emi += hue_rgb(r * 0.03 + gt * 0.2) * sum * ahead * (1.0 - gt / 5.0) * 1.2;
	}

	// --- The blinker line: a faint luminous seam across the whole slope.
	float gl = exp(-pow((wpos.z - gate_line_z) / 0.5, 2.0));
	float shimmer = 0.6 + 0.4 * sin(wpos.x * 0.6 - trip_time * 4.0);
	emi += mix(vec3(0.4, 0.95, 1.0), hue_rgb(wpos.x * 0.03 + trip_time * 0.2), clamp(trip_intensity * 2.0, 0.0, 1.0)) * gl * gate_line_glow * shimmer;

	ALBEDO = alb;
	EMISSION = emi;
	ROUGHNESS = 0.82;
	SPECULAR = 0.25;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// Wrap the light a little so shadowed snow is cool and soft rather than grey.
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.35) / 1.35, 0.0, 1.0);
	float lit = ndl * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(wrap * 0.1 * shadow_tint, vec3(lit), lit);
	// Rising phase: shadows separate into ribbons of colour.
	float shade = wrap * (1.0 - ATTENUATION);
	if (trip_ribbons > 0.001 && shade > 0.01) {
		float rib = sin(dot(wpos.xz, vec2(0.21, 0.07)) * 3.0 + trip_time * 0.8);
		vec3 rc = hue_rgb(dot(wpos.xz, vec2(0.012, 0.004)) + rib * 0.08 + trip_time * 0.04 + trip_hue);
		float ribbon = smoothstep(0.2, 0.9, abs(rib));
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * rc * shade * ribbon * trip_ribbons * 0.35;
	}
}
