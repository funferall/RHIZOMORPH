shader_type spatial;
render_mode unshaded, cull_disabled;

// Tree crowns, drawn only into the sun's shadow map: leaf cards with holes, so the
// floor gets dappled shade (and the volumetric fog light shafts) without the canopy
// ever covering the board. COLOR: r = hole threshold, g = phase, b = sway, a = leaf size.

uniform float wind = 0.25;   // 0 still air, 1 a windstorm
uniform sampler2D leaf_tex : filter_linear_mipmap, repeat_enable;   // r: leaf pattern, g: ragged card edge (tiling noise)
uniform float thin = 0.0;    // opens the leaves as the camera pulls back, so the overview stays bright

varying vec4 leaf;

void vertex() {
	leaf = COLOR;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * (0.7 + wind * 1.8);
	float ph = COLOR.g * 6.2832;
	float amp = (0.12 + wind * 0.9) * COLOR.b;
	// the whole crown leans with the gusts; each card flutters on its own
	float lean = sin(TIME * 0.35 + w.x * 0.02) * 0.5 + 0.5;
	VERTEX.x += (sin(t + ph + w.z * 0.05) * 0.6 + lean * wind * 1.4) * amp;
	VERTEX.z += cos(t * 0.8 + ph * 1.3 + w.x * 0.05) * 0.6 * amp;
	VERTEX.y += sin(t * 1.9 + ph * 2.0) * 0.25 * amp;
}

void fragment() {
	// one texture read per texel: this runs for every leaf in the shadow map
	vec2 c = UV * 2.0 - 1.0;
	vec2 n = texture(leaf_tex, UV * leaf.a * 2.5 + leaf.g * 7.3).rg;
	ALBEDO = vec3(0.12, 0.16, 0.06);
	ALPHA = step(length(c) + (n.g - 0.5) * 0.6, 0.92) * step(leaf.r + thin, n.r);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
