shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

// The Violet Webcap's cortina: silk painted in the atlas, hung on two-sided curtain cards
// and blended over the scene. Gold threads and dew beads glow faintly; light through the
// silk lifts it against dark ground. Moves with the legs through the shared gait.
#include "res://shaders/webcap_gait.gdshaderinc"

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float silk_opacity = 0.7;
uniform vec3 glow_color : source_color = vec3(1.0, 0.66, 0.24);
uniform float glow_energy = 1.6;

varying float dangle;

void vertex() {
	kind = floor(UV2.x + 0.001);
	dangle = kind > 4.5 ? clamp((UV2.x - kind) / 0.98, 0.0, 1.0) : 0.0;
	webcap_gait(VERTEX, UV2);
}

void fragment() {
	vec4 silk = texture(albedo_map, UV);
	float glow = texture(orm_map, UV).b;
	ALBEDO = webcap_tint(silk.rgb);
	// hanging fringes thin out toward their ragged ends
	ALPHA = clamp(silk.a * silk_opacity * (1.0 - wither * 0.7) * (1.0 - smoothstep(0.55, 1.0, dangle) * 0.6), 0.0, 1.0);
	ROUGHNESS = 0.45;
	SPECULAR = 0.6;
	BACKLIGHT = silk.rgb * 0.7;
	EMISSION = glow_color * glow * glow_energy + silk.rgb * 0.06 + vec3(1.0, 0.95, 0.85) * flash * 0.5;
}
