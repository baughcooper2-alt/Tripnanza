// Decorative hallucinations: glowing, translucent, liquid rainbow, no shading,
// no shadows, no rim. Deliberately the opposite of the solid-hazard look.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/trip_common.gdshaderinc"

uniform float alpha = 0.6;
uniform float stripe_freq = 6.0;
uniform float stripe_speed = 1.5;
uniform float hue_offset = 0.0;
// 0 = rainbow stripes (tunnel), 1 = petals/bubbles (flowers), 2 = rings
uniform int style = 0;
uniform float fade_near = 4.0;
uniform float grow = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = length(wpos - rider_pos);
	// Fade anything that gets too close to the rider or camera.
	float keep = smoothstep(fade_near * 0.5, fade_near * 2.0, d);
	vec3 col;
	if (style == 0) {
		float s = UV.x * stripe_freq + UV.y * 0.6 - trip_time * stripe_speed;
		col = hue_rgb(s * 0.08 + hue_offset + trip_hue);
		float thin = 0.55 + 0.45 * smoothstep(0.1, 0.0, abs(fract(s) - 0.5) - 0.38);
		col *= thin;
	} else if (style == 1) {
		// Depth-coded petals: each smaller scale shifts hue; teal/violet bubbles in the core.
		float depth = COLOR.r * 4.0;
		vec2 b = fract(UV * vec2(5.0, 5.0) + vec2(0.0, trip_time * 0.2)) - 0.5;
		float bubble = smoothstep(0.5, 0.2, length(b));
		col = hue_rgb(depth * 0.18 + COLOR.g * 0.3 + trip_time * 0.06 + hue_offset + trip_hue);
		col = mix(col, vec3(0.1, 0.85, 0.75) * (0.6 + 0.4 * bubble), step(UV.x, 0.5) * 0.6);
	} else {
		col = hue_rgb(UV.x + trip_time * 0.3 + hue_offset);
	}
	ALBEDO = col * alpha * keep * grow;
}
