shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx, diffuse_lambert;

// The sea under the world view. Two long swell trains move the surface itself (the same trains
// WorldPresentation.swell_height evaluates, so hulls and wakes ride the same water) and three
// octaves of scrolling value noise give the wind waves their normals. Nothing here needs a
// texture, a compute pass or anything the GL Compatibility renderer and the browser lack.

uniform vec3 deep_color : source_color = vec3(0.016, 0.070, 0.105);
uniform vec3 crest_color : source_color = vec3(0.060, 0.190, 0.235);
uniform vec3 sky_color : source_color = vec3(0.45, 0.60, 0.72);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.80);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);          // toward the sun, world space
uniform float sun_strength : hint_range(0.0, 1.0) = 1.0; // 0 at night
uniform float daylight : hint_range(0.0, 1.0) = 1.0;     // darkens foam and crests after dark
uniform float sea_state : hint_range(0.0, 6.0) = 2.0;    // Detection.sea_state
uniform vec4 swell_a = vec4(0.4, 90.0, 0.2, 55.0);       // amplitude, wavelength of two swell trains (m)
uniform vec4 swell_dir = vec4(1.0, 0.0, 0.8, 0.6);       // unit xz directions of the two trains
uniform vec2 origin_offset = vec2(0.0);                  // metres; keeps the field continuous as the focus moves
uniform float time_scale = 1.0;

varying vec3 v_world;
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

float swell(vec2 p, float t) {
	float k1 = 6.2831853 / max(swell_a.y, 1.0);
	float k2 = 6.2831853 / max(swell_a.w, 1.0);
	float w1 = sqrt(9.81 * k1);
	float w2 = sqrt(9.81 * k2);
	return swell_a.x * sin(dot(p, swell_dir.xy) * k1 - w1 * t) + swell_a.z * sin(dot(p, swell_dir.zw) * k2 - w2 * t + 1.7);
}

// Wind waves as a height field in metres, three octaves, drifting downwind.
float waves(vec2 p, float t) {
	vec2 wind = swell_dir.xy;
	float h = vnoise(p * 0.045 + wind * t * 0.9);
	h += 0.5 * vnoise(p * 0.11 - wind.yx * t * 0.7 + 7.3);
	h += 0.25 * vnoise(p * 0.27 + wind * t * 1.6 + 3.1);
	return h;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = w.xz + origin_offset;
	float d = distance(w.xz, CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(1500.0, 5000.0, d);
	float lift = swell(p, TIME * time_scale) * fade;
	VERTEX.y += lift;
	v_world = vec3(w.x, w.y + lift, w.z);
	v_dist = d;
}

void fragment() {
	float t = TIME * time_scale;
	vec2 p = v_world.xz + origin_offset;
	float chop = 0.45 + 0.42 * sea_state;
	float eps = 0.6 + v_dist * 0.004;
	float h0 = waves(p, t);
	float hx = waves(p + vec2(eps, 0.0), t);
	float hz = waves(p + vec2(0.0, eps), t);
	vec3 n = normalize(vec3(-(hx - h0) / eps * chop, 1.0, -(hz - h0) / eps * chop));
	float far = smoothstep(500.0, 9000.0, v_dist);
	n = normalize(mix(n, vec3(0.0, 1.0, 0.0), far * 0.85));
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world);
	float ndv = clamp(dot(n, view_dir), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	float rel = h0 / 1.75;
	float crest = smoothstep(0.35, 0.95, rel);
	vec3 water = mix(deep_color, crest_color, crest * 0.7);
	float cap_threshold = 1.02 - 0.07 * sea_state;
	vec2 perp = vec2(-swell_dir.y, swell_dir.x);
	float streak = vnoise(vec2(dot(p, swell_dir.xy) * 0.02 + t * 0.04, dot(p, perp) * 0.06));
	float whitecap = smoothstep(cap_threshold, cap_threshold + 0.14, rel + 0.35 * streak - 0.22 + 0.08 * vnoise(p * 0.6 + t * 0.4));
	whitecap *= step(1.5, sea_state) * (1.0 - far);
	vec3 albedo = mix(water, sky_color, fresnel * 0.8);
	albedo = mix(albedo, vec3(0.80, 0.84, 0.86) * (0.35 + 0.65 * daylight), whitecap * 0.55);
	ALBEDO = albedo;
	METALLIC = 0.0;
	ROUGHNESS = mix(0.05, 0.20, clamp(sea_state / 6.0, 0.0, 1.0)) + whitecap * 0.6;
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 r = reflect(-view_dir, n);
	float g = max(dot(r, normalize(sun_dir)), 0.0);
	float glint = pow(g, 40.0 + 180.0 / (1.0 + sea_state)) * sun_strength;
	EMISSION = sun_color * glint * 0.85;
}
