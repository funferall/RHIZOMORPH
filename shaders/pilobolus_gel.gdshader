shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
instance uniform float flash=0.0;
instance uniform float wither=0.0;
instance uniform float growing=0.0;
instance uniform vec4 team=vec4(1.0,1.0,1.0,0.0);
instance uniform float walk=0.0;
instance uniform float gait=6.2;
instance uniform float motion_time=-1.0;
instance uniform float strike=0.0;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
varying float kind;
void vertex(){
 kind=floor(UV2.x+0.001);
 float weight=clamp((UV2.x-kind)/0.98,0.0,1.0);
 float clock=motion_time>=0.0?motion_time:TIME;
 float phase=clock*gait+(1.0-UV2.y)*PI;
 float t=1.0-strike;
 // Coil backward, snap through the target at 0.24 s, then settle.
 float active=step(0.001,strike);
 float rear=smoothstep(0.0,0.22,t);
 float release=smoothstep(0.22,0.267,t);
 float settle=smoothstep(0.34,1.0,t);
 float bend=active*mix(-0.48*rear,0.22*(1.0-settle),release);
 float body_bob=sin(clock*gait*2.0)*0.022*walk;
 if(kind>0.5 && kind<1.5){
  VERTEX.x+=sin(phase)*0.13*weight*walk;
  VERTEX.y+=max(cos(phase),0.0)*0.13*weight*walk+body_bob*(1.0-weight);
 }else{
  float high=smoothstep(.5,1.8,VERTEX.y);
  VERTEX.x+=sin(clock*gait)*0.028*high*walk+bend*high*high;
  VERTEX.y-=abs(bend)*0.18*high;
  VERTEX.y+=body_bob;
 }
}
void fragment(){
 float rim=pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),2.3);
 vec3 tint=mix(vec3(.80,.86,.74),team.rgb,team.a*.08);
 ALBEDO=tint*mix(1.0,.55,growing);
 ROUGHNESS=.10;
 SPECULAR=0.9;
 METALLIC=0.0;
 ALPHA=mix(.19,.68,rim)*(1.0-wither*.25);
 BACKLIGHT=vec3(.55,.58,.38)*.20;
 EMISSION=vec3(.16,.19,.12)*rim*.35+vec3(1.0,.95,.85)*flash*.7;
}
