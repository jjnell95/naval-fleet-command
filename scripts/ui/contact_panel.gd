class_name ContactPanel
extends PanelContainer
## Right panel: the player's track picture. Reads Tracks only — never enemy Units.

signal track_chosen(track: Track)

const REFRESH_S := 0.5
const RowList = preload("res://scripts/ui/tactical_row_list.gd")

var track_manager: TrackManager
var player_faction := "BLUE"
var map: TacticalMap

var _filter := "ALL"
var _header: Label
var _summary: Label
var _list: RowList
var _detail: RichTextLabel
var _focus_btn: Button
var _prev_btn: Button
var _next_btn: Button
var _rows: Array = []
var _accum := REFRESH_S
var _shown_selection: Track


func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var hl := Label.new()
	hl.text = "TRACK FILE"
	hl.theme_type_variation = "HeaderLabel"
	v.add_child(hl)
	_header = Label.new()
	_header.text = "0 contacts"
	_header.theme_type_variation = "TitleLabel"
	v.add_child(_header)
	_summary = Label.new()
	_summary.theme_type_variation = "DimLabel"
	_summary.clip_text = true
	v.add_child(_summary)
	var filter_frame := PanelContainer.new()
	filter_frame.theme_type_variation = "SegmentedPanel"
	v.add_child(filter_frame)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 2)
	filter_frame.add_child(filters)
	var group := ButtonGroup.new()
	for domain in ["ALL", "AIR", "SURF", "SUB"]:
		var b := Button.new()
		b.text = domain
		b.theme_type_variation = "SegmentButton"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = domain == "ALL"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 28
		b.focus_mode = Control.FOCUS_ALL
		b.tooltip_text = "Filter the contact list to %s tracks" % domain.to_lower()
		b.pressed.connect(func() -> void: _filter = domain; refresh())
		filters.add_child(b)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	v.add_child(actions)
	_prev_btn = _nav_button("", "Previous priority contact  [Shift+N]", func() -> void: cycle_visible_track(-1))
	UIIcons.apply(_prev_btn, "chevron_left", 18)
	_prev_btn.custom_minimum_size.x = 36
	actions.add_child(_prev_btn)
	_focus_btn = _nav_button("FOCUS CONTACT", "Center the selected contact without changing zoom  [C]", _focus_current)
	UIIcons.apply(_focus_btn, "focus", 16)
	_focus_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_focus_btn)
	_next_btn = _nav_button("", "Next priority contact  [N]", func() -> void: cycle_visible_track(1))
	UIIcons.apply(_next_btn, "chevron_right", 18)
	_next_btn.custom_minimum_size.x = 36
	actions.add_child(_next_btn)
	_list = RowList.new()
	_list.configure_rows(13, 12, 36)
	_list.max_text_lines = 2
	_list.custom_minimum_size.y = 112
	_list.add_theme_font_size_override("font_size", 13)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.size_flags_stretch_ratio = 1.1
	_list.resized.connect(func() -> void: _list.fixed_column_width = maxi(int(_list.size.x) - 24, 100))
	_list.focus_mode = Control.FOCUS_ALL
	_list.tooltip_text = "Held contacts, ordered by identity, freshness and distance. Enter focuses a selected contact."
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(func(_i: int) -> void: _focus_current())
	v.add_child(_list)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = false
	_detail.scroll_active = true
	_detail.selection_enabled = false
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.custom_minimum_size.y = 95
	v.add_child(_detail)
	var board := DefenceBoard.new()
	board.contacts = self
	board.custom_minimum_size.y = 196
	v.add_child(board)
	_sync_nav_buttons()


func _nav_button(text: String, tip: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size.y = 32
	button.accessibility_name = tip.get_slice("  [", 0)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(action)
	return button


func _sync_nav_buttons() -> void:
	if _focus_btn == null:
		return
	var empty := _rows.is_empty()
	_focus_btn.disabled = map == null or map.selected_track == null
	_prev_btn.disabled = empty
	_next_btn.disabled = empty


func visible_track_count() -> int:
	return _rows.size()


func visible_tracks() -> Array:
	return _rows.duplicate()


## Buttons, N/Shift-N, and the command palette share this filtered sequence so the selected
## contact always remains present in the visible Track File.
func cycle_visible_track(step: int) -> Track:
	if map == null:
		return null
	refresh()
	if _rows.is_empty():
		return null
	var index := _rows.find(map.selected_track)
	index = posmod(index + step, _rows.size()) if index >= 0 else (_rows.size() - 1 if step < 0 else 0)
	var next := _rows[index] as Track
	map.select_track(next)
	map.set_follow_selection(false)
	map.center_on(next.position)
	refresh()
	call_deferred("_ensure_selected_visible")
	return next


func _ensure_selected_visible() -> void:
	if _list == null or map == null:
		return
	var index := _rows.find(map.selected_track)
	if index >= 0:
		_list.select(index)
		_list.ensure_current_is_visible()


func _focus_current() -> void:
	if map == null or map.selected_track == null:
		return
	map.set_follow_selection(false)
	map.center_on(map.selected_track.position)


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= REFRESH_S:
		_accum = 0.0
		refresh()


func refresh() -> void:
	if track_manager == null:
		return
	var now := SimClock.sim_time
	var ref := _reference_unit()
	var tracks: Array = map.priority_tracks() if map != null else (track_manager.tracks_for(ref) if ref != null else track_manager.get_tracks(player_faction)).duplicate()
	if _filter != "ALL":
		var domain: String = {"AIR": "air", "SURF": "surface", "SUB": "subsurface"}[_filter]
		tracks = tracks.filter(func(t: Track) -> bool: return t.domain == domain)
	if map == null:
		tracks.sort_custom(func(a: Track, b: Track) -> bool: return TacticalMap._track_precedes(a, b, ref))
	_rows = tracks
	var hostile := 0
	var unknown := 0
	var stale := 0
	for t: Track in tracks:
		if t.identity == "HOSTILE":
			hostile += 1
		elif t.identity == "UNKNOWN":
			unknown += 1
		if t.status == Track.Status.STALE:
			stale += 1
	_header.text = "%d contact%s" % [tracks.size(), "" if tracks.size() == 1 else "s"]
	_summary.text = "%d hostile · %d unknown · %d stale" % [hostile, unknown, stale]
	var scroll := _list.get_v_scroll_bar().value
	var selection_changed := map != null and map.selected_track != _shown_selection
	_list.clear_rows()
	var sel_idx := -1
	for i in tracks.size():
		var t: Track = tracks[i]
		var brg := "---"
		var rng := "--"
		if ref != null:
			brg = Geo.format_bearing(Geo.bearing_deg(ref.position, t.position))
			rng = "?" if t.is_bearing_only() else "~%.0f" % Geo.distance_nm(ref.position, t.position)
		var dom := "·"
		if t.domain == "air":
			dom = "A"
		elif t.domain == "subsurface":
			dom = "S"
		elif t.domain == "surface":
			dom = "U"
		var title := "%s  %s  %s" % [t.id, dom, t.class_short()]
		var detail := "%s  /  %s nm  ·  %s" % [brg, rng, t.status_short(now)]
		var col := map.track_color(t) if map != null else TacticalMap.COL_UNKNOWN
		if t.status == Track.Status.STALE:
			col.a = 0.6
		_list.add_row(title, detail, col)
		_list.set_item_tooltip(i, title + "\n" + detail + "\n" + t.identity)
		if map != null and map.selected_track == t:
			sel_idx = i
	if sel_idx >= 0:
		_list.select(sel_idx)
		if selection_changed:
			call_deferred("_ensure_selected_visible")
		else:
			_list.get_v_scroll_bar().set_deferred("value", scroll)
	else:
		_list.get_v_scroll_bar().set_deferred("value", scroll)
	_shown_selection = map.selected_track if map != null else null
	_detail.text = _detail_text(map.selected_track if map != null else null, ref, now)
	_sync_nav_buttons()


func _reference_unit() -> Unit:
	if map != null:
		return map.reference_unit()
	return null


func _kv(k: String, v: String) -> String:
	return "[color=%s][font_size=11]%-9s[/font_size][/color] %s" % [UITheme.HEX_MUTED, k, v]


func _detail_text(t: Track, ref: Unit, now: float) -> String:
	if t == null:
		return "[color=%s]Click a contact on the map or in the list.\n\nContacts classify with observation time: UNKNOWN → domain → class → identity. A bearing-only sonar contact firms up as the listener manoeuvres.[/color]" % UITheme.HEX_DIM
	var hex := UITheme.HEX_AMBER
	if t.identity == "HOSTILE":
		hex = UITheme.HEX_RED
	elif t.identity == "NEUTRAL":
		hex = UITheme.HEX_GREEN
	var lines := PackedStringArray()
	lines.append("[b][color=%s]%s[/color][/b]  %s" % [hex, t.id, t.description()])
	lines.append(_kv("IDENTITY", "[color=%s]%s[/color]" % [hex, t.identity]))
	lines.append(_kv("STATUS", "%s · seen %s ago" % [t.status_text(now), Track._fmt_age(t.age_s(now))]))
	lines.append(_kv("SOURCE", "%s%s" % [t.source.to_upper().replace("_", " "), "" if t.networked else "  [color=%s]not on the link[/color]" % UITheme.HEX_AMBER]))
	if t.is_bearing_only():
		lines.append(_kv("RANGE", "[color=%s]UNRESOLVED · bearing only[/color]" % UITheme.HEX_AMBER))
		lines.append(_kv("", "±%.1f nm along %s, ±%.1f across" % [t.error_major_nm, Geo.format_bearing(t.error_axis_deg), t.error_minor_nm]))
		lines.append(_kv("SOLUTION", "%.0f%%%s" % [t.tma_quality * 100.0, "  [color=%s]manoeuvre to refine[/color]" % UITheme.HEX_AMBER if t.tma_quality < 0.6 else ""]))
	else:
		lines.append(_kv("POS", "%s  %s  ±%.1f nm" % [Geo.format_axis(t.position.x, "E", "W"), Geo.format_axis(t.position.y, "N", "S"), t.position_error_nm]))
	if t.has_kinematics:
		lines.append(_kv("CSE/SPD", "%s / %.0f kn (est)" % [Geo.format_bearing(t.course_deg), t.speed_kn]))
	else:
		lines.append(_kv("CSE/SPD", "[color=%s]estimating…[/color]" % UITheme.HEX_DIM))
	if ref != null:
		lines.append(_kv("FROM", "%s: BRG %s" % [ref.callsign, Geo.format_bearing(Geo.bearing_deg(ref.position, t.position))]))
		lines.append(_kv("RANGE", t.range_text_from(ref.position)))
		var motion := RelativeMotion.solution(ref, t, now)
		if motion.valid:
			lines.append(_kv("CPA", "~%.1f nm in %s (est)" % [motion.distance_nm, Track._fmt_age(motion.time_s)]))
			lines.append(_kv("CLOSING", "%.0f kn · constant course" % motion.closing_kn))
		if ref.radar_emitting() and Detection.is_jammed_toward(ref, t.position):
			lines.append(_kv("EW", "[color=#f08cf0]radar jammed on this bearing[/color]"))
	lines.append(_kv("OBS TIME", Track._fmt_age(t.observation_time_s)))
	if t.classification < Track.Classification.CLASS_KNOWN:
		var next_s := Track.CLASS_TIMES_S[mini(t.classification + 1, Track.CLASS_TIMES_S.size() - 1)]
		lines.append(_kv("NEXT", "[color=%s]class in ~%s of observation[/color]" % [UITheme.HEX_DIM, Track._fmt_age(maxf(next_s - t.observation_time_s, 0.0))]))
	return "\n".join(lines)


func _on_item_selected(i: int) -> void:
	if i >= 0 and i < _rows.size():
		track_chosen.emit(_rows[i])
