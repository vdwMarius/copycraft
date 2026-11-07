shader_type canvas_item;
render_mode blend_disabled, unshaded;
// Fancraft procedural texture synthesiser.
// Draws an atlas of `tiles` square tiles (each `res` px) laid out in `cols` columns.
// mode 0: albedo (RGB colour, A opacity)
// mode 1: surface (RG tangent normal, OpenGL +Y up, B roughness, A height)
// mode 2: surface for a user pack, computed from the *_atlas inputs below.
// Every pattern is periodic over the tile, so blocks tile seamlessly.

uniform int mode = 0;
uniform float res = 64.0;
uniform int cols = 5;
uniform int tiles = 20;
uniform vec2 atlas_px = vec2(320.0, 256.0);
uniform float normal_depth = 0.1;

// mode 2 inputs (raw data, nearest sampling)
uniform sampler2D albedo_atlas : filter_nearest;
uniform sampler2D height_atlas : filter_nearest;
uniform sampler2D normal_atlas : filter_nearest;
uniform sampler2D rough_atlas : filter_nearest;
uniform sampler2D builtin_surface : filter_nearest;
// per tile bit flags: 1 height map, 2 normal map, 4 roughness map, 8 whole tile from built-in
uniform int flags[32];


float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Value noise, periodic with `per` lattice cells.
float vnoise(vec2 p, vec2 per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(mod(i, per));
	float b = hash21(mod(i + vec2(1.0, 0.0), per));
	float c = hash21(mod(i + vec2(0.0, 1.0), per));
	float d = hash21(mod(i + vec2(1.0, 1.0), per));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Tileable fBm over uv in [0,1): `base` lattice cells per tile on the first octave.
float fbm(vec2 uv, float base, int oct) {
	float s = 0.0;
	float a = 0.5;
	float tot = 0.0;
	float f = base;
	for (int i = 0; i < oct; i++) {
		s += a * vnoise(uv * f + float(i) * 7.31 * f, vec2(f));
		tot += a;
		f *= 2.0;
		a *= 0.5;
	}
	return s / tot;
}

vec2 cell_point(vec2 cell, float n, float jitter) {
	vec2 h = hash22(mod(cell, vec2(n)) + 11.0);
	return mix(vec2(0.5), h, jitter);
}

// Tileable Voronoi. x = distance to nearest point, y = distance to nearest edge,
// z = random id of the nearest cell, w unused. `rel` = offset from the cell point.
vec4 voronoi(vec2 uv, float n, float jitter, out vec2 rel) {
	vec2 p = uv * n;
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + cell_point(i + g, n, jitter) - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	float ed = 8.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 g = mg + vec2(float(x), float(y));
			vec2 r = g + cell_point(i + g, n, jitter) - f;
			vec2 dr = r - mr;
			if (dot(dr, dr) > 0.00001) {
				ed = min(ed, dot(0.5 * (mr + r), normalize(dr)));
			}
		}
	}
	rel = -mr;
	return vec4(sqrt(md) / n, ed / n, hash21(mod(i + mg, vec2(n)) + 3.7), 0.0);
}

vec4 voronoi(vec2 uv, float n, float jitter) {
	vec2 r;
	return voronoi(uv, n, jitter, r);
}

float px() {
	return 1.0 / res;
}

// ---------------------------------------------------------------- materials

void dirt_mat(vec2 uv, out vec3 col, out float h) {
	float f = fbm(uv, 4.0, 5);
	float g = fbm(uv, 16.0, 3);
	vec4 v = voronoi(uv, 9.0, 1.0);
	float pebble = smoothstep(0.06, 0.03, v.x) * step(0.85, v.z);
	h = 0.2 + 0.35 * f + 0.25 * g + 0.45 * pebble;
	col = mix(vec3(0.27, 0.17, 0.10), vec3(0.50, 0.35, 0.21), f * 0.8 + g * 0.4);
	col = mix(col, vec3(0.45, 0.39, 0.33) * (0.8 + 0.3 * f), pebble);
	col *= 0.8 + 0.3 * h;
}

void grass_mat(vec2 uv, out vec3 col, out float h) {
	float n1 = fbm(uv, 3.0, 4);
	vec4 clump = voronoi(uv, 7.0, 1.0);
	float c = 1.0 - smoothstep(0.0, 0.09, clump.x);
	// blades: stretched noise rotated per clump
	float ang = clump.z * TAU;
	vec2 dir = vec2(cos(ang), sin(ang));
	float blades = fbm(uv + dir * 0.01 * fbm(uv, 8.0, 2), 16.0, 3);
	h = 0.25 + 0.35 * c + 0.4 * blades;
	h = clamp(h, 0.0, 1.0);
	vec3 dark = vec3(0.14, 0.32, 0.07);
	vec3 light = vec3(0.47, 0.76, 0.22);
	col = mix(dark, light, smoothstep(0.25, 0.9, h));
	col = mix(col, col * vec3(1.15, 1.05, 0.7), smoothstep(0.55, 0.8, n1) * 0.6);
	// tiny flowers
	vec2 fc = floor(uv * 12.0);
	float fl = hash21(mod(fc, vec2(12.0)) + 91.0);
	vec2 fp = fract(uv * 12.0) - 0.5;
	if (fl > 0.94 && length(fp) < 0.22) {
		col = fl > 0.97 ? vec3(1.0, 0.9, 0.35) : vec3(0.95, 0.95, 1.0);
		h = 1.0;
	}
}

void mat(int id, vec2 uv, out vec3 col, out float h, out float r, out float a) {
	uv = fract(uv);
	col = vec3(1.0, 0.0, 1.0);
	h = 0.5;
	r = 0.85;
	a = 1.0;
	if (id == 0) { // grass_top
		grass_mat(uv, col, h);
	} else if (id == 1) { // grass_side
		dirt_mat(uv, col, h);
		h *= 0.75;
		float fringe = 0.16 + 0.12 * vnoise(vec2(uv.x * 6.0, 0.5), vec2(6.0, 1.0)) + 0.14 * vnoise(vec2(uv.x * 24.0, 0.5), vec2(24.0, 1.0));
		if (uv.y < fringe) {
			vec3 gc;
			float gh;
			grass_mat(uv, gc, gh);
			col = gc;
			h = 0.65 + 0.35 * gh;
		} else {
			col *= mix(0.55, 1.0, smoothstep(0.0, 0.08, uv.y - fringe));
		}
	} else if (id == 2) { // dirt
		dirt_mat(uv, col, h);
	} else if (id == 3) { // stone
		float f = fbm(uv, 4.0, 5);
		float s = fbm(uv, 24.0, 2);
		vec4 v = voronoi(uv, 3.0, 1.0);
		float crack = (1.0 - smoothstep(0.0, 0.004 + px() * 0.5, v.y)) * step(0.55, fbm(uv, 5.0, 2));
		float mottle = smoothstep(0.4, 0.7, fbm(uv + 0.5, 3.0, 4));
		h = 0.45 + 0.25 * (f - 0.5) + 0.15 * s + 0.15 * mottle - 0.45 * crack;
		col = mix(vec3(0.40, 0.41, 0.43), vec3(0.60, 0.60, 0.61), f * 0.8 + s * 0.4);
		col = mix(col, col * vec3(0.92, 0.9, 0.86), mottle * 0.5);
		col = mix(col, vec3(0.27, 0.27, 0.29), crack * 0.85);
		r = 0.8;
	} else if (id == 4) { // cobblestone
		vec4 v = voronoi(uv, 4.0, 0.85);
		float w = res <= 16.0 ? px() * 0.45 : 0.02 + px() * 0.5;
		float dome = sqrt(smoothstep(w, w + 0.09, v.y));
		float f = fbm(uv, 8.0, 3);
		h = dome * (0.8 + 0.2 * v.z) * (0.85 + 0.15 * f);
		vec3 sc = mix(vec3(0.42, 0.42, 0.44), vec3(0.62, 0.6, 0.57), v.z);
		sc = mix(sc, vec3(0.5, 0.44, 0.38), step(0.82, v.z) * 0.6);
		col = mix(vec3(0.16, 0.15, 0.15), sc * (0.75 + 0.35 * f) * (0.75 + 0.3 * dome), smoothstep(w * 0.5, w, v.y));
		r = 0.75;
	} else if (id == 5) { // sand
		float warp = fbm(uv, 2.0, 3);
		float ripple = sin(TAU * (uv.y * 5.0 + uv.x * 1.0 + warp * 1.5));
		float grain = hash21(floor(uv * res));
		float g2 = fbm(uv, 32.0, 1);
		h = 0.5 + 0.28 * ripple + 0.12 * g2 + 0.06 * grain;
		col = mix(vec3(0.80, 0.70, 0.48), vec3(0.95, 0.88, 0.66), h * 0.8 + 0.2 * grain);
		r = 0.9;
	} else if (id == 6) { // log_top
		vec2 c = uv - 0.5;
		float ang = atan(c.y, c.x);
		float rr = length(c) * 2.0;
		float wob = 0.03 * vnoise(vec2(ang / TAU * 8.0, 0.5), vec2(8.0, 1.0));
		float rings = 0.5 + 0.5 * sin((rr + wob) * 38.0 + fbm(uv, 4.0, 2) * 3.0);
		float barkr = 0.84 + 0.05 * vnoise(vec2(ang / TAU * 12.0, 0.5), vec2(12.0, 1.0));
		if (rr > barkr) {
			float g = vnoise(vec2(ang / TAU * 24.0, rr * 4.0), vec2(24.0, 100.0));
			h = 0.55 + 0.4 * g;
			col = mix(vec3(0.20, 0.13, 0.07), vec3(0.38, 0.26, 0.15), g);
		} else {
			h = 0.62 + 0.12 * rings - 0.08 * smoothstep(barkr - 0.06, barkr, rr);
			col = mix(vec3(0.62, 0.45, 0.26), vec3(0.80, 0.63, 0.40), rings);
			col *= 0.88 + 0.12 * fbm(uv, 8.0, 2);
		}
		r = 0.8;
	} else if (id == 7) { // log_side
		float g1 = vnoise(vec2(uv.x * 10.0, uv.y * 2.0), vec2(10.0, 2.0));
		float g2 = vnoise(vec2(uv.x * 22.0, uv.y * 5.0), vec2(22.0, 5.0));
		float groove = smoothstep(0.25, 0.75, g1 * 0.65 + g2 * 0.35);
		h = 0.15 + 0.85 * groove;
		col = mix(vec3(0.17, 0.11, 0.06), vec3(0.42, 0.29, 0.17), groove);
		col *= 0.9 + 0.2 * fbm(uv, 8.0, 2);
		r = 0.9;
	} else if (id == 8) { // planks
		float b = floor(uv.y * 4.0);
		float lv = fract(uv.y * 4.0);
		float off = hash21(vec2(b, 3.0));
		float sx = fract(uv.x + off);
		float dy = min(lv, 1.0 - lv) / 4.0;
		float dx = min(sx, 1.0 - sx);
		float e = min(dy, dx);
		float gw = max(0.008, px() * 0.75);
		float grain = vnoise(vec2((uv.x + off) * 3.0, uv.y * 52.0 + 4.0 * fbm(uv, 2.0, 2)), vec2(3.0, 52.0));
		float knot = smoothstep(0.06, 0.0, length((fract(vec2(uv.x + off * 2.3, lv * 0.25)) - vec2(0.6, 0.125)) * vec2(1.0, 4.0))) * step(0.6, off);
		h = smoothstep(gw, gw + 0.03, e) * (0.75 + 0.15 * grain) - 0.1 * knot;
		col = mix(vec3(0.52, 0.34, 0.18), vec3(0.76, 0.56, 0.33), grain * 0.7 + 0.15);
		col *= 0.82 + 0.3 * hash21(vec2(b, 9.0));
		col = mix(col, vec3(0.32, 0.2, 0.1), knot);
		col = mix(vec3(0.12, 0.07, 0.04), col, smoothstep(gw * 0.5, gw, e));
		r = 0.7;
	} else if (id == 9) { // leaves
		vec2 rel;
		vec4 v = voronoi(uv, 8.0, 1.0, rel);
		float shape = v.x / (0.55 / 8.0);
		float hole = step(0.68, fbm(uv, 6.0, 3)) + step(0.92, shape);
		a = hole > 0.5 ? 0.0 : 1.0;
		float vein = smoothstep(0.012, 0.0, abs(dot(rel, normalize(vec2(1.0, 0.6 + v.z)))) / 8.0);
		h = clamp(1.0 - shape * 0.8, 0.0, 1.0);
		col = mix(vec3(0.10, 0.30, 0.08), vec3(0.32, 0.62, 0.16), v.z * 0.6 + h * 0.5);
		col = mix(col, col * 1.3, vein * 0.5);
		r = 0.6;
	} else if (id == 10) { // glass
		vec2 p = floor(uv * res);
		float bw = max(1.0, floor(res / 16.0));
		float edge = min(min(p.x, res - 1.0 - p.x), min(p.y, res - 1.0 - p.y));
		float frame = step(edge, bw - 1.0);
		float streak = smoothstep(0.035, 0.0, abs(fract((uv.x + uv.y) * 2.0) - 0.3)) + smoothstep(0.02, 0.0, abs(fract((uv.x + uv.y) * 2.0) - 0.42));
		col = mix(vec3(0.75, 0.9, 0.95), vec3(0.9, 0.97, 1.0), frame);
		a = frame > 0.5 ? 1.0 : 0.14 + 0.25 * streak;
		h = frame > 0.5 ? 1.0 : 0.6;
		r = 0.04;
	} else if (id == 11) { // water
		float f = fbm(uv, 4.0, 4);
		float f2 = fbm(uv + f * 0.25, 8.0, 3);
		h = 0.35 + 0.35 * f2 + 0.2 * f;
		col = mix(vec3(0.07, 0.25, 0.52), vec3(0.25, 0.58, 0.82), h);
		a = 0.62;
		r = 0.04;
	} else if (id == 12) { // bricks
		float row = floor(uv.y * 4.0);
		float x = uv.x + mod(row, 2.0) * 0.25;
		float cx = floor(x * 2.0);
		float lx = fract(x * 2.0);
		float ly = fract(uv.y * 4.0);
		float e = min(min(lx, 1.0 - lx) * 0.5, min(ly, 1.0 - ly) * 0.25);
		float w = max(0.016, px() * 0.75);
		float bid = hash21(vec2(mod(cx, 2.0), mod(row, 4.0)) + 5.0);
		float f = fbm(uv, 8.0, 3);
		float bevel = smoothstep(w, w + 0.03, e);
		h = bevel * (0.72 + 0.18 * f + 0.1 * bid);
		vec3 bc = mix(vec3(0.55, 0.22, 0.15), vec3(0.72, 0.36, 0.24), bid);
		bc *= 0.8 + 0.35 * f;
		col = mix(vec3(0.64, 0.61, 0.56) * (0.8 + 0.2 * f), bc, step(w, e));
		r = 0.85;
	} else if (id == 13) { // snow
		float f = fbm(uv, 4.0, 4);
		float f2 = fbm(uv, 16.0, 2);
		h = 0.5 + 0.4 * (f - 0.5) + 0.12 * f2;
		col = mix(vec3(0.80, 0.86, 0.96), vec3(1.0, 1.0, 1.0), smoothstep(0.3, 0.75, h));
		float sp = hash21(floor(uv * res) + 31.0);
		if (sp > 0.985) {
			col = vec3(1.0);
			r = 0.15;
		} else {
			r = 0.6;
		}
	} else if (id == 14) { // gravel
		vec4 v = voronoi(uv, res <= 16.0 ? 4.0 : 7.0, 1.0);
		float w = res <= 16.0 ? px() * 0.35 : 0.008 + px() * 0.4;
		float dome = sqrt(smoothstep(w, w + 0.04, v.y));
		h = dome * (0.7 + 0.3 * v.z);
		vec3 sc = v.z < 0.33 ? vec3(0.45, 0.43, 0.42) : (v.z < 0.66 ? vec3(0.58, 0.53, 0.48) : vec3(0.33, 0.32, 0.33));
		sc *= 0.8 + 0.35 * fbm(uv, 16.0, 2);
		col = mix(vec3(0.12, 0.11, 0.1), sc * (0.7 + 0.35 * dome), smoothstep(w * 0.4, w, v.y));
		r = 0.85;
	} else if (id == 15) { // crystal
		vec2 rel;
		vec4 v = voronoi(uv, 3.0, 0.9, rel);
		float ang = v.z * TAU;
		vec2 dir = vec2(cos(ang), sin(ang));
		float facet = clamp(0.62 + dot(rel, dir) * 0.6, 0.0, 1.0);
		float edge = 1.0 - smoothstep(0.0, 0.012 + px() * 0.5, v.y);
		h = facet * (1.0 - edge * 0.6);
		col = mix(vec3(0.30, 0.90, 1.0), vec3(0.70, 0.42, 1.0), v.z);
		col *= 0.65 + 0.55 * facet;
		col = mix(col, vec3(0.95, 0.98, 1.0), edge);
		a = mix(0.72, 0.95, edge);
		r = 0.06;
	} else if (id == 16) { // mossy stone
		vec4 v = voronoi(uv, 3.0, 0.8);
		float w = 0.02 + px() * 0.5;
		float dome = pow(smoothstep(w, w + 0.12, v.y), 0.4);
		float f = fbm(uv, 6.0, 4);
		float moss = smoothstep(0.56, 0.66, fbm(uv + 0.3, 4.0, 5)) + 0.8 * (1.0 - smoothstep(w, w * 2.0, v.y));
		moss = clamp(moss, 0.0, 1.0);
		float fuzz = fbm(uv, 32.0, 2);
		h = dome * (0.75 + 0.15 * f) * (1.0 - moss * 0.2) + moss * (0.45 + 0.35 * fuzz);
		vec3 sc = mix(vec3(0.36, 0.37, 0.36), vec3(0.55, 0.55, 0.52), f + 0.2 * v.z);
		vec3 mc = mix(vec3(0.16, 0.32, 0.09), vec3(0.38, 0.55, 0.16), fuzz);
		col = mix(sc * (0.65 + 0.4 * dome), mc, moss);
		r = 0.85;
	} else if (id == 17) { // marble
		float f = fbm(uv, 3.0, 5);
		float vein = abs(sin(TAU * (uv.x + uv.y) * 1.0 + f * 9.0));
		float vein2 = abs(sin(TAU * (uv.x * 2.0 - uv.y) + f * 7.0 + 1.3));
		float vm = smoothstep(0.1, 0.0, vein) + 0.5 * smoothstep(0.05, 0.0, vein2);
		vec2 q = fract(uv * 2.0);
		float e = min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y)) * 0.5;
		float w = max(0.004, px() * 0.6);
		h = 0.85 * smoothstep(w, w + 0.02, e) + 0.08 * f;
		col = mix(vec3(0.86, 0.85, 0.82), vec3(0.97, 0.96, 0.94), f);
		col = mix(col, vec3(0.45, 0.43, 0.42), clamp(vm, 0.0, 1.0) * 0.7);
		col = mix(col, vec3(0.78, 0.66, 0.42), smoothstep(0.03, 0.0, vein2) * 0.5);
		col = mix(vec3(0.6, 0.58, 0.55), col, step(w, e));
		r = 0.12;
	} else if (id == 18) { // terracotta
		vec2 q = fract(uv * 2.0);
		vec2 t = floor(uv * 2.0);
		float e = min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y)) * 0.5;
		float w = max(0.012, px() * 0.75);
		float dia = abs(q.x - 0.5) + abs(q.y - 0.5);
		float stamp = smoothstep(0.05, 0.0, abs(dia - 0.3)) + smoothstep(0.06, 0.0, dia) ;
		float f = fbm(uv, 8.0, 3);
		float tv = hash21(t + 2.0);
		h = smoothstep(w, w + 0.03, e) * (0.7 + 0.1 * f) + 0.2 * stamp;
		col = mix(vec3(0.66, 0.32, 0.18), vec3(0.82, 0.47, 0.27), f * 0.6 + tv * 0.4);
		col = mix(col, vec3(0.93, 0.78, 0.5), clamp(stamp, 0.0, 1.0) * 0.55);
		col = mix(vec3(0.42, 0.36, 0.3), col, step(w, e));
		r = 0.55;
	} else if (id == 19) { // slate
		float row = floor(uv.y * 3.0);
		float ly = fract(uv.y * 3.0);
		float x = uv.x + mod(row, 2.0) * 0.25;
		float lx = fract(x * 2.0);
		float cx = floor(x * 2.0);
		float dx = min(lx, 1.0 - lx) * 0.5;
		float w = max(0.006, px() * 0.6);
		float sid = hash21(vec2(mod(cx, 2.0), row) + 17.0);
		float f = fbm(uv, 8.0, 3);
		// rounded lower corners
		float corner = length(max(vec2(0.0), vec2(0.12 - min(lx, 1.0 - lx), ly - 0.82)) * vec2(1.0, 0.7)) ;
		float cut = step(0.11, corner);
		h = (0.2 + 0.7 * ly) * smoothstep(w, w + 0.01, dx) * (1.0 - cut) + 0.05 * f;
		col = mix(vec3(0.17, 0.19, 0.23), vec3(0.30, 0.33, 0.38), sid * 0.6 + f * 0.5);
		col *= 0.7 + 0.45 * ly;
		col = mix(col, vec3(0.08, 0.08, 0.1), max(1.0 - step(w, dx), cut));
		r = 0.5;
	}
	col = clamp(col, 0.0, 1.0);
	h = clamp(h, 0.0, 1.0);
}

float height_of(int id, vec2 uv) {
	vec3 c;
	float h;
	float r;
	float a;
	mat(id, uv, c, h, r, a);
	return h;
}

// ---------------------------------------------------------------- pack mode

ivec2 wrap_tile(ivec2 p, int n) {
	return ivec2((p.x % n + n) % n, (p.y % n + n) % n);
}

float pack_height(ivec2 origin, ivec2 lp, int n, int fl) {
	ivec2 p = origin + wrap_tile(lp, n);
	if ((fl & 1) != 0) {
		return texelFetch(height_atlas, p, 0).r;
	}
	vec4 c = texelFetch(albedo_atlas, p, 0);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	return mix(0.5, lum, 0.65);
}

vec4 pack_surface(int id, ivec2 origin, ivec2 lp) {
	int n = int(res);
	int fl = flags[id];
	if ((fl & 8) != 0) {
		return texelFetch(builtin_surface, origin + lp, 0);
	}
	float h = 0.0;
	if ((fl & 1) != 0) {
		h = pack_height(origin, lp, n, fl);
	} else {
		// soft: 3x3 blur of luminance
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				h += pack_height(origin, lp + ivec2(x, y), n, fl);
			}
		}
		h /= 9.0;
	}
	vec2 nxy;
	if ((fl & 2) != 0) {
		nxy = texelFetch(normal_atlas, origin + lp, 0).rg;
	} else {
		// Sobel; image y grows downward, normal +Y points up the image.
		float tl = pack_height(origin, lp + ivec2(-1, -1), n, fl);
		float tc = pack_height(origin, lp + ivec2(0, -1), n, fl);
		float tr = pack_height(origin, lp + ivec2(1, -1), n, fl);
		float ml = pack_height(origin, lp + ivec2(-1, 0), n, fl);
		float mr = pack_height(origin, lp + ivec2(1, 0), n, fl);
		float bl = pack_height(origin, lp + ivec2(-1, 1), n, fl);
		float bc = pack_height(origin, lp + ivec2(0, 1), n, fl);
		float br = pack_height(origin, lp + ivec2(1, 1), n, fl);
		float gx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
		float gy = (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr);
		// gradients per pixel -> per uv unit
		float s = res * normal_depth / 8.0;
		vec3 nn = normalize(vec3(-gx * s, gy * s, 1.0));
		nxy = nn.xy * 0.5 + 0.5;
	}
	float rough = (fl & 4) != 0 ? texelFetch(rough_atlas, origin + lp, 0).r : texelFetch(builtin_surface, origin + lp, 0).b;
	return vec4(nxy, rough, h);
}

// ---------------------------------------------------------------- entry

void fragment() {
	vec2 pix = floor(UV * atlas_px);
	vec2 tile = floor(pix / res);
	int id = int(tile.y) * cols + int(tile.x);
	vec2 lp = pix - tile * res;
	vec2 uv = (lp + 0.5) / res;
	if (id >= tiles) {
		COLOR = vec4(0.0);
	} else if (mode == 2) {
		COLOR = pack_surface(id, ivec2(tile * res), ivec2(lp));
	} else {
		vec3 col;
		float h;
		float r;
		float a;
		mat(id, uv, col, h, r, a);
		if (mode == 0) {
			COLOR = vec4(col, a);
		} else {
			float e = 1.0 / res;
			float dhdu = (height_of(id, uv + vec2(e, 0.0)) - height_of(id, uv - vec2(e, 0.0))) / (2.0 * e);
			float dhdv = (height_of(id, uv + vec2(0.0, e)) - height_of(id, uv - vec2(0.0, e))) / (2.0 * e);
			vec3 nn = normalize(vec3(-dhdu * normal_depth, dhdv * normal_depth, 1.0));
			COLOR = vec4(nn.xy * 0.5 + 0.5, r, h);
		}
	}
}
