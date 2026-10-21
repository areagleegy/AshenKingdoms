shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Texture-free ground surface intended for the GL Compatibility renderer on Android.
// All pattern coordinates are in world space so the pattern does not slide when the
// 80x80 ground plane is moved or resized. This shader adds no texture-memory cost.
uniform vec4 stone_color : source_color = vec4(0.12, 0.145, 0.16, 1.0);
uniform vec4 seam_color : source_color = vec4(0.052, 0.060, 0.066, 1.0);
uniform float tile_scale : hint_range(0.15, 2.5, 0.05) = 0.72;
uniform float seam_width : hint_range(0.01, 0.12, 0.005) = 0.035;
uniform float variation_strength : hint_range(0.0, 0.25, 0.01) = 0.12;

varying vec3 world_position;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 pattern = world_position.xz * max(tile_scale, 0.01);
	// Half-tile row shift avoids a uniform square-grid look without textures.
	pattern.x += mod(floor(pattern.y), 2.0) * 0.5;
	vec2 tile_id = floor(pattern);
	vec2 local = fract(pattern);

	float edge_distance = min(
		min(local.x, 1.0 - local.x),
		min(local.y, 1.0 - local.y)
	);
	float stone_mask = smoothstep(seam_width, seam_width + 0.025, edge_distance);
	// One hash per tile gives each stone a slightly different tint without sampling
	// textures or layering a multi-octave noise function per fragment.
	float tile_variation = (hash21(tile_id) - 0.5) * variation_strength;
	vec3 stone = stone_color.rgb * (1.0 + tile_variation);

	ALBEDO = mix(seam_color.rgb, stone, stone_mask);
	ROUGHNESS = 0.98;
	METALLIC = 0.0;
	AO = 0.96;
}
