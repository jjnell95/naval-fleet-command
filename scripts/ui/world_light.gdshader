shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// A navigation light: a point of coloured light that keeps its size on screen however far away it
// is, as a lamp does at night. Ships show a white masthead light, red to port, green to starboard
// and white astern; aircraft red and green at the wingtips and a flashing red beacon. They come up
// as the light goes and are gone in daylight. The size is an angle, set by the quad the node draws.
// A ship's lights are screened to their arcs as the rules of the road have them, so at night the
// lights alone say which way she is heading: red and green together only from ahead.

global uniform float world_daylight;

uniform vec4 color : source_color = vec4(1.0);
uniform float flash_period = 0.0;  // seconds; 0 burns steadily

instance uniform float phase = 0.0;
// The arc the light shows over: its centre as a direction in the model (+X the bow, +Z starboard)
// and the cosine of half its width. A w below -1 shows all round.
instance uniform vec4 arc = vec4(1.0, 0.0, 0.0, -2.0);

varying float v_seen;

void vertex() {
	v_seen = 1.0;
	if (arc.w > -1.5) {
		vec3 centre = mat3(MODEL_MATRIX) * arc.xyz;
		vec3 to_eye = CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz;
		vec2 a = normalize(centre.xz + vec2(1e-6));
		vec2 e = normalize(to_eye.xz + vec2(1e-6));
		v_seen = smoothstep(arc.w - 0.04, arc.w + 0.04, dot(a, e));
	}
	// Face the camera, drop the parent's scale, and grow with distance so the size is an angle.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float distance_m = max(-MODELVIEW_MATRIX[3].z, 1.0);
	MODELVIEW_MATRIX[0] *= distance_m;
	MODELVIEW_MATRIX[1] *= distance_m;
	MODELVIEW_MATRIX[2] *= distance_m;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r2 = dot(c, c);
	float glow = exp(-r2 * 9.0) + 0.3 * exp(-r2 * 2.5);
	float night = 1.0 - smoothstep(0.28, 0.55, world_daylight);
	float on = 1.0;
	if (flash_period > 0.0) {
		on = step(0.82, fract(TIME / flash_period + phase));
	}
	ALBEDO = color.rgb * glow * night * on * v_seen * 2.2;
}
