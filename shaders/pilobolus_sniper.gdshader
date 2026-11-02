shader_type spatial;
render_mode cull_back;
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
 vec3 col=texture(albedo_map,UV).rgb;
 float rim=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),3.0);
 col=mix(col,team.rgb,rim*team.a*0.16);
 float gray=dot(col,vec3(.3,.55,.15));col=mix(col,vec3(gray*.7,gray*.55,gray*.4),wither);
 ALBEDO=col*mix(1.0,.55,growing);
 ROUGHNESS=(kind>1.5)?0.23:0.5;
 SPECULAR=0.65;
 BACKLIGHT=col*(kind>1.5?.20:.04);
 EMISSION=vec3(1.0,.95,.85)*flash*.7+vec3(.3,.12,.01)*rim*step(1.5,kind)*.2;
}
