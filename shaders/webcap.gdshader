shader_type spatial;
render_mode cull_back;

// Violet Webcap body, built in Blender (tools/blender/webcap_build.py): a baked atlas
// for colour, sculpted normals, occlusion, roughness and glow. The cortina is the mesh's
// second surface (webcap_silk.gdshader).
#include "res://shaders/webcap_gait.gdshaderinc"

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float cap_clearcoat = 0.9;
uniform float cap_sheen = 0.55;
uniform vec3 glow_color : source_color = vec3(1.0, 0.66, 0.24);
uniform float glow_energy = 1.4;
// Atlas centre of the cap's polar disk, in Godot UV space (glTF flips v).
const vec2 CAP_CENTER = vec2(0.25, 0.25);

void vertex() {
	kind = floor(UV2.x + 0.001);
	webcap_gait(VERTEX, UV2);
}

void fragment() {
	vec3 orm = texture(orm_map, UV).rgb;
	float is_cap = step(0.5, kind) * (1.0 - step(1.5, kind));
	float is_gill = step(1.5, kind) * (1.0 - step(2.5, kind));
	vec3 col = texture(albedo_map, UV).rgb;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, team.rgb, rim * team.a * 0.25);
	ALBEDO = webcap_tint(col);
	NORMAL_MAP = texture(normal_map, UV).rgb;
	ROUGHNESS = orm.g;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.35;
	SPECULAR = mix(0.5, 0.62, is_cap);
	// The cap: a wet clear coat over silky radial fibrils that throw a ring-shaped sheen.
	CLEARCOAT = cap_clearcoat * is_cap;
	CLEARCOAT_ROUGHNESS = 0.16;
	vec2 radial = UV - CAP_CENTER;
	ANISOTROPY = cap_sheen * is_cap * smoothstep(0.01, 0.05, length(radial));
	ANISOTROPY_FLOW = normalize(vec2(-radial.y, radial.x) + vec2(1e-5));
	BACKLIGHT = col * is_gill * 0.2;
	EMISSION = glow_color * orm.b * glow_energy + vec3(1.0, 0.95, 0.85) * flash * 0.7;
}
