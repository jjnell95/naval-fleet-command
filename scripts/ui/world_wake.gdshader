shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// Foam for the strips WorldScene lays behind a hull: a churned lane of aerated water down the
// middle, pale turquoise under white foam, and the two arms of the wake along the edges. UV.x
// runs across the strip, UV.y is metres astern, and the vertex colour carries the fade and the
// daylight. The strip is laid flat and every vertex is lifted onto the swell here, so it rides the
// same water as the ocean mesh; a strip lifted only at its samples used to dip under every crest
// between them, and a carrier's wake, sampled about one swell apart, came out in patches.

#include "res://scripts/ui/world_swell.gdshaderinc"

uniform vec3 aerated : source_color = vec3(0.30, 0.55, 0.64);
uniform float float_m = 0.35;  // how far above the water the foam lies, against z-fighting

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += world_sea_height(w, CAMERA_POSITION_WORLD) + float_m - w.y;
}

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
	// The churned lane narrows relative to the opening arms as the wake spreads astern.
	float lane_w = mix(0.8, 0.28, clamp(UV.y / 600.0, 0.0, 1.0));
	float arm = smoothstep(0.7, 0.9, across) * (1.0 - smoothstep(0.93, 1.0, across));
	float lane = 1.0 - smoothstep(lane_w * 0.4, lane_w, across);
	float n = vnoise(vec2(UV.x * 7.0, UV.y * 0.05) + vec2(0.0, TIME * 0.15));
	float n2 = vnoise(vec2(UV.x * 19.0, UV.y * 0.18) - vec2(TIME * 0.05, 0.0));
	float n3 = vnoise(vec2(UV.x * 41.0, UV.y * 0.55) + vec2(TIME * 0.11, 3.0));
	float churn = 1.0 + 1.4 * exp(-UV.y / 140.0);
	float foam = arm * (0.35 + 0.65 * n) * (0.6 + 0.4 * n3) * 0.8 + lane * (0.35 + 0.65 * n * n2) * churn * 0.8;
	float glow = lane * (0.6 + 0.4 * n2) * exp(-UV.y / 520.0);
	vec3 white = COLOR.rgb;
	vec3 under = aerated * COLOR.rgb;
	float f = clamp(foam, 0.0, 1.0);
	ALBEDO = mix(under, white, clamp(f * 1.3, 0.0, 1.0));
	ALPHA = clamp(max(f, glow * 0.6) * COLOR.a, 0.0, 1.0);
}
