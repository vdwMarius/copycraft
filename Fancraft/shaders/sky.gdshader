shader_type sky;
// Stylised sky: painted gradient, soft sun with halo, and layered cel-shaded clouds.
// No TIME: the radiance cubemap (ambient + reflections) only needs to update when
// uniforms change, which keeps it cheap on phones.

uniform vec3 zenith : source_color = vec3(0.12, 0.42, 0.86);
uniform vec3 horizon : source_color = vec3(0.62, 0.86, 0.98);
uniform vec3 ground : source_color = vec3(0.58, 0.78, 0.9);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.86, 0.62);
uniform vec3 cloud_light : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.7, 0.86);
uniform float cloud_cover = 0.48;
uniform float cloud_offset = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += noise(p) * a;
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float up = d.y;
	vec3 col;
	if (up >= 0.0) {
		float t = pow(1.0 - up, 3.0);
		col = mix(zenith, horizon, t);
	} else {
		col = mix(horizon, ground, smoothstep(0.0, 0.25, -up));
	}
	// Sun
	vec3 L = LIGHT0_DIRECTION;
	float sd = max(dot(d, L), 0.0);
	float halo = pow(sd, 12.0) * 0.35 + pow(sd, 120.0) * 0.6;
	col += sun_tint * halo * LIGHT0_ENERGY;
	if (!AT_CUBEMAP_PASS && sd > 0.9994) {
		col += sun_tint * 6.0 * LIGHT0_ENERGY;
	}
	// Clouds on a flat layer projected onto the dome.
	if (up > 0.02) {
		vec2 uv = d.xz / (up + 0.12) * 1.6 + vec2(cloud_offset, 0.0);
		float n = fbm(uv * 0.9);
		float shape = smoothstep(cloud_cover, cloud_cover + 0.06, n);   // crisp edges
		float lit = smoothstep(cloud_cover, cloud_cover + 0.32, fbm(uv * 0.9 + L.xz * 0.12));
		vec3 cc = mix(cloud_shade, cloud_light, 1.0 - lit * 0.7);
		cc += sun_tint * pow(sd, 6.0) * 0.4;
		float fade = smoothstep(0.02, 0.22, up);
		col = mix(col, cc, shape * fade * 0.92);
	}
	COLOR = col;
}
