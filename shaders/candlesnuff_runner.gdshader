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
void vertex(){
 float kind=floor(UV2.x+0.001);
 float weight=clamp((UV2.x-kind)/0.98,0.0,1.0);
 float clock=motion_time>=0.0?motion_time:TIME;
 // One forward rock over a weight-bearing arm, then rise upright again.
 float active=step(.001,strike);
 float moving=walk*(1.0-active);
 float stride=clock*gait/TAU;
 float cycle=fract(stride);
 float side=1.0-2.0*mod(floor(stride),2.0);
 float tilt=-0.64*side*pow(sin(cycle*PI),2.0)*moving;
 float c=cos(tilt), sn=sin(tilt);
 vec2 pivot=vec2(0.0,.44);
 vec2 p=VERTEX.xy-pivot;
 VERTEX.xy=pivot+vec2(p.x*c-p.y*sn,p.x*sn+p.y*c);
 NORMAL.xy=vec2(NORMAL.x*c-NORMAL.y*sn,NORMAL.x*sn+NORMAL.y*c);
 TANGENT.xy=vec2(TANGENT.x*c-TANGENT.y*sn,TANGENT.x*sn+TANGENT.y*c);
 BINORMAL.xy=vec2(BINORMAL.x*c-BINORMAL.y*sn,BINORMAL.x*sn+BINORMAL.y*c);
 // Keep the forward arm planted as the body passes over it. The swing is
 // entirely reversible and returns to the standing pose at each cycle boundary.
 float support=.94*side;
 float contact_y=.44+support*sn+(.025-.44)*c;
 float ground_lift=max(0.0,-contact_y)*moving;
 float planted_x=support-(support*c-(.025-.44)*sn);
 VERTEX.xy+=vec2(planted_x*moving,ground_lift);
 // Plant both arms into the soil, hold through impact, then withdraw.
 float t=1.0-strike;
 float press=active*smoothstep(0.0,.30,t)*(1.0-smoothstep(.43,.83,t));
 if(kind>0.5 && kind<1.5){
  VERTEX.y-=press*(.10+.18*weight);
  VERTEX.x+=sign(VERTEX.x)*.08*press*weight;
 }else{
  VERTEX.y-=.10*press;
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
 ROUGHNESS=.82;
 BACKLIGHT=col*.04;
 EMISSION=vec3(1.0,.95,.85)*flash*.7;
}
