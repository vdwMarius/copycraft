shader_type spatial;
// Grass and flower tufts (instanced): two-sided, wind sway weighted by UV.x, soft
// up-facing normals, colour patches across the field, and a shrink-out near the
// instancer's view distance so there is no hard edge.
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform float sway_strength = 0.12;
uniform float sway_speed = 1.6;
uniform float fade_start = 22.0;
uniform float fade_end = 34.0;
uniform vec3 patch_a : source_color = vec3(0.92, 1.0, 0.85);
uniform vec3 patch_b : source_color = vec3(1.08, 1.02, 0.82);

varying vec3 v_world;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float d = distance(CAMERA_POSITION_WORLD, origin);
	float s = 1.0 - smoothstep(fade_start, fade_end, d);
	float w = UV.x;
	float ph = origin.x * 0.21 + origin.z * 0.17;
	VERTEX.x += (sin(TIME * sway_speed + ph) * 0.7 + sin(TIME * sway_speed * 2.3 + ph * 3.0) * 0.3) * sway_strength * w;
	VERTEX.z += cos(TIME * sway_speed * 0.9 + ph * 1.7) * sway_strength * 0.6 * w;
	VERTEX *= s;
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_world = origin;
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float n = sin(v_world.x * 0.11) * sin(v_world.z * 0.13) * 0.5 + 0.5;
	c *= mix(patch_a, patch_b, n);
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
