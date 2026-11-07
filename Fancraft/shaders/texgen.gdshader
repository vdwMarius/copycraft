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

float px() {
	return 1.0 / res;
}

// Anti-aliased hard edge: 0 outside (d < 0), 1 inside, one-pixel transition.
float edge(float d) {
	float w = px() * 0.75;
	return smoothstep(-w, w, d);
}

// Rounded bevel profile: 0 at the rim, 1 once `w` inside the shape.
float bevel(float d, float w) {
	float t = clamp(d / w, 0.0, 1.0);
	return 1.0 - (1.0 - t) * (1.0 - t);
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

vec3 ramp3(vec3 a, vec3 b, vec3 c, float t) {
	t = clamp(t, 0.0, 1.0);
	return t < 0.5 ? mix(a, b, t * 2.0) : mix(b, c, t * 2.0 - 1.0);
}

// Fine grain whose size follows the output resolution, so 256/512 px gain real detail.
// Fades out at low resolutions where it would only add noise.
float grain(vec2 uv, float seed) {
	if (res < 48.0) {
		return 0.0;
	}
	float n = res / 4.0;
	float g = vnoise(uv * n + seed * 13.1, vec2(n)) - 0.5;
	float g2 = vnoise(uv * n * 2.0 + seed * 7.7, vec2(n * 2.0)) - 0.5;
	return (g + 0.5 * g2) * smoothstep(48.0, 192.0, res);
}

// Tileable Voronoi with per-axis period. Returns x = distance to point, y = distance to
// nearest edge (both in cell units), z = cell id in [0,1]. `rel` = offset from cell point.
vec4 voro(vec2 uv, vec2 n, float jitter, out vec2 rel) {
	vec2 p = uv * n;
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = mix(vec2(0.5), hash22(mod(i + g, n) + 11.0), jitter);
			vec2 r = g + o - f;
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
			vec2 o = mix(vec2(0.5), hash22(mod(i + g, n) + 11.0), jitter);
			vec2 r = g + o - f;
			vec2 dr = r - mr;
			if (dot(dr, dr) > 0.00001) {
				ed = min(ed, dot(0.5 * (mr + r), normalize(dr)));
			}
		}
	}
	rel = -mr;
	return vec4(sqrt(md), ed, hash21(mod(i + mg, n) + 3.7), 0.0);
}

// Field of pointed blades/leaves scattered on a jittered grid (n cells per tile).
// size = (length, half width) in cell units; returns x = height (0 = none),
// y = blade id, z = position along the blade (0 root .. 1 tip).
vec3 blades(vec2 uv, float n, vec2 size, float ang0, float spread, float seed) {
	vec2 p = uv * n;
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec3 best = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 c = mod(i + g, vec2(n));
			vec2 o = g + hash22(c + seed) - f;
			float a = ang0 + (hash21(c + seed * 1.37) - 0.5) * spread;
			vec2 q = rot(-o, -a);
			float t = q.x / size.x;
			if (t > 0.0 && t < 1.0) {
				float w = size.y * sin(3.14159 * pow(t, 0.75));
				float d = (w - abs(q.y)) / n;
				float cov = edge(d);
				if (cov > 0.0) {
					float rnd = hash21(c + seed * 2.11);
					float across = 1.0 - abs(q.y) / max(w, 0.0001);
					float hh = (0.45 + 0.4 * rnd + 0.15 * t) * (0.75 + 0.25 * sqrt(across));
					hh *= cov;
					if (hh > best.x) {
						best = vec3(hh, rnd, t);
					}
				}
			}
		}
	}
	return best;
}

// Small round dots on a grid: x = coverage, y = dome height, z = id.
vec3 dots(vec2 uv, float n, float density, float radius, float seed) {
	vec2 p = uv * n;
	vec2 i = floor(p);
	vec3 best = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = mod(i + vec2(float(x), float(y)), vec2(n));
			float h = hash21(c + seed);
			if (h < density) {
				vec2 ctr = i + vec2(float(x), float(y)) + 0.2 + 0.6 * hash22(c + seed * 3.1);
				float rr = radius * (0.6 + 0.8 * hash21(c + seed * 5.3));
				float d = rr - length(p - ctr);
				float cov = edge(d / n);
				if (cov > best.x) {
					best = vec3(cov, sqrt(clamp(d / rr, 0.0, 1.0)), h / density);
				}
			}
		}
	}
	return best;
}

// Grass blades hanging down from the top edge (grass_side). n columns per tile.
// Returns x = height (0 = none), y = blade id, z = position along blade (0 root .. 1 tip).
vec3 hang_blades(vec2 uv, float n, float y0, float len, float seed) {
	float pxu = uv.x * n;
	float i = floor(pxu);
	vec3 best = vec3(0.0);
	for (int k = -1; k <= 1; k++) {
		float c = mod(i + float(k), n);
		float rx = i + float(k) + hash21(vec2(c, seed));
		float ry = y0 + 0.05 * hash21(vec2(c, seed + 1.0));
		float l = len * (0.45 + 0.75 * hash21(vec2(c, seed + 2.0)));
		float ang = (hash21(vec2(c, seed + 3.0)) - 0.5) * 0.6;
		vec2 q = rot(vec2(pxu - rx, (uv.y - ry) * n), -ang);
		float t = q.y / (l * n);
		if (t > 0.0 && t < 1.0) {
			float w = 0.5 * pow(1.0 - t, 0.85) + 0.04;
			float cov = edge((w - abs(q.x)) / n);
			float hh = cov * (0.6 + 0.3 * hash21(vec2(c, seed + 4.0)) + 0.1 * (1.0 - abs(q.x) / w));
			if (hh > best.x) {
				best = vec3(hh, hash21(vec2(c, seed + 5.0)), t);
			}
		}
	}
	return best;
}

// ---------------------------------------------------------------- materials

void dirt_mat(vec2 uv, out vec3 col, out float h) {
	vec2 rel;
	vec4 v = voro(uv, vec2(5.0), 1.0, rel);
	float clod = bevel(v.y - 0.03, 0.14);
	float crack = (1.0 - edge(v.y / 5.0 - 0.004 - px() * 0.5)) * smoothstep(0.52, 0.6, fbm(uv + 0.2, 4.0, 3));
	float wash = fbm(uv, 3.0, 3);
	h = 0.22 + 0.3 * clod + 0.08 * wash + 0.05 * grain(uv, 1.0) - 0.2 * crack;
	col = ramp3(vec3(0.20, 0.12, 0.07), vec3(0.38, 0.24, 0.13), vec3(0.52, 0.36, 0.20), clod * 0.7 + v.z * 0.3);
	col *= mix(vec3(0.95, 1.0, 1.05), vec3(1.08, 1.0, 0.92), wash);
	col = mix(col, vec3(0.13, 0.07, 0.04), crack);
	vec2 prel;
	vec4 pv = voro(uv + 0.37, vec2(11.0), 1.0, prel);
	if (pv.z > 0.86) {
		float pr = (0.26 + 0.12 * fract(pv.z * 7.0)) - length(prel);
		float cov = edge(pr / 11.0);
		float dome = sqrt(clamp(pr / 0.25, 0.0, 1.0));
		vec3 pc = mix(vec3(0.50, 0.46, 0.42), vec3(0.70, 0.64, 0.55), fract(pv.z * 13.0));
		col = mix(col, pc * (0.75 + 0.3 * dome), cov);
		h = mix(h, 0.55 + 0.4 * dome, cov);
	}
	vec3 s = dots(uv, 16.0, 0.25, 0.12, 4.0);
	col = mix(col, col * 1.35, s.x * 0.6);
}

void grass_top_mat(vec2 uv, out vec3 col, out float h) {
	// Shadowed soil between blades.
	float wash = fbm(uv, 2.0, 3);
	col = mix(vec3(0.07, 0.17, 0.05), vec3(0.12, 0.24, 0.06), wash);
	h = 0.12 + 0.05 * wash;
	vec3 layers[3];
	layers[0] = blades(uv, 6.0, vec2(1.25, 0.2), 0.0, TAU, 1.0);
	layers[1] = blades(uv, 9.0, vec2(1.15, 0.17), 0.0, TAU, 2.0);
	layers[2] = blades(uv, 13.0, vec2(1.05, 0.15), 0.0, TAU, 3.0);
	for (int k = 0; k < 3; k++) {
		vec3 b = layers[k];
		if (b.x <= 0.0) {
			continue;
		}
		float bh = 0.3 + 0.2 * float(k) + 0.45 * b.x;
		if (bh > h) {
			h = bh;
			float tone = clamp(b.z * 0.8 + float(k) * 0.12 + (b.y - 0.5) * 0.3, 0.0, 1.0);
			vec3 c = ramp3(vec3(0.13, 0.33, 0.07), vec3(0.30, 0.58, 0.12), vec3(0.62, 0.84, 0.30), tone);
			c *= mix(vec3(1.08, 1.0, 0.82), vec3(0.88, 1.0, 1.08), b.y);
			col = c;
		}
	}
	// Tiny flowers.
	vec2 p = uv * 6.0;
	vec2 cell = floor(p);
	float fh = hash21(mod(cell, vec2(6.0)) + 77.0);
	if (fh > 0.82) {
		vec2 q = fract(p) - 0.5 - (hash22(mod(cell, vec2(6.0)) + 5.0) - 0.5) * 0.4;
		float r = length(q);
		float ang = atan(q.y, q.x) + fh * 10.0;
		float petal = 0.13 * (0.55 + 0.45 * cos(5.0 * ang)) - r;
		float cov = edge(petal / 6.0);
		vec3 pc = fh > 0.92 ? vec3(1.0, 0.86, 0.32) : (fh > 0.87 ? vec3(0.95, 0.5, 0.78) : vec3(0.96, 0.96, 1.0));
		col = mix(col, pc * (0.8 + 0.25 * (1.0 - r * 6.0)), cov);
		float centre = edge((0.035 - r) / 6.0);
		col = mix(col, vec3(1.0, 0.75, 0.2), centre);
		h = mix(h, 1.0, cov);
	}
	col *= 1.0 + 0.08 * grain(uv, 2.0);
}

void stone_plates(vec2 uv, float n, out vec3 col, out float h, out float ed_uv, out float id) {
	vec2 rel;
	vec4 v = voro(uv, vec2(n), 0.75, rel);
	ed_uv = v.y / n;
	id = v.z;
	float cw = 0.010 + px() * 0.6;
	float inside = edge(ed_uv - cw);
	float bev = bevel(ed_uv - cw, 0.05);
	float ang = id * TAU;
	float tilt = dot(rel, vec2(cos(ang), sin(ang))) * 0.12;
	vec2 crel;
	vec4 c = voro(uv + 0.11 * vec2(fbm(uv, 4.0, 2), fbm(uv + 0.5, 4.0, 2)), vec2(n * 3.0), 1.0, crel);
	float crack_mask = step(0.55, fract(id * 5.31)) * smoothstep(0.45, 0.55, fbm(uv + id, 5.0, 2));
	float crack = (1.0 - edge(c.y / (n * 3.0) - px() * 0.5)) * crack_mask * inside;
	float g = grain(uv, 3.0);
	h = inside * (0.5 + 0.38 * bev + tilt + 0.06 * g) - 0.3 * crack;
	float wash = fbm(uv, 3.0, 3);
	col = ramp3(vec3(0.36, 0.38, 0.43), vec3(0.52, 0.53, 0.55), vec3(0.66, 0.64, 0.60), id * 0.6 + wash * 0.5);
	col *= 1.0 + 0.1 * g;
	col = mix(col, col * vec3(1.06, 1.02, 0.94), smoothstep(0.55, 0.75, wash));
	col = mix(vec3(0.10, 0.10, 0.13), col, inside);
	col = mix(col, vec3(0.16, 0.16, 0.19), crack);
}

void mat(int id, vec2 uv, out vec3 col, out float h, out float r, out float a) {
	uv = fract(uv);
	col = vec3(1.0, 0.0, 1.0);
	h = 0.5;
	r = 0.85;
	a = 1.0;
	if (id == 0) { // grass_top
		grass_top_mat(uv, col, h);
		r = 0.8;
	} else if (id == 1) { // grass_side
		dirt_mat(uv, col, h);
		h *= 0.8;
		float lip = 0.10 + 0.02 * sin(TAU * uv.x * 3.0 + 0.4) + 0.012 * sin(TAU * uv.x * 11.0);
		vec3 b1 = hang_blades(uv, 9.0, 0.05, 0.34, 41.0);
		vec3 b2 = hang_blades(uv + vec2(0.37, 0.0), 13.0, 0.06, 0.26, 42.0);
		vec3 b3 = hang_blades(uv + vec2(0.71, 0.0), 19.0, 0.07, 0.17, 43.0);
		vec3 b = b1;
		float layer = 0.0;
		if (b2.x * 1.04 > b.x) { b = b2; layer = 1.0; }
		if (b3.x * 1.08 > b.x) { b = b3; layer = 2.0; }
		float in_lip = edge(lip - uv.y);
		float stroke_l = vnoise(vec2(uv.x * 40.0, uv.y * 8.0), vec2(40.0, 8.0));
		float grass = max(in_lip, step(0.01, b.x));
		// soil darkens just below the hanging grass (cast shadow)
		float below = clamp(uv.y - lip, 0.0, 1.0);
		float shade = 1.0 - 0.45 * (1.0 - smoothstep(0.0, 0.16, below)) * (1.0 - grass);
		col *= shade;
		h *= mix(0.7, 1.0, smoothstep(0.0, 0.16, below));
		float tone = in_lip > 0.5 ? 0.62 - uv.y * 1.5 + 0.2 * (stroke_l - 0.5) : clamp(0.55 - b.z * 0.4 + layer * 0.1 + (b.y - 0.5) * 0.3, 0.0, 1.0);
		vec3 gc = ramp3(vec3(0.12, 0.30, 0.06), vec3(0.28, 0.56, 0.12), vec3(0.58, 0.84, 0.28), tone);
		gc *= mix(vec3(1.06, 1.0, 0.82), vec3(0.88, 1.0, 1.06), b.y);
		float stroke = vnoise(vec2(uv.x * 64.0, uv.y * 6.0), vec2(64.0, 6.0));
		gc *= (0.92 + 0.16 * stroke) * mix(1.0, 0.82, in_lip);
		float gh = in_lip > 0.5 ? 0.92 : 0.7 + 0.25 * b.x;
		col = mix(col, gc, grass);
		h = mix(h, gh, grass);
		r = 0.85;
	} else if (id == 2) { // dirt
		dirt_mat(uv, col, h);
		r = 0.95;
	} else if (id == 3) { // stone
		float ed;
		float sid;
		stone_plates(uv, 3.0, col, h, ed, sid);
		r = 0.72;
	} else if (id == 4) { // cobblestone
		vec2 rel;
		vec4 v = voro(uv, vec2(4.0), 0.85, rel);
		float ed = v.y / 4.0;
		float mw = 0.018 + px() * 0.5;
		float inside = edge(ed - mw);
		float dome = sqrt(bevel(ed - mw, 0.12));
		float g = grain(uv, 5.0);
		h = inside * (0.35 + 0.6 * dome * (0.85 + 0.15 * v.z) + 0.05 * g);
		vec3 sc = ramp3(vec3(0.38, 0.39, 0.44), vec3(0.55, 0.54, 0.53), vec3(0.68, 0.63, 0.55), v.z);
		sc = mix(sc, sc * vec3(1.1, 0.98, 0.85), step(0.8, fract(v.z * 7.0)) * 0.6);
		sc *= 0.8 + 0.3 * dome + 0.1 * g;
		vec3 s = dots(uv, 20.0, 0.3, 0.1, 9.0);
		sc = mix(sc, sc * 0.75, s.x * 0.5);
		col = mix(vec3(0.09, 0.09, 0.1), sc, inside);
		r = 0.7;
	} else if (id == 5) { // sand
		float warp = fbm(uv, 2.0, 3);
		float ph = fract(uv.y * 5.0 + uv.x * 1.0 + warp * 1.2);
		// asymmetric dune ripple: long gentle slope, short steep face
		float ripple = ph < 0.8 ? ph / 0.8 : (1.0 - ph) / 0.2;
		ripple = smoothstep(0.0, 1.0, ripple);
		float g = grain(uv, 6.0);
		h = 0.35 + 0.4 * ripple + 0.06 * g;
		col = ramp3(vec3(0.78, 0.63, 0.40), vec3(0.90, 0.78, 0.53), vec3(0.98, 0.91, 0.70), ripple * 0.8 + warp * 0.3);
		vec3 s = dots(uv, 18.0, 0.35, 0.1, 12.0);
		col = mix(col, s.z > 0.5 ? vec3(0.62, 0.48, 0.32) : vec3(1.0, 0.97, 0.85), s.x * 0.7);
		col *= 1.0 + 0.06 * g;
		r = 0.92;
	} else if (id == 6) { // log_top
		vec2 c = uv - 0.5;
		float ang = atan(c.y, c.x);
		float rr = length(c) * 2.0;
		float wob = 0.035 * (vnoise(vec2(ang / TAU * 7.0, 0.5), vec2(7.0, 1.0)) - 0.5);
		float rw = rr + wob;
		float bark_r = 0.86 + 0.04 * vnoise(vec2(ang / TAU * 11.0, 0.5), vec2(11.0, 1.0));
		if (rr > bark_r) {
			float plate = vnoise(vec2(ang / TAU * 20.0, 0.5), vec2(20.0, 1.0));
			float groove = edge(fract(ang / TAU * 20.0 + plate * 0.4) - 0.12);
			h = 0.5 + 0.35 * groove + 0.1 * plate;
			col = mix(vec3(0.17, 0.10, 0.06), vec3(0.40, 0.27, 0.15), groove * (0.6 + 0.4 * plate));
		} else {
			float band = rw * (res <= 32.0 ? 4.0 : (res <= 64.0 ? 6.0 : 11.0));
			float ring = edge(abs(fract(band) - 0.5) - 0.44);
			float inner = fract(band) * 0.6 + 0.4 * mod(floor(band), 2.0);
			h = 0.72 + 0.08 * inner - 0.2 * (1.0 - ring) - 0.25 * (1.0 - edge(bark_r - 0.035 - rr));
			col = ramp3(vec3(0.62, 0.43, 0.24), vec3(0.78, 0.59, 0.36), vec3(0.88, 0.72, 0.48), inner * 0.6 + 0.4 * (1.0 - rr));
			col = mix(vec3(0.45, 0.28, 0.15), col, ring);
			// radial cracks and pith
			float crack = (1.0 - edge(abs(fract(ang / TAU * 3.0 + 0.1) - 0.5) * rr * 2.0 - px() * 2.0)) * step(0.15, rr) * step(rr, 0.6);
			col = mix(col, vec3(0.3, 0.18, 0.09), crack);
			h -= 0.3 * crack;
			float pith = 1.0 - edge(rr - 0.05);
			col = mix(col, vec3(0.42, 0.26, 0.13), pith);
			col = mix(col, col * 0.6, 1.0 - edge(bark_r - 0.035 - rr));
			col *= 1.0 + 0.08 * grain(uv, 7.0);
		}
		r = 0.8;
	} else if (id == 7) { // log_side
		vec2 rel;
		vec2 wuv = uv + vec2(0.04 * (fbm(vec2(uv.y * 2.0, uv.x), 3.0, 2) - 0.5), 0.0);
		float bn = res <= 32.0 ? 4.0 : 8.0;
		vec4 v = voro(wuv, vec2(bn, res <= 32.0 ? 2.0 : 3.0), 1.0, rel);
		float ed = v.y / bn;
		float gw = 0.007 + px() * 0.5;
		float inside = edge(ed - gw);
		float plate = bevel(ed - gw, 0.035);
		float lines = vnoise(vec2(uv.x * 40.0, uv.y * 3.0 + v.z * 5.0), vec2(40.0, 3.0));
		float fib = edge(lines - 0.62) * 0.35;
		float g = grain(uv, 8.0);
		h = inside * (0.35 + 0.55 * plate - 0.12 * fib + 0.05 * g);
		col = ramp3(vec3(0.22, 0.13, 0.07), vec3(0.40, 0.26, 0.14), vec3(0.56, 0.40, 0.24), plate * 0.6 + v.z * 0.4);
		col = mix(col, col * 0.72, fib);
		col *= 1.0 + 0.08 * g;
		col = mix(vec3(0.10, 0.06, 0.03), col, inside);
		r = 0.92;
	} else if (id == 8) { // planks
		float b = floor(uv.y * 4.0);
		float lv = fract(uv.y * 4.0);
		float off = hash21(vec2(b, 3.0));
		float sx = fract(uv.x + off);
		float dy = min(lv, 1.0 - lv) / 4.0;
		float dx = min(sx, 1.0 - sx);
		float e = min(dy, dx);
		float gw = 0.006 + px() * 0.6;
		float inside = edge(e - gw);
		float bev = bevel(e - gw, 0.025);
		float warp = fbm(vec2(sx * 2.0, lv), 2.0, 2);
		float gl = fract(lv * 3.0 + warp * 1.6 + sin(sx * TAU * 2.0 + off * 9.0) * 0.12);
		float grain_line = 1.0 - edge(abs(gl - 0.5) - 0.06 - px() * 2.0);
		float board = hash21(vec2(b, 9.0));
		vec3 bc = ramp3(vec3(0.45, 0.27, 0.13), vec3(0.62, 0.41, 0.22), vec3(0.78, 0.57, 0.33), board * 0.6 + bev * 0.3 + warp * 0.2);
		bc = mix(bc, bc * 0.72, grain_line * 0.7);
		float g = grain(uv, 10.0);
		bc *= 1.0 + 0.07 * g;
		// nail heads near the board ends
		vec2 np = vec2(min(sx, 1.0 - sx), abs(lv - 0.5) - 0.25);
		float nail = edge(0.02 - length(vec2(np.x - 0.04, abs(lv - 0.5) * 0.25 - 0.06)));
		bc = mix(bc, vec3(0.25, 0.24, 0.26), nail);
		h = inside * (0.62 + 0.3 * bev - 0.08 * grain_line + 0.04 * g) + 0.08 * nail;
		col = mix(vec3(0.10, 0.06, 0.03), bc, inside);
		r = 0.72;
	} else if (id == 9) { // leaves
		vec3 l1 = blades(uv, 5.0, vec2(1.15, 0.38), 0.0, TAU, 21.0);
		vec3 l2 = blades(uv + 0.1, 7.0, vec2(1.05, 0.34), 0.0, TAU, 22.0);
		vec3 l3 = blades(uv + 0.27, 9.0, vec2(0.95, 0.3), 0.0, TAU, 23.0);
		vec3 best = l1;
		float layer = 0.0;
		if (l2.x * 1.05 > best.x) { best = l2; layer = 1.0; }
		if (l3.x * 1.1 > best.x) { best = l3; layer = 2.0; }
		a = best.x > 0.02 ? 1.0 : 0.0;
		h = 0.3 + 0.6 * best.x;
		float tone = clamp(0.25 + layer * 0.22 + (best.y - 0.5) * 0.4 + best.z * 0.2, 0.0, 1.0);
		col = ramp3(vec3(0.07, 0.23, 0.06), vec3(0.20, 0.45, 0.11), vec3(0.45, 0.70, 0.22), tone);
		col *= mix(vec3(1.06, 1.0, 0.8), vec3(0.85, 1.0, 1.05), best.y);
		r = 0.6;
	} else if (id == 10) { // glass
		float fw = 0.06;
		float e = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
		float frame = 1.0 - edge(e - fw);
		float fb = bevel(e, fw);
		float diag = uv.x + uv.y;
		float glint = edge(0.035 - abs(diag - 0.62)) + edge(0.015 - abs(diag - 0.74)) + edge(0.02 - abs(diag - 1.32)) * 0.6;
		glint *= 1.0 - frame;
		col = mix(vec3(0.70, 0.88, 0.95), vec3(0.95, 0.99, 1.0), clamp(glint, 0.0, 1.0));
		vec3 fc = mix(vec3(0.62, 0.80, 0.88), vec3(0.96, 1.0, 1.0), fb);
		col = mix(col, fc, frame);
		a = mix(0.12 + 0.5 * clamp(glint, 0.0, 1.0), 1.0, frame);
		h = mix(0.6, 0.75 + 0.25 * fb, frame);
		r = 0.03;
	} else if (id == 11) { // water
		vec2 rel;
		vec2 wp = uv + 0.06 * vec2(fbm(uv, 3.0, 2), fbm(uv + 0.4, 3.0, 2));
		vec4 v = voro(wp, vec2(5.0), 1.0, rel);
		float line = 1.0 - edge(v.y / 5.0 - 0.008 - px() * 0.5);
		vec2 rel2;
		vec4 v2 = voro(wp + 0.31, vec2(9.0), 1.0, rel2);
		float line2 = 1.0 - edge(v2.y / 9.0 - 0.004 - px() * 0.4);
		float depth = fbm(uv, 2.0, 3);
		h = 0.35 + 0.25 * bevel(v.y / 5.0, 0.08) + 0.25 * line + 0.1 * line2;
		col = ramp3(vec3(0.04, 0.22, 0.42), vec3(0.08, 0.40, 0.62), vec3(0.20, 0.62, 0.78), depth * 0.7 + bevel(v.y / 5.0, 0.1) * 0.3);
		col = mix(col, vec3(0.75, 0.95, 1.0), line * 0.8 + line2 * 0.35);
		a = 0.62 + 0.25 * line;
		r = 0.03;
	} else if (id == 12) { // bricks
		float row = floor(uv.y * 4.0);
		float x = uv.x + mod(row, 2.0) * 0.25;
		float cx = floor(x * 2.0);
		float lx = fract(x * 2.0);
		float ly = fract(uv.y * 4.0);
		float e = min(min(lx, 1.0 - lx) * 0.5, min(ly, 1.0 - ly) * 0.25);
		float mw = 0.012 + px() * 0.6;
		vec2 cid = vec2(mod(cx, 2.0), mod(row, 4.0));
		float bid = hash21(cid + 5.0);
		// chipped corners/edges
		vec3 chip = dots(uv, 12.0, 0.22, 0.2, 31.0);
		float chipcut = chip.x * (1.0 - edge(e - mw - 0.014));
		float inside = edge(e - mw) * (1.0 - chipcut);
		float bev = bevel(e - mw, 0.03);
		float g = grain(uv, 12.0);
		float wash = fbm(uv, 6.0, 3);
		h = inside * (0.55 + 0.35 * bev + 0.05 * g + 0.05 * wash);
		vec3 bc = ramp3(vec3(0.46, 0.17, 0.11), vec3(0.64, 0.28, 0.17), vec3(0.78, 0.42, 0.26), bid * 0.6 + wash * 0.4);
		bc = mix(bc, bc * vec3(0.8, 0.85, 0.95), step(0.85, bid) * 0.5);
		vec3 s = dots(uv, 22.0, 0.35, 0.12, 14.0);
		bc = mix(bc, bc * 1.25, s.x * 0.5);
		bc *= 1.0 + 0.08 * g;
		vec3 mortar = vec3(0.62, 0.59, 0.53) * (0.85 + 0.15 * wash);
		col = mix(mortar * 0.85, bc, inside);
		h = max(h, 0.18 + 0.05 * wash);
		r = 0.85;
	} else if (id == 13) { // snow
		float drift = fbm(uv, 2.0, 4);
		float warp = fbm(uv + 0.3, 3.0, 2);
		float wind = fract(uv.y * 3.0 + uv.x + warp * 1.4);
		float ripple = smoothstep(0.0, 0.7, wind) * (1.0 - smoothstep(0.85, 1.0, wind));
		h = 0.3 + 0.45 * drift + 0.15 * ripple + 0.04 * grain(uv, 15.0);
		col = ramp3(vec3(0.58, 0.68, 0.90), vec3(0.84, 0.90, 0.99), vec3(1.0, 1.0, 1.0), h * 1.2 - 0.15);
		vec3 sp = dots(uv, 24.0, 0.2, 0.09, 17.0);
		vec3 sp2 = dots(uv + 0.5, 40.0, 0.12, 0.08, 18.0);
		col = mix(col, vec3(1.0), max(sp.x, sp2.x * 0.8));
		col = mix(col, vec3(0.7, 0.85, 1.0), sp.x * step(0.6, sp.z) * 0.5);
		r = mix(0.65, 0.1, sp.x);
	} else if (id == 14) { // gravel
		vec2 rel;
		vec4 v = voro(uv, vec2(res <= 16.0 ? 4.0 : 8.0), 1.0, rel);
		float n = res <= 16.0 ? 4.0 : 8.0;
		float ed = v.y / n;
		float gw = 0.01 + px() * 0.5;
		float inside = edge(ed - gw);
		float dome = sqrt(bevel(ed - gw, 0.06));
		h = inside * (0.3 + 0.65 * dome * (0.7 + 0.3 * v.z));
		vec3 sc = v.z < 0.33 ? vec3(0.46, 0.45, 0.47) : (v.z < 0.66 ? vec3(0.60, 0.54, 0.47) : vec3(0.34, 0.34, 0.38));
		sc *= 0.72 + 0.42 * dome + 0.08 * grain(uv, 16.0);
		col = mix(vec3(0.08, 0.07, 0.07), sc, inside);
		r = 0.85;
	} else if (id == 15) { // crystal
		vec2 rel;
		vec4 v = voro(uv, vec2(3.0), 0.9, rel);
		float ang = v.z * TAU;
		vec2 dir = vec2(cos(ang), sin(ang));
		// two planar facets per cell split along a random line
		float side = step(0.0, dot(rel, vec2(-dir.y, dir.x)));
		float facet = clamp(0.55 + dot(rel, dir) * (side > 0.5 ? 0.7 : -0.5), 0.0, 1.0);
		float ed = v.y / 3.0;
		float rim = 1.0 - edge(ed - 0.01 - px() * 0.5);
		float split = 1.0 - edge(abs(dot(rel, vec2(-dir.y, dir.x))) / 3.0 - px() * 0.6);
		h = 0.4 + 0.55 * facet - 0.3 * rim;
		vec3 base = mix(vec3(0.25, 0.85, 1.0), vec3(0.72, 0.40, 1.0), v.z);
		col = base * (0.45 + 0.75 * facet);
		col = mix(col, vec3(0.92, 1.0, 1.0), max(rim, split * 0.7));
		vec3 sp = dots(uv, 14.0, 0.2, 0.1, 19.0);
		col = mix(col, vec3(1.0), sp.x * 0.8);
		a = mix(0.78, 1.0, max(rim, sp.x));
		r = 0.05;
	} else if (id == 16) { // mossy stone
		float ed;
		float sid;
		stone_plates(uv, 3.0, col, h, ed, sid);
		float m = fbm(uv + 0.3, 3.0, 4) + 0.22 * (1.0 - smoothstep(0.0, 0.04, ed));
		vec3 bl = blades(uv, 18.0, vec2(1.0, 0.22), 0.0, TAU, 51.0);
		float fuzz = bl.x;
		float moss = edge(m + 0.06 * (fuzz - 0.5) - 0.68);
		float mh = bevel(m - 0.68, 0.1);
		vec3 mc = ramp3(vec3(0.10, 0.22, 0.06), vec3(0.22, 0.40, 0.10), vec3(0.45, 0.64, 0.20), mh * 0.5 + fuzz * 0.6);
		col = mix(col, mc, moss);
		h = mix(h, max(h, 0.6) + 0.25 * mh + 0.06 * fuzz, moss);
		r = mix(0.75, 0.95, moss);
	} else if (id == 17) { // marble
		vec2 q = fract(uv * 2.0);
		float e = min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y)) * 0.5;
		float sw = 0.004 + px() * 0.6;
		float inside = edge(e - sw);
		float bev = bevel(e - sw, 0.02);
		float f = fbm(uv, 3.0, 5);
		float ph = (uv.x + uv.y) * 2.0 + f * 1.2;
		float vd = abs(fract(ph) - 0.5) / 4.0;
		float vein = 1.0 - edge(vd - 0.0025 - px() * 0.5);
		float halo = 1.0 - smoothstep(0.0, 0.02, vd);
		float ph2 = (uv.x * 2.0 - uv.y) * 1.0 + fbm(uv + 0.71, 3.0, 4) * 1.8;
		float vein2 = 1.0 - edge(abs(fract(ph2) - 0.5) / 3.0 - 0.0018 - px() * 0.4);
		h = inside * (0.78 + 0.18 * bev) - 0.04 * vein;
		col = ramp3(vec3(0.82, 0.80, 0.78), vec3(0.92, 0.91, 0.88), vec3(0.99, 0.98, 0.96), f);
		col = mix(col, col * vec3(0.86, 0.87, 0.9), halo * 0.5);
		col = mix(col, vec3(0.40, 0.41, 0.46), vein * 0.85);
		col = mix(col, vec3(0.80, 0.66, 0.40), vein2 * 0.7);
		col = mix(vec3(0.55, 0.53, 0.5), col, inside);
		r = mix(0.5, 0.08, inside);
	} else if (id == 18) { // terracotta
		vec2 q = fract(uv * 2.0);
		vec2 t = floor(uv * 2.0);
		float e = min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y)) * 0.5;
		float sw = 0.01 + px() * 0.6;
		float inside = edge(e - sw);
		float bev = bevel(e - sw, 0.03);
		vec2 c = q - 0.5;
		float dia = abs(c.x) + abs(c.y);
		float ring = 1.0 - edge(abs(length(c) - 0.36) * 0.5 - 0.012);
		float diamond = edge(0.2 - dia);
		float dia_line = 1.0 - edge(abs(dia - 0.28) * 0.5 - 0.01);
		float motif = clamp(max(diamond, dia_line) + ring, 0.0, 1.0);
		float f = fbm(uv, 8.0, 3);
		float tv = hash21(t + 2.0);
		h = inside * (0.6 + 0.25 * bev + 0.08 * motif + 0.04 * f);
		vec3 tc = ramp3(vec3(0.58, 0.26, 0.13), vec3(0.75, 0.38, 0.19), vec3(0.88, 0.52, 0.28), f * 0.6 + tv * 0.3 + bev * 0.2);
		vec3 glaze = mix(vec3(0.96, 0.84, 0.58), vec3(0.20, 0.50, 0.55), diamond);
		col = mix(tc, glaze, motif * 0.9);
		col = mix(vec3(0.42, 0.36, 0.30), col, inside);
		r = mix(0.6, 0.18, motif * inside);
	} else if (id == 19) { // slate
		float rows = 4.0;
		float row = floor(uv.y * rows);
		float ly = fract(uv.y * rows);
		float x = uv.x + mod(row, 2.0) * 0.25;
		float lx = fract(x * 2.0);
		float cx = floor(x * 2.0);
		float dx = min(lx, 1.0 - lx) * 0.5;
		float sw = 0.006 + px() * 0.6;
		float sid = hash21(vec2(mod(cx, 2.0), mod(row, rows)) + 17.0);
		// rounded bottom corners
		vec2 cq = vec2(max(0.0, 0.1 - min(lx, 1.0 - lx)), max(0.0, ly - 0.9)) * vec2(1.0, 2.0);
		float corner = edge(0.1 - length(cq));
		float inside = edge(dx - sw) * corner;
		float g = grain(uv, 21.0);
		h = inside * (0.2 + 0.7 * pow(ly, 0.8) + 0.04 * g);
		col = ramp3(vec3(0.15, 0.17, 0.22), vec3(0.24, 0.27, 0.33), vec3(0.36, 0.40, 0.46), sid * 0.5 + ly * 0.5);
		col *= 1.0 + 0.07 * g;
		col = mix(col, col * 1.35, edge(ly - 0.93) * inside);
		col = mix(vec3(0.05, 0.05, 0.07), col, inside);
		r = 0.45;
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
			// Bake hand-painted light from the image's top-left: slopes facing it brighten,
			// the far side darkens, crevices get a little ambient occlusion.
			float e = 1.5 / res;
			float h2 = height_of(id, uv - vec2(e, e) * 0.7071);
			float slope = clamp((h - h2) / e * 0.035, -1.0, 1.0);
			col *= 1.0 + 0.42 * slope;
			col *= mix(0.72, 1.0, smoothstep(0.0, 0.45, h));
			COLOR = vec4(clamp(col, 0.0, 1.0), a);
		} else {
			float e = 1.0 / res;
			float dhdu = (height_of(id, uv + vec2(e, 0.0)) - height_of(id, uv - vec2(e, 0.0))) / (2.0 * e);
			float dhdv = (height_of(id, uv + vec2(0.0, e)) - height_of(id, uv - vec2(0.0, e))) / (2.0 * e);
			vec3 nn = normalize(vec3(-dhdu * normal_depth, dhdv * normal_depth, 1.0));
			COLOR = vec4(nn.xy * 0.5 + 0.5, r, h);
		}
	}
}
