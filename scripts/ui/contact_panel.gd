class_name ContactPanel
extends PanelContainer
## Right panel: the player's track picture. Reads Tracks only — never enemy Units.

signal track_chosen(track: Track)

const REFRESH_S := 0.5

var track_manager: TrackManager
var player_faction := "BLUE"
var map: TacticalMap

var _header: Label
var _summary: Label
var _list: ItemList
var _detail: RichTextLabel
var _rows: Array = []
var _accum := REFRESH_S


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
	_list = ItemList.new()
	_list.custom_minimum_size.y = 150
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.size_flags_stretch_ratio = 1.1
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(_on_item_selected)
	v.add_child(_list)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = false
	_detail.scroll_active = true
	_detail.selection_enabled = false
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.custom_minimum_size.y = 130
	v.add_child(_detail)
	var board := DefenceBoard.new()
	board.contacts = self
	board.custom_minimum_size.y = 236
	v.add_child(board)


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
	var tracks: Array = track_manager.get_tracks(player_faction).duplicate()
	tracks.sort_custom(func(a: Track, b: Track) -> bool:
		if (a.identity == "HOSTILE") != (b.identity == "HOSTILE"):
			return a.identity == "HOSTILE"
		return a.id < b.id)
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
	_list.clear()
	var sel_idx := -1
	for i in tracks.size():
		var t: Track = tracks[i]
		var brg := "---"
		var rng := "--"
		if ref != null:
			brg = Geo.format_bearing(Geo.bearing_deg(ref.position, t.position))
			rng = "%.0f" % Geo.distance_nm(ref.position, t.position)
		var dom := "·"
		if t.domain == "air":
			dom = "A"
		elif t.domain == "subsurface":
			dom = "S"
		elif t.domain == "surface":
			dom = "U"
		_list.add_item("%-5s %s %-7s %s/%-3s %s" % [t.id, dom, t.class_short().left(7), brg, rng, t.status_short(now)])
		var col := map.track_color(t) if map != null else TacticalMap.COL_UNKNOWN
		if t.status == Track.Status.STALE:
			col.a = 0.6
		_list.set_item_custom_fg_color(i, col)
		if map != null and map.selected_track == t:
			sel_idx = i
	if sel_idx >= 0:
		_list.select(sel_idx)
	_detail.text = _detail_text(map.selected_track if map != null else null, ref, now)


func _reference_unit() -> Unit:
	if map != null:
		return map.reference_unit()
	return null


func _kv(k: String, v: String) -> String:
	return "[color=%s]%-9s[/color] %s" % [UITheme.HEX_DIM, k, v]


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
	if t.bearing_only:
		lines.append(_kv("POS", "%s  %s" % [Geo.format_axis(t.position.x, "E", "W"), Geo.format_axis(t.position.y, "N", "S")]))
		lines.append(_kv("", "±%.1f nm along %s, ±%.1f across" % [t.error_major_nm, Geo.format_bearing(t.error_axis_deg), t.error_minor_nm]))
		lines.append(_kv("SOLUTION", "%.0f%%%s" % [t.tma_quality * 100.0, "  [color=%s]manoeuvre to refine[/color]" % UITheme.HEX_AMBER if t.tma_quality < 0.6 else ""]))
	else:
		lines.append(_kv("POS", "%s  %s  ±%.1f nm" % [Geo.format_axis(t.position.x, "E", "W"), Geo.format_axis(t.position.y, "N", "S"), t.position_error_nm]))
	if t.has_kinematics:
		lines.append(_kv("CSE/SPD", "%s / %.0f kn (est)" % [Geo.format_bearing(t.course_deg), t.speed_kn]))
	else:
		lines.append(_kv("CSE/SPD", "[color=%s]estimating…[/color]" % UITheme.HEX_DIM))
	if ref != null:
		lines.append(_kv("FROM", "%s: BRG %s  RNG %.1f nm" % [ref.callsign, Geo.format_bearing(Geo.bearing_deg(ref.position, t.position)), Geo.distance_nm(ref.position, t.position)]))
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
