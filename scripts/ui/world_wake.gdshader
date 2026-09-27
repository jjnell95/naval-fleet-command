shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// Foam for the strips WorldScene lays behind a hull: a churned lane of aerated water down the
// middle, pale turquoise under white foam, and the two arms of the wake along the edges. UV.x
// runs across the strip, UV.y is metres astern, and the vertex colour carries the fade and the
// daylight.

uniform vec3 aerated : source_color = vec3(0.30, 0.55, 0.64);

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
	float arm = smoothstep(0.66, 0.9, across) * (1.0 - smoothstep(0.92, 1.0, across));
	float lane = 1.0 - smoothstep(0.0, 0.55, across);
	float n = vnoise(vec2(UV.x * 7.0, UV.y * 0.06) + vec2(0.0, TIME * 0.15));
	float n2 = vnoise(vec2(UV.x * 19.0, UV.y * 0.2) - vec2(TIME * 0.05, 0.0));
	float n3 = vnoise(vec2(UV.x * 41.0, UV.y * 0.55) + vec2(TIME * 0.11, 3.0));
	float churn = 1.0 + 1.6 * exp(-UV.y / 160.0);
	float foam = arm * (0.4 + 0.6 * n) * (0.6 + 0.4 * n3) + lane * (0.2 + 0.8 * n * n2) * 0.85 * churn;
	float glow = lane * (0.55 + 0.45 * n2) * exp(-UV.y / 420.0);
	vec3 white = COLOR.rgb;
	vec3 under = aerated * COLOR.rgb;
	float f = clamp(foam, 0.0, 1.0);
	ALBEDO = mix(under, white, clamp(f * 1.4, 0.0, 1.0));
	ALPHA = clamp(max(f, glow * 0.55) * COLOR.a, 0.0, 1.0);
}
