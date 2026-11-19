// Clothing / hair recolour. dye_amount 0 = the asset's own colours, 1 = fully
// dyed to dye_color while keeping the texture's light and dark detail.
shader_type spatial;
render_mode diffuse_burley, cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform float use_normal = 0.0;
uniform vec3 dye_color : source_color = vec3(1.0);
uniform float dye_amount = 0.0;
uniform float alpha_cut = 0.0;     // > 0 for hair cards / lace
uniform float roughness = 0.8;
uniform float sheen = 0.0;

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	float l = dot(a.rgb, vec3(0.299, 0.587, 0.114));
	// Dye relative to the garment's own average brightness (lowest mip), so
	// dark and light fabrics both take the chosen colour and keep their folds.
	float avg = dot(textureLod(albedo_tex, UV, 12.0).rgb, vec3(0.299, 0.587, 0.114));
	vec3 dyed = dye_color * clamp(l / max(avg, 0.04), 0.35, 1.5);
	ALBEDO = mix(a.rgb, dyed, dye_amount);
	if (alpha_cut > 0.0) {
		ALPHA = a.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	}
	ROUGHNESS = roughness;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = ALBEDO * fres * sheen;
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
