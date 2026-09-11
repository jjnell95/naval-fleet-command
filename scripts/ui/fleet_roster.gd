class_name FleetRoster
extends ItemList
## Select ships and deck aircraft without hunting for overlapping map symbols.
var map: TacticalMap
var _rows: Array[Unit] = []
var _timer := 0.0

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	add_theme_font_size_override("font_size", 12)
	add_theme_constant_override("v_separation", 7)
	item_selected.connect(func(i: int) -> void:
		if i < _rows.size() and map != null:
			map.select_units([_rows[i]]))
	item_activated.connect(func(_i: int) -> void: map.center_on_selection())

func _process(delta: float) -> void:
	_timer += delta
	if _timer < 0.5 or map == null or map.unit_manager == null:
		return
	_timer = 0.0
	clear()
	_rows.clear()
	for u in map.unit_manager.get_faction_units(map.player_faction):
		if not u.alive:
			continue
		_rows.append(u)
		var state := "AIR" if u.airborne() else ("DECK" if u.is_aircraft() else ("SUB" if u.submerged() else "SURF"))
		add_item("%s  %s" % [state, u.callsign])
		set_item_tooltip(item_count - 1, "%s\n%s\nDouble-click to center" % [u.spec.display_name, u.spec.role])
		set_item_custom_fg_color(item_count - 1, UITheme.COL_BLUE if not u.is_aircraft() else (UITheme.COL_ACCENT if u.airborne() else UITheme.COL_DIM))
		if map.selected.has(u):
			select(item_count - 1, false)
