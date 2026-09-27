shader_type canvas_item;
// The sea floor under the chart, and the land beyond the scenario's coastline polygons. The rect is
// drawn in local pixels; the vertex stage turns each corner into world nautical miles, so depth,
// relief and grain are all sampled at a world position and stay put while the view pans.
//
// Water is stepped bands by depth (chart_palette.gdshaderinc). Inside the scenario's charted box
// the coastline polygons own the coast, so the raster's own land is painted as coastal water there
// and the polygons (ChartLand) are drawn over it. Outside the box the raster's coast carries on
// with the same land tint, edge to edge, with no dimming and no neatline.

#include "res://scripts/ui/chart_palette.gdshaderinc"

uniform vec2 view_origin_nm = vec2(0.0, 0.0); // world position of local pixel (0, 0)
uniform float nm_per_px = 0.25;

// Sea: half-float metres at half resolution (smooth band edges), its baked relief (0.5 = flat) and a
// full-resolution water mask (1 water, 0 the raster's land) for a crisp raster coast.
uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform vec2 depth_texel = vec2(0.001, 0.001);
uniform sampler2D sea_relief_tex : filter_linear, repeat_disable;
uniform vec2 sea_relief_texel = vec2(0.001, 0.001);
uniform float sea_relief = 0.0;               // 0.35 once sea_relief_tex is bound
uniform sampler2D water_tex : filter_linear, repeat_disable;
uniform vec2 water_texel = vec2(0.001, 0.001);
uniform float depth_raster = 0.0;             // 1 once depth_tex and water_tex are bound
uniform float uniform_depth_m = 2000.0;       // the floor where there is no raster
uniform vec4 charted_uv = vec4(-10.0, -10.0, -9.0, -9.0); // where polygons own the coast: x0, y0, x1, y1

const vec3 COASTLINE = vec3(0.0, 58.0, 6.0) / 255.0; // TacticalMap.COL_COASTLINE

varying vec2 world;

void vertex() {
	world = view_origin_nm + VERTEX * vec2(nm_per_px, -nm_per_px);
}

void fragment() {
	vec2 uv = raster_uv(world);
	bool raster = depth_raster > 0.5 && on_raster(uv);
	// Derivatives first, outside any branch.
	float d = raster ? max(smooth_sample(depth_tex, uv, depth_texel), 0.0) : uniform_depth_m;
	float fw = max(fwidth(d), 0.001);
	float water = raster ? smooth_sample(water_tex, uv, water_texel) : 1.0;
	float fm = max(fwidth(water), 0.0001);
	vec3 col = sea_colour(d, fw);
	if (raster) {
		float shade = (smooth_sample(sea_relief_tex, uv, sea_relief_texel) * 255.0 - 128.0) / 128.0;
		col *= 1.0 + shade * sea_relief * relief;
		bool charted = uv.x >= charted_uv.x && uv.y >= charted_uv.y && uv.x <= charted_uv.z && uv.y <= charted_uv.w;
		if (!charted) {
			float land = 1.0 - clamp((water - 0.5) / fm + 0.5, 0.0, 1.0);
			if (land > 0.0) {
				col = mix(col, land_colour(uv, world), land);
			}
			// The same thin dark coastline the map strokes along the polygons, on the raster's coast.
			float edge_px = abs(water - 0.5) / fm;
			col = mix(col, COASTLINE, (1.0 - smoothstep(0.3, 1.0, edge_px)) * 0.92);
		}
	}
	COLOR = vec4(finish(col, world), 1.0);
}
