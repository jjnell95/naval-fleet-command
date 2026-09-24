shader_type canvas_item;
// The sea floor under the tactical plot. TEXTURE is the regional chart raster: half-float depth in
// metres, 0 = land; UV runs outside [0, 1] where the view extends past the raster. Everything is
// drawn per pixel so contours stay one pixel wide at every zoom.
//
// Only Natural Earth's own contours are drawn as lines. Depth between them is interpolation and
// is shown as tint and relief, never as a line that would claim a surveyed isobath.

uniform vec2 texel = vec2(0.00033, 0.00057); // one raster cell in UV
uniform sampler2D relief_tex : filter_linear, hint_default_black; // baked hill-shade, 0.5 = flat
uniform float texel_px = 1.0;                // screen pixels per raster cell, for relief fade-out
uniform vec4 coast_uv = vec4(0.0, 0.0, 1.0, 1.0); // where coastline polygons supply the land
uniform vec4 chart_uv = vec4(0.0, 0.0, 1.0, 1.0); // charted region, undimmed: x0, y0, x1, y1
uniform float relief = 1.0;                  // 0 turns hill shading off
uniform vec4 ocean_outside : source_color = vec4(0.043, 0.118, 0.165, 1.0);
uniform vec4 land_outside : source_color = vec4(0.150, 0.200, 0.190, 1.0);

const vec3 SHOAL = vec3(0.118, 0.262, 0.302);
const vec3 SHELF = vec3(0.086, 0.215, 0.270);
const vec3 SLOPE = vec3(0.063, 0.170, 0.232);
const vec3 BASIN = vec3(0.045, 0.132, 0.192);
const vec3 ABYSS = vec3(0.032, 0.100, 0.155);

// Cubic B-spline filtering from four bilinear taps. Bilinear alone has a kinked gradient at every
// cell edge, which contour lines and tint both give away as a staircase; the B-spline is smooth
// and also averages out the 8-bit encoding steps.
vec4 bspline(float t) {
	float t2 = t * t;
	float t3 = t2 * t;
	return vec4(
		(1.0 - 3.0 * t + 3.0 * t2 - t3) / 6.0,
		(4.0 - 6.0 * t2 + 3.0 * t3) / 6.0,
		(1.0 + 3.0 * t + 3.0 * t2 - 3.0 * t3) / 6.0,
		t3 / 6.0);
}

float smooth_value(sampler2D tex, vec2 uv) {
	vec2 size = 1.0 / texel;
	vec2 st = uv * size - 0.5;
	vec2 i = floor(st);
	vec2 f = st - i;
	vec4 wx = bspline(f.x);
	vec4 wy = bspline(f.y);
	vec2 s0 = vec2(wx.x + wx.y, wy.x + wy.y);
	vec2 s1 = vec2(wx.z + wx.w, wy.z + wy.w);
	// Texel k's centre sits at k + 0.5; each tap lands between two centres at the ratio of
	// their weights, so one bilinear fetch returns their weighted sum.
	vec2 o0 = (i - 0.5 + vec2(wx.y, wy.y) / s0) * texel;
	vec2 o1 = (i + 1.5 + vec2(wx.w, wy.w) / s1) * texel;
	float a = texture(tex, vec2(o0.x, o0.y)).r;
	float b = texture(tex, vec2(o1.x, o0.y)).r;
	float c = texture(tex, vec2(o0.x, o1.y)).r;
	float d = texture(tex, vec2(o1.x, o1.y)).r;
	float gx = s0.x / (s0.x + s1.x);
	float gy = s0.y / (s0.y + s1.y);
	return mix(mix(d, c, gx), mix(b, a, gx), gy);
}

float depth_at(sampler2D tex, vec2 uv) {
	return smooth_value(tex, uv);
}

vec3 tint(float d) {
	vec3 c = mix(SHOAL, SHELF, smoothstep(0.0, 200.0, d));
	c = mix(c, SLOPE, smoothstep(200.0, 1200.0, d));
	c = mix(c, BASIN, smoothstep(1200.0, 2800.0, d));
	return mix(c, ABYSS, smoothstep(2800.0, 4500.0, d));
}

float contour(float d, float level, float fw, float width) {
	float dist = abs(d - level) / max(fw, 0.0001);
	return 1.0 - smoothstep(width * 0.5, width * 0.5 + 1.0, dist);
}

void fragment() {
	vec2 uv = UV;
	bool on_raster = uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0;
	bool charted = uv.x >= chart_uv.x && uv.y >= chart_uv.y && uv.x <= chart_uv.z && uv.y <= chart_uv.w;
	bool polygons = uv.x >= coast_uv.x && uv.y >= coast_uv.y && uv.x <= coast_uv.z && uv.y <= coast_uv.w;
	if (!on_raster) {
		COLOR = ocean_outside;
	} else {
		float d = depth_at(TEXTURE, uv);
		bool land = d < 0.5;
		if (land && !polygons) {
			// Beyond the scenario's coastline polygons the raster supplies a coarse coast of its
			// own, so the geography runs on instead of stopping at a straight clip line.
			COLOR = land_outside;
		} else {
			vec3 col = tint(max(d, 0.0));
			// Relief, baked offline from the full-precision field. Faded out once a raster cell spans
			// enough pixels for the interpolation to show.
			float shade = texture(relief_tex, uv).r - 0.5;
			float fade = relief * (1.0 - smoothstep(10.0, 40.0, texel_px));
			col *= 1.0 + clamp(shade, -0.5, 0.5) * 1.1 * fade;
			// Contours. The shelf break carries the most weight on a naval chart.
			float fw = fwidth(d);
			float line = contour(d, 200.0, fw, 1.1) * 0.42;
			line = max(line, contour(d, 1000.0, fw, 1.0) * 0.26);
			line = max(line, contour(d, 2000.0, fw, 0.9) * 0.20);
			line = max(line, contour(d, 3000.0, fw, 0.9) * 0.17);
			line = max(line, contour(d, 4000.0, fw, 0.9) * 0.15);
			line = max(line, contour(d, 5000.0, fw, 0.9) * 0.15);
			col = mix(col, vec3(0.50, 0.74, 0.84), line);
			COLOR = vec4(col, 1.0);
		}
	}
	if (!charted) {
		// Outside the charted area: dimmed, so the eye reads where the scenario's geography ends.
		COLOR.rgb = mix(COLOR.rgb, vec3(dot(COLOR.rgb, vec3(0.3, 0.5, 0.2))), 0.35) * 0.72;
	}
}
