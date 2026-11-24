shader_type spatial;

uniform sampler2D splatmap : filter_linear;
uniform sampler2D splatmap2 : filter_linear;
uniform sampler2D layer0 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer3 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer4 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer5 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer6 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer7 : source_color, filter_linear_mipmap, repeat_enable;
uniform float uv_tiling = 32.0;

void fragment() {
	vec4 s1 = texture(splatmap, UV);
	vec4 s2 = texture(splatmap2, UV);
	float total = max(s1.r + s1.g + s1.b + s1.a + s2.r + s2.g + s2.b + s2.a, 0.001);
	vec3 col = vec3(0.0);
	col += texture(layer0, UV * uv_tiling).rgb * s1.r;
	col += texture(layer1, UV * uv_tiling).rgb * s1.g;
	col += texture(layer2, UV * uv_tiling).rgb * s1.b;
	col += texture(layer3, UV * uv_tiling).rgb * s1.a;
	col += texture(layer4, UV * uv_tiling).rgb * s2.r;
	col += texture(layer5, UV * uv_tiling).rgb * s2.g;
	col += texture(layer6, UV * uv_tiling).rgb * s2.b;
	col += texture(layer7, UV * uv_tiling).rgb * s2.a;
	ALBEDO = col / total;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
