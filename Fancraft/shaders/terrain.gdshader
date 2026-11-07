shader_type spatial;
// Stylised smooth-terrain shader (Transvoxel meshes from Voxel Tools).
// - Transvoxel LOD seam smoothing (CUSTOM0) and per-vertex texture indices (CUSTOM1).
// - Triplanar mapping of the shared texture arrays (built-in painted set or user packs).
// - Topsoil turns into grass / sand / snow by height, dirt or rock on slopes.
// - Same cel-shaded light model as the building pieces.
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surface_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform int u_transition_mask;          // set by the voxel engine
uniform float tex_scale = 0.45;          // texture tiles per metre
uniform float water_level = 30.0;
uniform float snow_level = 68.0;
uniform vec3 sun_dir = vec3(0.45, 0.75, 0.35);
uniform float layer_grass_top = 0.0;
uniform float layer_grass_side = 1.0;
uniform float layer_dirt = 2.0;
uniform float layer_stone = 3.0;
uniform float layer_sand = 5.0;
uniform float layer_snow = 13.0;
uniform float layer_mossy_stone = 16.0;
uniform float layer_gravel = 14.0;
uniform float layer_water = 11.0;

varying vec3 w_pos;
varying vec3 w_nrm;
varying vec4 v_idx;
varying vec4 v_wt;

// --- Transvoxel seams (from the Voxel Tools documentation) ---
float get_transvoxel_secondary_factor(int idata) {
	int transition_mask = u_transition_mask & 0xff;
	int cell_border_mask = (idata >> 0) & 63;
	int vertex_border_mask = (idata >> 8) & 63;
	int m = transition_mask & cell_border_mask;
	float t = float(m != 0);
	t *= float((vertex_border_mask & ~transition_mask) == 0);
	return t;
}

vec3 get_transvoxel_position(vec3 vertex_pos, vec4 fdata) {
	int idata = floatBitsToInt(fdata.a);
	float secondary_factor = get_transvoxel_secondary_factor(idata);
	vec3 pos = mix(vertex_pos, fdata.xyz, secondary_factor);
	int itransition = (idata >> 16) & 0xff;
	float transition_cull = float(itransition == 0 || (itransition & u_transition_mask) != 0);
	return pos * transition_cull;
}

vec4 decode_8bit_vec4(float v) {
	uint i = floatBitsToUint(v);
	return vec4(float(i & 0xffu), float((i >> 8u) & 0xffu), float((i >> 16u) & 0xffu), float((i >> 24u) & 0xffu));
}

void vertex() {
	VERTEX = get_transvoxel_position(VERTEX, CUSTOM0);
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_idx = decode_8bit_vec4(CUSTOM1.x);
	v_wt = decode_8bit_vec4(CUSTOM1.y) / 255.0;
}

// Voxel material index -> (top layer, side layer) for this pixel.
vec2 layers_for(float idx, vec3 n) {
	if (idx < 0.5) {
		// Topsoil: grass, beaches near the water, snow up high; dirt / rock on slopes.
		float top = layer_grass_top;
		if (w_pos.y < water_level + 1.8) top = layer_sand;
		else if (w_pos.y > snow_level) top = layer_snow;
		float side = n.y < 0.42 ? layer_stone : (w_pos.y < water_level + 1.8 ? layer_sand : layer_dirt);
		return vec2(top, side);
	}
	if (idx < 1.5) {
		return vec2(layer_dirt, layer_dirt);
	}
	return vec2(layer_stone, layer_stone);
}

struct Sample {
	vec3 albedo;
	vec3 nrm;
	float height;
	float rough;
};

void sample_material(float idx, vec3 n, vec3 bl, vec3 p, inout Sample s, float w) {
	vec2 L = layers_for(idx, n);
	if (bl.y > 0.02) {
		float layer = n.y > 0.0 ? L.x : L.y;
		vec2 uv = p.xz;
		vec4 a = texture(albedo_tex, vec3(uv, layer));
		vec4 t = texture(surface_tex, vec3(uv, layer));
		vec2 ns = t.rg * 2.0 - 1.0;
		s.albedo += a.rgb * bl.y * w;
		s.nrm += vec3(ns.x, 0.0, -ns.y) * bl.y * w;
		s.height += t.a * bl.y * w;
		s.rough += t.b * bl.y * w;
	}
	if (bl.x > 0.02) {
		vec2 uv = vec2(p.z, -p.y);
		vec4 a = texture(albedo_tex, vec3(uv, L.y));
		vec4 t = texture(surface_tex, vec3(uv, L.y));
		vec2 ns = t.rg * 2.0 - 1.0;
		s.albedo += a.rgb * bl.x * w;
		s.nrm += vec3(0.0, ns.y, ns.x) * bl.x * w;
		s.height += t.a * bl.x * w;
		s.rough += t.b * bl.x * w;
	}
	if (bl.z > 0.02) {
		vec2 uv = vec2(p.x, -p.y);
		vec4 a = texture(albedo_tex, vec3(uv, L.y));
		vec4 t = texture(surface_tex, vec3(uv, L.y));
		vec2 ns = t.rg * 2.0 - 1.0;
		s.albedo += a.rgb * bl.z * w;
		s.nrm += vec3(ns.x, ns.y, 0.0) * bl.z * w;
		s.height += t.a * bl.z * w;
		s.rough += t.b * bl.z * w;
	}
}

void fragment() {
	vec3 n = normalize(w_nrm);
	vec3 bl = pow(abs(n), vec3(6.0));
	bl /= (bl.x + bl.y + bl.z);
	vec3 p = w_pos * tex_scale;
	vec4 wt = v_wt / max(v_wt.x + v_wt.y + v_wt.z + v_wt.w, 0.0001);
	Sample s = Sample(vec3(0.0), vec3(0.0), 0.0, 0.0);
	if (wt.x > 0.03) sample_material(v_idx.x, n, bl, p, s, wt.x);
	if (wt.y > 0.03) sample_material(v_idx.y, n, bl, p, s, wt.y);
	if (wt.z > 0.03) sample_material(v_idx.z, n, bl, p, s, wt.z);
	if (wt.w > 0.03) sample_material(v_idx.w, n, bl, p, s, wt.w);
	float cavity = mix(0.55, 1.0, s.height);
	vec3 wn = normalize(n + s.nrm * 0.9);
	ALBEDO = s.albedo * cavity;
	ROUGHNESS = clamp(s.rough, 0.05, 1.0);
	SPECULAR = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}

// Cel-shaded light, shared look with the building pieces.
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
}
