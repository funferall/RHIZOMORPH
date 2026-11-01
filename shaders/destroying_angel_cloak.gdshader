shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;

// Cloaked Destroying Angel, as its owner sees it: a glassy blue shimmer with a bright rim.
// Enemies do not see a cloaked Angel at all; the game hides the node for them.
uniform sampler2D skin_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_map : hint_normal, filter_linear_mipmap, repeat_enable;
instance uniform float flash = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float wither = 0.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.5);
	vec3 skin = texture(skin_map, UV).rgb;
	ALBEDO = mix(skin, vec3(0.04, 0.25, 0.55), 0.75);
	ROUGHNESS = 0.65;
	ALPHA = (0.23 + rim * 0.57) * (1.0 - wither);
	vec3 glow = mix(vec3(0.08, 0.55, 1.0), team.rgb, team.a * 0.3);
	EMISSION = glow * rim * 1.4 + vec3(1.0, 0.95, 0.85) * flash * 0.5;
}
