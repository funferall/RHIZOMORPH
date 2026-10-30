shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, depth_test_disabled, shadows_disabled;

// Flat faction ring under every unit / structure; brighter when selected.
// Drawn without depth test so moss never swallows it, but hidden when
// something solid (a trunk, a cap) stands well in front of it.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float selected = 0.0;

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -v.z / v.w;
	if (-VERTEX.z - scene_z > 1.4) {
		discard;
	}
	float r = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.78, 0.86, r) * (1.0 - smoothstep(0.92, 1.0, r));
	float fill = (1.0 - smoothstep(0.0, 0.9, r)) * 0.08;
	float a = ring * mix(0.35, 1.0, selected) + fill * selected;
	ALBEDO = team.rgb * a * (1.0 + selected);
}
