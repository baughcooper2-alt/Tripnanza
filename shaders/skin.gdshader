// Realistic skin for the MakeHuman body. Vertex colour encodes body regions
// (R torso, G arms, B legs, A feet; hands = all zero but flagged in UV2.x)
// so parts covered by clothing can be hidden and never poke through.
shader_type spatial;
render_mode diffuse_burley, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform float use_normal = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec4 hide = vec4(0.0);      // torso, arms, legs, feet (1 = hidden)
uniform float hide_hands = 0.0;
uniform float hide_head = 0.0;

void fragment() {
	vec4 r = COLOR;
	float hand = step(0.5, UV2.x);
	float headr = step(0.5, UV2.y);
	float hidden = max(max(r.r * hide.x, r.g * hide.y), max(r.b * hide.z, r.a * hide.w));
	hidden = max(hidden, hand * hide_hands);
	hidden = max(hidden, headr * hide_head);
	if (hidden > 0.5) {
		discard;
	}
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb * tint;
	ROUGHNESS = 0.55;
	SPECULAR = 0.35;
	SSS_STRENGTH = 0.35;
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
