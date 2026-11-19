// Board-edge marks. UV.x = birth time, COLOR = track colour, COLOR.a = 1 for
// persistent edge marks or 0 for the short-lived rainbow split ribbons.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert;

#include "res://shaders/trip_common.gdshaderinc"

uniform float split_life = 2.5;

void vertex() {
	// Pull slightly toward the camera so marks never z-fight the snow.
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz *= 0.9985;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	float age = trip_time - UV.x;
	float edge_fade = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.75, UV.y);
	if (COLOR.a > 0.5) {
		vec3 groove = vec3(0.66, 0.73, 0.88);
		float echo = trip_echo * exp(-age * 0.4);
		ALBEDO = mix(groove, hue_rgb(age * 0.25 + trip_hue), clamp(echo, 0.0, 0.8));
		EMISSION = hue_rgb(age * 0.25 + trip_hue) * echo * 0.8;
		ALPHA = 0.75 * edge_fade;
	} else {
		float life = 1.0 - clamp(age / split_life, 0.0, 1.0);
		ALBEDO = COLOR.rgb;
		EMISSION = COLOR.rgb * 1.6 * life;
		ALPHA = life * edge_fade * 0.9;
	}
}
