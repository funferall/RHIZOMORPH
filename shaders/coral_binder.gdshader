shader_type spatial;
render_mode cull_back;
instance uniform float flash=0.0;
instance uniform float wither=0.0;
instance uniform float growing=0.0;
instance uniform vec4 team=vec4(1.0,1.0,1.0,0.0);
instance uniform float motion_time=-1.0;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_map : filter_linear_mipmap_anisotropic;
varying float part;
varying float variation;
void vertex() {
 part=floor(UV2.x+0.001);
 variation=fract(sin(floor(1.0-UV2.y+0.002)*13.37)*437.19);
}
void fragment() {
 vec3 col=texture(albedo_map,UV).rgb;
 if(part>1.5) col*=mix(vec3(1.0,.78,.60),vec3(1.0,1.0,.92),variation);
 float rim=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),3.0);
 col=mix(col,team.rgb,rim*team.a*.16);
 float gray=dot(col,vec3(.3,.55,.15));
 col=mix(col,vec3(gray*.7,gray*.55,gray*.4),wither);
 ALBEDO=col*mix(1.0,.55,growing);
 NORMAL_MAP=texture(normal_map,UV).rgb;
 NORMAL_MAP_DEPTH=.65;
 vec3 orm=texture(orm_map,UV).rgb;
 ROUGHNESS=orm.g;
 AO=mix(1.0,orm.r,.55);
 AO_LIGHT_AFFECT=.4;
 BACKLIGHT=col*.10;
 EMISSION=vec3(1.0,.95,.85)*flash*.7;
}
