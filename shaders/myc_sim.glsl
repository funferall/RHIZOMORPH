#[compute]
#version 450

// One step of the mycelium war. Each texel holds (faction0, faction1, faction2, nutrient).
// Mycelium only lives where a connected structure, cord or unit "reaches"; inside that
// reach it creeps outward from neighbouring hyphae, eats nutrients, and digests the
// hyphae of the other factions where the fronts meet.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform restrict readonly image2D src_img;
layout(set = 0, binding = 1, rgba32f) uniform restrict writeonly image2D dst_img;
layout(set = 0, binding = 2, rgba8) uniform restrict readonly image2D sub_img;

struct Source {
	vec4 a; // x, z, radius, strength
	vec4 b; // faction, kind (0 disc, 1 capsule, 2 ring, 3 burn), x2/ring radius, z2
};
layout(set = 0, binding = 3, std430) restrict readonly buffer Sources {
	Source s[];
} src;

layout(push_constant, std430) uniform Params {
	float dt;
	float count;
	float res;
	float half_w;
	float half_d;
	float grow0;
	float grow1;
	float grow2;
} p;

float hash12(vec2 q) {
	vec3 p3 = fract(vec3(q.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	ivec2 sz = imageSize(src_img);
	if (c.x >= sz.x || c.y >= sz.y) {
		return;
	}
	vec4 sub = imageLoad(sub_img, c);
	float rock = sub.r;
	float water = sub.g;
	float base = (0.55 + sub.b * 0.9 + sub.a * 0.5) * (1.0 - rock * 0.7) * (1.0 - water);

	vec4 v = imageLoad(src_img, c);
	if (v.a < 0.0) {
		v = vec4(0.0, 0.0, 0.0, base);
	}
	vec3 d = v.rgb;
	float nut = v.a;

	vec3 nmax = vec3(0.0);
	ivec2 offs[8] = ivec2[](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1), ivec2(1, 1), ivec2(-1, 1), ivec2(1, -1), ivec2(-1, -1));
	for (int i = 0; i < 8; i++) {
		vec3 q = imageLoad(src_img, clamp(c + offs[i], ivec2(0), sz - 1)).rgb;
		nmax = max(nmax, q * (i < 4 ? 1.0 : 0.85));
	}
	nmax = max(nmax, vec3(0.0));

	vec2 wp = (vec2(c) + 0.5) / p.res - vec2(p.half_w, p.half_d);
	vec3 reach = vec3(0.0);
	float burn = 0.0;
	int n = int(p.count);
	for (int i = 0; i < n; i++) {
		vec4 a = src.s[i].a;
		vec4 b = src.s[i].b;
		int kind = int(b.y + 0.5);
		float dist;
		if (kind == 1) {
			vec2 pa = wp - a.xy;
			vec2 ba = b.zw - a.xy;
			float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
			dist = length(pa - ba * h);
		} else if (kind == 2) {
			dist = abs(length(wp - a.xy) - b.z);
		} else {
			dist = length(wp - a.xy);
		}
		// ragged, lobed edges instead of perfect circles
		dist *= 1.0 + (vnoise(wp * 0.21 + a.xy * 0.37) - 0.5) * 0.55;
		if (dist > a.z) {
			continue;
		}
		float f = a.w * (1.0 - smoothstep(a.z * 0.55, a.z, dist));
		if (kind == 3) {
			burn = max(burn, f);
			continue;
		}
		int fi = int(b.x + 0.5);
		if (fi == 0) {
			reach.r = max(reach.r, f);
		} else if (fi == 1) {
			reach.g = max(reach.g, f);
		} else {
			reach.b = max(reach.b, f);
		}
	}

	// Hyphae prefer rich ground and grow in irregular fingers.
	float jitter = 0.35 + 1.3 * vnoise(wp * 1.7) * (0.6 + 0.8 * hash12(vec2(c)));
	float cap = (1.0 - water) * (1.0 - 0.55 * rock);
	float total = d.r + d.g + d.b;
	float room = max(cap - total, 0.0);
	float rich = 0.45 + 0.55 * clamp(nut / max(base, 0.05), 0.0, 1.0);
	vec3 seed = step(vec3(0.8), reach);
	vec3 front = max(max(nmax * 0.95, d), seed * 0.5);
	vec3 grow = 1.7 * vec3(p.grow0, p.grow1, p.grow2) * reach * front * room * rich * jitter;
	vec3 starve = 0.45 * (1.0 - smoothstep(0.0, 0.1, reach)) * d + 0.04 * d * (1.0 - reach);
	vec3 others = vec3(d.g + d.b, d.r + d.b, d.r + d.g);
	vec3 oreach = vec3(max(reach.g, reach.b), max(reach.r, reach.b), max(reach.r, reach.g));
	vec3 fight = 1.4 * d * others * (0.35 + oreach) / (0.5 + reach);
	d += p.dt * (grow - starve - fight);
	d *= 1.0 - clamp(burn * 4.0 * p.dt * 10.0, 0.0, 1.0);
	d = clamp(d, 0.0, 1.0);

	// Digestion slowly exhausts the ground; burnt ground becomes rich ash.
	nut += p.dt * (0.0025 * (base - nut) - 0.003 * (d.r + d.g + d.b) * nut);
	nut = mix(nut, base * 1.3, clamp(burn * p.dt * 3.0, 0.0, 1.0));
	imageStore(dst_img, c, vec4(d, clamp(nut, 0.0, 1.6)));
}
