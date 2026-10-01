shader_type canvas_item;
render_mode unshaded;

// A sparse near-camera rain curtain. It has no texture, particles or simulation state; the
// scenario supplies intensity and the presentation supplies a clock that stops during pause.
uniform float weather_time = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float aspect = 2.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float drops(vec2 p, float scale, float speed, float seed) {
	vec2 q = vec2(p.x + p.y * 0.15, p.y - weather_time * speed) * vec2(scale, scale * 0.3);
	vec2 cell = floor(q);
	vec2 f = fract(q);
	float random = hash21(cell + seed);
	float x = 0.15 + hash21(cell + seed + 3.0) * 0.7;
	float width = max(fwidth(q.x) * 0.75, 0.025);
	float streak = (1.0 - smoothstep(0.0, width, abs(f.x - x))) * smoothstep(0.05, 0.2, f.y) * (1.0 - smoothstep(0.45, 0.9, f.y));
	return streak * step(1.0 - intensity * 0.35, random);
}

void fragment() {
	vec2 p = UV * vec2(aspect, 1.0);
	float near = drops(p, 35.0, 1.5, 5.0);
	float far = drops(p, 68.0, 0.95, 17.0);
	COLOR = vec4(vec3(0.65, 0.73, 0.8) * (0.35 + daylight * 0.65), (near * 0.22 + far * 0.12) * intensity);
}
