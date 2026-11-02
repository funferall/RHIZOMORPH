shader_type spatial;
render_mode cull_back;

// Muscarine Spitter, built in Blender (tools/blender/spitter_build.py): one opaque surface,
// one atlas. orm = occlusion, roughness, glow (the golden throat), unused.
// UV2.x = kind + 0.98 * gait weight (0 bulb, 1 stalk, 2 cap and gills); UV2.y = the bulb's gait pair.
// Nothing is skinned. The stalk bends like a reed by height and the cap rides its top
// rigidly, nodding about NECK, so the whole top-heavy body wobbles on its four bulbs.
instance uniform float flash = 0.0;
instance uniform float wither = 0.0;
instance uniform float growing = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float walk = 0.0;
instance uniform float gait = 6.6;
instance uniform float motion_time = -1.0;   // the game's clock, so pause freezes it
instance uniform float strike = 0.0;         // 1 when the spit begins, falling to 0 over it

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 glow_color : source_color = vec3(1.0, 0.76, 0.2);
uniform float glow_energy = 1.3;

varying float kind;
varying float charge;   // the throat brightens as the spit builds

// Rig, printed by the build script.
const vec3 NECK = vec3(-0.28, 1.34, 0.0);
const vec3 CAP_ORIGIN = vec3(-0.2008, 1.2307, 0.0);
const vec3 CAP_UP = vec3(-0.581, 0.8139, 0.0);
const float BASE_Y = 0.22;
// The spit, over 1 - strike (0 -> 1): the stalk coils back, the cap rears until its golden
// throat shows and squeezes tight, then the stalk lashes forward and the mouth snaps level
// at the target; the glob leaves at SPIT (where the game launches the shot), and the whole
// stalk shivers back to rest.
const float SPIT = 0.353;

vec2 turn(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

void vertex() {
	kind = floor(UV2.x + 0.001);
	float w = clamp((UV2.x - kind) / 0.98, 0.0, 1.0);
	float pair = 1.0 - UV2.y;   // glTF stores v flipped
	float clock = motion_time >= 0.0 ? motion_time : TIME;
	float stride = clock * gait;
	float phase = stride + pair * PI;
	vec3 rest = VERTEX;
	float bulb = 1.0 - step(0.5, kind);
	float cap = step(1.5, kind);
	// 0 at the foot of the stalk, 1 at the neck and through the cap
	float up = mix(clamp((rest.y - BASE_Y) / (NECK.y - BASE_Y), 0.0, 1.0), 1.0, cap) * (1.0 - bulb);
	float bend = up * up;

	// --- the spit
	float on = step(0.001, strike);
	float t = 1.0 - strike;
	float coil = on * smoothstep(0.0, SPIT - 0.03, t) * (1.0 - smoothstep(SPIT - 0.03, SPIT + 0.02, t));
	float lash = on * smoothstep(SPIT - 0.05, SPIT + 0.01, t) * (1.0 - smoothstep(SPIT + 0.06, SPIT + 0.34, t));
	float after = max(t - SPIT, 0.0);
	float shiver = on * step(SPIT, t) * sin(after * 34.0) * exp(-after * 6.0);
	charge = coil + lash * 0.8;

	// --- the wobble: every motion lags further behind the higher up the stalk it is
	float lag = up * 1.9;
	float sway_x = 0.06 * walk + sin(2.0 * stride - lag) * 0.06 * walk + sin(clock * 2.3) * 0.018;
	float sway_z = sin(stride - lag) * 0.14 * walk + sin(clock * 1.65 + 1.0) * 0.024;
	sway_x += -0.22 * coil + 0.24 * lash + 0.08 * shiver;
	sway_z += 0.03 * shiver;
	// the cap nods (positive lifts the opening and tips the hook back)
	float nod = sin(2.0 * stride - 2.9) * 0.10 * walk + sin(stride - lag - 0.5) * 0.05 * walk + sin(clock * 2.3 - 0.8) * 0.03;
	nod += 0.72 * coil + 0.16 * lash - 0.16 * shiver;
	// it squeezes the cap to drive the spit out, and the cap breathes
	float squeeze = 0.22 * coil - 0.09 * lash + 0.04 * shiver + sin(clock * 1.9) * 0.015 + sin(2.0 * stride) * 0.025 * walk;
	// it crouches into its bulbs as it coils, and bobs as it waddles
	float bob = -abs(sin(stride)) * 0.035 * walk - 0.06 * coil + 0.025 * lash;

	if (cap > 0.5) {
		// squeeze side to side and stretch along the cone, about the rim
		vec3 d = VERTEX - CAP_ORIGIN;
		VERTEX.z *= 1.0 - squeeze;
		VERTEX.xy += CAP_UP.xy * max(dot(d, CAP_UP), 0.0) * squeeze * 0.45;
		NORMAL.z /= 1.0 - squeeze;
		NORMAL = normalize(NORMAL);
	}
	// the nod turns the cap, and blends down into the top of the stalk
	float nod_w = max(cap, smoothstep(0.72, 1.0, up));
	vec2 arm = VERTEX.xy - NECK.xy;
	float a = nod * nod_w;
	VERTEX.xy = NECK.xy + turn(arm, a);
	NORMAL.xy = turn(NORMAL.xy, a);
	TANGENT.xy = turn(TANGENT.xy, a);
	BINORMAL.xy = turn(BINORMAL.xy, a);
	// bend the stalk; keep its length by letting the top sink as it swings out
	VERTEX.x += sway_x * bend;
	VERTEX.z += sway_z * bend;
	VERTEX.y -= (sway_x * sway_x + sway_z * sway_z) * 0.55 * bend;
	VERTEX.y += bob * smoothstep(0.0, 0.35, rest.y) * (1.0 - bulb);

	// the bulbs: diagonal pairs lift and swing forward; planted ones squash under the weight
	float lift = max(cos(phase), 0.0);
	float plant = max(-cos(phase), 0.0) * walk;
	VERTEX.x += sin(phase) * 0.10 * w * walk * bulb;
	VERTEX.y += lift * 0.075 * w * walk * bulb;
	float squash = (0.08 * plant + 0.12 * coil - 0.04 * lash) * bulb;
	VERTEX.y *= 1.0 - squash;
	VERTEX.xz *= 1.0 + squash * 0.35 * bulb;
}

void fragment() {
	vec3 col = texture(albedo_map, UV).rgb;
	vec4 orm = texture(orm_map, UV);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, team.rgb, rim * team.a * 0.22);
	float gray = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(gray * 0.7, gray * 0.55, gray * 0.4), wither);
	ALBEDO = col * mix(1.0, 0.55, growing);
	NORMAL_MAP = texture(normal_map, UV).rgb;
	ROUGHNESS = orm.g;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	SPECULAR = 0.5;
	BACKLIGHT = col * 0.10;
	float pulse = 0.8 + 0.2 * sin((motion_time >= 0.0 ? motion_time : TIME) * 2.7);
	EMISSION = glow_color * orm.b * glow_energy * (pulse + 2.6 * charge) + vec3(1.0, 0.95, 0.85) * flash * 0.7;
}
