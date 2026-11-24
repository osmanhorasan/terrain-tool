shader_type spatial;

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D splatmap : filter_linear, repeat_disable;
uniform sampler2D splatmap2 : filter_linear, repeat_disable;
uniform sampler2D layer0 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer3 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer4 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer5 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer6 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer7 : source_color, filter_linear_mipmap, repeat_enable;
uniform float uv_tiling = 32.0;
uniform float world_size = 128.0;
uniform float texel_uv = 0.00390625;
uniform float spacing = 0.5;
uniform int view_mode = 0; // 0 shaded, 1 height, 2 slope, 3 splat, 4 contour

varying vec2 tuv;
varying float vh;
varying float slope;

void vertex() {
	tuv = VERTEX.xz / world_size + 0.5;
	float h = texture(heightmap, tuv).r;
	VERTEX.y = h;
	vh = h;
	float hl = texture(heightmap, tuv - vec2(texel_uv, 0.0)).r;
	float hr = texture(heightmap, tuv + vec2(texel_uv, 0.0)).r;
	float hd = texture(heightmap, tuv - vec2(0.0, texel_uv)).r;
	float hu = texture(heightmap, tuv + vec2(0.0, texel_uv)).r;
	vec3 n = normalize(vec3(hl - hr, 2.0 * spacing, hd - hu));
	slope = 1.0 - n.y;
	NORMAL = n;
}

vec3 splat_debug(vec4 s1, vec4 s2) {
	vec3 c = vec3(0.0);
	c += s1.r * vec3(0.2, 0.8, 0.2);
	c += s1.g * vec3(0.6, 0.6, 0.6);
	c += s1.b * vec3(0.95, 0.95, 1.0);
	c += s1.a * vec3(0.85, 0.7, 0.4);
	c += s2.r * vec3(0.55, 0.35, 0.15);
	c += s2.g * vec3(0.35, 0.25, 0.15);
	c += s2.b * vec3(0.7, 0.7, 0.68);
	c += s2.a * vec3(0.15, 0.45, 0.1);
	return c;
}

void fragment() {
	vec4 s1 = texture(splatmap, tuv);
	vec4 s2 = texture(splatmap2, tuv);
	if (view_mode == 1) {
		ALBEDO = vec3(clamp(vh * 0.04 + 0.3, 0.0, 1.0));
		ROUGHNESS = 1.0;
	} else if (view_mode == 2) {
		float sl = clamp(slope * 4.0, 0.0, 1.0);
		ALBEDO = vec3(sl, 1.0 - sl, 0.0);
		ROUGHNESS = 1.0;
	} else if (view_mode == 3) {
		ALBEDO = splat_debug(s1, s2);
		ROUGHNESS = 1.0;
	} else {
		s1 = smoothstep(0.15, 0.85, s1);
		s2 = smoothstep(0.15, 0.85, s2);
		float total = max(s1.r + s1.g + s1.b + s1.a + s2.r + s2.g + s2.b + s2.a, 0.001);
		vec3 col = vec3(0.0);
		col += texture(layer0, tuv * uv_tiling).rgb * s1.r;
		col += texture(layer1, tuv * uv_tiling).rgb * s1.g;
		col += texture(layer2, tuv * uv_tiling).rgb * s1.b;
		col += texture(layer3, tuv * uv_tiling).rgb * s1.a;
		col += texture(layer4, tuv * uv_tiling).rgb * s2.r;
		col += texture(layer5, tuv * uv_tiling).rgb * s2.g;
		col += texture(layer6, tuv * uv_tiling).rgb * s2.b;
		col += texture(layer7, tuv * uv_tiling).rgb * s2.a;
		ALBEDO = col / total;
		if (view_mode == 4) { // contour lines every 5m
			float lw = fwidth(vh) * 1.5 + 0.05;
			float d = abs(fract(vh / 5.0 + 0.5) - 0.5) * 5.0;
			float line = 1.0 - smoothstep(0.0, lw, d);
			ALBEDO = mix(ALBEDO, vec3(0.05), line);
		}
		ROUGHNESS = 0.9;
		SPECULAR = 0.2;
	}
}
