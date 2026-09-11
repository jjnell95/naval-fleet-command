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
	var next: Array[Unit] = []
	for u: Unit in map.unit_manager.get_faction_units(map.player_faction):
		if u.alive:
			next.append(u)
	if next != _rows:
		var scroll := get_v_scroll_bar().value
		clear()
		_rows = next
		for u: Unit in _rows:
			add_item(u.callsign)
		get_v_scroll_bar().set_deferred("value", scroll)
	deselect_all()
	for i in _rows.size():
		var u := _rows[i]
		var state := "AIR" if u.airborne() else ("DECK" if u.is_aircraft() else ("SUB" if u.submerged() else "SURF"))
		set_item_text(i, "%s  /  %s" % [state, u.callsign])
		set_item_tooltip(i, "%s\n%s\nDouble-click to center" % [u.spec.display_name, u.spec.role])
		set_item_custom_fg_color(i, UITheme.COL_BLUE if not u.is_aircraft() else (UITheme.COL_ACCENT if u.airborne() else UITheme.COL_DIM))
		if map.selected.has(u):
			select(i, false)
