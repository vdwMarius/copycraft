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
// Cel-shaded, hand-painted style: flat tones per shape, thin warm-dark outlines,
// linear chamfers that the light pass (see fragment) turns into crisp highlight /
// shadow bands, and chipped corners on cut stone.

const vec3 OUTLINE = vec3(0.20, 0.15, 0.13);

float chamfer(float d, float w) {
	return clamp(d / w, 0.0, 1.0);
}

// Pick one of four palette entries by a random id.
vec3 pick4(vec3 a, vec3 b, vec3 c, vec3 d, float t) {
	return t < 0.25 ? a : (t < 0.5 ? b : (t < 0.75 ? c : d));
}

// Rows of cut blocks with random widths, optional stacked halves and chipped corners.
// Returns x = distance to the block outline (uv units), y = block id.
vec2 ashlar(vec2 uv, float rows, float seed) {
	float r = floor(uv.y * rows);
	float rr = mod(r, rows);
	float ly = fract(uv.y * rows);
	float n = 1.0 + floor(hash21(vec2(rr, seed)) * 2.99);
	float off = hash21(vec2(rr, seed + 1.0));
	float sx = fract(uv.x - off) * n;
	float j = floor(sx);
	float lx = fract(sx);
	float bid = hash21(vec2(rr * 7.0 + j, seed + 2.0));
	float bw = 1.0 / n;
	float bh = 1.0 / rows;
	float dy0 = ly * bh;
	float dy1 = (1.0 - ly) * bh;
	if (bid > 0.7) {
		// stacked half-height blocks
		float hh = step(0.5, ly);
		float l2 = fract(ly * 2.0);
		dy0 = l2 * bh * 0.5;
		dy1 = (1.0 - l2) * bh * 0.5;
		bid = hash21(vec2(bid * 31.0 + hh, seed + 3.0));
	}
	float dx0 = lx * bw;
	float dx1 = (1.0 - lx) * bw;
	float cx = min(dx0, dx1);
	float cy = min(dy0, dy1);
	float ci = (dx0 < dx1 ? 0.0 : 1.0) + (dy0 < dy1 ? 0.0 : 2.0);
	float c = hash21(vec2(bid * 13.0 + ci, seed + 5.0));
	float chip = c > 0.55 ? 0.025 + (c - 0.55) * 0.16 : 0.012;
	float ed = min(min(cx, cy), (cx + cy - chip) * 0.7071);
	// hand-cut wobble on the outline
	ed += (vnoise(uv * 24.0 + seed, vec2(24.0)) - 0.5) * 0.004;
	return vec2(ed, bid);
}

// Crisp painterly patch mask (two flat tones instead of a gradient).
float patch(vec2 uv, float n, float thr, float seed) {
	return edge((fbm(uv + seed, n, 3) - thr) * 0.5);
}

// Thin dark crack lines inside a fraction of the shapes.
float cracks(vec2 uv, float n, float chance, float id, float seed) {
	vec2 rel;
	vec2 w = uv + 0.06 * vec2(fbm(uv + seed, 4.0, 2), fbm(uv + seed + 0.5, 4.0, 2));
	vec4 c = voro(w, vec2(n), 1.0, rel);
	float line = 1.0 - edge(c.y / n - px() * 0.55);
	float mask = step(1.0 - chance, fract(id * 7.31 + c.z * 0.37)) * edge((fbm(uv + id, 5.0, 2) - 0.5) * 0.1);
	return line * mask;
}

// Shared cut-stone renderer. palette: 4 colours; rows of blocks.
void cut_stone(vec2 uv, float rows, float seed, vec3 p0, vec3 p1, vec3 p2, vec3 p3, out vec3 col, out float h, out float ed, out float bid) {
	vec2 a = ashlar(uv, rows, seed);
	ed = a.x;
	bid = a.y;
	float lw = res <= 32.0 ? px() * 0.45 : 0.0035 + px() * 0.6;
	float inside = edge(ed - lw);
	float ch = chamfer(ed - lw, res <= 32.0 ? 0.06 : 0.03);
	float cr = cracks(uv, 6.0, 0.35, bid, seed);
	float g = grain(uv, seed);
	h = inside * (0.5 + 0.4 * ch + 0.03 * g) - 0.18 * cr;
	vec3 base = pick4(p0, p1, p2, p3, bid);
	base *= mix(1.0, 0.93, patch(uv, 5.0, 0.58, bid * 3.0));
	base *= 1.0 + 0.05 * g;
	col = mix(OUTLINE, base, inside);
	col = mix(col, OUTLINE * 1.3, cr * 0.85);
}

// Rounded scalloped clumps (leaves, dirt clods). x = height, y = id,
// z = distance to rim (uv), w = how much the point faces the top-left light (-1..1).
vec4 clumps(vec2 uv, float n, float radius, float base_h, float seed) {
	vec2 p = uv * n;
	vec2 i = floor(p);
	vec4 best = vec4(0.0, 0.0, -1.0, 0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 c = mod(i + g, vec2(n));
			vec2 ctr = i + g + 0.2 + 0.6 * hash22(c + seed);
			vec2 q = p - ctr;
			float ang = atan(q.y, q.x);
			float hr = hash21(c + seed * 1.7);
			float rr = radius * (0.8 + 0.4 * hr) * (0.95 + 0.05 * cos(ang * 6.0 + hr * 20.0));
			float d = rr - length(q);
			if (d > -0.05) {
				float dome = sqrt(clamp(d / rr, 0.0, 1.0));
				float hh = (base_h + 0.3 * dome + 0.1 * hr) * edge(d / n);
				if (hh > best.x) {
					best = vec4(hh, hr, d / n, dot(q / rr, vec2(-0.7071, -0.7071)));
				}
			}
		}
	}
	return best;
}

// Blade tufts with a density control.
vec3 tufts(vec2 uv, float n, vec2 size, float density, float seed) {
	vec2 p = uv * n;
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec3 best = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 c = mod(i + g, vec2(n));
			if (hash21(c + seed * 3.3) > density) {
				continue;
			}
			vec2 root = g + hash22(c + seed) - f;
			// three blades fanning out of one root
			for (int k = 0; k < 3; k++) {
				float a = -1.5708 + (float(k) - 1.0) * 0.55 + (hash21(c + seed + float(k)) - 0.5) * 0.5;
				vec2 q = rot(-root, -a);
				float t = q.x / (size.x * (0.7 + 0.3 * float(k == 1)));
				if (t > 0.0 && t < 1.0) {
					float w = size.y * (1.0 - t);
					float cov = edge((w - abs(q.y)) / n);
					float hh = cov * (0.5 + 0.5 * t);
					if (hh > best.x) {
						best = vec3(hh, hash21(c + seed * 2.1), t);
					}
				}
			}
		}
	}
	return best;
}

void dirt_mat(vec2 uv, out vec3 col, out float h) {
	vec3 base = mix(vec3(0.56, 0.36, 0.21), vec3(0.51, 0.32, 0.19), patch(uv, 3.0, 0.55, 3.0));
	vec4 c1 = clumps(uv, 3.0, 0.62, 0.3, 91.0);
	vec4 c2 = clumps(uv + 0.29, 5.0, 0.55, 0.36, 92.0);
	vec4 best = c1.x >= c2.x ? c1 : c2;
	float g = grain(uv, 1.0);
	h = 0.25 + 0.6 * best.x + 0.03 * g;
	vec3 cc = mix(vec3(0.58, 0.38, 0.22), vec3(0.53, 0.34, 0.20), best.y);
	float lit = edge((best.w - 0.3) * 0.25) * step(0.0, best.z);
	float shad = edge((-0.5 - best.w) * 0.25) * step(0.0, best.z);
	cc = mix(mix(cc, cc * vec3(1.14, 1.1, 1.04), lit), cc * vec3(0.8, 0.78, 0.82), shad);
	col = mix(base * 0.88, cc, edge(best.z));
	float rimline = (1.0 - edge(best.z - 0.004 - px() * 0.5)) * edge(best.z + 0.004) * step(0.6, fract(best.y * 5.0));
	col = mix(col, vec3(0.34, 0.20, 0.12), rimline * 0.8);
	col *= 1.0 + 0.04 * g;
	vec3 pb = dots(uv, 6.0, 0.22, 0.18, 4.0);
	vec3 pc = mix(vec3(0.72, 0.64, 0.54), vec3(0.62, 0.57, 0.52), step(0.5, pb.z));
	col = mix(col, mix(vec3(0.30, 0.20, 0.14), pc, edge(pb.y - 0.25)), pb.x);
	h = mix(h, 0.6 + 0.3 * pb.y, pb.x);
	vec3 s = dots(uv, 18.0, 0.25, 0.1, 5.0);
	col = mix(col, vec3(0.42, 0.26, 0.15), s.x * 0.7);
}

void grass_top_mat(vec2 uv, out vec3 col, out float h) {
	vec3 lime = vec3(0.56, 0.80, 0.23);
	vec3 mid = vec3(0.46, 0.71, 0.19);
	col = mix(lime, mid, patch(uv, 3.0, 0.55, 7.0));
	h = 0.42 + 0.03 * fbm(uv, 4.0, 2);
	vec3 t1 = tufts(uv, 7.0, vec2(0.8, 0.13), 0.6, 61.0);
	vec3 t2 = tufts(uv + 0.31, 11.0, vec2(0.7, 0.12), 0.45, 62.0);
	if (t1.x > 0.0) {
		col = mix(col, mix(vec3(0.38, 0.64, 0.16), vec3(0.62, 0.86, 0.30), step(0.6, t1.z)), t1.x > 0.3 ? 1.0 : t1.x / 0.3);
		h = max(h, 0.45 + 0.12 * t1.x);
	}
	if (t2.x > 0.0) {
		col = mix(col, vec3(0.33, 0.58, 0.14), (t2.x > 0.3 ? 1.0 : t2.x / 0.3) * 0.85);
		h = max(h, 0.44 + 0.08 * t2.x);
	}
	// flower specks
	vec3 fl = dots(uv, 6.0, 0.28, 0.1, 71.0);
	vec3 fc = pick4(vec3(1.0, 0.55, 0.15), vec3(1.0, 0.85, 0.25), vec3(0.97, 0.97, 0.92), vec3(0.62, 0.48, 0.95), fl.z);
	col = mix(col, fc * mix(0.85, 1.05, fl.y), fl.x);
	h = mix(h, 0.6, fl.x);
	col *= 1.0 + 0.04 * grain(uv, 2.0);
}

void mat(int id, vec2 uv, out vec3 col, out float h, out float r, out float a) {
	uv = fract(uv);
	col = vec3(1.0, 0.0, 1.0);
	h = 0.5;
	r = 0.85;
	a = 1.0;
	float ed;
	float bid;
	if (id == 0) { // grass_top
		grass_top_mat(uv, col, h);
		r = 0.85;
	} else if (id == 1) { // grass_side
		dirt_mat(uv, col, h);
		h *= 0.85;
		float lip = 0.20 + 0.025 * sin(TAU * uv.x * 2.0 + 0.4) + 0.015 * sin(TAU * uv.x * 7.0);
		vec3 b1 = hang_blades(uv, 8.0, lip - 0.06, 0.20, 41.0);
		vec3 b2 = hang_blades(uv + vec2(0.37, 0.0), 12.0, lip - 0.05, 0.15, 42.0);
		vec3 b = b1.x >= b2.x ? b1 : b2;
		float in_lip = edge(lip - uv.y);
		float grass = max(in_lip, edge(b.x - 0.01));
		// silhouette distance for the dark outline under the grass
		float under = clamp(uv.y - lip, 0.0, 1.0);
		float shade = 1.0 - 0.4 * (1.0 - edge(under - 0.06)) * (1.0 - grass);
		col *= shade;
		vec3 gc = in_lip > 0.5 ? mix(vec3(0.56, 0.80, 0.23), vec3(0.45, 0.70, 0.19), edge(uv.y - (lip - 0.05))) : mix(vec3(0.42, 0.68, 0.18), vec3(0.32, 0.56, 0.14), step(0.55, b.z));
		vec3 t = tufts(uv, 9.0, vec2(0.6, 0.12), 0.5, 44.0);
		gc = mix(gc, vec3(0.38, 0.63, 0.16), (t.x > 0.3 ? 1.0 : t.x / 0.3) * in_lip * 0.8);
		vec3 fl = dots(uv, 8.0, 0.2, 0.09, 72.0);
		gc = mix(gc, pick4(vec3(1.0, 0.55, 0.15), vec3(1.0, 0.85, 0.25), vec3(0.97, 0.97, 0.92), vec3(0.62, 0.48, 0.95), fl.z), fl.x * step(uv.y, lip - 0.06));
		float gh = in_lip > 0.5 ? 0.85 : 0.65 + 0.2 * b.x;
		// outline: thin dark line just outside the grass silhouette
		float outline = (1.0 - grass) * (1.0 - edge(under - 0.01 - px() * 0.6)) * step(0.0, uv.y - lip + 0.001);
		col = mix(col, vec3(0.16, 0.28, 0.08), outline * 0.8);
		col = mix(col, gc, grass);
		h = mix(h, gh, grass);
		r = 0.88;
	} else if (id == 2) { // dirt
		dirt_mat(uv, col, h);
		r = 0.95;
	} else if (id == 3) { // stone: chunky cool grey-brown cut blocks
		cut_stone(uv, 3.0, 11.0, vec3(0.57, 0.53, 0.49), vec3(0.49, 0.46, 0.45), vec3(0.64, 0.58, 0.50), vec3(0.60, 0.47, 0.37), col, h, ed, bid);
		r = 0.78;
	} else if (id == 4) { // cobblestone: rounded irregular wall stones
		vec2 rel;
		vec4 v = voro(uv, vec2(4.0), 0.7, rel);
		ed = v.y / 4.0 + (vnoise(uv * 24.0, vec2(24.0)) - 0.5) * 0.006;
		float lw = 0.008 + px() * 0.55;
		float inside = edge(ed - lw);
		float ch = sqrt(chamfer(ed - lw, 0.07));
		float g = grain(uv, 5.0);
		h = inside * (0.45 + 0.45 * ch + 0.03 * g);
		vec3 base = pick4(vec3(0.55, 0.50, 0.46), vec3(0.47, 0.44, 0.43), vec3(0.62, 0.53, 0.43), vec3(0.52, 0.48, 0.47), v.z);
		base *= mix(1.0, 0.92, patch(uv, 6.0, 0.6, v.z * 5.0));
		col = mix(OUTLINE, base * (1.0 + 0.05 * g), inside);
		r = 0.75;
	} else if (id == 5) { // sand
		float warp = fbm(uv, 2.0, 3);
		float ph = fract(uv.y * 4.0 + uv.x + warp * 1.2);
		float ripple = ph < 0.75 ? ph / 0.75 : (1.0 - ph) / 0.25;
		h = 0.45 + 0.12 * ripple + 0.03 * grain(uv, 6.0);
		col = mix(vec3(0.93, 0.83, 0.60), vec3(0.86, 0.74, 0.52), patch(uv, 3.0, 0.58, 8.0));
		col = mix(col, vec3(0.98, 0.91, 0.72), edge(ph - 0.68) * edge(0.76 - ph));
		vec3 s = dots(uv, 16.0, 0.3, 0.1, 12.0);
		col = mix(col, s.z > 0.5 ? vec3(0.70, 0.52, 0.34) : vec3(0.99, 0.95, 0.85), s.x * 0.8);
		r = 0.92;
	} else if (id == 6) { // log_top
		vec2 c = uv - 0.5;
		float ang = atan(c.y, c.x);
		float rr = length(c) * 2.0;
		float wob = 0.03 * (vnoise(vec2(ang / TAU * 7.0, 0.5), vec2(7.0, 1.0)) - 0.5);
		float rw = rr + wob;
		float bark_r = 0.84 + 0.04 * vnoise(vec2(ang / TAU * 11.0, 0.5), vec2(11.0, 1.0));
		if (rr > bark_r) {
			float pl = fract(ang / TAU * 16.0 + vnoise(vec2(ang / TAU * 16.0, 0.5), vec2(16.0, 1.0)) * 0.4);
			float plate = edge(pl - 0.1);
			h = 0.55 + 0.3 * plate;
			col = mix(vec3(0.24, 0.10, 0.08), vec3(0.52, 0.26, 0.20), plate);
		} else {
			float rings = res <= 32.0 ? 3.0 : (res <= 64.0 ? 5.0 : 8.0);
			float band = rw * rings;
			float ring = 1.0 - edge(abs(fract(band) - 0.5) - 0.5 + 0.06 + px() * 0.5);
			float alt = mod(floor(band), 2.0);
			h = 0.75 - 0.06 * alt - 0.12 * ring;
			col = mix(vec3(0.82, 0.64, 0.43), vec3(0.75, 0.55, 0.36), alt);
			col = mix(col, vec3(0.55, 0.34, 0.20), ring);
			float rim = 1.0 - edge(bark_r - 0.03 - rr);
			col = mix(col, OUTLINE, rim);
			h -= 0.3 * rim;
			float pith = 1.0 - edge(rr - 0.05);
			col = mix(col, vec3(0.50, 0.30, 0.17), pith);
		}
		r = 0.85;
	} else if (id == 7) { // log_side: reddish-brown bark plates with dark line work
		vec2 rel;
		vec2 wuv = uv + vec2(0.04 * (fbm(vec2(uv.y * 2.0, uv.x), 3.0, 2) - 0.5), 0.0);
		float bn = res <= 32.0 ? 4.0 : 7.0;
		vec4 v = voro(wuv, vec2(bn, res <= 32.0 ? 2.0 : 3.0), 1.0, rel);
		ed = v.y / bn;
		float lw = 0.006 + px() * 0.55;
		float inside = edge(ed - lw);
		float ch = chamfer(ed - lw, 0.03);
		float stroke = vnoise(vec2(uv.x * 36.0, uv.y * 3.0 + v.z * 5.0), vec2(36.0, 3.0));
		float fib = edge((stroke - 0.66) * 0.1) * 0.6;
		h = inside * (0.45 + 0.4 * ch - 0.08 * fib);
		vec3 base = pick4(vec3(0.50, 0.25, 0.19), vec3(0.46, 0.22, 0.18), vec3(0.55, 0.29, 0.21), vec3(0.48, 0.24, 0.20), v.z);
		base = mix(base, base * 0.78, fib);
		col = mix(vec3(0.20, 0.08, 0.07), base, inside);
		r = 0.9;
	} else if (id == 8) { // planks: warm wood boards with dark seams
		float b = floor(uv.y * 4.0);
		float lv = fract(uv.y * 4.0);
		float off = hash21(vec2(b, 3.0));
		float sx = fract(uv.x + off);
		float dy = min(lv, 1.0 - lv) / 4.0;
		float dx = min(sx, 1.0 - sx);
		float e = min(dy, dx);
		float lw = 0.006 + px() * 0.6;
		float inside = edge(e - lw);
		float ch = chamfer(e - lw, 0.02);
		float warp = fbm(vec2(sx * 2.0, lv), 2.0, 2);
		float gl = fract(lv * 3.0 + warp * 1.4 + sin(sx * TAU * 2.0 + off * 9.0) * 0.1);
		float grain_line = 1.0 - edge(abs(gl - 0.5) - 0.5 + 0.035 + px() * 1.5);
		float board = hash21(vec2(b, 9.0));
		vec3 bc = pick4(vec3(0.62, 0.38, 0.22), vec3(0.56, 0.33, 0.19), vec3(0.67, 0.43, 0.25), vec3(0.59, 0.36, 0.21), board);
		bc = mix(bc, bc * 0.75, grain_line * 0.8);
		vec2 np = vec2(min(sx, 1.0 - sx) - 0.045, abs(lv - 0.5) * 0.25 - 0.06);
		float nail = edge(0.016 - length(np));
		bc = mix(bc, vec3(0.22, 0.20, 0.22), nail);
		h = inside * (0.62 + 0.3 * ch - 0.06 * grain_line) + 0.06 * nail;
		col = mix(vec3(0.20, 0.10, 0.06), bc, inside);
		r = 0.75;
	} else if (id == 9) { // leaves: rounded clumps, light top-left, dark underside
		vec4 c1 = clumps(uv, 2.0, 0.66, 0.3, 21.0);
		vec4 c2 = clumps(uv + 0.17, 3.0, 0.62, 0.38, 22.0);
		vec4 c3 = clumps(uv + 0.41, 5.0, 0.58, 0.46, 23.0);
		vec4 best = c1;
		float layer = 0.0;
		if (c2.x > best.x) { best = c2; layer = 1.0; }
		if (c3.x > best.x) { best = c3; layer = 2.0; }
		a = best.x > 0.02 ? 1.0 : 0.0;
		h = 0.2 + 0.8 * best.x;
		vec3 base = mix(vec3(0.20, 0.45, 0.18), vec3(0.26, 0.52, 0.20), layer * 0.5) * mix(1.04, 0.94, best.y);
		vec3 light = mix(base * 1.3, vec3(0.50, 0.76, 0.26), 0.45);
		vec3 dark = base * vec3(0.62, 0.68, 0.74);
		float lit = edge((best.w - 0.15) * 0.25);
		float shad = edge((-0.4 - best.w) * 0.25);
		col = mix(mix(base, light, lit), dark, shad);
		float rimline = 1.0 - edge(best.z - 0.005 - px() * 0.5);
		col = mix(col, vec3(0.06, 0.18, 0.08), rimline * 0.85);
		// small leaf strokes in the lit area
		vec3 lf = blades(uv, 14.0, vec2(0.6, 0.18), -0.8, 0.8, 24.0);
		col = mix(col, light * 1.08, edge(lf.x - 0.3) * lit * 0.7);
		r = 0.7;
	} else if (id == 10) { // glass
		float fw = 0.06;
		float e = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
		float frame = 1.0 - edge(e - fw);
		float diag = uv.x + uv.y;
		float glint = edge(0.035 - abs(diag - 0.62)) + edge(0.015 - abs(diag - 0.74)) + edge(0.02 - abs(diag - 1.32)) * 0.6;
		glint *= 1.0 - frame;
		col = mix(vec3(0.70, 0.92, 0.95), vec3(0.96, 1.0, 1.0), clamp(glint, 0.0, 1.0));
		float fo = 1.0 - edge(e - px() * 1.2) + (1.0 - edge(abs(e - fw) - px() * 0.6));
		vec3 fc = mix(vec3(0.78, 0.92, 0.95), vec3(0.30, 0.50, 0.55), clamp(fo, 0.0, 1.0));
		col = mix(col, fc, frame);
		a = mix(0.12 + 0.5 * clamp(glint, 0.0, 1.0), 1.0, frame);
		h = mix(0.6, 0.85, frame);
		r = 0.03;
	} else if (id == 11) { // water: turquoise with white foam squiggles
		float w1 = fbm(uv, 2.0, 3);
		float w2 = fbm(uv + 0.5, 3.0, 2);
		float ph = uv.y * 5.0 + 0.18 * sin(TAU * (uv.x * 3.0 + w1)) + w2 * 0.9;
		float d1 = abs(fract(ph) - 0.5) / 5.0;
		float dash = edge((fbm(uv + 0.6, 4.0, 2) - 0.5) * 0.5);
		float foam = (1.0 - edge(d1 - 0.006 - px() * 0.5)) * dash;
		float ph2 = uv.y * 9.0 + 0.25 * sin(TAU * (uv.x * 5.0 + w2)) + w1 * 1.3 + 0.3;
		float d2 = abs(fract(ph2) - 0.5) / 9.0;
		float dash2 = edge((fbm(uv + 0.2, 6.0, 2) - 0.6) * 0.5);
		float foam2 = (1.0 - edge(d2 - 0.0035 - px() * 0.4)) * dash2;
		float deep = patch(uv, 2.0, 0.55, 3.0);
		float shallow = patch(uv + 0.3, 3.0, 0.62, 9.0);
		h = 0.4 + 0.1 * w1 + 0.35 * foam + 0.2 * foam2;
		col = mix(vec3(0.16, 0.78, 0.88), vec3(0.07, 0.58, 0.82), deep);
		col = mix(col, vec3(0.42, 0.90, 0.93), shallow * (1.0 - deep) * 0.8);
		col = mix(col, vec3(0.94, 0.99, 1.0), max(foam, foam2 * 0.85));
		a = 0.66 + 0.3 * max(foam, foam2);
		r = 0.03;
	} else if (id == 12) { // bricks: warm sandstone cut blocks
		cut_stone(uv, 4.0, 31.0, vec3(0.80, 0.70, 0.55), vec3(0.74, 0.63, 0.49), vec3(0.85, 0.76, 0.60), vec3(0.76, 0.54, 0.36), col, h, ed, bid);
		r = 0.85;
	} else if (id == 13) { // snow
		float drift = fbm(uv, 2.0, 4);
		float warp = fbm(uv + 0.3, 3.0, 2);
		float wind = fract(uv.y * 3.0 + uv.x + warp * 1.4);
		float ripple = smoothstep(0.0, 0.7, wind) * (1.0 - smoothstep(0.85, 1.0, wind));
		h = 0.4 + 0.2 * drift;
		col = mix(vec3(0.97, 0.98, 1.0), vec3(0.80, 0.87, 0.97), patch(uv, 3.0, 0.6, 15.0));
		vec3 sp = dots(uv, 20.0, 0.18, 0.09, 17.0);
		col = mix(col, vec3(0.70, 0.85, 1.0), sp.x * 0.6);
		r = mix(0.65, 0.15, sp.x);
	} else if (id == 14) { // gravel
		float n = res <= 16.0 ? 4.0 : 8.0;
		vec2 rel;
		vec4 v = voro(uv, vec2(n), 1.0, rel);
		ed = v.y / n;
		float lw = 0.006 + px() * 0.5;
		float inside = edge(ed - lw);
		float dome = sqrt(chamfer(ed - lw, 0.04));
		h = inside * (0.35 + 0.55 * dome);
		vec3 sc = pick4(vec3(0.58, 0.54, 0.50), vec3(0.66, 0.58, 0.47), vec3(0.48, 0.46, 0.46), vec3(0.62, 0.52, 0.42), v.z);
		col = mix(OUTLINE, sc, inside);
		r = 0.85;
	} else if (id == 15) { // crystal
		vec2 rel;
		vec4 v = voro(uv, vec2(3.0), 0.9, rel);
		float ang = v.z * TAU;
		vec2 dir = vec2(cos(ang), sin(ang));
		float side = step(0.0, dot(rel, vec2(-dir.y, dir.x)));
		float facet = clamp(0.55 + dot(rel, dir) * (side > 0.5 ? 0.7 : -0.5), 0.0, 1.0);
		ed = v.y / 3.0;
		float rim = 1.0 - edge(ed - 0.008 - px() * 0.5);
		float split = 1.0 - edge(abs(dot(rel, vec2(-dir.y, dir.x))) / 3.0 - px() * 0.6);
		h = 0.4 + 0.55 * facet - 0.3 * rim;
		vec3 base = mix(vec3(0.25, 0.85, 1.0), vec3(0.70, 0.45, 1.0), v.z);
		col = base * mix(0.7, 1.15, step(0.5, facet));
		col = mix(col, vec3(0.95, 1.0, 1.0), max(rim, split * 0.7));
		vec3 sp = dots(uv, 14.0, 0.2, 0.1, 19.0);
		col = mix(col, vec3(1.0), sp.x * 0.8);
		a = mix(0.78, 1.0, max(rim, sp.x));
		r = 0.05;
	} else if (id == 16) { // mossy stone: cut stone with moss spilling from the top edge
		cut_stone(uv, 3.0, 11.0, vec3(0.57, 0.53, 0.49), vec3(0.49, 0.46, 0.45), vec3(0.64, 0.58, 0.50), vec3(0.60, 0.47, 0.37), col, h, ed, bid);
		// lobed moss edge: overlapping round drips hanging from the top
		float lobes = 0.0;
		for (int k = 0; k < 7; k++) {
			float cx = (float(k) + hash21(vec2(float(k), 81.0))) / 7.0;
			float len = 0.08 + 0.22 * hash21(vec2(float(k), 82.0));
			float wd = 0.07 + 0.05 * hash21(vec2(float(k), 83.0));
			float dx = abs(fract(uv.x - cx + 0.5) - 0.5);
			lobes = max(lobes, len * sqrt(max(0.0, 1.0 - (dx * dx) / (wd * wd))));
		}
		float drip = 0.1 + lobes;
		float band = edge(drip - uv.y);
		// a few moss pads on block tops elsewhere
		float pad = edge((fbm(uv + 0.3, 3.0, 4) - 0.68) * 0.5) * step(0.5, fract(bid * 3.7));
		float m = max(band, pad);
		vec3 mc = mix(vec3(0.54, 0.78, 0.22), vec3(0.44, 0.69, 0.18), patch(uv, 5.0, 0.55, 2.0));
		float under = edge(uv.y - drip + 0.022) * band;
		mc = mix(mc, vec3(0.30, 0.52, 0.13), under);
		vec3 t = tufts(uv, 10.0, vec2(0.5, 0.1), 0.35, 52.0);
		mc = mix(mc, vec3(0.38, 0.62, 0.16), step(0.3, t.x) * (1.0 - under));
		float ol = (1.0 - edge(uv.y - drip - px() * 1.5)) * (1.0 - band);
		col = mix(col, vec3(0.16, 0.28, 0.08), ol * 0.9);
		col = mix(col, mc, m);
		h = mix(h, 0.86 + 0.06 * t.x, m);
		r = mix(0.78, 0.92, m);
	} else if (id == 17) { // marble
		vec2 q = fract(uv * 2.0);
		float e = min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y)) * 0.5;
		float lw = 0.004 + px() * 0.6;
		float inside = edge(e - lw);
		float ch = chamfer(e - lw, 0.02);
		float f = fbm(uv, 3.0, 5);
		float ph = (uv.x + uv.y) * 2.0 + f * 1.2;
		float vd = abs(fract(ph) - 0.5) / 4.0;
		float vein = 1.0 - edge(vd - 0.0025 - px() * 0.5);
		float ph2 = (uv.x * 2.0 - uv.y) + fbm(uv + 0.71, 3.0, 4) * 1.8;
		float vein2 = 1.0 - edge(abs(fract(ph2) - 0.5) / 3.0 - 0.0018 - px() * 0.4);
		h = inside * (0.75 + 0.2 * ch) - 0.04 * vein;
		col = mix(vec3(0.95, 0.93, 0.88), vec3(0.89, 0.87, 0.83), patch(uv, 3.0, 0.55, 1.0));
		col = mix(col, vec3(0.55, 0.54, 0.58), vein * 0.85);
		col = mix(col, vec3(0.84, 0.66, 0.38), vein2 * 0.8);
		col = mix(vec3(0.45, 0.40, 0.36), col, inside);
		r = mix(0.5, 0.1, inside);
	} else if (id == 18) { // terracotta
		vec2 q = fract(uv * 2.0);
		vec2 t = floor(uv * 2.0);
		float e = min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y)) * 0.5;
		float lw = 0.008 + px() * 0.6;
		float inside = edge(e - lw);
		float ch = chamfer(e - lw, 0.025);
		vec2 c = q - 0.5;
		float dia = abs(c.x) + abs(c.y);
		float ring = 1.0 - edge(abs(length(c) - 0.36) * 0.5 - 0.012);
		float diamond = edge(0.2 - dia);
		float dia_line = 1.0 - edge(abs(dia - 0.28) * 0.5 - 0.01);
		float motif = clamp(max(diamond, dia_line) + ring, 0.0, 1.0);
		float tv = hash21(t + 2.0);
		h = inside * (0.6 + 0.25 * ch + 0.08 * motif);
		vec3 tc = mix(vec3(0.80, 0.45, 0.24), vec3(0.74, 0.40, 0.21), step(0.5, tv));
		vec3 glaze = mix(vec3(0.97, 0.86, 0.60), vec3(0.16, 0.58, 0.62), diamond);
		col = mix(tc, glaze, motif * 0.95);
		col = mix(OUTLINE, col, inside);
		r = mix(0.6, 0.18, motif * inside);
	} else if (id == 19) { // slate roof tiles
		float rows = 4.0;
		float row = floor(uv.y * rows);
		float ly = fract(uv.y * rows);
		float x = uv.x + mod(row, 2.0) * 0.25;
		float lx = fract(x * 2.0);
		float cx = floor(x * 2.0);
		float dx = min(lx, 1.0 - lx) * 0.5;
		float lw = 0.006 + px() * 0.6;
		float sid = hash21(vec2(mod(cx, 2.0), mod(row, rows)) + 17.0);
		vec2 cq = vec2(max(0.0, 0.1 - min(lx, 1.0 - lx)), max(0.0, ly - 0.9)) * vec2(1.0, 2.0);
		float corner = edge(0.1 - length(cq));
		float inside = edge(dx - lw) * corner * edge((1.0 - ly) / rows - lw * 0.5);
		h = inside * (0.25 + 0.65 * ly);
		col = pick4(vec3(0.32, 0.36, 0.44), vec3(0.28, 0.31, 0.39), vec3(0.36, 0.40, 0.47), vec3(0.30, 0.33, 0.42), sid);
		col = mix(col, col * 1.25, edge(ly - 0.88) * inside);
		col = mix(vec3(0.10, 0.10, 0.14), col, inside);
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
			// Cel-shaded light from the image's top-left: surfaces facing it get a crisp
			// highlight band, surfaces facing away a cool shadow band, flats stay mid-tone.
			float e = 1.5 / res;
			float h2 = height_of(id, uv - vec2(e, e) * 0.7071);
			float gain = (id == 9 || id == 2 || id == 1) ? 0.6 : 1.0;
			float slope = (h - h2) / e * 0.035 * gain;
			float cel = (id == 11 || id == 13 || id == 5) ? 0.45 : 1.0;
			float hi = smoothstep(0.10, 0.16, slope) * cel;
			float lo = (1.0 - smoothstep(-0.16, -0.10, slope)) * cel;
			col = mix(col, col * vec3(1.20, 1.17, 1.08) + vec3(0.03, 0.03, 0.02), hi);
			col = mix(col, col * vec3(0.68, 0.70, 0.80), lo);
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
