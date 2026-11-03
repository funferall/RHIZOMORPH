shader_type spatial;
render_mode cull_back;

// Splitgill Glider, built in Blender (tools/blender/glider_build.py): one opaque surface, one
// atlas. orm = occlusion, roughness, glow (gold flecks on the bombs), unused.
// UV2.x = kind + 0.98 * weight: 0 body (tail .. nose), 1 wing (root .. margin), 2 tail streamer
// (root .. tip), 3 bomb (top .. bottom), 4 cord (belly .. bomb). 1 - UV2.y = group: the wing side
// (0 left, 1 right) or the bomb index.
//
// Motion is skinned, but on the GPU with no Skeleton3D: the poses come from `bones`, a texture
// baked from UniMate clips by tools/unimate/glider_motion.py (one row per frame, two texels per
// bone: the rotation quaternion and the translation that take the rest pose to that frame). Each
// vertex blends two neighbouring bones along its part's chain, worked out from its data UV, so the
// mesh carries no skin weights. The constants (clips, chains, bombs) are in the include, which the
// baker writes.
#include "res://shaders/splitgill_glider_motion.gdshaderinc"

instance uniform float flash = 0.0;
instance uniform float wither = 0.0;
instance uniform float growing = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float walk = 0.0;
instance uniform float gait = 6.0;
instance uniform float motion_time = -1.0;   // the game's clock, so pause freezes it
instance uniform float strike = 0.0;         // 1 when the bomb run begins, falling to 0 over it

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bones : filter_nearest, repeat_disable;
uniform vec3 glow_color : source_color = vec3(1.0, 0.72, 0.28);
uniform float glow_energy = 1.2;

varying float charge;
const float FALL = 0.32;   // seconds a dropped bomb is seen falling

vec3 qrot(vec4 q, vec3 v) {
	return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}

// one bone's pose in one clip at time `ph` (frames, wrapped for loops)
void pose(int bone, int start, int len, float ph, bool loop, out vec4 q, out vec3 t) {
	float f = loop ? mod(ph, float(len)) : clamp(ph, 0.0, float(len - 1));
	int f0 = int(floor(f));
	int f1 = loop ? (f0 + 1) % len : min(f0 + 1, len - 1);
	float k = f - float(f0);
	vec4 qa = texelFetch(bones, ivec2(bone * 2, start + f0), 0);
	vec4 qb = texelFetch(bones, ivec2(bone * 2, start + f1), 0);
	qb *= sign(dot(qa, qb) + 1e-6);
	q = normalize(mix(qa, qb, k));
	t = mix(texelFetch(bones, ivec2(bone * 2 + 1, start + f0), 0).xyz, texelFetch(bones, ivec2(bone * 2 + 1, start + f1), 0).xyz, k);
}

// a bone's blended pose: glide and flight mixed by `walk`, the bomb run laid over it by `run`
void bone_pose(int bone, float t_glide, float t_fly, float t_run, float fly, float run, out vec4 q, out vec3 t) {
	vec4 qg; vec3 tg; vec4 qf; vec3 tf;
	pose(bone, GLIDE_START, GLIDE_LEN, t_glide, true, qg, tg);
	pose(bone, FLY_START, FLY_LEN, t_fly, true, qf, tf);
	qf *= sign(dot(qg, qf) + 1e-6);
	q = normalize(mix(qg, qf, fly));
	t = mix(tg, tf, fly);
	if (run > 0.0) {
		vec4 qr; vec3 tr;
		pose(bone, RUN_START, RUN_LEN, t_run, false, qr, tr);
		qr *= sign(dot(q, qr) + 1e-6);
		q = normalize(mix(q, qr, run));
		t = mix(t, tr, run);
	}
}

// which two bones a vertex follows, and how far between them: along a chain of (bone, centre)
void chain(int which, float x, out int a, out int b, out float f) {
	int n = CHAIN_LEN[which];
	a = CHAIN_BONE[which * 8];
	b = a;
	f = 0.0;
	if (x <= CHAIN_C[which * 8]) {
		return;
	}
	for (int i = 0; i < 7; i++) {
		if (i + 1 >= n) {
			a = CHAIN_BONE[which * 8 + n - 1];
			b = a;
			f = 0.0;
			return;
		}
		float c0 = CHAIN_C[which * 8 + i];
		float c1 = CHAIN_C[which * 8 + i + 1];
		if (x <= c1) {
			a = CHAIN_BONE[which * 8 + i];
			b = CHAIN_BONE[which * 8 + i + 1];
			f = (x - c0) / (c1 - c0);
			return;
		}
	}
}

void vertex() {
	float kind = floor(UV2.x + 0.001);
	float w = clamp((UV2.x - kind) / 0.98, 0.0, 1.0);
	int g = int(floor(1.0 - UV2.y + 0.002));
	float clock = motion_time >= 0.0 ? motion_time : TIME;

	// the bomb run, over 1 - strike (0 -> 1)
	float on = step(0.001, strike);
	float tr = 1.0 - strike;
	float run = on * smoothstep(0.0, 0.14, tr) * (1.0 - smoothstep(0.85, 1.0, tr));
	charge = on * smoothstep(RELEASE - 0.15, RELEASE, tr) * (1.0 - smoothstep(RELEASE, RELEASE + 0.3, tr));

	// clip times in frames; flight plays faster when the unit moves faster
	float t_glide = clock * CLIP_FPS;
	float t_fly = clock * CLIP_FPS * gait / GAIT_REF;
	float t_run = tr * float(RUN_LEN - 1);

	int a; int b; float f;
	if (kind < 0.5) {
		chain(0, VERTEX.x, a, b, f);
	} else if (kind < 1.5) {
		chain(g == 0 ? 2 : 3, w, a, b, f);
	} else if (kind < 2.5) {
		chain(1, w, a, b, f);
	} else {
		a = BOMB_BONE; b = BOMB_BONE; f = 0.0;
	}

	vec3 rest = VERTEX;
	// the bombs: they swing a little under the belly, drop at the release and grow back
	if (kind > 2.5) {
		int k = clamp(g, 0, 3);
		vec3 c = BOMB_CENTRE[k];
		float is_bomb = step(kind, 3.5);
		float drop = on * step(RELEASE, tr);
		float after = max(tr - RELEASE, 0.0) * SWING_SECONDS;
		// a bomb falls away whole under gravity, carried forward a little, and is gone by FALL;
		// then a new one swells at the cord's end before the run is over
		float falling = drop * (1.0 - step(FALL, after));
		float regrow = smoothstep(FALL, (1.0 - RELEASE) * SWING_SECONDS - 0.02, after);
		float s = mix(1.0, mix(1.0 - smoothstep(FALL - 0.12, FALL, after), regrow, step(FALL, after)), drop * is_bomb);
		vec3 d = rest - c;
		rest = c + d * max(s, 0.001);
		rest.y -= falling * is_bomb * 4.9 * after * after;
		rest.x += falling * is_bomb * 0.8 * after;
		// a cord pulls up while its bomb is gone
		rest.y += drop * (1.0 - is_bomb) * (1.0 - regrow) * 0.05 * w;
		float sway = sin(clock * 2.3 + float(k) * 1.7) * 0.035 + walk * -0.05;
		rest.x += sway * (w * (1.0 - is_bomb) + is_bomb);
	}

	vec4 qa; vec3 ta; vec4 qb; vec3 tb;
	bone_pose(a, t_glide, t_fly, t_run, walk, run, qa, ta);
	vec3 pa = qrot(qa, rest) + ta;
	vec3 na = qrot(qa, NORMAL);
	vec3 ka = qrot(qa, TANGENT);
	vec3 ba = qrot(qa, BINORMAL);
	if (b != a && f > 0.0) {
		bone_pose(b, t_glide, t_fly, t_run, walk, run, qb, tb);
		pa = mix(pa, qrot(qb, rest) + tb, f);
		na = mix(na, qrot(qb, NORMAL), f);
		ka = mix(ka, qrot(qb, TANGENT), f);
		ba = mix(ba, qrot(qb, BINORMAL), f);
	}
	VERTEX = pa;
	NORMAL = normalize(na);
	TANGENT = normalize(ka);
	BINORMAL = normalize(ba);
}

void fragment() {
	vec3 col = texture(albedo_map, UV).rgb;
	vec4 orm = texture(orm_map, UV);
	vec3 nm = texture(normal_map, UV).rgb;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, team.rgb, rim * team.a * 0.22);
	float gray = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(gray * 0.7, gray * 0.55, gray * 0.4), wither);
	ALBEDO = col * mix(1.0, 0.55, growing);
	NORMAL_MAP = nm;
	ROUGHNESS = orm.g;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	SPECULAR = 0.45;
	BACKLIGHT = col * 0.18;   // the thin fans glow through at the margin
	float glow = orm.b * glow_energy * (0.6 + 2.5 * charge) * (1.0 - wither);
	EMISSION = glow_color * glow + vec3(1.0, 0.95, 0.85) * flash * 0.7;
}
