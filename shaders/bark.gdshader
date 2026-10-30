shader_type spatial;
render_mode cull_disabled;

// Tree trunks. Oak: deep furrowed bark. Birch: white with black lenticels.
// Above cut_h the trunk dithers away so it never blocks the battle from above.

#include "res://shaders/noise.gdshaderinc"

uniform int kind = 0;
uniform float cut_h = 30.0;
uniform float fade = 6.0;
uniform float dead = 0.0;    // a snag: bleached, peeling, mossless

varying vec3 opos;
varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	opos = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float a = atan(VERTEX.z, VERTEX.x);
	if (kind == 0 || kind == 2) {
		float furrow = abs(sin(a * 22.0 + vnoise(vec2(a * 4.0, VERTEX.y * 0.6)) * 3.0));
		VERTEX += NORMAL * furrow * (kind == 0 ? 0.12 : 0.07);
	}
}

void fragment() {
	float a = atan(opos.z, opos.x);
	vec3 col;
	if (kind == 1) {
		col = vec3(0.86, 0.85, 0.8) * (0.9 + 0.15 * vnoise(vec2(a * 6.0, opos.y * 2.0)));
		float lent = smoothstep(0.75, 0.82, vnoise(vec2(a * 10.0, opos.y * 7.0))) * step(0.5, vnoise(vec2(a * 3.0, opos.y * 0.8)));
		col = mix(col, vec3(0.06, 0.05, 0.05), lent);
		col = mix(col, vec3(0.12, 0.1, 0.09), smoothstep(1.6, 0.2, opos.y) * 0.8);
	} else {
		float furrow = abs(sin(a * 22.0 + vnoise(vec2(a * 4.0, opos.y * 0.6)) * 3.0));
		vec3 dark = kind == 0 ? vec3(0.08, 0.065, 0.05) : vec3(0.13, 0.07, 0.05);
		vec3 light = kind == 0 ? vec3(0.32, 0.29, 0.25) : vec3(0.38, 0.22, 0.15);
		col = mix(dark, light, furrow * (0.7 + 0.4 * vnoise(vec2(a * 9.0, opos.y * 3.0))));
	}
	// moss creeping up the shady side
	float north = clamp(-wnorm.z * 0.6 + 0.5, 0.0, 1.0);
	float moss = smoothstep(0.55, 0.7, fbm(vec2(a * 3.0, opos.y * 1.2)) + north * 0.35 - opos.y * 0.04);
	col = mix(col, vec3(0.2, 0.33, 0.07) * (0.7 + 0.5 * vnoise(vec2(a * 30.0, opos.y * 30.0))), moss);
	float grey = dot(col, vec3(0.33));
	col = mix(col, vec3(grey) * vec3(0.95, 0.88, 0.8) * 0.85, dead * 0.85);
	float peel = smoothstep(0.6, 0.75, vnoise(vec2(a * 5.0, opos.y * 1.5)));
	col = mix(col, vec3(0.45, 0.36, 0.26), peel * dead);
	// ragged break above the cut height; the hollow inside reads as dark heartwood
	float edge = cut_h + (fbm(vec2(a * 2.5, 0.0) + 3.0) - 0.5) * fade;
	if (wpos.y > edge) {
		discard;
	}
	if (!FRONT_FACING) {
		col = vec3(0.05, 0.03, 0.02);
	}
	col = mix(col, vec3(0.32, 0.2, 0.11), smoothstep(edge - 0.35, edge, wpos.y) * 0.8);
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
