shader_type spatial;
render_mode cull_back;
varying float stem_height;
void vertex() { stem_height = VERTEX.y + 0.5; }
void fragment() {
 float chalk = smoothstep(.50,.92,stem_height);
 ALBEDO = mix(vec3(.026,.022,.018), vec3(.82,.81,.74), chalk);
 ROUGHNESS = .9;
}
