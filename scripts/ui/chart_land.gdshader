shader_type canvas_item;
// The scenario's coastline polygons (ChartMesh, vertices stored as world nm with y negated), filled
// with the chart's hypsometric land tint and hill shading sampled at each fragment's world position.
// The fill's edge is not anti-aliased; the tactical map strokes a crisp coastline over it.

#include "res://scripts/ui/chart_palette.gdshaderinc"

varying vec2 world;

void vertex() {
	// VERTEX is the mesh's own vertex; the draw transform only reaches the screen through MODEL_MATRIX.
	world = vec2(VERTEX.x, -VERTEX.y);
}

void fragment() {
	COLOR = vec4(finish(land_colour(raster_uv(world), world), world), 1.0);
}
