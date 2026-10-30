shader_type spatial;

// Dark oiled walnut under the terrarium. Kept low-contrast so the depth of field
// turns it into a warm blur rather than a stripy floor.

#include "res://shaders/noise.gdshaderinc"

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float warp = fbm(p * vec2(0.015, 0.05)) * 5.0;
	float grain = sin((p.y * 0.35 + warp) * 2.0 + fbm(p * vec2(0.03, 0.3)) * 3.0);
	float fine = vnoise(vec2(p.x * 0.3, p.y * 12.0));
	vec3 col = mix(vec3(0.035, 0.022, 0.015), vec3(0.075, 0.048, 0.03), 0.5 + 0.35 * grain);
	col *= 0.9 + 0.2 * fine;
	ALBEDO = col;
	ROUGHNESS = 0.35 + 0.15 * fine;
	SPECULAR = 0.4;
}
