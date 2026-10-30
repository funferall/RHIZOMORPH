shader_type spatial;
render_mode cull_disabled;

// One shader for every fruiting body. `pattern` picks the surface:
// 0 plain, 1 fly-agaric warts, 2 morel honeycomb, 3 lattice (clathrus / veil),
// 4 gills, 5 ridged gleba, 6 scaly, 7 warty puffball, 8 stripes, 9 glassy vesicle,
// 10 concentric growth zones (bracket shelves).

#include "res://shaders/noise.gdshaderinc"

uniform vec3 base_col : source_color = vec3(0.9, 0.88, 0.8);
uniform vec3 accent_col : source_color = vec3(1.0);
uniform int pattern = 0;
uniform float pscale = 6.0;
uniform float bump = 0.0;
uniform float rough = 0.6;
uniform float sss = 0.3;
uniform vec3 glow_col : source_color = vec3(0.0);
uniform float glow = 0.0;
uniform float sway = 0.0;

instance uniform float flash = 0.0;
instance uniform float wither = 0.0;
instance uniform float growing = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);

varying vec3 opos;

float pat(vec3 p, out float accent) {
	accent = 0.0;
	if (pattern == 1) {
		vec2 v = voronoi3(p * pscale);
		accent = 1.0 - smoothstep(0.16, 0.24, v.x);
		return accent;
	} else if (pattern == 2) {
		vec2 v = voronoi3(p * pscale);
		accent = 1.0 - smoothstep(0.02, 0.09, v.y);
		return accent - 0.4 * smoothstep(0.1, 0.4, v.y);
	} else if (pattern == 3) {
		vec2 v = voronoi3(p * pscale);
		accent = 1.0 - smoothstep(0.05, 0.1, v.y);
		return accent;
	} else if (pattern == 4) {
		float a = atan(p.z, p.x);
		accent = smoothstep(0.55, 0.9, abs(sin(a * pscale)));
		return accent;
	} else if (pattern == 5) {
		vec2 v = voronoi3(p * pscale * vec3(1.0, 0.5, 1.0));
		accent = 1.0 - smoothstep(0.0, 0.12, v.y);
		return accent;
	} else if (pattern == 6) {
		vec2 v = voronoi3(p * pscale);
		accent = smoothstep(0.35, 0.15, v.x) * step(0.5, hash33(floor(p * pscale)).x);
		return accent;
	} else if (pattern == 7) {
		vec2 v = voronoi3(p * pscale);
		accent = 1.0 - smoothstep(0.1, 0.3, v.x);
		return accent;
	} else if (pattern == 10) {
		float rr = length(p.xz);
		accent = smoothstep(0.35, 0.65, sin(rr * pscale + vnoise(p.xz * 4.0) * 1.5) * 0.5 + 0.5);
		return accent * 0.5;
	} else if (pattern == 8) {
		accent = smoothstep(0.4, 0.8, sin(p.y * pscale + vnoise(p.xz * 3.0) * 2.0) * 0.5 + 0.5);
		return accent;
	}
	return 0.0;
}

void vertex() {
	opos = VERTEX;
	float acc;
	float h = pat(VERTEX, acc);
	VERTEX += NORMAL * h * bump;
	if (sway > 0.0) {
		vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		VERTEX.x += sin(TIME * 1.3 + w.x * 0.7) * sway * VERTEX.y * VERTEX.y;
	}
}

void fragment() {
	float acc;
	pat(opos, acc);
	if (pattern == 3 && acc < 0.5) {
		discard;
	}
	vec3 col = base_col;
	col *= 0.85 + 0.3 * vnoise(opos.xz * 9.0 + opos.y * 4.0);
	if (pattern != 3) {
		col = mix(col, accent_col, acc);
	} else {
		col = accent_col * (0.85 + 0.2 * vnoise(opos.xy * 20.0));
	}
	// subtle team rim so armies read at a glance
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, team.rgb, rim * team.a);
	// withering: brown, dry, dark
	float g = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(g * 0.7, g * 0.55, g * 0.4), wither);
	col *= mix(1.0, 0.55, growing);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	if (pattern == 9) {
		ROUGHNESS = 0.08;
		SPECULAR = 0.9;
		col = mix(col, vec3(1.0), rim * 0.6);
		ALBEDO = col;
	}
	BACKLIGHT = col * sss;
	EMISSION = glow_col * glow * (0.7 + 0.3 * sin(TIME * 1.7 + opos.x * 3.0)) + vec3(1.0, 0.95, 0.85) * flash * 0.7 + team.rgb * rim * team.a * 0.25;
}
