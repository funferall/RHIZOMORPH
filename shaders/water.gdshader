shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// Still puddle water: an opaque, near-black mirror so screen-space reflections
// pick up trunks and fruiting bodies, with a slow ripple in the normal.

#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/fog.gdshaderinc"

uniform vec2 half_size = vec2(96.0, 72.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME * 0.25;
	float hx = vnoise(p * 2.4 + vec2(t, 0.0)) - vnoise(p * 2.4 + vec2(t + 0.05, 0.0));
	float hz = vnoise(p * 2.4 + vec2(0.0, t * 0.8)) - vnoise(p * 2.4 + vec2(0.0, t * 0.8 + 0.05));
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(hx * 1.2, 0.0, hz * 1.2, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	// in the fog the sky stops glinting off the water
	float fv = smoothstep(0.05, 0.95, fog_at((p + half_size) / (half_size * 2.0)));
	ALBEDO = mix(vec3(0.022, 0.026, 0.016), vec3(0.08, 0.08, 0.06), fres) * mix(0.15, 1.0, fv);
	ROUGHNESS = mix(0.9, 0.03, fv);
	METALLIC = 0.0;
	SPECULAR = 0.9 * fv;
}
