// Full-screen trip layer. Strongest at the screen edges and the far top,
// never inside the protected play window around the rider and the line ahead.
// No flashes: every term changes smoothly over seconds.
shader_type canvas_item;

#include "res://shaders/trip_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 focus = vec2(0.5, 0.6);      // rider + line ahead, in screen UV
uniform vec2 window = vec2(0.36, 0.42);   // protected ellipse radii
uniform float kaleido = 0.0;
uniform float echo = 0.0;
uniform float melt = 0.0;
uniform float aberration = 0.0;
uniform float speed01 = 0.0;
uniform float reduced = 0.0;

vec3 tex(vec2 uv) {
	return textureLod(screen_tex, clamp(uv, vec2(0.001), vec2(0.999)), 0.0).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = (uv - focus) / window;
	float r = length(p);
	float edge = smoothstep(0.85, 1.6, r);
	float k = 1.0 - reduced * 0.75;

	// Liquid swirl at the edges (melting-portrait reference).
	vec2 w = vec2(fbm(uv * 3.0 + trip_time * 0.07), fbm(uv * 3.0 + 4.1 - trip_time * 0.06)) - 0.5;
	vec2 suv = uv + w * 0.06 * trip_warp * edge * k;
	// Drips running down from the top edge.
	float drip_col = vnoise(vec2(uv.x * 26.0, 0.0)) ;
	float drip_len = drip_col * 0.25 * melt * k;
	float in_drip = smoothstep(drip_len, drip_len - 0.04, uv.y) * step(0.45, drip_col);
	suv.y -= in_drip * 0.05 * melt;

	// Kaleidoscope: fold the angle around the focus but keep the radius, so
	// the folded image comes from the edge ring only (never copies the rider).
	if (kaleido > 0.001) {
		vec2 c = (suv - focus) * vec2(aspect, 1.0);
		float ang = atan(c.y, c.x) + trip_time * 0.04;
		float seg = 6.2831 / 6.0;
		float fa = abs(mod(ang, seg) - seg * 0.5) - trip_time * 0.04 + 1.5708 * 0.0;
		vec2 kuv = focus + vec2(cos(fa), sin(fa)) * length(c) / vec2(aspect, 1.0);
		// Bilateral mirror (flower reference) blended in at the very sides.
		vec2 muv = vec2(0.5 - abs(suv.x - 0.5), suv.y);
		kuv = mix(kuv, muv, 0.5 + 0.5 * sin(trip_time * 0.1));
		suv = mix(suv, kuv, edge * kaleido * k);
	}

	vec3 col = tex(suv);

	// Chromatic aberration grows with speed and edge distance.
	vec2 dir = (uv - focus);
	float ab = aberration * edge * (0.004 + speed01 * 0.006) * k;
	col.r = tex(suv + dir * ab * 2.0).r;
	col.b = tex(suv - dir * ab * 2.0).b;

	// Radial zoom echo: hue-shifted copies streaming outward (astronaut reference).
	if (echo > 0.001) {
		vec3 acc = vec3(0.0);
		for (int i = 1; i <= 4; i++) {
			float f = float(i) / 4.0;
			vec2 e_uv = focus + (suv - focus) * (1.0 - f * 0.08 * (1.0 + speed01));
			vec3 s = tex(e_uv);
			acc += s * hue_rgb(f * 0.35 + trip_time * 0.05 + trip_hue) * (1.0 - f * 0.5);
		}
		col = mix(col, max(col, acc * 0.55), edge * echo * k);
	}

	// Rainbow liquid boundaries in the far top of the image.
	float top = smoothstep(0.32, 0.0, uv.y) * trip_warp * k;
	vec3 liquid = hue_rgb(fbm(uv * 4.0 + w * 2.0 + trip_time * 0.03) * 2.0 + trip_hue);
	col = mix(col, col * 0.5 + liquid * 0.6, top * 0.45);
	col = mix(col, col * 0.4 + liquid * 0.7, in_drip * melt * 0.7);

	// Gentle vignette (always on) that tints toward violet with the trip.
	float vig = smoothstep(1.1, 2.2, r);
	col *= 1.0 - vig * 0.25;
	col += vec3(0.25, 0.05, 0.35) * vig * trip_intensity * 0.25 * k;

	COLOR = vec4(col, 1.0);
}
