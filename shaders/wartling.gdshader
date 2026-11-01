shader_type spatial;
render_mode cull_back;

// One opaque material for body, gills, warts and all six root legs.
// COLOR.rgb is baked paint; COLOR.a is the leg's deformation weight.
// UV2.x selects the surface response, UV2.y the alternating tripod phase.
instance uniform float flash = 0.0;
instance uniform float wither = 0.0;
instance uniform float growing = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float walk = 0.0;
instance uniform float gait = 10.0;
// The game supplies its clock so paused units really stop. Catalogs use TIME.
instance uniform float motion_time = -1.0;

uniform sampler2D surface_map : repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_map : hint_normal, repeat_enable, filter_linear_mipmap;

varying float surface_kind;
varying vec3 paint;

void vertex() {
	surface_kind = UV2.x;
	paint = COLOR.rgb;
	float clock = motion_time >= 0.0 ? motion_time : TIME;
	float phase = clock * gait + UV2.y;
	if (UV2.x > 2.5 && UV2.x < 3.5) {
		vec2 radial = normalize(VERTEX.xz + vec2(0.0001));
		VERTEX.x += sin(phase) * 0.11 * COLOR.a * walk;
		VERTEX.z += radial.x * sin(phase) * 0.025 * COLOR.a * walk;
		VERTEX.y += max(cos(phase), 0.0) * 0.075 * COLOR.a * walk;
	} else {
		VERTEX.y += sin(clock * gait * 2.0) * 0.012 * walk;
	}
}

void fragment() {
	vec3 data = texture(surface_map, UV).rgb;
	float cap = step(0.5, surface_kind) * (1.0 - step(1.5, surface_kind));
	float gill = step(3.5, surface_kind) * (1.0 - step(4.5, surface_kind));
	float flake = step(1.5, surface_kind) * (1.0 - step(2.5, surface_kind));
	float grain = mix(data.b, data.r, cap);
	vec3 col = paint * (0.84 + data.g * 0.24 + grain * 0.10);
	// Warm brown creases in root skin and stalk; patchy scarlet on the cap.
	col *= mix(vec3(0.86, 0.82, 0.74), vec3(1.04), smoothstep(0.24, 0.61, grain)) * (1.0 - cap)
		+ mix(vec3(0.76, 0.48, 0.31), vec3(1.12, 1.05, 0.92), data.g) * cap;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, team.rgb, rim * team.a * 0.25);
	float gray = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(gray * 0.7, gray * 0.55, gray * 0.4), wither);
	ALBEDO = col * mix(1.0, 0.55, growing);
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = mix(0.48, 0.16, cap) * (1.0 - gill * 0.65);
	ROUGHNESS = clamp(mix(0.87, 0.57, cap) + (data.r - 0.5) * 0.18 + flake * 0.07, 0.45, 1.0);
	SPECULAR = 0.25;
	BACKLIGHT = col * (0.10 + gill * 0.14);
	EMISSION = vec3(0.46, 0.59, 0.045) * gill * 0.24
		+ vec3(1.0, 0.95, 0.85) * flash * 0.7;
}
