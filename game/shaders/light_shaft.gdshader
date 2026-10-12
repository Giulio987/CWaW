// Fixed light-shaft cards (window beams): additive like the original, faded out
// when seen edge-on or from close by, so the flat card does not show (level.gd).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float strength = 0.45;
uniform float near_fade = 4.0;   // metres: fully faded at 1 m, full at this distance

varying float dist;

void vertex() {
	dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fade = smoothstep(0.05, 0.45, facing) * smoothstep(1.0, near_fade, dist);
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * COLOR.rgb;
	ALPHA = tex.a * COLOR.a * strength * fade;
}
