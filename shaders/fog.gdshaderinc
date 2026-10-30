// Fog of war for the ground. fog_tex.r: 0 never seen, ~0.45 explored, 1 in sight.
// Explored ground keeps its shape but loses the live faction tint (no free scouting).

uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform float fog_on = 0.0;

float fog_at(vec2 uv) {
	return fog_on > 0.5 ? texture(fog_tex, uv).r : 1.0;
}

vec3 fogged(vec3 col, float fv) {
	float vis = smoothstep(0.6, 0.95, fv);
	float seen = smoothstep(0.05, 0.4, fv);
	vec3 grey = vec3(dot(col, vec3(0.3, 0.5, 0.2))) * vec3(0.95, 0.92, 0.86);
	vec3 dim = mix(col * 0.03, grey * 0.38, seen);
	return mix(dim, col, vis);
}
