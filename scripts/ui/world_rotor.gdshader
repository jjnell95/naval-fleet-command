shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// A helicopter's main rotor turning: the blades as a faint disc with the streaks of their passage,
// darker toward the tips. The models' blades are stationary geometry under it.

global uniform float world_daylight;

uniform float blades = 4.0;

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float a = atan(c.y, c.x);
	float sweep = 0.5 + 0.5 * cos(blades * (a - TIME * 31.0));
	float disc = (1.0 - smoothstep(0.94, 1.0, r)) * smoothstep(0.06, 0.14, r);
	float tip = smoothstep(0.82, 0.97, r) * (1.0 - smoothstep(0.97, 1.0, r));
	vec3 col = mix(vec3(0.07, 0.075, 0.08), vec3(0.3, 0.3, 0.28), tip) * (0.35 + 0.65 * world_daylight);
	ALBEDO = col;
	ALPHA = disc * (0.16 + 0.12 * sweep + 0.25 * tip);
}
