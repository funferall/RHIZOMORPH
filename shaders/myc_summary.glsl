#[compute]
#version 450

// Averages the fine mycelium field into a coarse grid (1 cell per world unit)
// that the CPU reads back for income, build placement and unit effects.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform restrict readonly image2D src_img;
layout(set = 0, binding = 1, std430) restrict writeonly buffer Out {
	vec4 v[];
} outb;

layout(push_constant, std430) uniform Params {
	float cw;
	float ch;
	float k;
	float pad;
} p;

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	int cw = int(p.cw);
	int ch = int(p.ch);
	if (c.x >= cw || c.y >= ch) {
		return;
	}
	int k = int(p.k);
	vec4 acc = vec4(0.0);
	for (int y = 0; y < k; y++) {
		for (int x = 0; x < k; x++) {
			acc += max(imageLoad(src_img, c * k + ivec2(x, y)), vec4(0.0));
		}
	}
	outb.v[c.y * cw + c.x] = acc / float(k * k);
}
