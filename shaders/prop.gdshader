// Solid things you can hit (trees, rocks, kickers) and the rider.
// Visual language: matte, faceted, opaque, with a dark rim that strengthens
// as the trip deepens, so hazards always read against the hallucinations.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

#include "res://shaders/trip_common.gdshaderinc"

uniform vec3 tint : source_color = vec3(1.0);
uniform float rim_base = 0.25;
uniform float emission_boost = 0.0;
uniform vec3 emission_color : source_color = vec3(0.0);
// Tree-only: breathing together and distant mirror-folding.
uniform float is_tree = 0.0;
uniform float tree_height = 9.0;
uniform float reduced = 0.0;
uniform vec3 shadow_tint : source_color = vec3(0.62, 0.7, 0.98);

varying float fold_amt;
varying vec3 wpos;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float d = length(origin.xz - rider_pos.xz);
	fold_amt = 0.0;
	if (is_tree > 0.5) {
		// A bank of trees breathes together (phase shared per ~40 m patch).
		float patch_phase = hash12(floor(origin.xz / 40.0)) * 6.28;
		float near_damp = smoothstep(6.0, 22.0, d);
		float breath = sin(trip_time * 1.25 + patch_phase) * trip_breathe * near_damp * (1.0 - reduced * 0.7);
		VERTEX.xz *= 1.0 + 0.1 * breath * smoothstep(0.5, 6.0, VERTEX.y);
		VERTEX.y *= 1.0 + 0.05 * breath;
		// Distant treetops fold into mirrored, kaleidoscopic forms and resolve as you approach.
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
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Faceted normal from screen derivatives, always facing the viewer.
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) n = -n;
	NORMAL = n;
	vec3 base = COLOR.rgb * tint;
	float rim = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 2.0);
	float rim_amt = rim_base + trip_intensity * 0.55;
	base *= 1.0 - rim * rim_amt;
	// Folded (hallucinated) far trees glow in rainbow; solid near trees stay natural.
	vec3 emi = emission_color * emission_boost;
	if (fold_amt > 0.001) {
		vec3 hc = hue_rgb(wpos.y * 0.05 + trip_time * 0.1 + trip_hue);
		base = mix(base, hc * 0.5, fold_amt * 0.7);
		emi += hc * fold_amt * 0.6;
	}
	ALBEDO = base;
	EMISSION = emi;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp((ndl + 0.35) / 1.35, 0.0, 1.0);
	float lit = clamp(ndl, 0.0, 1.0) * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(wrap * 0.16 * shadow_tint, vec3(lit), lit);
}
