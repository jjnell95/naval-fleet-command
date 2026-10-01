shader_type sky;
render_mode use_debanding;

// The world view's sky, in the manner of the 1990s fleet-command games: violet-blue overhead
// fading to pale lavender at the horizon, a thin band of haze on the horizon itself and a soft
// sun. The gradient does most of its work in the first twenty degrees above the horizon, which is
// all a camera tethered low over a ship ever sees. WorldScene sets the colours by time of day.

uniform vec3 top_color : source_color = vec3(0.408, 0.361, 0.855);      // #685CDA
uniform vec3 horizon_color : source_color = vec3(0.616, 0.600, 0.800);  // #9D99CC
uniform vec3 zenith_color : source_color = vec3(0.30, 0.26, 0.74);
uniform vec3 haze_color : source_color = vec3(0.70, 0.68, 0.84);
uniform vec3 below_color : source_color = vec3(0.12, 0.13, 0.19);
uniform float gradient_top = 0.2;    // sin(elevation) where the top colour is reached
uniform float haze_strength = 0.3;
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.88);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float sun_size_deg = 0.7;
uniform float sun_glow = 0.28;
uniform float sun_visible = 1.0;
uniform float stars = 0.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.28;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 cloud_wind = vec2(0.002, 0.0);
uniform float weather_time = 0.0;
uniform vec3 cloud_light : source_color = vec3(0.9, 0.92, 0.95);
uniform vec3 cloud_shadow : source_color = vec3(0.4, 0.45, 0.54);

float hash31(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float cloud_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash31(vec3(cell, 0.0));
	float b = hash31(vec3(cell + vec2(1.0, 0.0), 0.0));
	float c = hash31(vec3(cell + vec2(0.0, 1.0), 0.0));
	float e = hash31(vec3(cell + vec2(1.0), 0.0));
	return mix(mix(a, b, f.x), mix(c, e, f.x), f.y);
}

float cloud_field(vec2 p) {
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float broad = cloud_noise(p);
	p = turn * p * 2.07 + vec2(19.0, 7.0);
	float middle = cloud_noise(p);
	p = turn * p * 2.13 + vec2(43.0, 13.0);
	return broad * 0.63 + middle * 0.25 + cloud_noise(p) * 0.12;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 col;
	if (y >= 0.0) {
		float g = smoothstep(0.0, gradient_top, y);
		col = mix(horizon_color, top_color, g);
		col = mix(col, zenith_color, smoothstep(gradient_top, 1.0, y) * 0.6);
	} else {
		col = mix(haze_color, below_color, smoothstep(0.0, 0.06, -y));
	}
	col = mix(col, haze_color, exp(-abs(y) * 90.0) * haze_strength);
	vec3 s = normalize(sun_dir);
	float cs = dot(d, s);
	float disc = smoothstep(cos(radians(sun_size_deg)), cos(radians(sun_size_deg * 0.6)), cs);
	float halo = pow(max(cs, 0.0), 6000.0) * 0.9 + pow(max(cs, 0.0), 120.0) * 0.22 + pow(max(cs, 0.0), 14.0) * sun_glow;
	col += sun_color * (disc * 2.2 + halo) * sun_visible * smoothstep(-0.03, 0.01, y);
	if (stars > 0.0 && y > 0.0) {
		vec3 cell = floor(d * 420.0);
		float star = step(0.9975, hash31(cell)) * hash31(cell + 3.1);
		col += vec3(star) * stars * smoothstep(0.0, 0.2, y);
	}
	// A drifting horizontal layer, continuous across all camera headings. Broad soft banks read
	// at pane size; three noise octaves avoid the cost of volumetrics in the browser renderer.
	if (y > 0.0 && cloud_cover > 0.0) {
		// A curved distant layer avoids a hard projection clamp near the horizon, which repeats
		// the same sample vertically and makes curtains. Haze merges the far banks into the sky.
		vec2 p = d.xz / (y + 0.25) * 1.5 + cloud_wind * weather_time;
		float field = cloud_field(p);
		float threshold = mix(0.8, 0.22, cloud_cover);
		float density = smoothstep(threshold - 0.05, threshold + 0.17, field);
		density *= smoothstep(0.005, 0.07, y) * smoothstep(0.0, 0.06, cloud_cover);
		float body = smoothstep(threshold - 0.03, threshold + 0.28, field);
		float silver = pow(max(dot(d, s), 0.0), 12.0) * (1.0 - body) * sun_visible;
		vec3 cloud = mix(cloud_shadow, cloud_light, 0.5 + body * (0.5 - rain_intensity * 0.2));
		cloud += sun_color * silver * 0.05;
		col = mix(col, cloud, density * 0.96);
	}
	COLOR = col;
}
