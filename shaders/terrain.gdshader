// Realistic snow: smooth slopes with wind ripples, sparkle glints, subsurface
// translucency and rock showing through on steep faces. Every trip effect on the
// ground also lives here, masked so the rider and the line ahead stay readable.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/trip_common.gdshaderinc"

uniform vec3 snow_color : source_color = vec3(0.93, 0.95, 0.99);
uniform vec3 rock_color : source_color = vec3(0.27, 0.26, 0.27);
uniform vec3 sun_dir = vec3(0.6, 0.36, 0.33);     // set by Main (direction toward the sun)
uniform vec2 wind = vec2(0.8, 0.6);
uniform float ripple_strength = 0.35;
uniform vec3 shadow_tint : source_color = vec3(0.62, 0.7, 0.98);
uniform float reduced = 0.0;
// Recent track polyline: xyz = (x, z, birth time). Updated by Tracks.
uniform vec3 track_pts[24];
uniform int track_count = 0;

varying vec3 wpos;
varying vec3 wnorm;
varying float d_rider;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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

float ripple(vec2 p) {
	vec2 w = normalize(wind);
	float warp = vnoise(p * 0.25) * 5.0 + vnoise(p * 0.9) * 1.2;
	return sin(dot(p, w) * 2.6 + warp) * 0.5 + vnoise(p * 3.0) * 0.35;
}

void fragment() {
	vec3 alb = snow_color * COLOR.rgb;
	vec3 emi = vec3(0.0);
	vec3 V = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float cam_d = length(VERTEX);
	vec3 wn = normalize(wnorm);
	// Wind-packed patches and sastrugi ripples (fade out with distance: no shimmer).
	alb *= mix(vec3(1.0), vec3(0.9, 0.93, 1.0), fbm(wpos.xz * 0.02) * 0.6);
	float rs = ripple_strength * (1.0 - smoothstep(15.0, 60.0, cam_d));
	if (rs > 0.01) {
		float e = 0.06;
		float r0 = ripple(wpos.xz);
		vec2 g = vec2(ripple(wpos.xz + vec2(e, 0.0)) - r0, ripple(wpos.xz + vec2(0.0, e)) - r0) / e;
		wn = normalize(wn - vec3(g.x, 0.0, g.y) * rs * 0.06);
	}
	// Rock shows through where it's too steep for snow to hold.
	float rocky = smoothstep(0.8, 0.66, wn.y + (fbm(wpos.xz * 0.15) - 0.5) * 0.2);
	vec3 rock = rock_color * (0.7 + 0.6 * fbm(wpos.xz * 0.7 + wpos.y * 0.3));
	alb = mix(alb, rock, rocky);
	// Sparkle: tiny ice crystals catching the sun close to the camera.
	vec2 cell = floor(wpos.xz * 7.0);
	float glint = step(0.985, hash12(cell)) * (1.0 - smoothstep(6.0, 28.0, cam_d)) * (1.0 - rocky);
	float spec_align = pow(clamp(dot(reflect(-V, wn), normalize(sun_dir)), 0.0, 1.0), 6.0);
	emi += vec3(1.0, 0.97, 0.9) * glint * spec_align * 2.5;
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

	// --- Eyes open in the far snow and follow you (Net of Being reference).
	if (trip_eyes > 0.01 && d_rider > 22.0) {
		float cs = 13.0;
		vec2 cell = floor(wpos.xz / cs);
		float h = hash12(cell + 17.0);
		if (h > 0.5) {
			vec2 center = (cell + 0.5 + (vec2(hash12(cell + 3.1), hash12(cell + 7.7)) - 0.5) * 0.4) * cs;
			vec2 ay = normalize(travel_dir.xz + vec2(1e-4));
			vec2 ax = vec2(-ay.y, ay.x);
			float size = 5.0 + h * 3.5;
			vec2 q = wpos.xz - center;
			vec2 e = vec2(dot(q, ax), dot(q, ay) * 0.55) / size;
			// Lids open slowly and close slowly; never a blink-flash.
			float open = clamp(sin(trip_time * 0.35 + h * 40.0) * 1.6 + 0.4, 0.0, 1.0) * trip_eyes;
			float lid = open * 0.5 * (1.0 - e.x * e.x);
			float inside = step(abs(e.x), 1.0) * smoothstep(0.0, 0.04, lid - abs(e.y));
			float rim = step(abs(e.x), 1.05) * (1.0 - smoothstep(0.0, 0.12, abs(abs(e.y) - lid))) * step(0.02, open);
			vec2 look = rider_pos.xz - center;
			vec2 gaze = vec2(dot(look, ax), dot(look, ay) * 0.55);
			vec2 ic = normalize(gaze + vec2(1e-4)) * 0.28;
			float di = length((e - ic) * vec2(1.0, 1.4));
			vec3 iris = hue_rgb(di * 3.0 - trip_time * 0.2 + h + trip_hue);
			vec3 eye_col = vec3(0.97, 0.94, 0.9);
			eye_col = mix(eye_col, iris, smoothstep(0.34, 0.3, di));
			eye_col = mix(eye_col, vec3(0.03), smoothstep(0.13, 0.1, di));
			float fade = smoothstep(22.0, 45.0, d_rider);
			alb = mix(alb, eye_col, inside * fade);
			emi += eye_col * inside * fade * 0.45;
			alb = mix(alb, vec3(0.2, 0.02, 0.06), rim * fade);
		}
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

	// Rising phase: slopes turned away from the sun split into ribbons of colour.
	float shade = 1.0 - smoothstep(-0.05, 0.3, dot(wn, normalize(sun_dir)));
	if (trip_ribbons > 0.001 && shade > 0.01) {
		float rib = sin(dot(wpos.xz, vec2(0.21, 0.07)) * 3.0 + trip_time * 0.8);
		vec3 rc = hue_rgb(dot(wpos.xz, vec2(0.012, 0.004)) + rib * 0.08 + trip_time * 0.04 + trip_hue);
		emi += rc * shade * smoothstep(0.2, 0.9, abs(rib)) * trip_ribbons * 0.35;
	}

	ALBEDO = alb;
	EMISSION = emi;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = mix(0.72, 0.9, rocky);
	SPECULAR = mix(0.5, 0.3, rocky);
	SSS_STRENGTH = 0.3 * (1.0 - rocky);
}
