// Trip compositor. Reads the off-screen world (world_tex) and the tracer buffer
// (trail_tex) and builds the trip on screen. Layers, roughly in phase order:
//   tracers         - previous frames linger as hue-tinted ghosts (frame feedback)
//   false colour    - a gradient map on brightness through a palette taken from the
//                     references (infrared forest, cyan forest, Net of Being, ...).
//                     Brightness order is kept, so dark hazards stay dark on light snow
//   colour grain    - slow-moving chromatic speckle in the shadows
//   zoom smear      - radial smear streaming outward from the rider
//   paint-by-number - flat colour bands with ink outlines; "unpainted" patches
//                     drift through the edges like a canvas that isn't finished
//   kaleidoscope, liquid sky, drips at the far edges
// Readability: a bubble around the rider and an ellipse over the line ahead are
// protected from most of it. Nothing flashes: every term moves over seconds.
shader_type canvas_item;

#include "res://shaders/trip_common.gdshaderinc"

uniform sampler2D world_tex : filter_linear;
uniform sampler2D trail_tex : filter_linear;
uniform vec2 focus = vec2(0.5, 0.55);     // the line ahead, in screen UV
uniform vec2 window = vec2(0.42, 0.5);    // protected ellipse radii
uniform vec2 rider_uv = vec2(0.5, 0.68);
uniform float rider_r = 0.07;             // rider bubble radius (screen height units)
uniform float kaleido = 0.0;
uniform float echo = 0.0;
uniform float melt = 0.0;
uniform float aberration = 0.0;
uniform float speed01 = 0.0;
uniform float reduced = 0.0;
uniform float trail_amt = 0.0;
uniform float false_amt = 0.0;
uniform vec3 pal_a[5];
uniform vec3 pal_b[5];
uniform float pal_mix = 0.0;
uniform float poster_amt = 0.0;
uniform float poster_levels = 10.0;
uniform float unpainted = 0.0;
uniform float grain = 0.0;

vec3 tex(vec2 uv) {
	return textureLod(world_tex, clamp(uv, vec2(0.001), vec2(0.999)), 0.0).rgb;
}

vec3 pal(vec3 p[5], float x) {
	float f = clamp(x, 0.0, 1.0) * 4.0;
	int i = min(int(floor(f)), 3);
	return mix(p[i], p[i + 1], f - float(i));
}

vec3 palette(float x) {
	return mix(pal(pal_a, x), pal(pal_b, x), pal_mix);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = (uv - focus) / window;
	float r = length(p);
	float edge = smoothstep(0.85, 1.6, r);
	// Strongest at the top (distance) and far sides; gentler at the bottom corners
	// where hazards you are passing still need to read.
	float vmask = mix(1.0, 0.25, smoothstep(0.45, 0.85, uv.y));
	float k = 1.0 - reduced * 0.75;
	// Rider bubble: 1 at the rider, 0 outside.
	vec2 rd = (uv - rider_uv) * vec2(aspect, 1.0);
	float bubble = 1.0 - smoothstep(rider_r * 0.8, rider_r * 3.2, length(rd));
	float protect = 1.0 - bubble * 0.85;

	// --- Liquid swirl + drips at the edges (melting portrait).
	vec2 w = vec2(fbm(uv * 3.0 + trip_time * 0.07), fbm(uv * 3.0 + 4.1 - trip_time * 0.06)) - 0.5;
	vec2 suv = uv + w * 0.06 * trip_warp * edge * vmask * k;
	float drip_col = vnoise(vec2(uv.x * 26.0, 0.0));
	float drip_len = drip_col * 0.25 * melt * k;
	float in_drip = smoothstep(drip_len, drip_len - 0.04, uv.y) * step(0.45, drip_col);
	suv.y -= in_drip * 0.05 * melt;

	vec3 col = tex(suv);
	vec2 dir = uv - focus;
	float ab = aberration * edge * (0.004 + speed01 * 0.006) * k;
	col.r = tex(suv + dir * ab * 2.0).r;
	col.b = tex(suv - dir * ab * 2.0).b;

	// --- Zoom smear: the image streams outward from the rider (village reference).
	if (echo > 0.001) {
		vec3 acc = vec3(0.0);
		float wsum = 0.0;
		for (int i = 1; i <= 8; i++) {
			float f = float(i) / 8.0;
			vec2 e_uv = rider_uv + (suv - rider_uv) * (1.0 - f * 0.12 * (1.0 + speed01));
			float wt = 1.0 - f * 0.6;
			acc += tex(e_uv) * mix(vec3(1.0), hue_rgb(f * 0.4 + trip_time * 0.05 + trip_hue), 0.35) * wt;
			wsum += wt;
		}
		col = mix(col, acc / wsum, clamp(edge * echo * k * 1.2, 0.0, 0.85));
	}

	// --- Tracers: earlier frames hang in the air, tinted.
	if (trail_amt > 0.001) {
		vec3 tr = textureLod(trail_tex, uv, 0.0).rgb;
		float diff = length(tr - col);
		vec3 ghost = mix(tr, tr * hue_rgb(trip_time * 0.04 + uv.y * 0.6 + trip_hue) * 1.6, 0.5);
		float ta = trail_amt * mix(0.35, 1.0, edge) * protect;
		col = mix(col, ghost, clamp(ta * (0.4 + diff * 2.0), 0.0, 0.8));
	}

	// --- Kaleidoscope (colour blend, never coordinate blend: no rider copies).
	float kal = edge * kaleido * vmask * k;
	if (kal > 0.001) {
		vec2 c = (suv - focus) * vec2(aspect, 1.0);
		float ang = atan(c.y, c.x);
		float seg = 6.2831 / 6.0;
		float fa = abs(mod(ang + trip_time * 0.04, seg) - seg * 0.5);
		vec3 kc = tex(focus + vec2(cos(fa), sin(fa)) * length(c) / vec2(aspect, 1.0));
		vec3 mc = tex(vec2(min(suv.x, 1.0 - suv.x), suv.y));
		col = mix(col, mix(kc, mc, 0.5 + 0.5 * sin(trip_time * 0.1)), kal);
	}

	// --- False colour: gradient map on brightness (infrared / cyan forest).
	float L = luma(col);
	// Snow lives in a narrow bright band; stretch it so facets, shadows and
	// tracks land on different palette colours (order is still preserved).
	// Local contrast (infrared photo look): brightness relative to the surrounding
	// area, so every facet, shadow and track flips to its own palette colour.
	float mean = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785 + 0.3;
		float rr = (i % 2 == 0) ? 0.035 : 0.08;
		mean += luma(tex(uv + vec2(cos(a) / aspect, sin(a)) * rr));
	}
	mean /= 8.0;
	float local = clamp(0.5 + (L - mean) * 4.0, 0.0, 1.0);
	float pos = clamp(mix(pow(L, 2.6), local, 0.55), 0.0, 1.0);
	// Liquid colour boundaries: distant regions drift to different colours.
	pos = clamp(pos + (fbm(uv * 1.7 + vec2(trip_time * 0.02, -trip_time * 0.015)) - 0.5) * 0.45 * max(edge, smoothstep(0.45, 0.1, uv.y)), 0.0, 1.0);
	if (false_amt > 0.001) {
		vec3 fc = palette(pos);
		// Keep a little of the original hue so the scene doesn't go flat.
		fc = mix(fc, fc * (0.75 + col * 0.5), 0.15);
		float fa_amt = false_amt * mix(0.55, 1.0, max(edge, smoothstep(0.35, 0.0, uv.y))) * protect;
		col = mix(col, fc, fa_amt);
	}

	// --- Colour grain in the shadows (cyan forest floor). Drifts, doesn't flicker.
	if (grain > 0.001) {
		vec2 gp = floor(uv / SCREEN_PIXEL_SIZE / 2.0) + vec2(trip_time * 9.0, trip_time * 5.0);
		vec3 gc = hue_rgb(hash12(floor(gp)) + trip_hue);
		float dark = smoothstep(0.75, 0.15, L);
		col = mix(col, gc * (0.4 + L), grain * dark * 0.35 * protect);
	}

	// --- Paint-by-number: flat bands + ink outlines; unpainted canvas patches.
	if (poster_amt > 0.001) {
		float lv = pos * poster_levels;
		float band = (floor(lv) + 0.5) / poster_levels;
		vec3 flatc = palette(band);
		float fw = max(fwidth(lv), 1e-3);
		float ink = 1.0 - smoothstep(0.0, fw * 1.6, min(fract(lv), 1.0 - fract(lv)));
		float pm = poster_amt * mix(0.35, 1.0, max(edge, smoothstep(0.4, 0.0, uv.y))) * protect;
		col = mix(col, flatc, pm * 0.85);
		col = mix(col, vec3(0.12, 0.16, 0.55), ink * pm * 0.75);
		float patchm = smoothstep(0.58, 0.64, fbm(uv * vec2(2.2, 1.6) + vec2(trip_time * 0.015, -trip_time * 0.01)));
		float um = patchm * unpainted * edge * vmask * k;
		vec3 paper = vec3(0.97, 0.96, 0.93);
		col = mix(col, mix(paper, vec3(0.2, 0.35, 0.85), ink), um);
	}

	// --- Rainbow liquid boundaries in the far top of the image.
	float top = smoothstep(0.32, 0.0, uv.y) * trip_warp * k;
	vec3 liquid = hue_rgb(fbm(uv * 4.0 + w * 2.0 + trip_time * 0.03) * 2.0 + trip_hue);
	col = mix(col, col * 0.35 + liquid * 0.65, top * 0.5);
	col = mix(col, col * 0.4 + liquid * 0.7, in_drip * melt * 0.7);

	// --- Saturation lift (away from the rider).
	float l2 = luma(col);
	col = mix(vec3(l2), col, 1.0 + trip_intensity * (0.25 + 0.45 * edge) * k * protect);
	col = max(col, vec3(0.0));

	float vig = smoothstep(1.1, 2.2, r);
	col *= 1.0 - vig * 0.25;
	col += vec3(0.25, 0.05, 0.35) * vig * trip_intensity * 0.25 * k;

	COLOR = vec4(col, 1.0);
}
