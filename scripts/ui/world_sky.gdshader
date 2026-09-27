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

float hash31(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
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
	float halo = pow(max(cs, 0.0), 900.0) * 1.2 + pow(max(cs, 0.0), 60.0) * 0.3 + pow(max(cs, 0.0), 14.0) * sun_glow;
	col += sun_color * (disc * 4.0 + halo) * sun_visible * smoothstep(-0.03, 0.01, y);
	if (stars > 0.0 && y > 0.0) {
		vec3 cell = floor(d * 420.0);
		float star = step(0.9975, hash31(cell)) * hash31(cell + 3.1);
		col += vec3(star) * stars * smoothstep(0.0, 0.2, y);
	}
	COLOR = col;
}
