shader_type spatial;
// Stylised foliage (canopies, bushes, conifer tiers): vertex-colour cel shading,
// wind sway weighted by vertex alpha, back-light glow. No texture sampling.
render_mode cull_back, diffuse_lambert_wrap, specular_disabled;

#define BACKLIGHT_GLOW
uniform float sway_strength = 0.1;
uniform float sway_speed = 1.2;
uniform vec3 tint : source_color = vec3(1.0);

varying float v_var;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float ph = origin.x * 0.37 + origin.z * 0.23;
	float w = COLOR.a;
	VERTEX.x += sin(TIME * sway_speed + ph + VERTEX.y * 0.35) * sway_strength * w;
	VERTEX.z += cos(TIME * sway_speed * 0.83 + ph * 1.3) * sway_strength * 0.7 * w;
	v_var = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2)) * tint;
	// Per-plant hue/value variation so forests are not copy-paste.
	c *= mix(vec3(0.9, 0.95, 0.88), vec3(1.08, 1.04, 0.96), v_var);
	ALBEDO = c;
	ROUGHNESS = 0.95;
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
