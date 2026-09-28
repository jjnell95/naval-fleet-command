// The body shared by the two looks the world view gives a model that is not being shown as itself:
// a contact drawn from the plot (world_tint.gdshader, the identity colour, over the water) and
// anything under it (world_xray.gdshader, seen through the sea). Instead of one flat colour, the
// model keeps its form: lit a little from above, brighter at its silhouette, and, under water, it
// dims with depth and a faint sonar sweep runs along it.

uniform vec4 tint : source_color = vec4(1.0);
uniform float sweep = 0.0;  // 1 for the under-water look's sonar bands

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float ndv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 2.4);
	float shade = 0.5 + 0.5 * clamp(nw.y * 0.5 + 0.5, 0.0, 1.0);
	float depth = clamp(1.0 + min(v_world.y, 0.0) / 800.0, 0.55, 1.0);
	float bands = 1.0 - sweep * 0.18 * smoothstep(0.6, 1.0, sin(v_world.x * 0.09 + v_world.z * 0.09 - TIME * 2.2));
	ALBEDO = tint.rgb * (shade * 0.95 + rim * 1.0) * depth * bands;
	ALPHA = clamp(tint.a * (0.8 + 0.8 * rim) * mix(1.0, depth, sweep), 0.0, 1.0);
}
