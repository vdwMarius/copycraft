shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform sampler2DArray color_layers : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2DArray height_layers : filter_nearest_mipmap, repeat_enable;
uniform float grid_size = 4.0;
uniform float texture_size = 64.0;
uniform bool relief_enabled = true;
uniform bool is_relief_geometry = false;
varying float geometry_strength;
varying vec3 world_position;
varying vec3 world_normal;
varying float material_index;

void vertex() {
	geometry_strength = 1.0;
	if (is_relief_geometry) {
		geometry_strength = smoothstep(0.0, 1.0, INSTANCE_CUSTOM.r);
		int code = int(round(UV.y));
		vec3 axis = code < 3 ? vec3(1,0,0) : (code < 5 ? vec3(0,1,0) : vec3(0,0,1));
		float axis_sign = (code == 1 || code == 3 || code == 5) ? 1.0 : -1.0;
		VERTEX -= axis * axis_sign * UV.x * (1.0 - geometry_strength);
	}
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	material_index = round(COLOR.r * 255.0);
}

void fragment() {
	if (is_relief_geometry && geometry_strength < 0.001) { discard; }
	vec3 n = abs(world_normal);
	vec2 uv = n.y > 0.5 ? world_position.xz : (n.x > 0.5 ? world_position.zy : world_position.xy);
	float layer = clamp(round(material_index), 0.0, 5.0);
	if (layer < 0.5 && n.y < 0.5) { layer = 1.0; }
	vec3 color = texture(color_layers, vec3(uv, layer)).rgb;
	vec2 face = uv * grid_size;
	vec2 edge = min(fract(face), 1.0 - fract(face));
	vec2 aa = max(fwidth(face), vec2(0.001));
	vec2 lines = 1.0 - smoothstep(vec2(0.015), vec2(0.015) + aa, edge);
	float near_detail = 1.0 - smoothstep(10.0, 28.0, distance(CAMERA_POSITION_WORLD, world_position));
	float seams = abs(layer - 2.0) < 0.5 ? lines.x : max(lines.x, lines.y);
	ALBEDO = color * (1.0 - 0.075 * seams * near_detail);
	if (relief_enabled) {
		float step_uv = 1.0 / texture_size;
		float h0 = texture(height_layers, vec3(uv, layer)).r;
		float hx = texture(height_layers, vec3(uv + vec2(step_uv, 0.0), layer)).r - h0;
		float hy = texture(height_layers, vec3(uv + vec2(0.0, step_uv), layer)).r - h0;
		vec3 u = n.y > 0.5 ? vec3(1,0,0) : (n.x > 0.5 ? vec3(0,0,1) : vec3(1,0,0));
		vec3 v = n.y > 0.5 ? vec3(0,0,1) : vec3(0,1,0);
		vec3 slope = (u * hx + v * hy) * 0.8 * near_detail;
		NORMAL = normalize(NORMAL - mat3(VIEW_MATRIX) * slope);
	}
	ROUGHNESS = 0.96;
}
