shader_type spatial;
render_mode cull_disabled;

// The terrarium floor. Moss floor, leaf litter, rock and wet mud come from the
// substrate map. Wherever the GPU mycelium has spread, each court marks the ground
// its own way: the Court's silky mycorrhizal fans over dark soil, the Hollow's
// bleached white rot with black zone lines, the Choir's powdery spore colonies.

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

	// digested substrate: each court rots the ground its own way, blended by share
	vec3 w = d / max(total, 0.001);
	float fleck = hash12(floor(p * 13.0));
	vec2 wofs = vec2(fbm(p * 0.8), fbm(p * 0.8 + 7.0));   // shared domain warp
	vec2 warp = p * 1.9 + wofs * 3.0;
	vec3 dig = vec3(0.0);
	vec3 hy = vec3(0.0);   // colour of the surface hyphae
	float hya = 0.0;       // how much the threads show
	if (w.r > 0.01) {
		// Amanita Court, ectomycorrhizal: it feeds roots rather than eating the floor, so the
		// soil stays dark and rich under silky rose-white fans, dotted with red root tips
		vec3 c = mix(vec3(0.06, 0.035, 0.03), vec3(0.15, 0.085, 0.065), vnoise(p * 2.1) * 0.6 + n1 * 0.4);
		float fan = 1.0 - smoothstep(0.0, 0.08, abs(vnoise(warp * 1.3 + 2.0) - 0.5));
		c = mix(c, vec3(0.78, 0.6, 0.58), fan * 0.32);
		c = mix(c, vec3(0.72, 0.1, 0.06), step(0.968, hash12(floor(p * 9.0 + 3.0))) * 0.85);
		dig += w.r * c;
		hy += w.r * vec3(1.0, 0.9, 0.88);
		hya += w.r * 0.5;
	}
	if (w.g > 0.01) {
		// Morel Hollow, white rot: bleached spongy wood-meal, amber stain, and the black
		// zone lines (spalting) where rival colonies of the rot meet
		vec3 c = mix(vec3(0.4, 0.34, 0.23), vec3(0.6, 0.52, 0.36), fbm(p * 1.7 + 9.0));
		c = mix(c, vec3(0.55, 0.33, 0.1), smoothstep(0.5, 0.75, vnoise(p * 0.7 + 2.0)) * 0.7);
		vec2 zl = voronoi2(p * 0.5 + wofs * 1.3);
		float zone = 1.0 - smoothstep(0.012, 0.045, zl.y);
		c *= mix(0.82, 1.05, fleck);
		c = mix(c, vec3(0.04, 0.03, 0.02), zone * 0.9);
		dig += w.g * c;
		hy += w.g * vec3(0.98, 0.95, 0.86);
		hya += w.g * 0.25;
	}
	if (w.b > 0.01) {
		// Veiled Choir, an insect parasite: mauve ground spotted with round, powdery
		// conidial colonies - violet at the heart, white and fuzzy at the edge
		vec3 c = mix(vec3(0.11, 0.085, 0.125), vec3(0.21, 0.165, 0.235), vnoise(p * 2.4 + 5.0) * 0.6 + n1 * 0.4);
		vec2 q = p * 0.75 + 11.0;
		vec2 cv = voronoi2(q);
		float rad = 0.16 + 0.26 * vnoise(q * 0.9);
		float fuzz = vnoise(p * 22.0);
		// colonies cluster where infection spread: only some cells hold one
		float host = smoothstep(0.45, 0.6, vnoise(p * 0.35 + 4.0) + 0.25 * hash12(floor(q + 0.5)));
		float colony = (1.0 - smoothstep(rad * 0.65, rad * (1.0 + 0.25 * fuzz), cv.x)) * host;
		vec3 spore = mix(vec3(0.58, 0.4, 0.78), vec3(0.94, 0.91, 0.96), smoothstep(0.0, rad, cv.x));
		c = mix(c, spore, colony * (0.7 + 0.3 * fuzz));
		c = mix(c, vec3(0.88, 0.84, 0.95), step(0.94, fleck) * 0.55);
		dig += w.b * c;
		hy += w.b * vec3(0.9, 0.82, 1.0);
		hya += w.b * 0.3;
	}
	float thread = 1.0 - smoothstep(0.0, 0.045, abs(vnoise(warp) - 0.5));
	float thread2 = 1.0 - smoothstep(0.0, 0.035, abs(vnoise(warp * 2.7 + 5.0) - 0.5));
	float cover = smoothstep(0.22, 0.6, total + (fbm(p * 1.3) - 0.5) * 0.3);
	col = mix(col, dig, cover);
	col = mix(col, hy * 0.95, max(thread, thread2 * 0.6) * smoothstep(0.1, 0.5, total) * 0.55 * hya);

	// fluffy hyphal front, in the colour of whoever is advancing
	float rim = smoothstep(0.05, 0.22, total) * (1.0 - smoothstep(0.3, 0.6, total));
	col = mix(col, hy * 0.86, rim * (0.35 + 0.55 * vnoise(p * 10.0)));

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
