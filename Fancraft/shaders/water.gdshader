shader_type spatial;
// Cheap stylised water plane: painted water texture scrolled in two directions,
// fresnel sky reflection and a toon sun glint. Unshaded (lighting done here).
render_mode blend_mix, cull_disabled, depth_draw_opaque, unshaded, shadows_disabled;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surface_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float layer_water = 11.0;
uniform vec3 sun_dir = vec3(0.45, 0.75, 0.35);
uniform vec3 sky_reflect : source_color = vec3(0.62, 0.86, 0.98);
uniform vec3 deep_tint : source_color = vec3(0.05, 0.42, 0.62);

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv1 = w_pos.xz * 0.18 + vec2(TIME * 0.02, TIME * 0.013);
	vec2 uv2 = w_pos.zx * 0.11 - vec2(TIME * 0.015, TIME * 0.022);
	vec4 a = texture(albedo_tex, vec3(uv1, layer_water));
	vec4 b = texture(albedo_tex, vec3(uv2, layer_water));
	vec2 n1 = texture(surface_tex, vec3(uv1, layer_water)).rg * 2.0 - 1.0;
	vec2 n2 = texture(surface_tex, vec3(uv2, layer_water)).rg * 2.0 - 1.0;
	vec3 n = normalize(vec3((n1.x + n2.x) * 0.25, 1.0, (n1.y + n2.y) * 0.25));
	vec3 V = normalize(CAMERA_POSITION_WORLD - w_pos);
	float vn = max(dot(V, n), 0.0);
	float fres = pow(1.0 - vn, 3.0);
	vec3 col = mix(deep_tint, (a.rgb + b.rgb) * 0.5, 0.65);
	col = mix(col, sky_reflect, fres * 0.6);
	vec3 R = reflect(-normalize(sun_dir), n);
	float spec = smoothstep(0.82, 0.9, pow(max(dot(R, V), 0.0), 40.0));
	col += vec3(1.0, 0.95, 0.85) * spec;
	ALBEDO = col;
	ALPHA = clamp(0.72 + fres * 0.25 + spec, 0.0, 1.0);
}
