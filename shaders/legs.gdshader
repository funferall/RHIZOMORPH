shader_type spatial;
render_mode cull_disabled;

// Spindly chitin legs for the walking sporelings. Vertex COLOR.r = gait phase,
// COLOR.g = 0 at the hip .. 1 at the foot. `walk` (0..1) is set per unit.

// the first four must match fungus.gdshader's instance uniforms, in order
instance uniform float flash = 0.0;
instance uniform float wither = 0.0;
instance uniform float growing = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float walk = 0.0;
instance uniform float gait = 9.0;

void vertex() {
	float ph = COLOR.r * 6.2831;
	float w = COLOR.g;
	float t = TIME * gait + ph;
	vec3 radial = normalize(vec3(VERTEX.x, 0.0, VERTEX.z) + vec3(0.0001));
	vec3 tangent = vec3(-radial.z, 0.0, radial.x);
	VERTEX += (tangent * sin(t) * 0.18 + vec3(0.0, max(cos(t), 0.0) * 0.14, 0.0)) * w * walk;
}

void fragment() {
	ALBEDO = vec3(0.07, 0.055, 0.045);
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
	EMISSION = vec3(1.0, 0.9, 0.8) * flash * 0.5;
}
