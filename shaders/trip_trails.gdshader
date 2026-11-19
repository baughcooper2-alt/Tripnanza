// Trail buffer. Its viewport is never cleared, so drawing the current frame at
// partial opacity leaves exponentially fading copies of previous frames.
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D world_tex : filter_linear;
uniform float keep = 0.0;   // how much of the previous trail survives each frame

void fragment() {
	COLOR = vec4(texture(world_tex, UV).rgb, 1.0 - keep);
}
