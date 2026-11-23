class_name ScenarioPreview
extends Control
## A small chart of the player's own starting dispositions and the objective area, drawn from
## the scenario JSON. Deliberately shows nothing about the other side: the briefing knows where
## our ships are, not where theirs are. Drawn in the chart's own palette, deep blue sea and green
## land, inside the three-line frame, like the mission map on a late-1990s operations desk.

## The own-force symbols are drawn a little smaller than on the chart; a map name keeps this far
## from the symbol's centre (its frame and heading tick) so it never prints across a ship.
const SYMBOL_SCALE := 0.8
const SYMBOL_CLEAR_PX := (MapSymbols.RADIUS + MapSymbols.HEADING_TICK) * SYMBOL_SCALE
## A map name that would print over the force moves this far up or down, a line at a time, before
## it is left off: the name of the cape the force is rounding still belongs on the chart.
const LABEL_STEP_PX := 13.0
const LABEL_TRIES := 3

var scenario: Dictionary = {}
var _font: Font
var _coasts: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true  # a coastline runs past the edge of a chart this small
	_font = UITheme.data_font()


func set_scenario(sc: Dictionary) -> void:
	scenario = sc
	_coasts.clear()
	for entry in scenario.get("terrain", {}).get("land", []):
		var land := Landmass.from_dict(entry)
		if land.valid():
			_coasts.append({"land": land, "mesh": ChartMesh.build(land.points)})
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.CHART_SEA)
	if scenario.is_empty():
		UITheme.draw_bevel_frame(self, Rect2(Vector2.ZERO, size))
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
	var outlines: Array[PackedVector2Array] = []
	for cached in _coasts:
		var l: Landmass = cached["land"]
		var pts := PackedVector2Array()
		for p in l.points:
			pts.append(mid + Vector2((p.x-center.x)*ppn, -(p.y-center.y)*ppn))
		pts.append(pts[0])
		outlines.append(pts)
		# A band of shallow water along every coast, under the land.
		draw_polyline(pts, UITheme.CHART_SHALLOW, 7.0, true)
	for i in _coasts.size():
		if _coasts[i]["mesh"] != null:
			draw_mesh(_coasts[i]["mesh"], null, transform, UITheme.CHART_LAND)
		draw_polyline(outlines[i], UITheme.CHART_COAST, 1.0, true)
	var layout := label_layout()
	for placed: Dictionary in layout["labels"]:
		_text(placed["point"], placed["text"], 10, Color(1, 1, 1, 0.85))
	for o in scenario.get("objectives", {}).get("victory", []):
		if o.get("type", "") in ["reach_area", "hold_area"]:
			var oc: Array = o.get("center_nm", [0, 0])
			var op := mid + Vector2((float(oc[0]) - center.x) * ppn, -(float(oc[1]) - center.y) * ppn)
			draw_arc(op, float(o.get("radius_nm", 5.0)) * ppn, 0.0, TAU, 40, Color.WHITE, 1.0, true)
	for unit: Dictionary in layout["force"]:
		MapSymbols.draw_symbol(self, unit["point"], TacticalMap.COL_FRIENDLY, MapSymbols.Frame.FRIENDLY, unit["domain"], unit["heading"], true, unit["glyph"], _font, SYMBOL_SCALE)
	_text(Vector2(size.x - 20, 22), "N", 12, Color.WHITE)
	draw_line(Vector2(size.x - 16, 42), Vector2(size.x - 16, 28), Color.WHITE, 1.5, true)
	draw_line(Vector2(size.x - 16, 28), Vector2(size.x - 20, 34), Color.WHITE, 1.5, true)
	draw_line(Vector2(size.x - 16, 28), Vector2(size.x - 12, 34), Color.WHITE, 1.5, true)
	_text(Vector2(10, size.y - 10), "%.0f nmi  ·  own force only" % (size.x / ppn), 11, Color.WHITE)
	UITheme.draw_bevel_frame(self, Rect2(Vector2.ZERO, size))


## Where this chart puts the player's own units and the geographic names, in the control's own
## pixels: {"force": [{point, domain, heading, glyph}], "symbols": [Rect2], "labels": [{point,
## text, rect}]}. The force is placed first and its symbols are reserved, so a name never prints
## across a ship; a name that would print over another name or over the force moves a line up or
## down, and is left off only when no nearby line is clear (the chart is small).
func label_layout() -> Dictionary:
	var out := {"force": [], "symbols": [], "labels": []}
	if scenario.is_empty() or _font == null:
		return out
	var m: Dictionary = scenario.get("map", {})
	var c: Array = m.get("center_nm", [0, 0])
	var center := Vector2(float(c[0]), float(c[1]))
	var ppn := minf(size.x, size.y) / maxf(float(m.get("extent_nm", 200.0)), 1.0) * 0.9
	var mid := size * 0.5
	var player: String = scenario.get("player_faction", "BLUE")
	var occupied: Array[Rect2] = []
	for ud in scenario.get("units", []):
		if ud.get("faction", "") != player or not ud.has("position_nm"):
			continue
		var p: Array = ud["position_nm"]
		var sp := mid + Vector2((float(p[0]) - center.x) * ppn, -(float(p[1]) - center.y) * ppn)
		var spec := DataDB.platform(ud.get("platform", ""))
		out["force"].append({"point": sp, "domain": spec.domain if spec != null else "surface",
			"heading": float(ud.get("heading_deg", 0.0)),
			"glyph": MapSymbols.category_glyph(spec.category, spec.domain) if spec != null else ""})
		var symbol := Rect2(sp - Vector2.ONE * SYMBOL_CLEAR_PX, Vector2.ONE * SYMBOL_CLEAR_PX * 2.0)
		out["symbols"].append(symbol)
		occupied.append(symbol)
	var label_rect := Rect2(Vector2(8, 24), size - Vector2(60, 50))
	for label: Dictionary in m.get("labels", []):
		var position: Array = label.get("position_nm", [0, 0])
		var anchor := mid + Vector2((float(position[0]) - center.x) * ppn, -(float(position[1]) - center.y) * ppn)
		if not label_rect.has_point(anchor):
			continue
		var text := str(label.get("text", ""))
		var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		if label.get("kind", "land") == "water":
			anchor.x = roundf(anchor.x - width * 0.5)
			if anchor.x < 4.0:
				continue  # a sea name centred on a point near the edge would run off the chart
		for attempt in LABEL_TRIES * 2 + 1:
			# 0, one line down, one line up, two down, two up...
			var dy := LABEL_STEP_PX * floorf((attempt + 1) * 0.5) * (1.0 if attempt % 2 == 1 else -1.0)
			var point := anchor + Vector2(0.0, dy)
			if not label_rect.has_point(point):
				continue
			var rect := Rect2(point.x, point.y - 9.0, minf(width, size.x - point.x - 8.0), 12.0)
			var collides := false
			for other in occupied:
				if other.grow(4.0).intersects(rect):
					collides = true
					break
			if collides:
				continue
			occupied.append(rect)
			out["labels"].append({"point": point, "text": text, "rect": rect})
			break
	return out


## White bold text with a one-pixel black shadow, the chart's text style.
func _text(at: Vector2, text: String, font_size: int, color: Color) -> void:
	var width := int(size.x - at.x - 8)
	draw_string(_font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, Color(0, 0, 0, 0.85 * color.a))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)
