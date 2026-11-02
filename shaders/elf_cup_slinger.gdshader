shader_type spatial;
render_mode cull_back;
instance uniform float flash = 0.0;
instance uniform float wither = 0.0;
instance uniform float growing = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float walk = 0.0;
instance uniform float gait = 6.4;
instance uniform float motion_time = -1.0;
instance uniform float strike = 0.0;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
varying float kind;
void vertex() {
 kind = floor(UV2.x + 0.001);
 float weight = clamp((UV2.x-kind)/0.98,0.0,1.0);
 float clock = motion_time >= 0.0 ? motion_time : TIME;
 float phase = clock*gait + (1.0-UV2.y)*PI;
 float high = smoothstep(0.22,0.85,VERTEX.y);
 // The curled supports paddle alternately, while the cup bobs on its short neck.
 VERTEX.x += sin(phase)*0.12*weight*walk;
 VERTEX.y += max(cos(phase),0.0)*0.085*weight*walk;
 VERTEX.y += sin(clock*gait*2.0)*0.018*high*walk;
 // Immediate spore release, elastic recoil and a damped return. No gameplay windup.
 float t = 1.0-strike;
 float on = step(0.001,strike);
 float kick = on * (1.0-smoothstep(0.10,0.72,t)) * smoothstep(0.0,0.065,t);
 float rebound = on*sin(t*PI*4.0)*exp(-t*5.0)*smoothstep(0.12,0.25,t);
 float theta = (-0.20*kick+0.06*rebound)*high;
 vec2 pivot = vec2(-0.24,0.45);
 vec2 p=VERTEX.xy-pivot;
 float c=cos(theta), s=sin(theta);
 VERTEX.xy=pivot+vec2(p.x*c-p.y*s,p.x*s+p.y*c);
 NORMAL.xy=vec2(NORMAL.x*c-NORMAL.y*s,NORMAL.x*s+NORMAL.y*c);
 TANGENT.xy=vec2(TANGENT.x*c-TANGENT.y*s,TANGENT.x*s+TANGENT.y*c);
 BINORMAL.xy=vec2(BINORMAL.x*c-BINORMAL.y*s,BINORMAL.x*s+BINORMAL.y*c);
 VERTEX.x -= 0.15*kick*high;
 // Soft breathing and a pulse through the rolled rim.
 VERTEX.z *= 1.0 + (sin(clock*1.8)*0.012-0.065*kick)*high;
}
void fragment() {
 vec3 col=texture(albedo_map,UV).rgb;
 float rim=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),3.0);
 col=mix(col,team.rgb,rim*team.a*0.20);
 float gray=dot(col,vec3(0.3,0.55,0.15));
 col=mix(col,vec3(gray*0.7,gray*0.55,gray*0.4),wither);
 ALBEDO=col*mix(1.0,0.55,growing);
 NORMAL_MAP=texture(normal_map,UV).rgb;
 NORMAL_MAP_DEPTH=0.65;
 float inner=step(0.5,kind)*(1.0-step(1.5,kind));
 ROUGHNESS=mix(0.74,0.31,inner);
 SPECULAR=0.45;
 BACKLIGHT=col*0.08;
 EMISSION=vec3(1.0,0.95,0.85)*flash*0.7;
}
