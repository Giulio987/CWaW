// Fixed soft-edged additive cards (window and wall-lamp shafts, smoke plumes): additive
// like the original, faded out when seen edge-on or from close by, so the flat card
// does not show; flat shafts get two crossed copies (level.gd _cross_shaft).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float strength = 0.45;
uniform float near_fade = 4.0;   // metres: fully faded at 1 m, full at this distance
uniform float facing_lo = 0.05;   // facing the camera (|cos|): invisible below, full above facing_hi
uniform float facing_hi = 0.45;
uniform vec2 uv_offset = vec2(0.0);   // texture cel animation (level.gd _animate_cels)

varying float dist;

void vertex() {
	dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	// the card's own plane: the models' normals do not always follow it (lamp beams)
	vec3 face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float facing = abs(dot(face, normalize(VIEW)));
	float fade = smoothstep(facing_lo, facing_hi, facing) * smoothstep(1.0, near_fade, dist);
	vec4 tex = texture(albedo_tex, UV + uv_offset);
	ALBEDO = tex.rgb * COLOR.rgb;
	ALPHA = tex.a * COLOR.a * strength * fade;
}
