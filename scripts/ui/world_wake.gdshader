shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// Foam for the strips WorldScene lays behind a hull: a turbulent lane down the middle and the
// two arms of the wake along the edges. UV.x runs across the strip, UV.y is metres astern, and
// the vertex colour carries the fade and the daylight.

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
	float across = abs(UV.x * 2.0 - 1.0);
	float arm = smoothstep(0.62, 0.88, across) * (1.0 - smoothstep(0.9, 1.0, across));
	float core = 1.0 - smoothstep(0.0, 0.5, across);
	float n = vnoise(vec2(UV.x * 7.0, UV.y * 0.06) + vec2(0.0, TIME * 0.15));
	float n2 = vnoise(vec2(UV.x * 19.0, UV.y * 0.2) - vec2(TIME * 0.05, 0.0));
	float churn = 1.0 + 1.6 * exp(-UV.y / 180.0);
	float foam = arm * (0.45 + 0.55 * n) + core * (0.25 + 0.75 * n * n2) * 0.9 * churn;
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(foam * COLOR.a, 0.0, 1.0);
}
