shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, ambient_light_disabled;

// The fleet's finishes in the world view. The models carry flat colours named for what each surface
// is (naval_paint, deck_non_skid, antifouling, rubber, airframe ...); WorldMaterials hands each one
// to this shader with a `finish` that says how it should age and catch the light:
//
//  - painted steel shows its plating seams and the rust and grime that run down from scuppers
//    and fittings, more on some navies' hulls than others;
//  - decks are mottled non-skid, glazing is dark glass that mirrors the sky, airframes have panel
//    lines and a lighter underside, a submarine's rubber tiles show their grid close to;
//  - wherever a hull meets the sea (the swell is the ocean's own, from world_swell.gdshaderinc) it
//    is wet and dark above the water and edged with foam, and at speed the bow throws spray.
//
// The sun is the renderer's own light, so shadows fall as usual. The ambient is not: the
// environment's flat lavender ambient washed every face to the same pale grey, so it is turned off
// here and replaced by a hemisphere, the sky above and the dark sea below, with the sky mirrored in
// the glossy surfaces at a grazing angle. Every detail is sized in metres and fades out before it
// can alias, so a frigate filling the view and a carrier on the horizon both read cleanly.

#include "res://scripts/ui/world_swell.gdshaderinc"

const int PAINT = 0;
const int DECK = 1;
const int BOTTOM = 2;
const int GLASS = 3;
const int AIRFRAME = 4;
const int ANECHOIC = 5;
const int METAL = 6;
const int MARKING = 7;
const int FITTING = 8;
const int ORDNANCE = 9;
const int GROUND = 10;
const float SUN_RESPONSE = 0.78;

uniform vec3 albedo : source_color = vec3(0.5);
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform int finish = 0;
uniform float weathering : hint_range(0.0, 1.0) = 0.4;

global uniform vec4 world_sky_color;      // ambient from above
global uniform vec4 world_sea_color;      // ambient from below: the sea's dark bounce
global uniform vec4 world_horizon_color;  // what a grazing reflection sees
global uniform float world_ambient;       // the hemisphere's strength for the time of day

// 1 for a hull in the water (waterline, wetness, bow spray), 0 for anything aloft or ashore.
// Material uniforms, not instance uniforms: WorldMaterials keeps one variant per band of speed
// (see WAY_BANDS), because each instance with instance uniforms takes sixteen slots of a buffer
// that WebGL holds to 4096, and a carrier group's meshes, lights and bow waves would exhaust it.
uniform float at_sea = 0.0;
// Metres per second through the water, for the bow's spray.
uniform float hull_speed = 0.0;

varying vec3 v_local;   // model space in metres: +X to the bow, +Y up, +Z to starboard
varying vec3 v_world;
varying float v_half_length;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	v_local = VERTEX * s;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_half_length = 5.0 * s;  // every model is normalised to ten units along its longest axis
}

// An anti-aliased line every `spacing` metres along `coord`, `width` metres wide, gone before it
// is too fine for the pixel.
float seam(float coord, float spacing, float width) {
	float d = abs(fract(coord / spacing + 0.5) - 0.5) * spacing;
	float fw = max(fwidth(coord), 1e-4);
	float line = 1.0 - smoothstep(width, width + fw * 1.5, d);
	return line * (1.0 - smoothstep(spacing * 0.06, spacing * 0.2, fw));
}

void fragment() {
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 base = albedo;
	float rough = roughness;
	float metal = metallic;
	float gloss_boost = 0.0;
	float vertical = 1.0 - smoothstep(0.35, 0.75, abs(nw.y));
	float side = v_local.x + v_local.z;

	if (finish == PAINT || finish == BOTTOM) {
		// Strakes and butts of the shell plating.
		float plates = max(seam(v_local.y, 2.4, 0.035), seam(v_local.x, 7.2, 0.035)) * vertical;
		base *= 1.0 - 0.13 * plates;
		// Grime and rust running down from scuppers and fittings.
		float run = world_noise(vec2(side * 1.6, v_local.y * 0.085));
		float run2 = world_noise(vec2((v_local.x - v_local.z) * 0.55 + 11.0, v_local.y * 0.03));
		float streak = smoothstep(0.58, 0.95, run) * (0.45 + 0.55 * run2) * vertical;
		base *= 1.0 - 0.24 * streak * weathering;
		base = mix(base, vec3(0.19, 0.085, 0.04), smoothstep(0.86, 1.0, run) * run2 * vertical * weathering * 0.5);
		// Patchy repainting on the horizontal faces.
		float touch_up = world_noise(v_local.xz * 0.16 + 3.0);
		base *= 1.0 + (touch_up - 0.5) * 0.12 * (1.0 - vertical);
	} else if (finish == DECK) {
		float mottle = world_noise(v_local.xz * 0.3) * 0.6 + world_noise(v_local.xz * 1.9 + 7.0) * 0.4;
		base *= 0.84 + 0.3 * mottle;
		// Tyre and exhaust wear down the middle of a flight deck long enough to land jets on.
		float lane = 1.0 - smoothstep(0.0, v_half_length * 0.09, abs(v_local.z));
		base *= 1.0 - 0.18 * lane * world_noise(vec2(v_local.x * 0.08, v_local.z * 0.6)) * smoothstep(80.0, 120.0, v_half_length);
	} else if (finish == AIRFRAME) {
		float panels = max(seam(v_local.x, 1.35, 0.012), seam(v_local.z + v_local.y, 0.95, 0.012));
		base *= 1.0 - 0.1 * panels;
		// Counter-shading: the undersides of naval aircraft are painted lighter.
		base *= mix(1.22, 0.94, smoothstep(-0.6, 0.6, nw.y));
		// Exhaust soot toward the tail.
		base *= 1.0 - 0.2 * (1.0 - smoothstep(-0.48, -0.25, v_local.x / max(v_half_length * 2.0, 1.0))) * world_noise(v_local.xz * 2.0);
	} else if (finish == ANECHOIC) {
		float tiles = max(seam(v_local.x, 0.62, 0.02), seam(v_local.y + v_local.z, 0.62, 0.02));
		base = mix(base, base * 1.8 + vec3(0.01), tiles * 0.5);
		base *= 0.85 + 0.3 * world_noise(v_local.xy * vec2(0.4, 1.2));
	} else if (finish == MARKING) {
		base *= 0.8 + 0.2 * world_noise(v_local.xz * 3.0);
	} else if (finish == GROUND) {
		base *= 0.8 + 0.4 * world_noise(v_local.xz * 0.05) * world_noise(v_local.xz * 0.6 + 5.0);
	} else if (finish == GLASS) {
		gloss_boost = 0.8;
	}

	// Where the hull meets the sea: wet and dark above it, foam lapping along it, spray at the bow.
	if (at_sea > 0.5) {
		float h = v_world.y - world_sea_height(v_world, CAMERA_POSITION_WORLD);
		float fore = smoothstep(0.55, 0.98, v_local.x / max(v_half_length, 1.0));
		float speed = clamp(hull_speed / 14.0, 0.0, 1.0);
		float spray_h = 0.5 + fore * speed * (1.2 + 0.03 * v_half_length);
		float wet = 1.0 - smoothstep(0.0, 1.0 + spray_h, h);
		base *= mix(1.0, 0.6, wet);
		rough = mix(rough, 0.2, wet * 0.85);
		float lap = world_noise(vec2(v_local.x * 0.7 - TIME * (0.8 + 2.0 * speed), TIME * 0.35 + v_local.z * 0.7));
		float top = 0.18 + 0.4 * lap + spray_h * 0.55;
		float foam = smoothstep(-0.3, 0.0, h) * (1.0 - smoothstep(top * 0.55, top, h));
		foam *= 0.5 + 0.5 * world_noise(vec2(v_local.x * 2.3 + TIME * 1.5, v_local.y * 5.0 - TIME * 2.0));
		base = mix(base, vec3(0.8, 0.84, 0.88), clamp(foam, 0.0, 1.0) * 0.9);
		rough = mix(rough, 0.95, foam);
	}

	// The sun is the renderer's; a haze-grey deck in full sun burned out to white under it at the
	// strength the sea and the land were tuned for, so the finishes take a little less of it.
	ALBEDO = base * SUN_RESPONSE;
	ROUGHNESS = rough;
	METALLIC = metal;

	// The hemisphere: the sky above, the sea below, a vertical face half of each.
	vec3 hemi = mix(world_sea_color.rgb, world_sky_color.rgb, clamp(nw.y * 0.5 + 0.5, 0.0, 1.0));
	vec3 lit = base * hemi * world_ambient * (1.0 - 0.85 * metal);
	// The sky mirrored at a grazing angle, by what a reflection off this face would see.
	vec3 r = normalize((INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz);
	vec3 seen = mix(world_sea_color.rgb * 0.6, world_horizon_color.rgb, smoothstep(-0.12, 0.04, r.y));
	seen = mix(seen, world_sky_color.rgb, smoothstep(0.1, 0.7, r.y));
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	float gloss = (1.0 - rough) * (1.0 - rough);
	vec3 tint = mix(vec3(1.0), base, metal);
	float strength = mix(fresnel, 0.6 + 0.4 * fresnel, metal) * (gloss + gloss_boost);
	EMISSION = lit + seen * tint * strength * world_ambient * 1.25;
}
