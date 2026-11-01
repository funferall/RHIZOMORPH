shader_type spatial;
render_mode cull_disabled;

// Revealed Destroying Angel: the GLB's ivory PBR look plus the game's team rim and hit flash.
uniform sampler2D skin_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_map : hint_normal, filter_linear_mipmap, repeat_enable;
instance uniform float flash = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float wither = 0.0;

void fragment() {
	vec3 col = texture(skin_map, UV).rgb * 0.7;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, team.rgb, rim * team.a * 0.25);
	float gray = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(gray * 0.7, gray * 0.55, gray * 0.4), wither);
	ALBEDO = col;
	NORMAL_MAP = texture(detail_map, UV).rgb;
	NORMAL_MAP_DEPTH = 0.42;
	ROUGHNESS = 0.82;
	EMISSION = vec3(1.0, 0.95, 0.85) * flash * 0.7;
}
