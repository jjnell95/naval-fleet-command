class_name FleetRoster
extends ItemList
## Select ships and deck aircraft without hunting for overlapping map symbols.
signal unit_located(position: Vector2)

var map: TacticalMap
var _rows: Array[Unit] = []
var _timer := 0.0
var _terms := PackedStringArray()

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	select_mode = ItemList.SELECT_MULTI
	tooltip_text = "Ctrl- or Command-click to select several platforms. Double-click a row or press Enter to show it on the chart."
	add_theme_font_size_override("font_size", 12)
	add_theme_constant_override("v_separation", 10)
	item_selected.connect(func(_i: int) -> void: _push_selection())
	multi_selected.connect(func(_i: int, _selected: bool) -> void: _push_selection())
	item_activated.connect(_locate_row)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_refresh())


func _locate_row(index: int) -> void:
	if map == null or index < 0 or index >= _rows.size():
		return
	var unit := _rows[index]
	if not unit.alive or unit.faction != map.player_faction:
		return
	var source := unit.home if unit.is_aircraft() and not unit.in_flight() and unit.home != null else unit
	if not source.alive or source.faction != map.player_faction:
		return
	if not SubmarineComms.connected(source) and not source.comms_report.has("position"):
		return
	var plot := SubmarineComms.reported_position(source)
	if plot.is_finite():
		unit_located.emit(plot)


func _push_selection() -> void:
	if map == null:
		return
	var units: Array[Unit] = []
	# Ctrl/Command and Shift extend a selection across searches. A plain click replaces it.
	if not _terms.is_empty() and (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_SHIFT)):
		for u: Unit in map.selected:
			if u.alive and not _rows.has(u):
				units.append(u)
	for index in get_selected_items():
		if index >= 0 and index < _rows.size():
			units.append(_rows[index])
	map.select_units(units)


func filter_by(query: String) -> void:
	_terms = query.to_lower().split(" ", false)
	_refresh(true)


func focus_results(query: String) -> void:
	if _rows.is_empty():
		return
	grab_focus()
	# A carrier's whole air wing can contain its callsign, and "Flight 1" can match "Flight 10".
	var exact := query.strip_edges().to_lower()
	var matches := _rows.filter(func(u: Unit) -> bool: return u.callsign.to_lower() == exact)
	if matches.size() == 1 or _rows.size() == 1:
		var match_unit: Unit = matches[0] if matches.size() == 1 else _rows[0]
		select(_rows.find(match_unit))
		ensure_current_is_visible()
		map.select_units([match_unit])


func _matches(u: Unit) -> bool:
	if _terms.is_empty():
		return true
	var text := ("%s %s %s" % [u.callsign, u.spec.display_name, u.spec.short_name]).to_lower()
	for term: String in _terms:
		if not text.contains(term):
			return false
	return true


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.5:
		_refresh()


func _refresh(query_changed := false) -> void:
	_timer = 0.0
	if map == null or map.unit_manager == null:
		return
	var next: Array[Unit] = []
	for u: Unit in map.unit_manager.get_faction_units(map.player_faction):
		if u.alive and _matches(u):
			next.append(u)
	if query_changed or next != _rows:
		var scroll := 0.0 if query_changed else get_v_scroll_bar().value
		clear()
		_rows = next
		for u: Unit in _rows:
			add_item(u.callsign)
		if _rows.is_empty() and not _terms.is_empty():
			add_item("No matching friendly platforms")
			set_item_disabled(0, true)
		get_v_scroll_bar().set_deferred("value", scroll)
	for i in _rows.size():
		var u := _rows[i]
		var state := "AIR" if u.airborne() else ("DECK" if u.is_aircraft() else ("SUB" if u.submerged() else ("SHORE" if u.spec.domain == "land" else "SURF")))
		if u.is_aircraft():
			if u.flight_state == Unit.FlightState.RECOVERING:
				state = "LAND"
			elif u.returning:
				state = "RTB"
			elif u.flight_state == Unit.FlightState.TURNAROUND:
				state = "REARM"
			elif u.flight_state == Unit.FlightState.RESERVE:
				state = "RESERVE"
		set_item_text(i, "%s  /  %s" % [state, u.callsign])
		set_item_tooltip(i, "%s\n%s\nDouble-click to center" % [u.spec.display_name, u.spec.role])
		set_item_custom_fg_color(i, UITheme.COL_BLUE if not u.is_aircraft() else (UITheme.COL_ACCENT if u.in_flight() else UITheme.COL_DIM))
	sync_selection(map.selected)


func sync_selection(units: Array) -> void:
	for i in _rows.size():
		if is_selected(i) != units.has(_rows[i]):
			if is_selected(i):
				deselect(i)
			else:
				select(i, false)
