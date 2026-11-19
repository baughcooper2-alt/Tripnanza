// Realistic rock: triplanar layered stone with strata and cracks, snow caught
// on the upper surfaces. Solid hazard: no trip distortion, darker rim with depth.
shader_type spatial;
render_mode diffuse_burley;

#include "res://shaders/trip_common.gdshaderinc"

uniform vec3 stone_a : source_color = vec3(0.24, 0.23, 0.24);
uniform vec3 stone_b : source_color = vec3(0.42, 0.39, 0.36);
uniform vec3 snow : source_color = vec3(0.93, 0.95, 1.0);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri_fbm(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return fbm(p.yz) * w.x + fbm(p.xz) * w.y + fbm(p.xy) * w.z;
}

void fragment() {
	vec3 n = normalize(wnorm);
	float big = tri_fbm(wpos * 0.6, n);
	float fine = tri_fbm(wpos * 3.5, n);
	float strata = 0.5 + 0.5 * sin(wpos.y * 9.0 + big * 6.0);
	vec3 col = mix(stone_a, stone_b, big * 0.8 + strata * 0.2);
	col *= 0.8 + fine * 0.4;
	float crack = smoothstep(0.03, 0.0, abs(tri_fbm(wpos * 1.4 + 7.0, n) - 0.5));
	col *= 1.0 - crack * 0.5;
	// Lichen speckles.
	col = mix(col, vec3(0.45, 0.42, 0.2), smoothstep(0.72, 0.8, fine) * 0.3);
	float sn = smoothstep(0.35, 0.7, n.y + (big - 0.5) * 0.6);
	col = mix(col, snow, sn);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	col *= 1.0 - rim * (0.15 + trip_intensity * 0.4);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.6, sn);
	SPECULAR = 0.3;
}
