class_name ScenarioPreview
extends Control
## A small chart of the player's own starting dispositions and the objective area, drawn from
## the scenario JSON. Deliberately shows nothing about the other side: the briefing knows where
## our ships are, not where theirs are.

var scenario: Dictionary = {}
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()


func set_scenario(sc: Dictionary) -> void:
	scenario = sc
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("081320"))
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.COL_BORDER, false, 1.0)
	if scenario.is_empty():
		return
	var m: Dictionary = scenario.get("map", {})
	var c: Array = m.get("center_nm", [0, 0])
	var center := Vector2(float(c[0]), float(c[1]))
	var extent := float(m.get("extent_nm", 200.0))
	var ppn := minf(size.x, size.y) / maxf(extent, 1.0) * 0.9
	var mid := size * 0.5
	var step := 50.0 if extent > 150.0 else 20.0
	var n := int(extent / step) + 2
	for i in range(-n, n + 1):
		var x := mid.x + (i * step + (center.x - fmod(center.x, step)) - center.x) * ppn
		var y := mid.y - (i * step + (center.y - fmod(center.y, step)) - center.y) * ppn
		if x >= 0.0 and x <= size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(UITheme.COL_BORDER, 0.5), 1.0)
		if y >= 0.0 and y <= size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(UITheme.COL_BORDER, 0.5), 1.0)
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
	draw_string(_font, Vector2(10, 16), "OWN FORCE DISPOSITION", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.COL_ACCENT)
	draw_string(_font, Vector2(10, size.y - 8), "%.0f nm across · hostile positions unknown" % extent, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.COL_DIM)
