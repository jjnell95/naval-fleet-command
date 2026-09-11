class_name ReadinessBars
extends Control
## Horizontal readiness bars for one unit: hull, subsystems, fuel, decoys. Drawn, not text, so
## the state of a ship is readable at a glance from across the room.

var unit: Unit
var _font: Font

const ROW_H := 17.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UITheme.body_font()


func _process(_delta: float) -> void:
	queue_redraw()


func rows_for(u: Unit) -> Array:
	if u == null:
		return []
	var rows: Array = []
	rows.append({"label": "HULL", "value": Damage.health_fraction(u), "kind": "hull"})
	rows.append({"label": "PROP", "value": u.component("propulsion"), "kind": "sys"})
	rows.append({"label": "SENS", "value": u.component("sensors"), "kind": "sys"})
	rows.append({"label": "WPNS", "value": u.component("weapons"), "kind": "sys"})
	if u.is_aircraft():
		rows.append({"label": "FUEL", "value": u.fuel_fraction(), "kind": "fuel"})
	if u.spec.decoy_count > 0:
		rows.append({"label": "DCOY", "value": float(u.decoys) / maxf(float(u.spec.decoy_count), 1.0), "kind": "stock", "text": "%d" % u.decoys})
	return rows


func preferred_height(u: Unit) -> float:
	return rows_for(u).size() * ROW_H + 4.0


func _draw() -> void:
	if unit == null or _font == null:
		return
	var rows := rows_for(unit)
	var y := 2.0
	var label_w := 40.0
	var bar_x := label_w + 6.0
	var bar_w := size.x - bar_x - 44.0
	for r: Dictionary in rows:
		var v: float = clampf(float(r["value"]), 0.0, 1.0)
		var col := UITheme.COL_ACCENT
		if v < 0.55:
			col = UITheme.COL_RED
		elif v < 0.85:
			col = UITheme.COL_AMBER
		if r["kind"] == "fuel" and v < 0.3:
			col = UITheme.COL_RED
		draw_string(_font, Vector2(0, y + 12), r["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.COL_DIM)
		draw_rect(Rect2(bar_x, y + 7, bar_w, 3), Color("13232f"))
		draw_rect(Rect2(bar_x, y + 7, bar_w * v, 3), Color(col, 0.85))
		if r["kind"] == "sys" and v < Damage.REPAIR_CAP - 1e-4 and Damage.repairing(unit):
			var mark := bar_x + bar_w * Damage.REPAIR_CAP
			draw_line(Vector2(mark, y + 2), Vector2(mark, y + 13), Color(UITheme.COL_AMBER, 0.7), 1.0)
		var text: String = r.get("text", "%d%%" % int(round(v * 100.0)))
		draw_string(_font, Vector2(bar_x + bar_w + 6, y + 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		y += ROW_H
