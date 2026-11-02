shader_type spatial;
render_mode cull_back;
instance uniform float flash=0.0;
instance uniform float wither=0.0;
instance uniform float growing=0.0;
instance uniform vec4 team=vec4(1.0,1.0,1.0,0.0);
instance uniform float walk=0.0;
instance uniform float gait=9.2;
instance uniform float motion_time=-1.0;
instance uniform float strike=0.0;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_map : filter_linear_mipmap_anisotropic;
void vertex(){
 float kind=floor(UV2.x+0.001);
 float weight=clamp((UV2.x-kind)/0.98,0.0,1.0);
 float group=floor(1.0-UV2.y+0.002);
 float clock=max(motion_time,0.0);
 float active=step(.001,strike);
 float moving=walk*(1.0-active);
 float phase=clock*gait+group*PI;
 // Alternating bent arms lift at their tips; their roots stay attached.
 if(kind>0.5 && kind<1.5){
  VERTEX.x+=sin(phase)*.10*weight*moving;
  VERTEX.y+=max(cos(phase),0.0)*.075*weight*moving;
 }else{
  VERTEX.y+=sin(clock*gait*2.0)*.012*moving;
  if(kind>1.5) VERTEX.x+=sin(clock*gait)*.018*weight*moving;
 }
 // Plant arms, hold through the existing 0.32 s impact, then withdraw.
 float t=1.0-strike;
 float press=active*smoothstep(0.0,.30,t)*(1.0-smoothstep(.43,.83,t));
 if(kind>0.5 && kind<1.5){
  VERTEX.y-=press*(.05+.08*weight);
  VERTEX.x+=sign(VERTEX.x)*.08*press*weight;
 }else{
  VERTEX.y-=.05*press;
  if(kind>1.5) VERTEX.x+=.07*press*weight;
 }
}
void fragment(){
 vec3 col=texture(albedo_map,UV).rgb;
 float rim=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),3.0);
 col=mix(col,team.rgb,rim*team.a*.18);
 float gray=dot(col,vec3(.3,.55,.15));col=mix(col,vec3(gray*.7,gray*.55,gray*.4),wither);
 ALBEDO=col*mix(1.0,.55,growing);
 NORMAL_MAP=texture(normal_map,UV).rgb;
 NORMAL_MAP_DEPTH=.55;
 vec3 orm=texture(orm_map,UV).rgb;
 ROUGHNESS=orm.g;
 AO=orm.r;
 AO_LIGHT_AFFECT=.4;
 BACKLIGHT=col*.04;
 EMISSION=vec3(1.0,.95,.85)*flash*.7;
}
