// Violet Webcap gait, shared by the body and silk surfaces so the veil moves with the legs.
// UV2.x = kind + 0.98 * weight (0 stalk, 1 cap, 2 gills, 3 leg, 4 web sheet, 5 hanging web).
// The weight is the gait weight, or for hanging web how far down it hangs. UV2.y = tripod.
instance uniform float flash = 0.0;
instance uniform float wither = 0.0;
instance uniform float growing = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float walk = 0.0;
instance uniform float gait = 7.0;
// The game supplies its clock so paused units really stop. Catalogs use TIME.
instance uniform float motion_time = -1.0;

varying float kind;

void webcap_gait(inout vec3 vertex, vec2 data) {
	float k = floor(data.x + 0.001);
	float w = clamp((data.x - k) / 0.98, 0.0, 1.0);
	if (k > 4.5) {
		// Hanging silk: its weight is how far down the fringe it is. It sways, and
		// trails behind when the unit walks; it does not step with the legs.
		float d = w * w;
		float clock_h = motion_time >= 0.0 ? motion_time : TIME;
		vertex.x += (sin(clock_h * 2.1 + vertex.z * 4.0) * 0.022 - 0.06 * walk + sin(clock_h * gait * 2.0 + 1.2) * 0.02 * walk) * d;
		vertex.z += sin(clock_h * 1.7 + vertex.x * 4.0) * 0.02 * d;
		w = 0.0;
	}
	float clock = motion_time >= 0.0 ? motion_time : TIME;
	float phase = clock * gait + data.y * PI;
	// Long stilts: the foot swings forward and lifts; the knee follows at its weight.
	vertex.x += sin(phase) * 0.15 * w * walk;
	vertex.y += max(cos(phase), 0.0) * 0.09 * w * walk;
	// The body bobs twice per stride and the tall cap sways a little even at rest.
	float body = 1.0 - w;
	float high = smoothstep(0.6, 1.8, vertex.y);
	vertex.y += sin(clock * gait * 2.0) * 0.016 * walk * body;
	vertex.x += (sin(clock * 1.1) * 0.012 + sin(clock * gait * 2.0 + 0.6) * 0.012 * walk) * high * body;
	vertex.z += sin(clock * 0.83 + 1.7) * 0.008 * high * body;
}

vec3 webcap_tint(vec3 col) {
	float gray = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(gray * 0.7, gray * 0.55, gray * 0.4), wither);
	return col * mix(1.0, 0.55, growing);
}
