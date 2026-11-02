shader_type spatial;
render_mode cull_back;

// The beetle and its Whitecoat Bulwark thrall, built in Blender (tools/blender/beetle_build.py):
// one opaque surface, one atlas. orm = occlusion, roughness, where the white spore dust settles
// on an infected body, unused.
// UV2.x = kind + 0.98 * weight: 0 shell, 1 leg (weight hip 0 -> claw 1), 2 pronotum, 3 head
// (weight along an antenna); 5..8 are Beauveria tufts riding kind - 5.
// 1 - UV2.y = group + tuft radius: the leg index 0..5 (side = k % 2, pair = k / 2) on legs;
// 0 head capsule, 1 / 2 antennae, 3 / 4 mandibles on the head.
// Nothing is skinned: legs swing about their hips on alternating tripods, the head nods
// about NECK, and the whole body rears and slams about PIVOT to attack.
instance uniform float flash = 0.0;
instance uniform float wither = 0.0;
instance uniform float growing = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float walk = 0.0;
instance uniform float gait = 13.0;
instance uniform float motion_time = -1.0;   // the game's clock, so pause freezes it
instance uniform float strike = 0.0;         // 1 when the attack begins, falling to 0 over it
instance uniform float infect = 1.0;         // 0 a healthy beetle .. 1 a thrall, white with Beauveria

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 dust_color : source_color = vec3(0.93, 0.91, 0.85);

varying float fuzz;
varying float shell;

// Rig, printed by the build script.
const vec3 HIPS[6] = vec3[6](vec3(0.3, 0.23, -0.13), vec3(0.3, 0.23, 0.13), vec3(0.1, 0.23, -0.13),
	vec3(0.1, 0.23, 0.13), vec3(-0.1, 0.23, -0.13), vec3(-0.1, 0.23, 0.13));
const vec3 NECK = vec3(0.46, 0.44, 0.0);
const vec3 MANDIBLE = vec3(0.585, 0.33, 0.06);   // z mirrored for the left one
const vec3 PIVOT = vec3(-0.24, 0.1, 0.0);        // it rears back onto its hind legs
// The attack, over 1 - strike (0 -> 1): it rears up with its mandibles spread and front legs
// pawing, slams down and forward, and snaps them shut on the bite at IMPACT; a shiver runs
// through it and, on a thrall, the tufts puff out.
const float IMPACT = 0.4;

vec2 turn(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

void vertex() {
	float kind = floor(UV2.x + 0.001);
	float w = clamp((UV2.x - kind) / 0.98, 0.0, 1.0);
	float vv = 1.0 - UV2.y;   // glTF stores v flipped
	float grp = floor(vv + 0.002);
	float rr = clamp(vv - grp, 0.0, 0.5);
	float tuft = step(4.5, kind);
	float base = kind - 5.0 * tuft;
	fuzz = tuft;
	float is_leg = 1.0 - step(0.5, abs(base - 1.0));
	float is_head = 1.0 - step(0.5, abs(base - 3.0));
	shell = (1.0 - tuft) * (1.0 - is_leg);
	float clock = motion_time >= 0.0 ? motion_time : TIME;
	float stride = clock * gait;

	// --- the attack
	float on = step(0.001, strike);
	float t = 1.0 - strike;
	float rear = on * smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.3, IMPACT, t));
	float slam = on * smoothstep(0.28, IMPACT, t) * (1.0 - smoothstep(IMPACT + 0.08, 0.95, t));
	float after = max(t - IMPACT, 0.0);
	float shiver = on * step(IMPACT, t) * sin(after * 42.0) * exp(-after * 8.0);
	float puff = on * exp(-pow((t - IMPACT - 0.05) / 0.09, 2.0));

	// --- tufts swell out of the seams as the infection takes, breathe, and puff at the bite
	if (tuft > 0.5) {
		float grow = smoothstep(0.0, 1.0, infect);
		VERTEX -= NORMAL * rr * (1.0 - grow) * 1.05;
		VERTEX += NORMAL * rr * (0.25 * puff + 0.035 * sin(clock * 1.7 + rr * 60.0 + grp));
	}

	// --- the head: antennae flick, mandibles chew and spread, the head nods about the neck
	if (is_head > 0.5) {
		if (grp > 0.5 && grp < 2.5) {
			float sd = grp < 1.5 ? -1.0 : 1.0;
			float ww = w * w;
			VERTEX.y += (sin(clock * 3.1 + grp * 1.7) * 0.025 + 0.06 * rear - 0.03 * slam) * ww;
			VERTEX.z += sd * (sin(clock * 2.3 + grp) * 0.018 + 0.05 * rear) * ww;
			VERTEX.x -= 0.04 * rear * ww;
		} else if (grp > 2.5) {
			float sd = grp < 3.5 ? -1.0 : 1.0;
			float open = 0.75 * rear + 0.1 * max(sin(clock * 2.6 + grp), 0.0) * (1.0 - on);
			vec3 hinge = vec3(MANDIBLE.x, MANDIBLE.y, sd * MANDIBLE.z);
			vec2 arm = vec2(VERTEX.x - hinge.x, VERTEX.z - hinge.z);
			vec2 r2 = turn(arm, sd * open);
			VERTEX.x = hinge.x + r2.x;
			VERTEX.z = hinge.z + r2.y;
			NORMAL.xz = turn(NORMAL.xz, sd * open);
		}
		float nod = 0.32 * rear - 0.22 * slam + 0.05 * shiver + sin(2.0 * stride + 0.6) * 0.025 * walk
			+ sin(clock * 0.9) * 0.02;
		vec2 arm = VERTEX.xy - NECK.xy;
		VERTEX.xy = NECK.xy + turn(arm, nod);
		NORMAL.xy = turn(NORMAL.xy, nod);
		TANGENT.xy = turn(TANGENT.xy, nod);
		BINORMAL.xy = turn(BINORMAL.xy, nod);
	}

	// --- legs: alternating tripods (left front, right middle, left hind, then the others)
	float planted = 0.0;   // how much this vertex stays on the ground while the body moves
	if (is_leg > 0.5) {
		int leg = int(grp + 0.5);
		int side = leg % 2;
		int pair = leg / 2;
		float sd = side == 0 ? -1.0 : 1.0;
		float phase = stride + float((pair + side) % 2) * PI;
		float m = smoothstep(0.0, 0.18, w);
		float lift = max(cos(phase), 0.0) * walk;
		float swing = sin(phase) * 0.34 * walk;
		// front legs paw the air while it rears; the others brace
		float paw = pair == 0 ? rear : 0.0;
		swing += (pair == 0 ? 0.35 * rear - 0.15 * slam : (pair == 2 ? -0.12 * rear : 0.0));
		vec3 hip = HIPS[leg];
		vec2 arm = vec2(VERTEX.x - hip.x, VERTEX.z - hip.z);
		float a = swing * sd * m;
		vec2 r2 = turn(arm, a);
		VERTEX.x = hip.x + r2.x;
		VERTEX.z = hip.z + r2.y;
		NORMAL.xz = turn(NORMAL.xz, a);
		TANGENT.xz = turn(TANGENT.xz, a);
		BINORMAL.xz = turn(BINORMAL.xz, a);
		VERTEX.y += (lift * 0.075 + paw * 0.2 * smoothstep(0.3, 1.0, w)) * m;
		planted = pair == 0 ? 0.0 : smoothstep(0.35, 0.8, w);
	}

	// --- the body: rear and slam about the hind legs, lunge, bob and roll as it walks
	float pitch = 0.36 * rear - 0.12 * slam + 0.04 * shiver;
	float roll = sin(stride) * 0.035 * walk;
	float bob = sin(2.0 * stride) * 0.014 * walk - 0.02 * slam;
	float lunge = 0.13 * slam - 0.05 * rear;
	float k = 1.0 - planted;
	vec3 p = VERTEX;
	vec3 n = NORMAL;
	vec2 pa = turn(p.xy - PIVOT.xy, pitch);
	p.xy = PIVOT.xy + pa;
	n.xy = turn(n.xy, pitch);
	vec2 pr = turn(vec2(p.z, p.y - 0.3), roll);
	p.z = pr.x;
	p.y = pr.y + 0.3;
	n.zy = turn(n.zy, roll);
	p.x += lunge;
	p.y += bob;
	VERTEX = mix(VERTEX, p, k);
	NORMAL = normalize(mix(NORMAL, n, k));
	TANGENT.xy = mix(TANGENT.xy, turn(TANGENT.xy, pitch), k);
	BINORMAL.xy = mix(BINORMAL.xy, turn(BINORMAL.xy, pitch), k);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// cotton has no hard outline: fibres fray its edge where it turns away from the eye
	if (fuzz > 0.5) {
		float edge = 1.0 - abs(dot(NORMAL, VIEW));
		float fibre = hash(floor(UV * vec2(900.0, 260.0)));
		if (edge > 0.62 + 0.36 * fibre) {
			discard;
		}
	}
	vec3 col = texture(albedo_map, UV).rgb;
	vec4 orm = texture(orm_map, UV);
	float grow = smoothstep(0.0, 1.0, infect);
	// white muscardine dust over an infected shell, thickest in the seams
	float dust = smoothstep(0.15, 0.85, orm.b) * grow * (1.0 - fuzz);
	col = mix(col, dust_color, dust * 0.75);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, team.rgb, rim * team.a * 0.22);
	// cotton catches the light at its edges
	col += fuzz * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0) * 0.18;
	float gray = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(gray * 0.7, gray * 0.55, gray * 0.4), wither);
	ALBEDO = col * mix(1.0, 0.55, growing);
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.55, fuzz);   // soft cotton, not crust
	ROUGHNESS = mix(orm.g, 0.9, dust);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	SPECULAR = 0.5;
	// a lacquered shell, cotton that lets light through
	CLEARCOAT = 0.6 * shell * (1.0 - dust);
	CLEARCOAT_ROUGHNESS = 0.25;
	BACKLIGHT = mix(col * 0.04, vec3(0.5, 0.48, 0.42), fuzz);
	EMISSION = vec3(1.0, 0.95, 0.85) * flash * 0.7;
}
