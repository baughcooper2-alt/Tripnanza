// Snowboard graphics. Uses the board's own local position (x = nose/tail,
// z = edge to edge), so no texture is needed. Patterns are listed in
// CustomizationData.BOARD_PATTERNS.
shader_type spatial;
render_mode diffuse_burley;

uniform vec3 base_color : source_color = vec3(0.93, 0.18, 0.45);
uniform vec3 accent_color : source_color = vec3(0.1, 0.1, 0.12);
uniform vec3 third_color : source_color = vec3(1.0, 0.9, 0.3);
uniform int pattern = 0;
uniform float gloss = 0.35;

varying vec3 lp;
varying vec3 ln;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec2 p = vec2(lp.x / 0.78, lp.z / 0.15);   // -1..1 along and across
	vec3 c = base_color;
	if (ln.y < -0.5) {
		c = accent_color * 0.6;                  // base (P-tex) underside
	} else if (abs(ln.y) < 0.5) {
		c = vec3(0.08);                          // sidewall / edges
	} else if (pattern == 1) {                  // racing stripes
		c = mix(c, accent_color, step(abs(p.y), 0.22));
		c = mix(c, third_color, step(abs(abs(p.y) - 0.3), 0.04));
	} else if (pattern == 2) {                  // chevrons
		float v = fract(p.x * 3.0 + abs(p.y) * 0.8);
		c = mix(c, accent_color, step(0.5, v));
	} else if (pattern == 3) {                  // split
		c = mix(c, accent_color, step(0.0, p.x + p.y * 0.4));
	} else if (pattern == 4) {                  // dots
		vec2 g = fract(p * vec2(6.0, 2.5)) - 0.5;
		c = mix(c, accent_color, step(length(g), 0.28));
	} else if (pattern == 5) {                  // flames from the nose
		float n = hash(floor(vec2(p.x * 20.0, p.y * 4.0)));
		float f = smoothstep(0.2, 0.9, p.x + sin(p.y * 6.0 + p.x * 9.0) * 0.12 + n * 0.08);
		c = mix(c, mix(third_color, accent_color, f), f);
	} else if (pattern == 6) {                  // trip swirl
		float a = atan(p.y * 3.0, p.x);
		float r = length(vec2(p.x, p.y * 3.0));
		float s = sin(a * 4.0 + r * 12.0);
		c = mix(base_color, mix(accent_color, third_color, 0.5 + 0.5 * sin(r * 8.0)), smoothstep(-0.2, 0.2, s));
	} else if (pattern == 7) {                  // wood topsheet
		float grain = sin(p.x * 30.0 + sin(p.y * 7.0) * 2.0 + hash(vec2(floor(p.y * 9.0), 1.0)) * 6.0);
		c = mix(vec3(0.55, 0.38, 0.22), vec3(0.42, 0.27, 0.15), 0.5 + 0.5 * grain);
		c = mix(c, base_color, step(0.85, abs(p.y)));
	}
	ALBEDO = c;
	ROUGHNESS = 1.0 - gloss;
	SPECULAR = 0.5;
}
