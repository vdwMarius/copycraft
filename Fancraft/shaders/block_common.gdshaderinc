// Shared block surface shader. Expects BLOCK_FILTER and one of PASS_OPAQUE /
// PASS_CUTOUT / PASS_TRANSLUCENT to be defined by the including shader.
//
// Vertex data: UV.x = texture layer, UV.y = emission, COLOR.r = ambient occlusion.
// Texture coordinates come from world position, so pieces of any size or offset
// tile seamlessly. Height (surface.a) drives parallax occlusion mapping.

uniform sampler2DArray albedo_tex : source_color, BLOCK_FILTER, repeat_enable;
uniform sampler2DArray surface_tex : BLOCK_FILTER, repeat_enable;
uniform int pom_steps = 12;
uniform float pom_scale = 0.05;
uniform float pom_fade_start = 8.0;
uniform float pom_fade_end = 20.0;
uniform bool pom_shadows = false;
uniform vec3 sun_dir = vec3(0.45, 0.75, 0.35);
uniform float water_layer = 11.0;
uniform float cavity_strength = 0.75;

varying vec3 w_pos;
varying vec3 w_nrm;
varying flat float v_layer;
varying flat float v_emis;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = NORMAL;
	v_layer = UV.x;
	v_emis = UV.y;
#ifdef PASS_CUTOUT
	// Gentle wind sway for foliage.
	float sway = sin(TIME * 1.6 + w_pos.x * 0.7 + w_pos.z * 0.5) * 0.025;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
#endif
}

float depth_at(vec2 uv, vec2 dx, vec2 dy) {
	return 1.0 - textureGrad(surface_tex, vec3(uv, v_layer), dx, dy).a;
}

void fragment() {
	vec3 N = normalize(w_nrm);
	vec3 an = abs(N);
	vec3 T;
	vec3 Bv;
	if (an.y > 0.5) {
		T = vec3(1.0, 0.0, 0.0);
		Bv = vec3(0.0, 0.0, sign(N.y));
	} else if (an.x > 0.5) {
		T = vec3(0.0, 0.0, -sign(N.x));
		Bv = vec3(0.0, -1.0, 0.0);
	} else {
		T = vec3(sign(N.z), 0.0, 0.0);
		Bv = vec3(0.0, -1.0, 0.0);
	}
	vec2 uv = vec2(dot(w_pos, T), dot(w_pos, Bv));
	bool is_water = abs(v_layer - water_layer) < 0.5;
	if (is_water) {
		uv += vec2(sin(TIME * 0.35 + uv.y * 0.6), cos(TIME * 0.3 + uv.x * 0.5)) * 0.08 + vec2(TIME * 0.03, TIME * 0.017);
	}
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec3 to_cam = CAMERA_POSITION_WORLD - w_pos;
	float dist = length(to_cam);
	vec3 V = to_cam / max(dist, 0.0001);
	float vn = max(dot(V, N), 0.12);
	float fade = 1.0 - smoothstep(pom_fade_start, pom_fade_end, dist);

	vec2 puv = uv;
#ifdef PASS_OPAQUE
	if (pom_steps > 0 && fade > 0.02) {
		float steps = mix(4.0, float(pom_steps), 1.0 - vn);
		int n = int(steps);
		float layer_d = 1.0 / steps;
		vec2 vuv = vec2(dot(V, T), dot(V, Bv));
		vec2 delta = -vuv / vn * (pom_scale * fade) * layer_d;
		vec2 cur = uv;
		float cur_d = 0.0;
		float d = depth_at(cur, dx, dy);
		for (int i = 0; i < 48; i++) {
			if (i >= n || cur_d >= d) {
				break;
			}
			cur += delta;
			cur_d += layer_d;
			d = depth_at(cur, dx, dy);
		}
		vec2 prev = cur - delta;
		float after = d - cur_d;
		float before = depth_at(prev, dx, dy) - (cur_d - layer_d);
		float w = after / min(after - before, -0.0001);
		puv = mix(cur, prev, clamp(w, 0.0, 1.0));
	}
#endif

	vec4 alb = textureGrad(albedo_tex, vec3(puv, v_layer), dx, dy);
	vec4 surf = textureGrad(surface_tex, vec3(puv, v_layer), dx, dy);
	vec2 ns = surf.rg * 2.0 - 1.0;
	float nz = sqrt(max(1.0 - dot(ns, ns), 0.0));
	vec3 wn = normalize(T * ns.x - Bv * ns.y + N * nz);
	float shade = 1.0;
#ifdef PASS_OPAQUE
	if (pom_shadows && fade > 0.02) {
		vec3 L = normalize(sun_dir);
		float ln = dot(L, N);
		if (ln > 0.05) {
			vec2 luv = vec2(dot(L, T), dot(L, Bv)) / ln * pom_scale * fade;
			float h0 = surf.a;
			for (int i = 1; i <= 6; i++) {
				float t = float(i) / 6.0;
				float h = textureGrad(surface_tex, vec3(puv + luv * t * (1.0 - h0), v_layer), dx, dy).a;
				if (h > h0 + t * (1.0 - h0) + 0.02) {
					shade = 0.62;
					break;
				}
			}
		}
	}
#endif
	float cavity = mix(1.0, mix(0.5, 1.0, surf.a), cavity_strength * mix(0.45, 1.0, fade));
	float ao = COLOR.r;
	ALBEDO = alb.rgb * cavity * shade * mix(1.0, ao, 0.55);
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	// Soft rim sheen on edges facing away from the camera: a stylised "pop".
	RIM = 0.22;
	RIM_TINT = 0.6;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = surf.b;
	SPECULAR = 0.45;
	if (v_emis > 0.0) {
		EMISSION = alb.rgb * v_emis * (0.75 + 0.25 * sin(TIME * 1.7 + w_pos.y * 2.0));
	}
#ifdef PASS_CUTOUT
	ALPHA = alb.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	BACKLIGHT = alb.rgb * 0.3;
#endif
#ifdef PASS_TRANSLUCENT
	float fres = pow(1.0 - vn, 3.0);
	ALPHA = clamp(mix(alb.a, 1.0, fres * 0.7), 0.0, 1.0);
	if (is_water) {
		ROUGHNESS = 0.04;
		SPECULAR = 0.7;
	}
#endif
}
