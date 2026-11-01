shader_type spatial;
render_mode cull_back;

// Violet Webcap: one opaque material for cap, gills, bulb, six stilt legs and the cortina.
// COLOR.rgb is baked paint; COLOR.a is how far the gait moves a vertex (0 body, 1 foot).
// UV2.x is the surface kind: 0 stalk, 1 cap, 2 gills, 3 leg, 4 web, 5 glowing web, 6 fibril.
// UV2.y is the step phase (two alternating tripods).
instance uniform float flash = 0.0;
instance uniform float wither = 0.0;
instance uniform float growing = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float walk = 0.0;
instance uniform float gait = 7.0;
// The game supplies its clock so paused units really stop. Catalogs use TIME.
instance uniform float motion_time = -1.0;

uniform sampler2D surface_map : repeat_enable, filter_linear_mipmap;

varying float kind;
varying vec3 paint;

void vertex() {
	kind = UV2.x;
	paint = COLOR.rgb;
	float clock = motion_time >= 0.0 ? motion_time : TIME;
	float w = COLOR.a;
	float phase = clock * gait + UV2.y;
	// Long stilts: the foot swings forward and lifts; the knee follows at its weight.
	VERTEX.x += sin(phase) * 0.15 * w * walk;
	VERTEX.y += max(cos(phase), 0.0) * 0.09 * w * walk;
	// The body bobs twice per stride and the tall cap sways a little even at rest.
	float body = 1.0 - w;
	float high = smoothstep(0.6, 1.8, VERTEX.y);
	VERTEX.y += sin(clock * gait * 2.0) * 0.016 * walk * body;
	VERTEX.x += (sin(clock * 1.1) * 0.012 + sin(clock * gait * 2.0 + 0.6) * 0.012 * walk) * high * body;
	VERTEX.z += sin(clock * 0.83 + 1.7) * 0.008 * high * body;
}

void fragment() {
	vec3 data = texture(surface_map, UV).rgb;
	float is_cap = step(0.5, kind) * (1.0 - step(1.5, kind));
	float is_gill = step(1.5, kind) * (1.0 - step(2.5, kind));
	float is_leg = step(2.5, kind) * (1.0 - step(3.5, kind));
	float is_web = step(3.5, kind) * (1.0 - step(5.5, kind));
	float is_glow = step(4.5, kind) * (1.0 - step(5.5, kind));
	vec3 col = paint * (0.86 + data.g * 0.22);
	// Pale silky fibrils streak the violet cap; the legs and stalk carry a lengthwise grain.
	float fibril = smoothstep(0.64, 0.82, data.b) * 0.45 + smoothstep(0.70, 0.86, data.r) * 0.30;
	col = mix(col, vec3(0.62, 0.50, 0.84), fibril * is_cap);
	col *= mix(1.0, 0.88 + data.b * 0.2, is_leg + step(kind, 0.5));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, team.rgb, rim * team.a * 0.25 * (1.0 - is_web));
	float gray = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(gray * 0.7, gray * 0.55, gray * 0.4), wither);
	ALBEDO = col * mix(1.0, 0.55, growing);
	ROUGHNESS = mix(mix(0.72, 0.48, is_cap), 0.55, is_web) + (data.r - 0.5) * 0.12;
	SPECULAR = mix(0.3, 0.45, is_cap);
	// Thin silk and gills let light through.
	BACKLIGHT = col * (is_gill * 0.18 + is_web * 0.5);
	EMISSION = vec3(1.0, 0.62, 0.20) * is_glow * 0.75 + vec3(0.95, 0.92, 0.86) * is_web * (1.0 - is_glow) * 0.08
		+ vec3(1.0, 0.95, 0.85) * flash * 0.7;
}
