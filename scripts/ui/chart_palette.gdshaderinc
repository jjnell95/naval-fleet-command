// The chart's palette, samplers and grain, shared by the sea floor (chart_floor.gdshader) and the
// polygon land (chart_land.gdshader), on the tactical map and on the regional map alike. One file,
// so the water, the raster's own land and the scenario's vector land can never drift apart.
//
// The look is the classic naval command display: stepped saturated blues that lighten toward the
// coast, a hypsometric green-to-khaki land ramp, hill shading from the baked relief rasters and a
// fine grain anchored to the world so large flat areas never read as vector fills.

// Raster bounds in world nautical miles: x (west), y (south), width, height. Every chart raster of a
// region shares these bounds and a north-first row order, so one transform samples them all.
uniform vec4 world_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float px_per_nm = 4.0;         // screen pixels per nautical mile, for grain and fades
uniform float relief = 1.0;            // 0 turns hill shading off (the chart's relief toggle)

// Land: height code (metres = 6000 * v^2) and its hill-shade (0.5 = flat), full raster resolution.
uniform sampler2D land_tex : filter_linear, repeat_disable;
uniform sampler2D land_relief_tex : filter_linear, repeat_disable;
uniform vec2 land_texel = vec2(0.001, 0.001);
// 1 once the land rasters are bound. A missing sampler reads as a default colour, and a default
// that is not exactly 0.5 would shade every pixel, so an unbound raster is switched off instead.
uniform float land_raster = 0.0;

// Regional map treatment: darker, less saturated, with translucent radar-coverage discs.
uniform float tone_brightness = 1.0;
uniform float tone_saturation = 1.0;
uniform vec4 coverage[16];             // centre x, centre y, radius (all nm), unused
uniform int coverage_count = 0;

const float LAND_SCALE_M = 6000.0;
const float GRAIN_PX = 1.6;            // grain cell size on screen
const float GRAIN = 0.03;              // +/- brightness of the grain
const float DETAIL = 0.06;             // +/- brightness of the close-zoom land texture

// World nautical miles to raster UV (north row first).
vec2 raster_uv(vec2 w) {
	return vec2((w.x - world_rect.x) / world_rect.z, (world_rect.y + world_rect.w - w.y) / world_rect.w);
}

bool on_raster(vec2 uv) {
	return uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0;
}

// Cubic B-spline filtering from four bilinear taps. Bilinear alone has a kinked gradient at every
// cell edge, which shows as diamonds once a cell spans tens of pixels; the B-spline is smooth and
// also averages out the 8-bit encoding steps.
vec4 bspline(float t) {
	float t2 = t * t;
	float t3 = t2 * t;
	return vec4(
		(1.0 - 3.0 * t + 3.0 * t2 - t3) / 6.0,
		(4.0 - 6.0 * t2 + 3.0 * t3) / 6.0,
		(1.0 + 3.0 * t + 3.0 * t2 - 3.0 * t3) / 6.0,
		t3 / 6.0);
}

float smooth_sample(sampler2D tex, vec2 uv, vec2 texel) {
	vec2 st = uv / texel - 0.5;
	vec2 i = floor(st);
	vec2 f = st - i;
	vec4 wx = bspline(f.x);
	vec4 wy = bspline(f.y);
	vec2 s0 = vec2(wx.x + wx.y, wy.x + wy.y);
	vec2 s1 = vec2(wx.z + wx.w, wy.z + wy.w);
	// Texel k's centre sits at k + 0.5; each tap lands between two centres at the ratio of their
	// weights, so one bilinear fetch returns their weighted sum.
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

// Catmull-Rom from nine bilinear taps: an interpolating cubic, so hill shading keeps the raster's
// crispness at a wide zoom and stays smooth, with no diamonds, when a cell spans many pixels.
float sharp_sample(sampler2D tex, vec2 uv, vec2 texel) {
	vec2 st = uv / texel;
	vec2 p1 = floor(st - 0.5) + 0.5;
	vec2 f = st - p1;
	vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
	vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
	vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
	vec2 w3 = f * f * (-0.5 + 0.5 * f);
	vec2 w12 = w1 + w2;
	vec2 t0 = (p1 - 1.0) * texel;
	vec2 t12 = (p1 + w2 / w12) * texel;
	vec2 t3 = (p1 + 2.0) * texel;
	float r = 0.0;
	r += texture(tex, vec2(t0.x, t0.y)).r * w0.x * w0.y;
	r += texture(tex, vec2(t12.x, t0.y)).r * w12.x * w0.y;
	r += texture(tex, vec2(t3.x, t0.y)).r * w3.x * w0.y;
	r += texture(tex, vec2(t0.x, t12.y)).r * w0.x * w12.y;
	r += texture(tex, vec2(t12.x, t12.y)).r * w12.x * w12.y;
	r += texture(tex, vec2(t3.x, t12.y)).r * w3.x * w12.y;
	r += texture(tex, vec2(t0.x, t3.y)).r * w0.x * w3.y;
	r += texture(tex, vec2(t12.x, t3.y)).r * w12.x * w3.y;
	r += texture(tex, vec2(t3.x, t3.y)).r * w3.x * w3.y;
	return r;
}

// One stepped band edge, one screen pixel wide: fw is the depth change across a pixel.
vec3 band(vec3 c, float d, float fw, float from_m, vec3 rgb) {
	return mix(c, rgb / 255.0, clamp((d - from_m) / fw + 0.5, 0.0, 1.0));
}

// Stepped sea bands by depth in metres, lightest at the coast, no green.
vec3 sea_colour(float d, float fw) {
	vec3 c = vec3(30.0, 32.0, 150.0) / 255.0;
	c = band(c, d, fw, 20.0, vec3(24.0, 26.0, 140.0));
	c = band(c, d, fw, 50.0, vec3(18.0, 20.0, 132.0));
	c = band(c, d, fw, 100.0, vec3(10.0, 12.0, 128.0));
	c = band(c, d, fw, 200.0, vec3(4.0, 5.0, 124.0));
	c = band(c, d, fw, 500.0, vec3(0.0, 0.0, 118.0));
	c = band(c, d, fw, 1000.0, vec3(0.0, 0.0, 108.0));
	c = band(c, d, fw, 2000.0, vec3(0.0, 0.0, 98.0));
	c = band(c, d, fw, 3000.0, vec3(0.0, 0.0, 88.0));
	return band(c, d, fw, 4000.0, vec3(0.0, 0.0, 78.0));
}

vec3 ramp(vec3 c, float h, float from_m, float to_m, vec3 rgb) {
	return mix(c, rgb / 255.0, clamp((h - from_m) / (to_m - from_m), 0.0, 1.0));
}

// Hypsometric land tint, interpolated smoothly between stops (metres).
vec3 land_tint(float h) {
	vec3 c = vec3(0.0, 98.0, 0.0) / 255.0;
	c = ramp(c, h, 0.0, 60.0, vec3(10.0, 106.0, 4.0));
	c = ramp(c, h, 60.0, 200.0, vec3(40.0, 110.0, 14.0));
	c = ramp(c, h, 200.0, 500.0, vec3(80.0, 120.0, 18.0));
	c = ramp(c, h, 500.0, 900.0, vec3(110.0, 126.0, 26.0));
	c = ramp(c, h, 900.0, 1500.0, vec3(140.0, 132.0, 50.0));
	c = ramp(c, h, 1500.0, 2200.0, vec3(160.0, 140.0, 80.0));
	c = ramp(c, h, 2200.0, 3200.0, vec3(176.0, 160.0, 120.0));
	return ramp(c, h, 3200.0, 4500.0, vec3(210.0, 205.0, 190.0));
}

// Value noise on a hashed lattice, in [-1, 1]. The lattice index wraps every 4096 cells, which is
// never visible and keeps the hash exact far from the anchor at fine grain.
float hash12(vec2 p) {
	p = mod(p, 4096.0);
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

// A fine grain about two pixels across at every zoom, anchored to the world: the lattice steps by
// octaves with the scale and cross-fades between neighbours, so it never swims while panning and
// never pops while zooming.
float grain_level(vec2 w, float level) {
	// Each octave keeps its own lattice offset, so the octave faded in above one boundary is the
	// same one faded out below the next.
	return value_noise(w / exp2(level) + vec2(level * 17.0, level * 31.0));
}

float grain(vec2 w) {
	float level = log2(GRAIN_PX / max(px_per_nm, 0.0001));
	float l0 = floor(level);
	return mix(grain_level(w, l0), grain_level(w, l0 + 1.0), level - l0);
}

// Close-zoom land texture: two world-anchored octaves (~0.3 nm and ~0.08 nm), each faded in only
// once it is several pixels across so it never aliases into noise at a wide zoom.
float land_detail(vec2 w) {
	float a = value_noise(w / 0.3 + 5.0) * smoothstep(1.5, 5.0, 0.3 * px_per_nm);
	float b = value_noise(w / 0.08 + 41.0) * smoothstep(1.5, 5.0, 0.08 * px_per_nm);
	return a * 0.6 + b * 0.4;
}

// Land colour at a raster position: tint by height, then hill shading that lifts lit slopes more
// than it darkens shaded ones (shadows never go black), then the close-zoom texture.
vec3 land_colour(vec2 uv, vec2 w) {
	float h = 0.0;
	float shade = 0.0;
	if (land_raster > 0.5 && on_raster(uv)) {
		float v = max(sharp_sample(land_tex, uv, land_texel), 0.0);
		h = LAND_SCALE_M * v * v;
		shade = clamp((sharp_sample(land_relief_tex, uv, land_texel) * 255.0 - 128.0) / 128.0, -1.0, 1.0);
	}
	vec3 c = land_tint(h);
	c *= 1.0 + shade * (shade > 0.0 ? 0.9 : 0.7) * relief;
	return c * (1.0 + land_detail(w) * DETAIL);
}

// The shared finish: grain, then the regional map's tone and radar-coverage discs.
vec3 finish(vec3 c, vec2 w) {
	c *= 1.0 + grain(w) * GRAIN;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, tone_saturation) * tone_brightness;
	float covered = 0.0;
	float nm_px = 1.0 / max(px_per_nm, 0.0001);
	for (int i = 0; i < 16; i++) {
		if (i >= coverage_count) {
			break;
		}
		float edge = length(w - coverage[i].xy) - coverage[i].z;
		covered = max(covered, clamp(0.5 - edge / nm_px, 0.0, 1.0));
	}
	return mix(c, vec3(180.0, 255.0, 180.0) / 255.0, 0.18 * covered);
}
