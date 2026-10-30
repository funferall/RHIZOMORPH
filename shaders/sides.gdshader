shader_type spatial;
render_mode cull_disabled;

// The cut face of the terrarium block: dark soil with perlite specks, a band of
// mycelium channels that lights up where a faction holds the ground above, and
// a pale cobblestone footing.

#include "res://shaders/noise.gdshaderinc"

uniform sampler2D myc_tex : filter_linear, repeat_disable;
uniform vec2 half_size = vec2(48.0, 36.0);
uniform float top_y = 0.0;
uniform float bottom_y = -11.0;
uniform vec3 fcol0 : source_color = vec3(1.0, 0.5, 0.45);
uniform vec3 fcol1 : source_color = vec3(1.0, 0.75, 0.4);
uniform vec3 fcol2 : source_color = vec3(0.55, 0.95, 0.9);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	// run along the face: z for the left/right faces, x for front/back
	float along = abs(wnorm.x) > 0.5 ? wpos.z : wpos.x;
	float y = wpos.y;
	vec2 q = vec2(along, y);

	vec2 uv = (wpos.xz + half_size) / (half_size * 2.0);
	uv = clamp(uv, vec2(0.002), vec2(0.998));
	vec3 d = clamp(texture(myc_tex, uv).rgb, 0.0, 1.0);
	float total = clamp(d.r + d.g + d.b, 0.0, 1.0);
	vec3 tint = (d.r * fcol0 + d.g * fcol1 + d.b * fcol2) / max(total, 0.001);

	float soil_n = fbm(q * vec2(0.6, 2.2));
	vec3 col = mix(vec3(0.11, 0.075, 0.05), vec3(0.2, 0.14, 0.09), soil_n);
	// strata
	col *= 0.85 + 0.25 * smoothstep(0.4, 0.6, vnoise(vec2(along * 0.15, y * 1.4)));
	// perlite specks
	float sp = hash12(floor(q * 9.0));
	col = mix(col, vec3(0.85, 0.83, 0.78), step(0.965, sp));
	// moss lip at the very top
	col = mix(col, vec3(0.12, 0.22, 0.04), smoothstep(top_y - 0.9, top_y - 0.2, y) * (1.0 - total * 0.7));

	// hyphal channels: domain-warped iso-lines that brighten under owned ground
	vec2 w = q * vec2(0.35, 0.9) + vec2(fbm(q * 0.3), fbm(q * 0.3 + 4.0)) * 2.0;
	float ch = 1.0 - smoothstep(0.0, 0.06, abs(fract(vnoise(w) * 4.0) - 0.5));
	float band = smoothstep(bottom_y + 2.4, bottom_y + 3.5, y) * (1.0 - smoothstep(top_y - 2.0, top_y - 0.8, y));
	float faint = 0.18;
	col = mix(col, mix(vec3(0.75, 0.72, 0.66), vec3(0.97) * mix(vec3(1.0), tint, 0.6), total), ch * band * (faint + total * 0.8));
	EMISSION = tint * ch * band * total * 0.25;

	// cobblestone footing
	float cob = 1.0 - smoothstep(bottom_y + 1.9, bottom_y + 2.1, y);
	vec2 vr = voronoi2(q * vec2(1.2, 1.6));
	vec3 stone = mix(vec3(0.62, 0.6, 0.56), vec3(0.8, 0.78, 0.74), hash12(floor(q * vec2(1.2, 1.6)) + vr.x));
	stone *= mix(0.35, 1.0, smoothstep(0.0, 0.07, vr.y));
	col = mix(col, stone, cob);

	ALBEDO = col;
	ROUGHNESS = 0.92;
}
