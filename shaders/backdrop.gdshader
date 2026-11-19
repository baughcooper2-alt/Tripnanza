// Horizon peaks. Each peak is drawn twice: the solid peak and a ghost copy.
// During the "peaks split" encounter they drift apart and recombine.
shader_type spatial;
render_mode diffuse_lambert, fog_disabled, cull_disabled, shadows_disabled, depth_draw_always;

#include "res://shaders/trip_common.gdshaderinc"

uniform float ghost = 0.0;
uniform vec3 haze : source_color = vec3(0.74, 0.8, 0.95);
uniform float haze_amt = 0.62;

varying float vy;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float side = sign(sin(o.x * 0.013 + o.z * 0.007) + 0.001);
	float s = trip_split * (ghost > 0.5 ? 1.0 : -1.0);
	// Rotate a little and slide apart along the peak's tangent.
	float a = s * 0.35 * side;
	VERTEX.xz = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * VERTEX.xz;
	VERTEX.x += s * side * 0.7;
	VERTEX.y *= 1.0 + abs(s) * 0.25 * sin(trip_time * 0.4 + o.x);
	vy = VERTEX.y;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) n = -n;
	NORMAL = n;
	vec3 c = COLOR.rgb;
	c = mix(c, haze, haze_amt * (1.0 - vy * 0.5));
	if (ghost > 0.5) {
		c = hue_rgb(vy * 0.6 + trip_time * 0.05 + trip_hue) * 0.8;
		EMISSION = c * 0.6 * trip_split;
	}
	ALBEDO = c;
	ALPHA = ghost > 0.5 ? clamp(trip_split * 1.4, 0.0, 0.85) : 1.0;
	ROUGHNESS = 1.0;
}
