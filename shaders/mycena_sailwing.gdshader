shader_type spatial;
render_mode cull_back;

// Mycena Sailwing, built in Blender (tools/blender/sailwing_build.py): one opaque surface,
// one atlas. orm = occlusion, roughness, glow (gold gills and strand tips), unused.
// UV2.x = kind + 0.98 * weight: 0 body (tail .. beak), 1 cap (axis .. rim), 2 stem (body .. cap),
// 3 strand (root .. tip). 1 - UV2.y = group: the cap index for caps and stems (0 the crown, then
// pairs out along the wing, odd on the left), the strand index for strands.
// Nothing is skinned. Each cap swings rigidly about its stem's root and its stem bends to follow;
// the bells contract like a jellyfish's, in a ripple from the crown out to the wingtips.
instance uniform float flash = 0.0;
instance uniform float wither = 0.0;
instance uniform float growing = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float walk = 0.0;
instance uniform float gait = 6.0;
instance uniform float motion_time = -1.0;   // the game's clock, so pause freezes it
instance uniform float strike = 0.0;         // 1 when the volley begins, falling to 0 over it

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 glow_color : source_color = vec3(1.0, 0.74, 0.26);
uniform float glow_energy = 1.4;

varying float kind;
varying float charge;   // the gills flare bright as the volley builds and lands
varying float beat;

// Rig, printed by the build script (--rig).
const vec3 STEM_ROOT[7] = {vec3(-0.1000, 1.3000, 0.0000), vec3(0.0200, 1.3000, -0.0500), vec3(0.0200, 1.3000, 0.0500), vec3(-0.1400, 1.2800, -0.0800), vec3(-0.1400, 1.2800, 0.0800), vec3(-0.2800, 1.2400, -0.0700), vec3(-0.2800, 1.2400, 0.0700)};
const vec3 CAP_AXIS[7] = {vec3(-0.0959, 0.9954, 0.0000), vec3(0.1819, 0.9262, -0.3302), vec3(0.1819, 0.9262, 0.3302), vec3(-0.1784, 0.8147, -0.5517), vec3(-0.1784, 0.8147, 0.5517), vec3(-0.4668, 0.6659, -0.5820), vec3(-0.4668, 0.6659, 0.5820)};
const vec3 CAP_CENTRE[7] = {vec3(-0.1920, 1.7331, 0.0000), vec3(0.1126, 1.7144, -0.3860), vec3(0.1126, 1.7144, 0.3860), vec3(-0.3535, 1.5726, -0.7839), vec3(-0.3535, 1.5726, 0.7839), vec3(-0.7747, 1.1788, -0.8413), vec3(-0.7747, 1.1788, 0.8413)};
const vec3 HUB = vec3(-0.05, 1.18, 0.0);
// The volley, over 1 - strike (0 -> 1): it rears with the bells flared and the wings raised,
// then at CLAP the wings beat down, the bells snap shut and the darts leave from the beak;
// it lunges after them and shivers back to its hover.
const float CLAP = 0.4;

// Rodrigues: v turned by angle a about the unit axis k.
vec3 turn(vec3 v, vec3 k, float a) {
	float c = cos(a);
	float s = sin(a);
	return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
}

void vertex() {
	kind = floor(UV2.x + 0.001);
	float w = clamp((UV2.x - kind) / 0.98, 0.0, 1.0);
	int g = int(floor(1.0 - UV2.y + 0.002));
	float clock = motion_time >= 0.0 ? motion_time : TIME;
	float is_cap = step(0.5, kind) * (1.0 - step(1.5, kind));
	float is_stem = step(1.5, kind) * (1.0 - step(2.5, kind));
	float is_strand = step(2.5, kind);

	// --- the volley
	float on = step(0.001, strike);
	float t = 1.0 - strike;
	float rear = on * smoothstep(0.0, CLAP - 0.04, t) * (1.0 - smoothstep(CLAP - 0.04, CLAP + 0.03, t));
	float clap = on * smoothstep(CLAP - 0.05, CLAP + 0.02, t) * (1.0 - smoothstep(CLAP + 0.08, CLAP + 0.45, t));
	float after = max(t - CLAP, 0.0);
	float shiver = on * step(CLAP, t) * sin(after * 32.0) * exp(-after * 6.5);
	charge = rear * 0.6 + clap;

	// --- the caps and stems: a flap about each stem root, rippling out along the wing
	if (is_cap + is_stem > 0.5) {
		int k = clamp(g, 0, 6);
		float pair = float((k + 1) / 2);
		float sd = k == 0 ? 0.0 : (k % 2 == 1 ? -1.0 : 1.0);
		float lag = pair * 0.55;
		// at rest a slow pulse; in flight one beat per stride (gait radians a second)
		float p_rest = pow(0.5 + 0.5 * sin(clock * 2.2 - lag), 2.0);   // 1 at the bell's tightest
		float p_fly = pow(0.5 + 0.5 * sin(clock * gait - lag), 2.0);
		float p = mix(p_rest, p_fly, walk);
		beat = p;
		// a wing beat: up as the bell opens, down as it closes; harder in flight
		float flap = (0.10 + 0.08 * walk) * (0.5 - p) * (0.4 + 0.3 * pair);
		flap += 0.22 * rear * (0.4 + 0.25 * pair) - 0.30 * clap * (0.4 + 0.25 * pair) + 0.05 * shiver;
		// the crown nods instead, back as it rears, forward as it claps
		float nod = k == 0 ? (0.05 * (0.5 - p) + 0.18 * rear - 0.22 * clap) : 0.0;
		// in flight the wings sweep back
		float sweep = sd * (0.10 * walk + 0.06 * rear);
		vec3 pivot = STEM_ROOT[k];
		float bend = is_cap > 0.5 ? 1.0 : smoothstep(0.0, 1.0, w);
		// the bell contracts toward its axis, the rim most, and stretches along it
		if (is_cap > 0.5) {
			vec3 U = CAP_AXIS[k];
			vec3 d = VERTEX - CAP_CENTRE[k];
			float h = dot(d, U);
			vec3 lat = d - U * h;
			float squeeze = (0.13 * p - 0.16 * rear + 0.30 * clap - 0.05 * shiver) * w * w;
			VERTEX = CAP_CENTRE[k] + lat * (1.0 - squeeze) + U * (h + squeeze * 0.12);
		}
		vec3 arm = VERTEX - pivot;
		float a_roll = -sd * flap * bend;   // positive flap lifts the wing on either side
		arm = turn(arm, vec3(1.0, 0.0, 0.0), a_roll);
		NORMAL = turn(NORMAL, vec3(1.0, 0.0, 0.0), a_roll);
		TANGENT = turn(TANGENT, vec3(1.0, 0.0, 0.0), a_roll);
		BINORMAL = turn(BINORMAL, vec3(1.0, 0.0, 0.0), a_roll);
		float a_yaw = sweep * bend;
		arm = turn(arm, vec3(0.0, 1.0, 0.0), a_yaw);
		NORMAL = turn(NORMAL, vec3(0.0, 1.0, 0.0), a_yaw);
		TANGENT = turn(TANGENT, vec3(0.0, 1.0, 0.0), a_yaw);
		BINORMAL = turn(BINORMAL, vec3(0.0, 1.0, 0.0), a_yaw);
		float a_nod = nod * bend;
		arm = turn(arm, vec3(0.0, 0.0, 1.0), a_nod);
		NORMAL = turn(NORMAL, vec3(0.0, 0.0, 1.0), a_nod);
		TANGENT = turn(TANGENT, vec3(0.0, 0.0, 1.0), a_nod);
		BINORMAL = turn(BINORMAL, vec3(0.0, 0.0, 1.0), a_nod);
		VERTEX = pivot + arm;
	} else {
		beat = mix(0.5 + 0.5 * sin(clock * 2.2 - 0.3), 0.5 + 0.5 * sin(clock * gait - 0.3), walk);
	}

	// --- the strands: a travelling wave, streaming back in flight and on the lunge
	if (is_strand > 0.5) {
		float gf = float(g);
		float reach = pow(w, 1.4);
		float wave = clock * 2.6 - w * 5.0 + gf * 1.9;
		float fly = clock * gait - w * 5.0 + gf * 1.9;
		VERTEX.z += mix(sin(wave), sin(fly), walk) * 0.07 * reach;
		VERTEX.y += mix(sin(wave * 0.8 + 1.3), sin(fly + 1.3), walk) * 0.035 * reach;
		VERTEX.x += sin(wave * 0.6 + gf) * 0.03 * reach * (1.0 - walk);
		VERTEX.x -= (0.22 * walk + 0.14 * clap) * reach;
		VERTEX.y += (0.16 * walk + 0.06 * clap) * reach;
	}

	// --- the whole body: hover bob, rear back and lunge, nose down in flight
	float bob = sin(clock * 1.7) * 0.06 + (beat - 0.5) * 0.03 + 0.08 * rear - 0.05 * clap;
	float pitch = -0.08 * walk + sin(clock * 1.3 + 0.4) * 0.025 + 0.24 * rear - 0.20 * clap + 0.05 * shiver;
	float roll = sin(clock * 0.9) * 0.035;
	vec3 arm = VERTEX - HUB;
	arm = turn(arm, vec3(0.0, 0.0, 1.0), pitch);
	arm = turn(arm, vec3(1.0, 0.0, 0.0), roll);
	NORMAL = turn(turn(NORMAL, vec3(0.0, 0.0, 1.0), pitch), vec3(1.0, 0.0, 0.0), roll);
	TANGENT = turn(turn(TANGENT, vec3(0.0, 0.0, 1.0), pitch), vec3(1.0, 0.0, 0.0), roll);
	BINORMAL = turn(turn(BINORMAL, vec3(0.0, 0.0, 1.0), pitch), vec3(1.0, 0.0, 0.0), roll);
	VERTEX = HUB + arm + vec3(0.12 * clap - 0.06 * rear, bob, 0.0);
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
	// the bonnets are thin and waxy: light comes through them
	float cap = step(0.5, kind) * (1.0 - step(1.5, kind));
	BACKLIGHT = col * mix(0.12, 0.45, cap);
	float glow = orm.b * glow_energy * (0.75 + 0.35 * beat + 2.2 * charge) * (1.0 - wither);
	EMISSION = glow_color * glow + vec3(1.0, 0.95, 0.85) * flash * 0.7;
}
