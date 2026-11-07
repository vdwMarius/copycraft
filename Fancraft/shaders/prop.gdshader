shader_type spatial;
// Textured props and building parts: texture-array layer per vertex (UV2.x), mesh UVs,
// vertex colour tint/AO (authored in sRGB; COLOR.a = saturation 0..1), cavity shading
// from the height channel.
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surface_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_texture = false;
uniform vec3 fallback_color : source_color = vec3(0.6, 0.5, 0.4);

varying flat float v_layer;

void vertex() {
	v_layer = UV2.x;
}

void fragment() {
	vec3 vc = pow(COLOR.rgb, vec3(2.2));
	vec3 col = fallback_color * vc * 1.6;
	float rough = 0.85;
	if (use_texture) {
		vec4 a = texture(albedo_tex, vec3(UV, v_layer));
		vec4 s = texture(surface_tex, vec3(UV, v_layer));
		col = a.rgb * vc * mix(0.6, 1.0, s.a);
		rough = s.b;
	}
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, COLOR.a);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.3, 1.0);
	SPECULAR = 0.35;
}

// Cel-shaded light, identical to the terrain and block shaders.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = ndl * 0.5 + 0.5;
	float lit = mix(0.38, 1.0, smoothstep(0.42, 0.58, wrap));
	lit = mix(lit, 1.12, smoothstep(0.82, 0.9, wrap) * 0.6);
	float shadow = mix(0.38, 1.0, ATTENUATION);
	DIFFUSE_LIGHT += LIGHT_COLOR * min(lit, shadow) / PI;
	vec3 H = normalize(VIEW + LIGHT);
	float gloss = 1.0 - ROUGHNESS;
	float spec = smoothstep(0.45, 0.55, pow(max(dot(NORMAL, H), 0.0), mix(12.0, 160.0, gloss))) * gloss * gloss;
	SPECULAR_LIGHT += LIGHT_COLOR * spec * ATTENUATION * 0.6 / PI;
	float rim = smoothstep(0.62, 0.78, 1.0 - max(dot(NORMAL, VIEW), 0.0)) * max(ndl, 0.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * rim * 0.18 / PI;
#ifdef BACKLIGHT_GLOW
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * max(-ndl, 0.0) * 0.35 * ATTENUATION / PI;
#endif
}
