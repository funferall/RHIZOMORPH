shader_type spatial;
render_mode cull_back;

// Morel Bruiser, built in Blender (tools/blender/bruiser_build.py): one opaque surface, one
// atlas. orm = occlusion, roughness, glow, height (1 honeycomb ridge, 0 pit floor).
// UV2.x = kind + 0.98 * gait weight (0 belly, 1 cap, 2 shoulder, 3 limb, 4 toe/knuckle);
// UV2.y = gait pair, plus 2 on the arms and shoulders (they swing in the attack).
// The honeycomb gets parallax depth only when the camera is close; far away it costs nothing.
instance uniform float flash = 0.0;
instance uniform float wither = 0.0;
instance uniform float growing = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float walk = 0.0;
instance uniform float gait = 5.6;
instance uniform float motion_time = -1.0;   // the game's clock, so pause freezes it
instance uniform float strike = 0.0;         // 1 when the swing starts, falling to 0 over it

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 glow_color : source_color = vec3(1.0, 0.72, 0.28);
uniform float glow_energy = 1.6;
uniform float parallax_near = 5.0;    // full parallax inside this distance (m)
uniform float parallax_far = 16.0;    // none beyond it
// Pit depth in atlas units along u and v (5 cm over the cap's circumference and height).
uniform vec2 parallax_depth = vec2(0.016, 0.024);

varying float kind;

// The attack, over 1 - strike (0 -> 1): both arms rise overhead, smash down and forward
// at SMASH (where the game lands the blow), then settle. Angles are about each shoulder.
const float SMASH = 0.45;
const vec3 SHOULDER = vec3(0.22, 0.66, 0.50);

void vertex() {
	kind = floor(UV2.x + 0.001);
	float w = clamp((UV2.x - kind) / 0.98, 0.0, 1.0);
	float group = 1.0 - UV2.y;   // glTF stores v flipped
	float arm = step(1.5, group);
	float pair = group - 2.0 * arm;
	float clock = motion_time >= 0.0 ? motion_time : TIME;
	float phase = clock * gait + pair * PI;
	vec3 rest = VERTEX;
	// Knuckle-walk on a diagonal trot: fists and feet swing forward and lift.
	VERTEX.x += sin(phase) * 0.17 * w * walk;
	VERTEX.y += max(cos(phase), 0.0) * 0.11 * w * walk;
	float body = 1.0 - w;
	float high = smoothstep(0.35, 1.45, rest.y);
	// The cap-body drops onto each step and rolls from side to side.
	VERTEX.y += (abs(sin(phase)) * -0.035 + 0.02) * walk * body;
	VERTEX.y += rest.z * sin(phase) * 0.06 * walk * body;
	// Breathing: the honeycomb swells a little, slowly.
	VERTEX.xz *= 1.0 + sin(clock * 1.5) * 0.012 * high * body * (1.0 - arm);
	// The blow.
	float on = step(0.001, strike);
	float t = 1.0 - strike;
	float raise = smoothstep(0.0, SMASH - 0.08, t);
	float slam = smoothstep(SMASH - 0.08, SMASH + 0.04, t);
	float settle = smoothstep(SMASH + 0.1, 1.0, t);
	float theta = on * mix(raise * 2.35, mix(0.18, 0.0, settle), slam);
	// rear back while the arms go up, then drive the whole bulk into the smash
	float lean = on * (-0.10 * raise * (1.0 - slam) + 0.22 * slam * (1.0 - settle));
	if (arm > 0.5) {
		vec3 pivot = vec3(SHOULDER.x, SHOULDER.y, sign(rest.z) * SHOULDER.z);
		vec2 d = VERTEX.xy - pivot.xy;
		float c = cos(theta);
		float s = sin(theta);
		VERTEX.xy = pivot.xy + vec2(d.x * c - d.y * s, d.x * s + d.y * c);
		NORMAL.xy = vec2(NORMAL.x * c - NORMAL.y * s, NORMAL.x * s + NORMAL.y * c);
		TANGENT.xy = vec2(TANGENT.x * c - TANGENT.y * s, TANGENT.x * s + TANGENT.y * c);
		BINORMAL.xy = vec2(BINORMAL.x * c - BINORMAL.y * s, BINORMAL.x * s + BINORMAL.y * c);
		VERTEX.x += lean * 0.75;
		VERTEX.y -= lean * 0.15;
	} else {
		VERTEX.x += lean * body * smoothstep(0.15, 1.0, rest.y);
		VERTEX.y -= max(lean, 0.0) * 0.30 * high * body;
	}
}

void fragment() {
	float is_honey = step(0.5, kind) * (1.0 - step(2.5, kind));
	vec2 uv = UV;
	float fade = is_honey * (1.0 - smoothstep(parallax_near, parallax_far, length(VERTEX)));
	if (fade > 0.01) {
		// Steep parallax through the pit height map in tangent space, then a short
		// binary search between the last two layers so pit walls don't step.
		vec3 v = normalize(vec3(dot(VIEW, TANGENT), dot(VIEW, -BINORMAL), dot(VIEW, NORMAL)));
		vec2 dx = dFdx(UV);
		vec2 dy = dFdy(UV);
		float layers = mix(28.0, 10.0, abs(v.z)) * mix(0.5, 1.0, fade);
		vec2 step_uv = v.xy / max(v.z, 0.25) * parallax_depth * fade / layers;
		float depth = 0.0;
		float h = 1.0 - textureGrad(orm_map, uv, dx, dy).a;
		for (int i = 0; i < 28; i++) {
			if (depth >= h || float(i) >= layers) {
				break;
			}
			uv -= step_uv;
			depth += 1.0 / layers;
			h = 1.0 - textureGrad(orm_map, uv, dx, dy).a;
		}
		vec2 half_uv = step_uv * 0.5;
		float half_d = 0.5 / layers;
		for (int i = 0; i < 5; i++) {
			if (depth >= h) {
				uv += half_uv;
				depth -= half_d;
			} else {
				uv -= half_uv;
				depth += half_d;
			}
			half_uv *= 0.5;
			half_d *= 0.5;
			h = 1.0 - textureGrad(orm_map, uv, dx, dy).a;
		}
	}
	vec3 col = texture(albedo_map, uv).rgb;
	vec4 orm = texture(orm_map, uv);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, team.rgb, rim * team.a * 0.22);
	float gray = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(gray * 0.7, gray * 0.55, gray * 0.4), wither);
	ALBEDO = col * mix(1.0, 0.55, growing);
	NORMAL_MAP = texture(normal_map, uv).rgb;
	ROUGHNESS = orm.g;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.45;
	SPECULAR = mix(0.4, 0.5, is_honey);
	BACKLIGHT = col * 0.06;
	float pulse = 0.82 + 0.18 * sin((motion_time >= 0.0 ? motion_time : TIME) * 2.3);
	EMISSION = glow_color * orm.b * glow_energy * pulse + vec3(1.0, 0.95, 0.85) * flash * 0.7;
}
