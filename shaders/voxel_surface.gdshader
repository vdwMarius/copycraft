shader_type spatial;
render_mode diffuse_burley, specular_disabled;

// Quarter-block surface detail without subdividing the simulation or collision grid.
varying vec3 world_position;
varying vec3 world_normal;
varying vec3 voxel_color;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	voxel_color = COLOR.rgb;
}

float cell_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.11369, 0.13787));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec3 grid = (world_position - world_normal * 0.001) * 4.0;
	vec2 face = n.y > 0.5 ? grid.xz : (n.x > 0.5 ? grid.zy : grid.xy);
	vec2 edge_distance = min(fract(face), 1.0 - fract(face));
	vec2 aa = max(fwidth(face), vec2(0.001));
	vec2 lines = 1.0 - smoothstep(vec2(0.018), vec2(0.018) + aa, edge_distance);
	float near_detail = 1.0 - smoothstep(14.0, 32.0, distance(CAMERA_POSITION_WORLD, world_position));
	float tint = mix(0.94, 1.05, cell_hash(floor(grid)));
	float seams = 1.0 - 0.08 * max(lines.x, lines.y);
	vec3 base = voxel_color;
	if (!OUTPUT_IS_SRGB) {
		base = pow(base, vec3(2.2));
	}
	ALBEDO = base * mix(1.0, tint * seams, near_detail);
	ROUGHNESS = 0.96;
}
