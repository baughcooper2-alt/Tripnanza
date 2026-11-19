// Billboarded powder puffs. Colour + alpha come from the MultiMesh instance.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(vec4(s, 0, 0, 0), vec4(0, s, 0, 0), vec4(0, 0, s, 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 c = UV - 0.5;
	// Hexagonal puff for a faceted look.
	float a = atan(c.y, c.x);
	float hexr = cos(3.14159 / 6.0) / cos(mod(a, 3.14159 / 3.0) - 3.14159 / 6.0);
	float d = length(c) / (0.5 * hexr);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * smoothstep(1.0, 0.6, d);
}
