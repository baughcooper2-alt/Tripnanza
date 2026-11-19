// Realistic fir: bark (is_foliage = 0) and alpha-cut needle branches
// (is_foliage = 1) with snow resting on the upper sides. Keeps the trip's tree
// behaviours (breathing banks, distant mirror-folding) from prop.gdshader.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

#include "res://shaders/trip_common.gdshaderinc"

uniform float is_foliage = 1.0;
uniform float tree_height = 8.0;
uniform float reduced = 0.0;
uniform vec3 needle_dark : source_color = vec3(0.06, 0.13, 0.09);
uniform vec3 needle_light : source_color = vec3(0.16, 0.27, 0.15);
uniform vec3 snow : source_color = vec3(0.92, 0.95, 1.0);

varying vec3 wpos;
varying vec3 wnorm;
varying float fold_amt;
varying float tree_rand;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	tree_rand = hash12(origin.xz);
	float d = length(origin.xz - rider_pos.xz);
	float patch_phase = hash12(floor(origin.xz / 40.0)) * 6.28;
	float near_damp = smoothstep(6.0, 22.0, d);
	float breath = sin(trip_time * 1.25 + patch_phase) * trip_breathe * near_damp * (1.0 - reduced * 0.7);
	VERTEX.xz *= 1.0 + 0.1 * breath * smoothstep(0.5, 6.0, VERTEX.y);
	VERTEX.y *= 1.0 + 0.05 * breath;
	// Wind sway on branch tips (real world, always on).
	float sway = sin(TIME * 1.3 + origin.x * 0.2 + VERTEX.y * 0.4) * 0.03 * VERTEX.y * UV.y * is_foliage;
	VERTEX.x += sway;
	float f = smoothstep(55.0, 110.0, d) * trip_fold * (1.0 - reduced);
	fold_amt = f;
	if (f > 0.001) {
		float h = tree_height * 0.5;
		float ang = atan(VERTEX.z, VERTEX.x);
		float r = length(VERTEX.xz);
		float seg = 6.2831 / 6.0;
		float a2 = abs(mod(ang + trip_time * 0.3, seg) - seg * 0.5) * 2.0;
		r *= 1.0 + f * 0.9 * cos(a2 * 3.0);
		float y = VERTEX.y;
		float mirrored = h + abs(y - h) * sign(y - h + 0.001) * cos(f * 3.14159);
		VERTEX.y = mix(y, mirrored, f);
		VERTEX.xz = vec2(cos(ang + f * y * 0.15), sin(ang + f * y * 0.15)) * r * (1.0 + f * 0.6);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col;
	float rough = 0.85;
	if (is_foliage > 0.5) {
		// Procedural fir branch: a tapering spine with angled side-shoots of needles.
		vec2 uv = UV;
		float across = abs(uv.x - 0.5) * 2.0;
		float width = mix(1.0, 0.25, uv.y) * smoothstep(0.0, 0.08, uv.y);
		float shoot = fract(uv.y * 9.0 + across * 1.6 + COLOR.r * 3.0);
		float needles = smoothstep(0.62, 0.35, shoot) * step(across, width);
		float spine = step(across, 0.06);
		float edge_noise = vnoise(uv * vec2(30.0, 60.0) + COLOR.r * 20.0);
		float a = max(needles * step(across, width * (0.75 + edge_noise * 0.35)), spine * step(uv.y, 0.95));
		ALPHA = a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
		col = mix(needle_dark, needle_light, edge_noise * 0.7 + COLOR.r * 0.3);
		col *= 0.8 + 0.25 * tree_rand;
		// Snow sits on the upper side of the branches, thicker near the tip.
		float up = clamp(dot(normalize(wnorm), vec3(0, 1, 0)), 0.0, 1.0);
		float sn = smoothstep(0.62, 0.85, up * (0.55 + 0.6 * vnoise(wpos.xz * 1.7 + wpos.y)) + uv.y * 0.18 - COLOR.g * 0.12);
		col = mix(col, snow, sn * 0.85);
		rough = mix(0.8, 0.6, sn);
		BACKLIGHT = vec3(0.08, 0.12, 0.05);
	} else {
		float streak = vnoise(vec2(atan(wpos.x, wpos.z) * 6.0, wpos.y * 1.5));
		col = mix(vec3(0.17, 0.12, 0.09), vec3(0.32, 0.25, 0.19), streak);
	}
	// Trip: folded far trees turn to glowing colour; near trees keep their look
	// and gain a soft dark rim as the trip deepens so they stay readable.
	vec3 emi = vec3(0.0);
	if (fold_amt > 0.001) {
		vec3 hc = hue_rgb(wpos.y * 0.05 + trip_time * 0.1 + trip_hue);
		col = mix(col, hc * 0.5, fold_amt * 0.7);
		emi += hc * fold_amt * 0.6;
	}
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	col *= 1.0 - rim * trip_intensity * 0.4;
	ALBEDO = col;
	EMISSION = emi;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
