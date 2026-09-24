class_name ScenarioPreview
extends Control
## A small chart of the player's own starting dispositions and the objective area, drawn from
## the scenario JSON. Deliberately shows nothing about the other side: the briefing knows where
## our ships are, not where theirs are.

var scenario: Dictionary = {}
var _font: Font
var _coasts: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true  # a coastline runs past the edge of a chart this small
	_font = UITheme.body_font()


func set_scenario(sc: Dictionary) -> void:
	scenario = sc
	_coasts.clear()
	for entry in scenario.get("terrain", {}).get("land", []):
		var land := Landmass.from_dict(entry)
		if land.valid():
			_coasts.append({"land": land, "mesh": ChartMesh.build(land.points)})
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("091824"))
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.COL_BORDER, false, 1.0)
	if scenario.is_empty():
		return
	var m: Dictionary = scenario.get("map", {})
	var c: Array = m.get("center_nm", [0, 0])
	var center := Vector2(float(c[0]), float(c[1]))
	var extent := float(m.get("extent_nm", 200.0))
	var ppn := minf(size.x, size.y) / maxf(extent, 1.0) * 0.9
	var mid := size * 0.5
	# Land comes from the scenario being previewed, not from Terrain, which holds whatever
	# scenario is actually loaded. Geography is the one thing this chart shows in full.
	var transform := Transform2D(Vector2(ppn, 0), Vector2(0, ppn), mid + Vector2(-center.x, center.y)*ppn)
	for cached in _coasts:
		var l: Landmass = cached["land"]
		if cached["mesh"] != null:
			draw_mesh(cached["mesh"], null, transform, TacticalMap.COL_LAND)
		var pts := PackedVector2Array()
		for p in l.points:
			pts.append(mid + Vector2((p.x-center.x)*ppn, -(p.y-center.y)*ppn))
		pts.append(pts[0])
		draw_polyline(pts, Color(TacticalMap.COL_COAST, 0.7), 1.0, true)
	var step := 50.0 if extent > 150.0 else 20.0
	var n := int(extent / step) + 2
	for i in range(-n, n + 1):
		var x := mid.x + (i * step + (center.x - fmod(center.x, step)) - center.x) * ppn
		var y := mid.y - (i * step + (center.y - fmod(center.y, step)) - center.y) * ppn
		if x >= 0.0 and x <= size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(UITheme.COL_BORDER, 0.5), 1.0)
		if y >= 0.0 and y <= size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(UITheme.COL_BORDER, 0.5), 1.0)
	# Geographic labels orient a commander without revealing the opposing force.
	var label_rect := Rect2(Vector2(12, 38), size - Vector2(70, 86))
	for label: Dictionary in m.get("labels", []):
		var position: Array = label.get("position_nm", [0, 0])
		var point := mid + Vector2((float(position[0]) - center.x) * ppn, -(float(position[1]) - center.y) * ppn)
		if label_rect.has_point(point):
			draw_string(_font, point, str(label.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, int(size.x - point.x - 18), 13, Color(UITheme.COL_DIM, 0.8))
	var player: String = scenario.get("player_faction", "BLUE")
	for o in scenario.get("objectives", {}).get("victory", []):
		if o.get("type", "") == "reach_area":
			var oc: Array = o.get("center_nm", [0, 0])
			var op := mid + Vector2((float(oc[0]) - center.x) * ppn, -(float(oc[1]) - center.y) * ppn)
			draw_arc(op, float(o.get("radius_nm", 5.0)) * ppn, 0.0, TAU, 40, Color(TacticalMap.COL_WAYPOINT, 0.8), 1.5, true)
	for ud in scenario.get("units", []):
		if ud.get("faction", "") != player or not ud.has("position_nm"):
			continue
		var p: Array = ud["position_nm"]
		var sp := mid + Vector2((float(p[0]) - center.x) * ppn, -(float(p[1]) - center.y) * ppn)
		var spec := DataDB.platform(ud.get("platform", ""))
		var domain := spec.domain if spec != null else "surface"
		var glyph := MapSymbols.category_glyph(spec.category, spec.domain) if spec != null else ""
		MapSymbols.draw_symbol(self, sp, TacticalMap.COL_FRIENDLY, MapSymbols.Frame.FRIENDLY, domain, float(ud.get("heading_deg", 0.0)), true, glyph, _font, 0.8)
	draw_rect(Rect2(1, 1, size.x - 2, 30), Color("091824", 0.94))
	draw_rect(Rect2(1, size.y - 30, size.x - 2, 29), Color("091824", 0.94))
	draw_string(_font, Vector2(12, 21), "OWN FORCE DISPOSITION", HORIZONTAL_ALIGNMENT_LEFT, int(size.x - 44), 13, UITheme.COL_AMBER)
	draw_string(_font, Vector2(size.x - 27, 21), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.COL_TEXT)
	draw_line(Vector2(size.x - 23, 44), Vector2(size.x - 23, 29), UITheme.COL_DIM, 1.5, true)
	draw_line(Vector2(size.x - 23, 29), Vector2(size.x - 27, 35), UITheme.COL_DIM, 1.5, true)
	draw_line(Vector2(size.x - 23, 29), Vector2(size.x - 19, 35), UITheme.COL_DIM, 1.5, true)
	draw_string(_font, Vector2(12, size.y - 11), "%.0f nm wide  ·  Own force only" % (size.x / ppn), HORIZONTAL_ALIGNMENT_LEFT, int(size.x - 24), 13, UITheme.COL_DIM)
