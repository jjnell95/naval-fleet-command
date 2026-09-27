shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_schlick_ggx;

// Land for the world view: one static grid around the focus, lifted in the vertex stage from the
// region's presentation height raster and cut in the fragment stage to the chart's own coast.
// The coast comes from two masks WorldLand renders from the coastline polygons (a fine one near
// the focus, a coarse one out to the edge of the grid) or, outside the scenario's charted box,
// from the depth raster's own land. Everything here is plain texture reads and arithmetic, so the
// GL Compatibility renderer and the browser draw it as they draw anything else.

uniform sampler2D height_tex : filter_linear, repeat_disable;  // L8: height_m = scale * v^2
uniform sampler2D depth_tex : filter_linear, repeat_disable;   // L8: 0 is land
uniform sampler2D near_mask : filter_linear, repeat_disable;   // coastline polygons, white on clear
uniform sampler2D far_mask : filter_linear, repeat_disable;
uniform sampler2D ramp_mask : filter_linear, repeat_disable;  // the same polygons, drawn coarse
uniform vec2 height_size = vec2(1024.0);
uniform vec2 uv_origin = vec2(0.5);      // raster uv at the grid centre
uniform vec2 uv_per_m = vec2(0.0);       // raster uv per metre east (+x) and per metre south (+z)
uniform float near_half_m = 22224.0;
uniform float far_half_m = 111120.0;
uniform vec4 charted_m = vec4(-1e9, -1e9, 1e9, 1e9); // x0, z0, x1, z1: polygons inside, raster outside
uniform float use_polygons = 1.0;
uniform float use_raster = 1.0;
uniform float height_scale_m = 6000.0;
uniform float base_m = 1.4;
uniform float flat_m = 40.0;              // inland height where no raster covers the chart
uniform float min_inland_m = 10.0;
uniform vec3 col_beach : source_color = vec3(0.78, 0.70, 0.52);
uniform vec3 col_low : source_color = vec3(0.70, 0.58, 0.40);
uniform vec3 col_mid : source_color = vec3(0.60, 0.48, 0.33);
uniform vec3 col_high : source_color = vec3(0.50, 0.42, 0.34);
uniform vec3 col_rock : source_color = vec3(0.42, 0.36, 0.30);
uniform vec3 col_snow : source_color = vec3(0.92, 0.93, 0.95);
uniform float snow_line_m = 4000.0;
uniform float mid_m = 250.0;
uniform float high_m = 900.0;
uniform float ground_glow = 0.3;

varying vec3 v_local;
varying float v_height;
varying float v_dist;

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

vec4 cubic(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) * (1.0 / 6.0);
}

// A cubic B-spline through four bilinear reads: smooth hills from a coarse raster, no diamonds.
float bicubic(sampler2D t, vec2 uv, vec2 size) {
	vec2 inv = 1.0 / size;
	vec2 st = uv * size - 0.5;
	vec2 fxy = fract(st);
	st -= fxy;
	vec4 xc = cubic(fxy.x);
	vec4 yc = cubic(fxy.y);
	vec4 c = st.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 off = (c + vec4(xc.yw, yc.yw) / s) * inv.xxyy;
	float s0 = textureLod(t, off.xz, 0.0).r;
	float s1 = textureLod(t, off.yz, 0.0).r;
	float s2 = textureLod(t, off.xw, 0.0).r;
	float s3 = textureLod(t, off.yw, 0.0).r;
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

bool charted(vec2 local) {
	return local.x >= charted_m.x && local.y >= charted_m.y && local.x <= charted_m.z && local.y <= charted_m.w;
}

float raster_land(vec2 local) {
	float d = textureLod(depth_tex, uv_origin + local * uv_per_m, 0.0).r;
	return 1.0 - smoothstep(0.8 / 255.0, 5.0 / 255.0, d);
}

// The coast from the polygons: the fine mask near the focus, the wide one beyond it.
float polygon_land(vec2 local) {
	vec2 near_uv = local / (2.0 * near_half_m) + 0.5;
	float far = textureLod(far_mask, local / (2.0 * far_half_m) + 0.5, 0.0).r;
	float edge = max(abs(near_uv.x - 0.5), abs(near_uv.y - 0.5));
	if (edge < 0.49) {
		float near = textureLod(near_mask, near_uv, 0.0).r;
		return mix(near, far, smoothstep(0.44, 0.49, edge));
	}
	return far;
}

// How much of a point is land, 0..1, with the coast at one half.
float land_mask(vec2 local) {
	if (use_polygons > 0.5 && charted(local)) {
		return polygon_land(local);
	}
	return use_raster > 0.5 ? raster_land(local) : 0.0;
}

// The same, widened: hills rise over the first quarter mile or so inland instead of from the
// waterline. The ramp mask is the polygons drawn coarse, so one bilinear read is the blur.
float inland(vec2 local) {
	if (use_polygons > 0.5 && charted(local)) {
		return smoothstep(0.5, 1.0, textureLod(ramp_mask, local / (2.0 * far_half_m) + 0.5, 0.0).r);
	}
	return use_raster > 0.5 ? smoothstep(0.5, 1.0, raster_land(local)) : 0.0;
}

float ground(vec2 local) {
	float h = flat_m;
	if (use_raster > 0.5) {
		float v = bicubic(height_tex, uv_origin + local * uv_per_m, height_size);
		h = max(height_scale_m * v * v, min_inland_m);
	}
	return base_m + h * inland(local);
}

void vertex() {
	vec2 local = VERTEX.xz;
	float h = ground(local);
	float e = max(60.0, length(local) * 0.01);
	float hx = ground(local + vec2(e, 0.0)) - h;
	float hz = ground(local + vec2(0.0, e)) - h;
	VERTEX.y = h;
	NORMAL = normalize(vec3(-hx, e, -hz));
	v_local = vec3(local.x, h, local.y);
	v_height = h;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_dist = distance(w, CAMERA_POSITION_WORLD);
}

void fragment() {
	vec2 local = v_local.xz;
	float m = land_mask(local);
	if (m < 0.5) {
		discard;
	}
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - n_world.y;
	float h = v_height;
	// Ground texture, world-anchored: a broad, faint variation and a fine grain that fades out with
	// distance before it can alias.
	float fine = smoothstep(9000.0, 1500.0, v_dist);
	float n1 = vnoise(local * 0.0021);
	float n2 = vnoise(local * 0.017 + 17.0);
	float n3 = vnoise(local * 0.09 + 3.0);
	float mottle = (n1 - 0.5) * 0.06 + ((n2 - 0.5) * 0.07 + (n3 - 0.5) * 0.06) * fine;
	vec3 col = mix(col_low, col_mid, smoothstep(mid_m * 0.4, mid_m * 1.6, h + (n1 - 0.5) * mid_m));
	col = mix(col, col_high, smoothstep(high_m * 0.6, high_m * 1.5, h + (n2 - 0.5) * high_m * 0.4));
	col = mix(col, col_rock, smoothstep(0.28, 0.55, slope + (n2 - 0.5) * 0.15));
	float beach = (1.0 - smoothstep(0.52, 0.66, m)) * (1.0 - smoothstep(6.0, 22.0, h));
	col = mix(col, col_beach, beach);
	float snow = smoothstep(snow_line_m - 120.0, snow_line_m + 200.0, h + (n1 - 0.5) * 260.0) * (1.0 - smoothstep(0.45, 0.7, slope));
	col = mix(col, col_snow, snow);
	col *= 1.0 + mottle;
	ALBEDO = col;
	// Some of the ground's own colour whatever the light, so a desert reads as sand under a low
	// sun and a lavender sky, as the old games drew it, and not as mauve.
	EMISSION = col * col * ground_glow;
	ROUGHNESS = 0.95 - snow * 0.4;
	SPECULAR = 0.2 + snow * 0.3;
	// Detail bumps for the near ground, so a hillside a mile off is not a smooth plastic sheet.
	vec2 g = vec2(vnoise(local * 0.05 + vec2(1.3, 0.0)) - vnoise(local * 0.05 - vec2(1.3, 0.0)), vnoise(local * 0.05 + vec2(0.0, 1.3)) - vnoise(local * 0.05 - vec2(0.0, 1.3)));
	vec3 bumped = normalize(n_world + vec3(g.x, 0.0, g.y) * 0.06 * fine);
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
}
