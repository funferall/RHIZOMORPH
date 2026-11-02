shader_type spatial;
render_mode cull_back;
instance uniform float flash = 0.0;
instance uniform float wither = 0.0;
instance uniform float growing = 0.0;
instance uniform vec4 team = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float walk = 0.0;
instance uniform float gait = 5.6;
instance uniform float motion_time = -1.0;
instance uniform float strike = 0.0;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
void vertex() {
 float kind=floor(UV2.x+0.001);
 float weight=clamp((UV2.x-kind)/0.98,0.0,1.0);
 float clock=motion_time>=0.0?motion_time:TIME;
 float phase=clock*gait+(1.0-UV2.y)*PI;
 float t=1.0-strike;
 float kick=step(0.001,strike)*smoothstep(0.0,0.08,t)*(1.0-smoothstep(0.12,0.82,t));
 float body_x=sin(clock*gait)*0.025*walk - 0.10*kick;
 float body_y=sin(clock*gait*2.0)*0.025*walk;
 if(kind>0.5 && kind<1.5){
  // Shoulders follow the body and its recoil; the foot ends stay at ground
  // height during the planted half of each stride. Every toe uses weight 1.
  float shoulder=1.0-weight;
  VERTEX.x+=body_x*shoulder+sin(phase)*0.12*weight*walk;
  VERTEX.y+=(body_y+(1.05-0.79)*0.16*kick)*shoulder;
  VERTEX.y+=max(cos(phase),0.0)*0.09*weight*walk;
 } else {
  // Compress the body around its centre; the vent follows the same transform.
  VERTEX.y=1.05+(VERTEX.y-1.05)*(1.0-0.16*kick)+body_y;
  VERTEX.x+=body_x;
 }
}
void fragment() {
 vec3 col=texture(albedo_map,UV).rgb;
 float rim=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),3.0);
 col=mix(col,team.rgb,rim*team.a*0.2);
 float gray=dot(col,vec3(.3,.55,.15));
 col=mix(col,vec3(gray*.7,gray*.55,gray*.4),wither);
 ALBEDO=col*mix(1.0,.55,growing);
 NORMAL_MAP=texture(normal_map,UV).rgb;
 NORMAL_MAP_DEPTH=.7;
 ROUGHNESS=.87;
 BACKLIGHT=col*.08;
 EMISSION=vec3(1.0,.95,.85)*flash*.7;
}
