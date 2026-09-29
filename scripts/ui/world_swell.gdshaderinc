// The two long swell trains of the world view's sea, shared by everything that has to ride the same
// water as the ocean shader: hull finishes (where the waterline falls), wakes and bow waves. The
// ocean itself carries the same function with per-material uniforms; WorldScene sets both from one
// place, WorldPresentation.swell_params, so they agree. Globals are declared in project.godot.

global uniform vec4 world_swell_a;         // amplitude, wavelength of two trains (m)
global uniform vec4 world_swell_dir;       // unit xz directions of the two trains
global uniform vec2 world_origin_offset;   // metres; the floating origin's wrap
global uniform float world_swell_time;     // WorldScene's clock

float world_swell(vec2 p) {
	float k1 = 6.2831853 / max(world_swell_a.y, 1.0);
	float k2 = 6.2831853 / max(world_swell_a.w, 1.0);
	float w1 = sqrt(9.81 * k1);
	float w2 = sqrt(9.81 * k2);
	return world_swell_a.x * sin(dot(p, world_swell_dir.xy) * k1 - w1 * world_swell_time)
		+ world_swell_a.z * sin(dot(p, world_swell_dir.zw) * k2 - w2 * world_swell_time + 1.7);
}

// The sea surface under a world point, faded with distance from the eye exactly as the ocean mesh
// fades its displacement, so a strip laid on it never sinks under the ocean or floats above it.
float world_sea_height(vec3 world, vec3 eye) {
	float fade = 1.0 - smoothstep(1500.0, 5000.0, distance(world.xz, eye.xz));
	return world_swell(world.xz + world_origin_offset) * fade;
}

// An integer hash of a lattice point; callers pass floored points (see the ocean shader).
float world_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(p)) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n >> 8u) * (1.0 / 16777216.0);
}

float world_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = world_hash(i);
	float b = world_hash(i + vec2(1.0, 0.0));
	float c = world_hash(i + vec2(0.0, 1.0));
	float d = world_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
