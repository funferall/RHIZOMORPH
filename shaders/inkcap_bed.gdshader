shader_type spatial;
render_mode cull_back;
instance uniform float flash=0.0;
instance uniform float wither=0.0;
instance uniform float growing=0.0;
instance uniform vec4 team=vec4(1.0,1.0,1.0,0.0);
instance uniform float motion_time=-1.0;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
varying float kind;
void vertex(){
 kind=floor(UV2.x+0.001);
 if(kind>2.5){
  // Independent, short falling paths; game time makes droplets freeze on pause.
  float clock=motion_time>=0.0?motion_time:TIME;
  float phase=fract(clock*.65+(1.0-UV2.y));
  VERTEX.y-=phase*.48;
 }
}
void fragment(){
 vec3 col=texture(albedo_map,UV).rgb;
 float rim=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),3.0);
 col=mix(col,team.rgb,rim*team.a*.16);
 float gray=dot(col,vec3(.3,.55,.15));col=mix(col,vec3(gray*.7,gray*.55,gray*.4),wither);
 ALBEDO=col*mix(1.0,.55,growing);
 NORMAL_MAP=texture(normal_map,UV).rgb;
 NORMAL_MAP_DEPTH=.55;
 float wet=step(1.5,kind);
 ROUGHNESS=mix(.83,.20,wet);
 SPECULAR=mix(.40,.68,wet);
 BACKLIGHT=col*.06;
 EMISSION=vec3(1.0,.95,.85)*flash*.7;
}
