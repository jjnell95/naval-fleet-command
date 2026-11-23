class_name ChartAnnotations
extends RefCounted
## The plotting aids the commander lays on the chart: labelled position marks, range circles fixed
## at a chosen point, and corridors (a lane of a given width between two points). They are part of
## the commander's picture, not the simulation, so they are saved with the screen's own state and
## nothing in the simulation reads them. Positions are world nautical miles.

const MARK := "mark"
const CIRCLE := "circle"
const CORRIDOR := "corridor"
const PREFIX := {MARK: "M", CIRCLE: "R", CORRIDOR: "C"}
const RANK := [MARK, CIRCLE, CORRIDOR]
const CIRCLE_RADII_NM: Array[float] = [5.0, 10.0, 20.0, 50.0]
const CORRIDOR_WIDTHS_NM: Array[float] = [2.0, 5.0, 10.0]
## How close, in pixels, a right-click must come to an aid to remove it.
const PICK_PX := 14.0
const LIMIT := 64

## Each aid: {"kind", "label", "at"} and, by kind, "radius_nm" or "to" and "width_nm".
var items: Array[Dictionary] = []
## Where a corridor being laid starts, or Vector2.INF.
var corridor_from := Vector2.INF
var _counters := {MARK: 0, CIRCLE: 0, CORRIDOR: 0}


func clear() -> void:
	items.clear()
	corridor_from = Vector2.INF
	_counters = {MARK: 0, CIRCLE: 0, CORRIDOR: 0}


func is_empty() -> bool:
	return items.is_empty()


func add_mark(at: Vector2) -> String:
	return _add({"kind": MARK, "at": at})


func add_circle(at: Vector2, radius_nm: float) -> String:
	if not radius_nm > 0.0:
		return ""
	return _add({"kind": CIRCLE, "at": at, "radius_nm": radius_nm})


func start_corridor(at: Vector2) -> void:
	corridor_from = at


## Lays the corridor begun with `start_corridor` to `to`. Returns its label, or "" when none was
## begun or both ends are one point.
func end_corridor(to: Vector2, width_nm: float) -> String:
	if not corridor_from.is_finite() or corridor_from.distance_to(to) < 0.01 or not width_nm > 0.0:
		return ""
	var label := _add({"kind": CORRIDOR, "at": corridor_from, "to": to, "width_nm": width_nm})
	corridor_from = Vector2.INF
	return label


func _add(aid: Dictionary) -> String:
	if items.size() >= LIMIT or not (aid.at as Vector2).is_finite():
		return ""
	var kind: String = aid.kind
	_counters[kind] = int(_counters[kind]) + 1
	aid["label"] = "%s%d" % [PREFIX[kind], _counters[kind]]
	items.append(aid)
	return aid.label


## The index of the aid nearest `at` within `within_nm` of its mark, circle or lane, or -1. On a
## tie a mark wins over a circle and a circle over a corridor, so a mark laid inside a lane can
## still be picked out of it.
func nearest(at: Vector2, within_nm: float) -> int:
	var best := -1
	var best_d := INF
	var best_rank := 0
	for i in items.size():
		var d := distance_nm(items[i], at)
		var rank := RANK.find(str(items[i].kind))
		if d <= within_nm and (d < best_d or (d == best_d and rank < best_rank)):
			best = i
			best_d = d
			best_rank = rank
	return best


static func distance_nm(aid: Dictionary, at: Vector2) -> float:
	var centre: Vector2 = aid.at
	match str(aid.kind):
		CIRCLE:
			var from_centre := centre.distance_to(at)
			return minf(from_centre, absf(from_centre - float(aid.radius_nm)))
		CORRIDOR:
			var on_line := Geometry2D.get_closest_point_to_segment(at, centre, aid.to)
			return maxf(on_line.distance_to(at) - float(aid.width_nm) * 0.5, 0.0)
	return centre.distance_to(at)


## Removes the aid nearest `at`, returning its label, or "" when none is that close.
func remove_near(at: Vector2, within_nm: float) -> String:
	var i := nearest(at, within_nm)
	if i < 0:
		return ""
	var label: String = items[i].label
	items.remove_at(i)
	return label


## What a load needs to put the aids back.
func to_dict() -> Dictionary:
	return {"items": items.duplicate(true), "corridor_from": corridor_from, "counters": _counters.duplicate()}


## Puts saved aids back; anything malformed (or an older save with none) leaves the chart clear.
func restore(d: Variant) -> void:
	clear()
	if typeof(d) != TYPE_DICTIONARY:
		return
	for aid: Variant in d.get("items", []):
		if typeof(aid) != TYPE_DICTIONARY or not PREFIX.has(str(aid.get("kind", ""))) or not aid.get("at") is Vector2:
			continue
		if aid.kind == CORRIDOR and not aid.get("to") is Vector2:
			continue
		items.append((aid as Dictionary).duplicate(true))
	var from: Variant = d.get("corridor_from", Vector2.INF)
	corridor_from = from if from is Vector2 else Vector2.INF
	var counters: Variant = d.get("counters", {})
	for kind: String in _counters:
		if typeof(counters) == TYPE_DICTIONARY:
			_counters[kind] = int(counters.get(kind, 0))
	# A counter never runs behind a label already on the chart, so no two aids share one.
	for aid: Dictionary in items:
		var n := str(aid.get("label", "")).substr(1).to_int()
		_counters[aid.kind] = maxi(int(_counters[aid.kind]), n)


## The chart menu's "Chart marks" entries. `state` carries "mark_at" (the world point the menu was
## opened on, absent when it was not opened on the chart), "marks" (how many aids are laid),
## "corridor_from" (a corridor waiting for its far end) and "mark_near" (the aid under the click).
static func menu_items(state: Dictionary) -> Array:
	var at: Variant = state.get("mark_at", Vector2.INF)
	var here: bool = at is Vector2 and (at as Vector2).is_finite()
	var no_place := "Open this menu with a right-click on the chart to place an aid there."
	var items_out: Array = [
		CdsMenus.item("Mark this position", {"kind": "chart_mark", "op": "mark", "at": at}, not here, "A labelled mark at the point you right-clicked." if here else no_place),
	]
	var radii: Array = []
	for r in CIRCLE_RADII_NM:
		radii.append(CdsMenus.item("%s nm" % Geo.format_nm(r), {"kind": "chart_mark", "op": "circle", "at": at, "radius_nm": r}))
	items_out.append(CdsMenus.submenu("Range circle here", radii, not here, "A range circle fixed at this point, not on a platform." if here else no_place))
	if bool(state.get("corridor_from", false)):
		var widths: Array = []
		for w in CORRIDOR_WIDTHS_NM:
			widths.append(CdsMenus.item("%s nm wide" % Geo.format_nm(w), {"kind": "chart_mark", "op": "corridor_end", "at": at, "width_nm": w}))
		items_out.append(CdsMenus.submenu("End corridor here", widths, not here, "Lays the corridor from where it was started to this point."))
		items_out.append(CdsMenus.item("Cancel corridor", {"kind": "chart_mark", "op": "corridor_cancel"}))
	else:
		items_out.append(CdsMenus.item("Start a corridor here", {"kind": "chart_mark", "op": "corridor_start", "at": at}, not here, "Then right-click its far end and choose End corridor here." if here else no_place))
	items_out.append(CdsMenus.sep())
	var near := str(state.get("mark_near", ""))
	if near != "":
		items_out.append(CdsMenus.item("Remove %s" % near, {"kind": "chart_mark", "op": "remove", "at": at}))
	items_out.append(CdsMenus.item("Clear all marks", {"kind": "chart_mark", "op": "clear"}, int(state.get("marks", 0)) == 0))
	return items_out
