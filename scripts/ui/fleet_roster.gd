class_name FleetRoster
extends ItemList
## Select ships and deck aircraft without hunting for overlapping map symbols.
var map: TacticalMap
var _rows: Array[Unit] = []
var _timer := 0.0

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	select_mode = ItemList.SELECT_MULTI
	tooltip_text = "Friendly force roster. Use Command/Control to select a group; press Enter to focus it on the map."
	add_theme_font_size_override("font_size", 12)
	add_theme_constant_override("v_separation", 10)
	item_selected.connect(func(_i: int) -> void: _push_selection())
	multi_selected.connect(func(_i: int, _selected: bool) -> void: _push_selection())
	item_activated.connect(func(_i: int) -> void: map.center_on_selection())


func _push_selection() -> void:
	if map == null:
		return
	var units: Array[Unit] = []
	for index in get_selected_items():
		if index >= 0 and index < _rows.size():
			units.append(_rows[index])
	map.select_units(units)

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
		if u.is_aircraft():
			if u.flight_state == Unit.FlightState.RECOVERING:
				state = "LAND"
			elif u.returning:
				state = "RTB"
			elif u.flight_state == Unit.FlightState.TURNAROUND:
				state = "REARM"
		set_item_text(i, "%s  /  %s" % [state, u.callsign])
		set_item_tooltip(i, "%s\n%s\nDouble-click to center" % [u.spec.display_name, u.spec.role])
		set_item_custom_fg_color(i, UITheme.COL_BLUE if not u.is_aircraft() else (UITheme.COL_ACCENT if u.in_flight() else UITheme.COL_DIM))
		if map.selected.has(u):
			select(i, false)
