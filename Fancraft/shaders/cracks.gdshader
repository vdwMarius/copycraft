shader_type spatial;
// Minecraft-style breaking overlay: a box hugging the piece being broken, multiplied
// over the scene. Voronoi crack lines spread from the middle of each face in 10 stages.
render_mode blend_mul, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform float progress = 0.0;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distance to the nearest Voronoi cell border (crack lines).
float borders(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return md;
}

void fragment() {
	vec3 an = abs(wn);
	vec2 uv = an.y > 0.5 ? wp.xz : (an.x > 0.5 ? wp.zy : wp.xy);
	float stage = floor(progress * 10.0) / 10.0;     // 10 discrete stages
	vec2 c = fract(uv) - 0.5;
	float reach = smoothstep(stage * 0.85 + 0.08, stage * 0.85 - 0.02, length(c) * 1.3);
	float w = mix(0.025, 0.06, stage);
	float big = 1.0 - smoothstep(w * 0.5, w, borders(uv * 2.6));
	float fine = (1.0 - smoothstep(w * 0.25, w * 0.55, borders(uv * 6.5 + 3.7))) * step(0.45, stage);
	float crack = clamp(max(big, fine * 0.8) * reach, 0.0, 1.0) * step(0.05, progress);
	ALBEDO = vec3(mix(1.0, 0.16, crack));
}
