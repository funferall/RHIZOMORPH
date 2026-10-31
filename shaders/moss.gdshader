shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Shell-textured cushion moss. Drawn as a MultiMesh of the same ground mesh; each
// instance is one shell, pushed up by INSTANCE_ID. Strands are hashed in world
// space and clipped where rock, water or the mycelium has eaten the moss.
// Cushions are voronoi domes with dark crevices between them; four moss species
// (deep green, yellow-green, grey olive, dry gold) drift across the board.

#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/fog.gdshaderinc"

uniform sampler2D myc_tex : filter_linear, repeat_disable;
uniform sampler2D sub_tex : filter_linear, repeat_disable;
uniform vec2 half_size = vec2(48.0, 36.0);
uniform float shells = 20.0;
instance uniform float shells_drawn = 20.0;   // this tile's level of detail: its shells span the full height
uniform float moss_h = 0.5;
uniform float strand_freq = 34.0;

varying vec3 wpos;
varying float shell;
varying float vmask;     // moss coverage: slow-varying, so per vertex
varying vec2 vlean;      // strand lean, likewise

float moss_mask(vec2 p) {
	vec2 uv = (p + half_size) / (half_size * 2.0);
	vec4 sub = texture(sub_tex, uv);
	vec3 d = clamp(texture(myc_tex, uv).rgb, 0.0, 1.0);
	float total = d.r + d.g + d.b;
	float m = (1.0 - smoothstep(0.25, 0.6, sub.r)) * (1.0 - smoothstep(0.02, 0.2, sub.g));
	m *= 1.0 - smoothstep(0.12, 0.5, total + (vnoise(p * 1.4) - 0.5) * 0.35);
	m *= mix(1.0, 0.35, sub.a);
	// bare patches of soil and litter between the cushions
	m *= smoothstep(0.28, 0.42, fbm(p * 0.22 + 31.0));
	return m;
}

void vertex() {
	shell = (float(INSTANCE_ID) + 1.0) / max(shells_drawn, 1.0);
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float mask = moss_mask(w.xz);
	vmask = mask;
	vlean = (vec2(vnoise(w.xz * 0.6), vnoise(w.xz * 0.6 + 5.0)) - 0.5) * 0.9;
	float clump = 0.5 + 0.9 * fbm(w.xz * 0.45);
	VERTEX += NORMAL * shell * moss_h * clump * max(mask, 0.05);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float m = vmask;
	if (m < 0.05) {
		discard;
	}
	// cushions
	vec2 cv = voronoi2(p * 0.9 + vec2(fbm(p * 0.5), fbm(p * 0.5 + 9.0)) * 0.8);
	float dome = 1.0 - smoothstep(0.1, 0.8, cv.x);
	float gap = smoothstep(0.0, 0.14, cv.y);
	// strands lean with height so the shells do not stack into visible discs
	vec2 lean = vlean;
	vec2 q = p * strand_freq + lean * shell * 1.5;
	vec2 cell = floor(q);
	vec2 local = fract(q) - 0.5;
	float r = hash12(cell);
	vec2 jit = hash22(cell + 3.1) - 0.5;
	float h = (0.3 + 0.7 * r) * (0.3 + 0.7 * dome) * (0.35 + 0.65 * gap) * m;
	float radius = 0.5 * (1.0 - shell * shell * 0.8);
	if (shell > h || length(local - jit * 0.3) > radius) {
		discard;
	}
	float sp = vnoise(p * 0.18 + 2.0);
	float sp2 = vnoise(p * 0.31 + 17.0);
	vec3 tip = mix(vec3(0.06, 0.17, 0.035), vec3(0.2, 0.32, 0.05), smoothstep(0.35, 0.65, sp));
	tip = mix(tip, vec3(0.13, 0.15, 0.07), smoothstep(0.6, 0.8, sp2) * 0.8);
	tip = mix(tip, vec3(0.25, 0.18, 0.06), smoothstep(0.78, 0.9, sp2 * sp + 0.35) * 0.7);
	tip *= 0.75 + 0.5 * hash12(floor(p * 3.0 + 0.5));
	vec3 base = vec3(0.012, 0.02, 0.006);
	float up = pow(shell / max(h, 0.01), 1.5);
	vec3 col = mix(base, tip, up);
	col *= 0.8 + 0.4 * hash12(cell + 9.0);
	// pale sporophyte tips on a few strands
	col = mix(col, vec3(0.55, 0.42, 0.18), step(0.985, r) * step(0.8, up));
	col = fogged(col, fog_at((p + half_size) / (half_size * 2.0)));
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.8;
	AO = mix(0.2, 1.0, up);
	AO_LIGHT_AFFECT = 0.6;
}
