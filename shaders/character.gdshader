// Rider: smooth shading, fabric-like jacket and pants, soft sheen and a subtle
// rim so the silhouette always reads against snow and trip colours.
shader_type spatial;
render_mode diffuse_burley;

#include "res://shaders/trip_common.gdshaderinc"

uniform vec3 tint : source_color = vec3(1.0);
uniform float roughness = 0.75;
uniform float sheen = 0.25;

void fragment() {
	vec3 base = tint * COLOR.rgb;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// Fabric weave noise (very fine) for a less plastic look.
	float weave = vnoise(UV * 220.0) * 0.06;
	ALBEDO = base * (0.97 - weave) * (1.0 - fres * (0.25 + trip_intensity * 0.3));
	EMISSION = base * fres * sheen * 0.4;
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
}
