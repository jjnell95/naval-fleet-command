shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, unshaded, fog_disabled;

// The sea under the world view: deep and dark, glinting where the sun catches it and paling to
// the sky's lavender at a grazing angle, as the late-1990s fleet-command games painted it, with
// the waves a modern renderer can afford. Two long swell trains move the surface itself (the
// same trains WorldPresentation.swell_height evaluates, so hulls and wakes ride the same water);
// six short wind-wave trains and two octaves of noise give it its normals, faded out with
// distance before they alias. Lighting is done here by hand so the palette holds exactly; the
// environment's fog is still applied on top. Nothing here needs a texture beyond the coast mask,
// a compute pass or anything the GL Compatibility renderer and the browser lack.

uniform vec3 deep_color : source_color = vec3(0.043, 0.059, 0.106);   // #0B0F1B
uniform vec3 body_color : source_color = vec3(0.105, 0.135, 0.185);   // a wave face toward the light
uniform vec3 sky_top : source_color = vec3(0.408, 0.361, 0.855);
uniform vec3 sky_horizon : source_color = vec3(0.616, 0.600, 0.800);
uniform vec3 foam_color : source_color = vec3(0.86, 0.89, 0.93);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.86);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);          // toward the sun, world space
uniform float sun_strength : hint_range(0.0, 1.0) = 1.0; // 0 at night
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float reflect_strength = 0.22;
uniform vec3 far_color : source_color = vec3(0.075, 0.094, 0.137);   // the sea just short of the horizon
uniform float haze_m = 30000.0;                                       // distance over which it gets there
uniform float sea_state : hint_range(0.0, 6.0) = 2.0;    // Detection.sea_state
uniform vec4 swell_a = vec4(0.4, 90.0, 0.2, 55.0);       // amplitude, wavelength of two swell trains (m)
uniform vec4 swell_dir = vec4(1.0, 0.0, 0.8, 0.6);       // unit xz directions of the two trains
uniform vec2 origin_offset = vec2(0.0);                  // metres; keeps the field continuous as the focus moves
uniform float time_scale = 1.0;
uniform float swell_time = 0.0;                          // WorldScene's clock, so hulls ride this water
uniform sampler2D coast_mask : filter_linear, repeat_disable;
uniform vec3 coast_window = vec3(0.0, 0.0, -1.0);        // x, z of the mask's centre, half size (m); < 0: none

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

// Gradient of value noise by central differences, for normals.
vec2 vnoise_grad(vec2 p, float e) {
	return vec2(vnoise(p + vec2(e, 0.0)) - vnoise(p - vec2(e, 0.0)), vnoise(p + vec2(0.0, e)) - vnoise(p - vec2(0.0, e))) / (2.0 * e);
}

float swell(vec2 p, float t) {
	float k1 = 6.2831853 / max(swell_a.y, 1.0);
	float k2 = 6.2831853 / max(swell_a.w, 1.0);
	float w1 = sqrt(9.81 * k1);
	float w2 = sqrt(9.81 * k2);
	return swell_a.x * sin(dot(p, swell_dir.xy) * k1 - w1 * t) + swell_a.z * sin(dot(p, swell_dir.zw) * k2 - w2 * t + 1.7);
}

vec2 swell_grad(vec2 p, float t) {
	float k1 = 6.2831853 / max(swell_a.y, 1.0);
	float k2 = 6.2831853 / max(swell_a.w, 1.0);
	float w1 = sqrt(9.81 * k1);
	float w2 = sqrt(9.81 * k2);
	return swell_a.x * k1 * cos(dot(p, swell_dir.xy) * k1 - w1 * t) * swell_dir.xy + swell_a.z * k2 * cos(dot(p, swell_dir.zw) * k2 - w2 * t + 1.7) * swell_dir.zw;
}

// One wind-wave train: its slope (d height / d x, d height / d z), faded once the wave is too
// short for the pixel footprint.
vec2 wave(vec2 p, float t, vec2 dir, float len, float amp, float footprint, inout float crest) {
	float k = 6.2831853 / len;
	float w = sqrt(9.81 * k);
	float ph = dot(p, dir) * k - w * t;
	float fade = 1.0 - smoothstep(len * 0.25, len * 0.9, footprint);
	crest += amp * sin(ph) * fade / len;
	return amp * k * cos(ph) * dir * fade;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = w.xz + origin_offset;
	float d = distance(w.xz, CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(1500.0, 5000.0, d);
	float lift = swell(p, swell_time) * fade;
	VERTEX.y += lift;
	v_world = vec3(w.x, w.y + lift, w.z);
	v_dist = d;
}

void fragment() {
	float t = TIME * time_scale;
	vec2 p = v_world.xz + origin_offset;
	vec3 to_eye = CAMERA_POSITION_WORLD - v_world;
	float dist = length(to_eye);
	vec3 view_dir = to_eye / max(dist, 1e-4);
	// How many metres one pixel covers here, roughly: what the waves may resolve.
	float footprint = max(length(fwidth(v_world.xz)), 0.02);
	float s = clamp(sea_state, 0.0, 6.0);
	float amp = 0.10 + 0.07 * s;
	vec2 wind = swell_dir.xy;
	vec2 side = vec2(-wind.y, wind.x);
	float crest = 0.0;
	vec2 g = swell_grad(p, swell_time) * (1.0 - smoothstep(1500.0, 5000.0, v_dist));
	g += wave(p, t, normalize(wind + side * 0.2), 41.0, amp * 1.5, footprint, crest);
	g += wave(p, t * 1.03, normalize(wind + side * 0.9), 23.0, amp * 0.9, footprint, crest);
	g += wave(p, t * 0.97, normalize(wind - side * 0.75), 13.7, amp * 0.55, footprint, crest);
	g += wave(p, t * 1.05, normalize(wind + side * 2.1), 7.9, amp * 0.3, footprint, crest);
	// Three octaves of drifting noise break up the regularity: cat's paws and chop.
	float chop_fade = 1.0 - smoothstep(0.6, 4.0, footprint);
	g += vnoise_grad(p * 0.045 + wind * t * 0.12, 0.3) * 0.045 * (0.9 + 0.35 * s) * (1.0 - smoothstep(3.0, 18.0, footprint));
	g += vnoise_grad(p * 0.21 + wind * t * 0.35, 0.25) * 0.21 * (0.3 + 0.12 * s) * chop_fade;
	g += vnoise_grad(p * 0.9 - wind * t * 0.8 + 11.0, 0.25) * 0.9 * (0.05 + 0.03 * s) * (1.0 - smoothstep(0.08, 0.7, footprint));
	vec3 n = normalize(vec3(-g.x, 1.0, -g.y));
	// Far away the surface smooths into one dark sheet up to a crisp horizon.
	float far = smoothstep(2500.0, haze_m, v_dist);
	n = normalize(mix(n, vec3(0.0, 1.0, 0.0), far * 0.75));
	float ndv = clamp(dot(n, view_dir), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	vec3 r = reflect(-view_dir, n);
	r.y = abs(r.y);
	vec3 sky = mix(sky_horizon, sky_top, smoothstep(0.0, 0.32, r.y));
	vec3 sd = normalize(sun_dir);
	float lit = clamp(dot(n, sd) * 0.5 + 0.5, 0.0, 1.0);
	// Large, slow blotches of darker and lighter water, as wind slicks paint a real sea.
	float slick = vnoise(p * 0.0024 + wind * t * 0.004) * 0.65 + vnoise(p * 0.009 - side * t * 0.01) * 0.35;
	float face = clamp(lit * 0.8 - 0.25 + crest * 5.0 + (slick - 0.5) * 0.45, 0.0, 1.0);
	vec3 water = mix(deep_color, body_color, face) * (0.35 + 0.65 * daylight);
	vec3 col = mix(water, sky * 0.62 * (0.25 + 0.75 * daylight), clamp(fresnel * reflect_strength * (1.0 - far * 0.6), 0.0, 1.0));
	col = mix(col, far_color * (0.3 + 0.7 * daylight), far);
	// Sunlight: a broad sheen on the sun's side and hard glints where a facet catches it.
	float rs = max(dot(r, sd), 0.0);
	float sheen = pow(rs, 24.0) * 0.12 + pow(rs, 180.0) * 0.6;
	float glint = pow(rs, 900.0) * 5.0 * (1.0 - far);
	float sparkle = step(0.94, vnoise(p * 1.9 + t * vec2(0.7, -0.5))) * pow(rs, 60.0) * 2.0 * (1.0 - smoothstep(0.05, 0.6, footprint));
	col += sun_color * (sheen + glint + sparkle) * sun_strength;
	// Whitecaps on the steep crests, from sea state 2 up.
	float steep = length(g);
	float cap = smoothstep(0.95 - 0.06 * s, 1.2 - 0.06 * s, steep * 2.2 + vnoise(p * 0.3 + t * 0.3) * 0.25);
	cap *= smoothstep(1.5, 3.0, s) * (1.0 - far) * (0.5 + 0.5 * vnoise(p * 0.05 + wind * t * 0.1));
	col = mix(col, foam_color * (0.3 + 0.7 * daylight), cap * 0.5);
	// Surf where the sea meets the chart's coast.
	if (coast_window.z > 0.0) {
		vec2 cuv = (v_world.xz - coast_window.xy) / (2.0 * coast_window.z) + 0.5;
		if (cuv.x > 0.0 && cuv.y > 0.0 && cuv.x < 1.0 && cuv.y < 1.0) {
			float m = textureLod(coast_mask, cuv, 0.0).r;
			float surf = smoothstep(0.03, 0.4, m) * (0.55 + 0.45 * vnoise(p * 0.08 + vec2(t * 0.25, 0.0)));
			float shoal = smoothstep(0.0, 0.25, m);
			col = mix(col, col * 1.35 + vec3(0.02, 0.05, 0.05) * daylight, shoal * 0.5 * (1.0 - far));
			col = mix(col, foam_color * (0.3 + 0.7 * daylight), surf * 0.75 * (1.0 - far));
		}
	}
	ALBEDO = col;
}
