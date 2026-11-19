// Blinker gate frame. UV.x = position along the frame from base (0) to crown
// (1). Segments light up from the snow toward the crown as `lit` rises.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;

#include "res://shaders/trip_common.gdshaderinc"

uniform float lit = 0.0;
uniform float segments = 9.0;
uniform vec3 base_color : source_color = vec3(0.35, 0.95, 1.0);
uniform float rainbow = 0.0;
uniform float fade = 1.0;
uniform float pulse = 0.0;

void fragment() {
	float seg = floor(UV.x * segments) / segments;
	float on = step(seg, lit * 1.001 - 0.0001);
	float gap = smoothstep(0.0, 0.12, fract(UV.x * segments)) * smoothstep(1.0, 0.88, fract(UV.x * segments));
	vec3 c = mix(base_color, hue_rgb(seg * 0.6 + trip_time * 0.2), rainbow);
	float glow = mix(0.12, 1.0, on) * (0.85 + 0.15 * sin(trip_time * 3.0 - seg * 6.0)) + pulse;
	ALBEDO = c * glow * gap * fade * 1.4;
}
