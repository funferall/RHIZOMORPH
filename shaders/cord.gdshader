shader_type spatial;
render_mode cull_disabled;

// Rhizomorph supply cord: a black Armillaria "bootlace" with glowing beads of
// faction-tinted gold travelling toward the Heart (UV.x runs child -> parent).

#include "res://shaders/noise.gdshaderinc"

instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float progress = 1.0;
instance uniform float severed = 0.0;
instance uniform float flash = 0.0;
instance uniform float length_m = 10.0;
instance uniform float load = 0.0;    // carried income / capacity; over 1 the cord runs hot

void fragment() {
	float u = UV.x;
	if (u > progress) {
		discard;
	}
	if (severed > 0.5 && abs(u - 0.5) < 0.04) {
		discard;
	}
	float n = vnoise(vec2(u * length_m * 6.0, UV.y * 8.0));
	vec3 col = mix(vec3(0.016, 0.012, 0.01), vec3(0.07, 0.045, 0.03), n);
	// fine longitudinal fibres
	col *= 0.8 + 0.4 * smoothstep(0.3, 0.7, vnoise(vec2(u * length_m * 1.5, UV.y * 40.0)));
	float tipglow = smoothstep(progress - 0.04, progress, u) * step(progress, 0.999);
	float bead = 0.0;
	if (severed < 0.5) {
		// busier cords carry more, faster beads (half as many as at first: the board was too busy)
		float busy = clamp(load, 0.0, 1.0);
		float s = fract(u * length_m * mix(0.125, 0.4, busy) - TIME * mix(0.2, 0.65, busy));
		bead = smoothstep(0.9, 0.95, s) * (1.0 - smoothstep(0.96, 1.0, s));
	}
	vec3 gold = mix(vec3(1.0, 0.62, 0.15), team.rgb, 0.3);
	float hot = smoothstep(1.0, 1.3, load);
	gold = mix(gold, vec3(1.0, 0.22, 0.08) * (1.2 + 0.5 * sin(TIME * 6.0)), hot);
	ALBEDO = mix(col, gold, bead * 0.7);
	ROUGHNESS = mix(0.5, 0.25, bead);
	SPECULAR = 0.6;
	EMISSION = gold * (bead * 2.2 + 0.04) + vec3(1.0) * tipglow * 1.5 + vec3(1.0, 0.5, 0.3) * flash;
	if (severed > 0.5) {
		ALBEDO *= 0.5;
		EMISSION = vec3(1.0, 0.3, 0.1) * smoothstep(0.12, 0.04, abs(u - 0.5)) * 1.5;
	}
}
