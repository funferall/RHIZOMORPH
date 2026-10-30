shader_type spatial;
render_mode cull_disabled;

// The terrarium floor. Moss floor, leaf litter, rock and wet mud come from the
// substrate map; wherever the GPU mycelium has spread, the ground is digested into
// pale grey-beige gravel laced with white hyphae, tinted by the owning faction.

#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/fog.gdshaderinc"

uniform sampler2D myc_tex : filter_linear, repeat_disable;
uniform sampler2D sub_tex : filter_linear, repeat_disable;
uniform vec2 half_size = vec2(48.0, 36.0);
uniform vec3 fcol0 : source_color = vec3(1.0, 0.8, 0.78);
uniform vec3 fcol1 : source_color = vec3(1.0, 0.86, 0.66);
uniform vec3 fcol2 : source_color = vec3(0.8, 0.98, 0.94);
uniform float show_grid = 0.0;
uniform vec2 ghost_pos = vec2(9999.0);
uniform float ghost_r = 0.0;
uniform vec3 ghost_col : source_color = vec3(1.0);
uniform vec4 zones[24];       // tree root zones: x, z, radius (0 = none)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float zone_ring(vec4 z, vec2 p) {
	if (z.z <= 0.0) {
		return 0.0;
	}
	float d = length(p - z.xy);
	return (1.0 - smoothstep(0.0, 0.18, abs(d - z.z))) * 0.8 + (1.0 - smoothstep(0.0, z.z, d)) * 0.08;
}

void fragment() {
	vec2 uv = (wpos.xz + half_size) / (half_size * 2.0);
	vec4 sub = texture(sub_tex, uv);
	vec3 d = clamp(texture(myc_tex, uv).rgb, 0.0, 1.0);
	float total = clamp(d.r + d.g + d.b, 0.0, 1.0);
	vec2 p = wpos.xz;

	float n1 = fbm(p * 0.35);
	// dark loam with a green algal film; visible in the gaps between moss cushions
	vec3 col = mix(vec3(0.05, 0.035, 0.022), vec3(0.06, 0.08, 0.025), n1);
	col *= 0.75 + 0.5 * hash12(floor(p * 9.0));

	float leafy = smoothstep(0.42, 0.7, fbm(p * 1.6 + 3.0));
	vec2 lv = voronoi2(p * 2.2);
	vec3 litter = mix(vec3(0.08, 0.055, 0.035), vec3(0.19, 0.13, 0.075), leafy) * (0.6 + 0.6 * smoothstep(0.0, 0.1, lv.y));
	col = mix(col, litter, sub.a);

	vec2 vr = voronoi2(p * 1.1);
	float crack = smoothstep(0.0, 0.05, vr.y);
	vec3 rockc = mix(vec3(0.15, 0.145, 0.135), vec3(0.34, 0.33, 0.31), fbm(p * 2.3)) * mix(0.4, 1.0, crack);
	float lich = smoothstep(0.7, 0.78, vnoise(p * 5.0 + 11.0));
	rockc = mix(rockc, vec3(0.42, 0.46, 0.32), lich * 0.6);
	rockc = mix(rockc, vec3(0.05, 0.1, 0.02), smoothstep(0.55, 0.75, fbm(p * 0.9 + 4.0)) * 0.8);
	col = mix(col, rockc, smoothstep(0.2, 0.6, sub.r));

	// wet mud darkening toward the waterline
	float wet = 1.0 - smoothstep(-0.45, 0.1, wpos.y);
	col = mix(col, col * 0.35 + vec3(0.012, 0.01, 0.008), wet);
	col = mix(col, vec3(0.22, 0.14, 0.07) * (0.6 + 0.6 * vnoise(vec2(p.x * 0.6, p.y * 5.0))), sub.b * 0.25);

	// digested substrate
	float fleck = hash12(floor(p * 13.0));
	vec2 grit = voronoi2(p * 6.0);
	vec3 dig = mix(vec3(0.15, 0.145, 0.135), vec3(0.32, 0.31, 0.29), fbm(p * 2.7));
	dig *= mix(0.55, 1.0, smoothstep(0.0, 0.12, grit.y));
	dig = mix(dig, vec3(0.7, 0.69, 0.65), step(0.9, fleck));
	dig = mix(dig, vec3(0.06, 0.055, 0.05), step(fleck, 0.08));
	vec3 tint = (d.r * fcol0 + d.g * fcol1 + d.b * fcol2) / max(total, 0.001);
	dig *= mix(vec3(1.0), tint, 0.7);
	vec2 warp = p * 1.9 + vec2(fbm(p * 0.8), fbm(p * 0.8 + 7.0)) * 3.0;
	float thread = 1.0 - smoothstep(0.0, 0.045, abs(vnoise(warp) - 0.5));
	float thread2 = 1.0 - smoothstep(0.0, 0.035, abs(vnoise(warp * 2.7 + 5.0) - 0.5));
	float cover = smoothstep(0.22, 0.6, total + (fbm(p * 1.3) - 0.5) * 0.3);
	col = mix(col, dig, cover);
	col = mix(col, vec3(0.95, 0.94, 0.9) * mix(vec3(1.0), tint, 0.3), max(thread, thread2 * 0.6) * smoothstep(0.1, 0.5, total) * 0.45);

	// fluffy white hyphal front
	float rim = smoothstep(0.05, 0.22, total) * (1.0 - smoothstep(0.3, 0.6, total));
	col = mix(col, vec3(0.86, 0.85, 0.8), rim * (0.35 + 0.55 * vnoise(p * 10.0)));

	// placement aids
	if (ghost_r > 0.0) {
		float gd = length(p - ghost_pos);
		col = mix(col, ghost_col, (1.0 - smoothstep(0.0, 0.12, abs(gd - ghost_r))) * 0.8);
	}
	float z = 0.0;
	for (int zi = 0; zi < 24; zi++) {
		z += zone_ring(zones[zi], p);
	}
	col = mix(col, vec3(1.0, 0.82, 0.3), clamp(z, 0.0, 1.0) * show_grid);

	ALBEDO = fogged(col, fog_at(uv));
	ROUGHNESS = mix(0.95, 0.25, wet);
	SPECULAR = 0.35;
}
