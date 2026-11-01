shader_type spatial;
render_mode cull_back;

// The alpha channel stores gait weight, not opacity. UV2 is surface kind / phase.
// Atlas: chestnut cap / reticulate stalk / pore sponge / foot skin.
uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_roughness_map : hint_normal, filter_linear_mipmap, repeat_disable;
instance uniform float flash = 0.0;
instance uniform float wither = 0.0;
instance uniform float growing = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float walk = 0.0;
instance uniform float gait = 4.8;
instance uniform float motion_time = -1.0;
instance uniform float brace = 0.0;
instance uniform float bash = -1.0;

varying vec3 paint;
varying float surface_kind;
varying float edge_veil;

void vertex() {
	paint = COLOR.rgb;
	surface_kind = UV2.x;
	edge_veil = COLOR.a;
	float clock = motion_time >= 0.0 ? motion_time : TIME;
	float walking = walk * (1.0 - brace);
	if (UV2.x > 2.5) {
		float cycle = fract(clock * gait / 6.2831853 + UV2.y);
		float swing = clamp(cycle * 4.0, 0.0, 1.0);
		float lift = sin(swing * 3.14159265);
		float travel = cycle < 0.25 ? mix(-0.075, 0.075, smoothstep(0.0, 1.0, swing))
			: mix(0.075, -0.075, (cycle - 0.25) / 0.75);
		VERTEX.x += travel * COLOR.a * walking;
		VERTEX.y += lift * 0.065 * COLOR.a * walking;
		VERTEX.xz += normalize(VERTEX.xz + vec2(0.0001)) * brace * 0.12 * COLOR.a;
	} else {
		// The large shield settles slightly behind the body's four-beat weight shift.
		float lag = UV2.x < 0.5 ? 0.32 : 0.0;
		VERTEX.y += sin(clock * gait * 4.0 - lag) * 0.007 * walking;
		VERTEX.z += sin(clock * gait * 2.0) * 0.010 * walking;
	}
	// Roots pass below the terrain; at full brace only the shield cap is exposed.
	VERTEX.y -= 0.85 * brace;
	if (bash >= 0.0 && brace < 0.01) {
		float wind = smoothstep(0.0, 0.30, bash) * (1.0 - smoothstep(0.32, 0.47, bash));
		float drive = smoothstep(0.30, 0.43, bash) * (1.0 - smoothstep(0.50, 1.0, bash));
		float push = -0.10 * wind + 0.50 * drive;
		bool shield = UV2.x < 0.5 || (UV2.x > 1.5 && UV2.x < 2.5);
		if (shield) {
			float angle = 0.10 * wind - 0.22 * drive;
			float c = cos(angle);
			float s = sin(angle);
			vec2 pivot = VERTEX.xy - vec2(0.035, 1.08);
			VERTEX.xy = vec2(c * pivot.x - s * pivot.y, s * pivot.x + c * pivot.y) + vec2(0.035, 1.08);
			NORMAL.xy = vec2(c * NORMAL.x - s * NORMAL.y, s * NORMAL.x + c * NORMAL.y);
			TANGENT.xy = vec2(c * TANGENT.x - s * TANGENT.y, s * TANGENT.x + c * TANGENT.y);
			BINORMAL.xy = vec2(c * BINORMAL.x - s * BINORMAL.y, s * BINORMAL.x + c * BINORMAL.y);
			VERTEX.x += push;
			VERTEX.y -= 0.22 * drive;
		} else {
			float rooted = UV2.x > 2.5 ? 1.0 - COLOR.a : smoothstep(0.15, 0.85, VERTEX.y);
			VERTEX.x += push * rooted;
			VERTEX.y -= 0.07 * drive * rooted;
		}
	}
}

void fragment() {
	vec4 skin = texture(albedo_map, UV);
	vec4 detail = texture(normal_roughness_map, UV);
	float cap = 1.0 - step(0.5, surface_kind);
	float pore = step(1.5, surface_kind) * (1.0 - step(2.5, surface_kind));
	vec3 col = mix(skin.rgb, vec3(0.68, 0.58, 0.36), edge_veil * cap) * paint;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, team.rgb, rim * team.a * 0.22);
	float gray = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(gray * 0.7, gray * 0.55, gray * 0.4), wither);
	ALBEDO = col * mix(1.0, 0.55, growing);
	NORMAL_MAP = detail.rgb;
	NORMAL_MAP_DEPTH = mix(0.75, 0.40, cap);
	ROUGHNESS = detail.a;
	SPECULAR = mix(0.25, 0.36, cap);
	BACKLIGHT = col * (0.08 + pore * 0.06);
	EMISSION = vec3(1.0, 0.95, 0.85) * flash * 0.7;
}
