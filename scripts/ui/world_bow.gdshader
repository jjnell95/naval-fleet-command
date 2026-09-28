shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// The water a hull pushes aside: foam along both sides of a ship under way and the two arms of the
// bow wave opening from the stem, drawn on a patch of sea around the hull that rides the swell. The
// node is scaled to the patch in metres (x along the hull, z across it) and its own material carries
// the hull's beam and speed; the wake strip takes over astern. Nothing shows when stopped.

#include "res://scripts/ui/world_swell.gdshaderinc"

const float PATCH_LENGTH = 1.5;  // patch length as a multiple of the hull's

global uniform float world_daylight;

uniform float hull_beam = 15.0;
uniform float hull_speed = 0.0;  // metres per second

varying vec2 v_hull;   // metres in the hull's frame: x toward the bow, y to starboard
varying vec3 v_world;
varying float v_length;

void vertex() {
	float sx = length(MODEL_MATRIX[0].xyz);
	float sz = length(MODEL_MATRIX[2].xyz);
	v_hull = vec2(VERTEX.x * sx, VERTEX.z * sz);
	v_length = sx / PATCH_LENGTH;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += world_sea_height(w, CAMERA_POSITION_WORLD) + 0.3 - w.y;
	v_world = w;
}

void fragment() {
	float hl = v_length * 0.5;
	float x = v_hull.x;
	float y = abs(v_hull.y);
	float t = clamp(x / hl, -1.0, 1.0);
	// The waterplane: fine at the bow, full amidships, a transom aft.
	float half_breadth = 0.5 * hull_beam * (t > 0.0 ? 1.0 - pow(t, 2.2) : 1.0 - 0.25 * pow(-t, 3.0));
	float outside = y - half_breadth;
	if (x > hl) {
		outside = length(vec2(x - hl, y));
	} else if (x < -hl) {
		outside = length(vec2(-hl - x, max(y - 0.375 * hull_beam, 0.0)));
	}
	float speed = smoothstep(0.6, 9.0, hull_speed);
	float fast = clamp(hull_speed / 15.0, 0.0, 1.0);
	float fore = smoothstep(-0.4, 0.8, t);
	vec2 p = v_world.xz + world_origin_offset;
	float n = world_noise(p * 0.45 + vec2(TIME * 0.6, 0.0));
	float n2 = world_noise(p * 1.7 - vec2(0.0, TIME * 0.9));

	// Foam pushed out along the sides, thicker forward.
	float skirt = exp(-max(outside, 0.0) / (0.7 + 2.2 * fast)) * (0.35 + 0.65 * fore);
	// The divergent bow wave: two crests from the stem at about 20 degrees, widening and fading aft.
	float aft_of_stem = max(hl - x, 0.0);
	float crest = abs(y - aft_of_stem * 0.36);
	float arm = exp(-crest / (0.8 + aft_of_stem * 0.05)) * exp(-aft_of_stem / (v_length * (0.25 + 0.35 * fast)));
	arm *= step(x, hl + 1.0);
	float foam = (skirt * 0.85 + arm) * (0.45 + 0.55 * n) * (0.65 + 0.35 * n2);
	foam *= step(0.0, outside) * speed;
	// Thins out toward the edge of the patch.
	vec2 edge = abs(v_hull) / vec2(v_length * PATCH_LENGTH * 0.5, max(v_length * 0.5, 1.0));
	foam *= 1.0 - smoothstep(0.75, 1.0, max(edge.x, edge.y));
	float light = 0.4 + 0.6 * world_daylight;
	ALBEDO = mix(vec3(0.3, 0.52, 0.6), vec3(0.9, 0.93, 0.95), clamp(foam * 1.4, 0.0, 1.0)) * light;
	ALPHA = clamp(foam, 0.0, 0.95);
}
