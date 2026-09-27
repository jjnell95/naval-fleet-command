shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// A missile's smoke trail: the camera-facing ribbon WorldEffects lays along a round's path. UV.x
// runs across the ribbon and UV.y is metres along the flight from the launcher, fixed to the
// smoke rather than to the round, so the lumps stay where they were laid while the trail widens,
// drifts and fades. The vertex colour carries the light and the age.

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float across = UV.x * 2.0 - 1.0;
	float n = vnoise(vec2(UV.y * 0.035, across * 1.6));
	float n2 = vnoise(vec2(UV.y * 0.13, across * 3.1) + 7.0);
	float edge = 1.0 - smoothstep(0.25 + 0.3 * n, 1.0, abs(across));
	float body = 0.7 + 0.3 * n2;
	float core = 1.0 - abs(across);
	ALBEDO = COLOR.rgb * (0.86 + 0.18 * core);
	ALPHA = clamp(COLOR.a * edge * body, 0.0, 1.0);
}
