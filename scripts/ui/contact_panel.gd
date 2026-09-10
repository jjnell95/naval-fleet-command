class_name ContactPanel
extends PanelContainer
## Right panel: the player's track picture. Reads Tracks only — never enemy Units.

signal track_chosen(track: Track)

const REFRESH_S := 0.5

var track_manager: TrackManager
var player_faction := "BLUE"
var map: TacticalMap

var _header: Label
var _list: ItemList
var _detail: Label
var _rows: Array = []
var _accum := REFRESH_S


func _ready() -> void:
	var v := VBoxContainer.new()
	add_child(v)
	_header = Label.new()
	_header.text = "CONTACTS"
	v.add_child(_header)
	_list = ItemList.new()
	_list.custom_minimum_size.y = 240
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(_on_item_selected)
	v.add_child(_list)
	_detail = Label.new()
	_detail.clip_text = true
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_detail)


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
	tracks.sort_custom(func(a: Track, b: Track) -> bool: return a.id < b.id)
	_rows = tracks
	_header.text = "CONTACTS (%d)" % tracks.size()
	_list.clear()
	var sel_idx := -1
	for i in tracks.size():
		var t: Track = tracks[i]
		var brg := "---"
		var rng := "--"
		if ref != null:
			brg = Geo.format_bearing(Geo.bearing_deg(ref.position, t.position))
			rng = "%.0f" % Geo.distance_nm(ref.position, t.position)
		_list.add_item("%s %-5s %s/%s %s" % [t.id, t.class_short(), brg, rng, t.status_short(now)])
		var col := TacticalMap.COL_HOSTILE if t.identity == "HOSTILE" else TacticalMap.COL_UNKNOWN
		if t.status == Track.Status.STALE:
			col.a = 0.6
		_list.set_item_custom_fg_color(i, col)
		if map != null and map.selected_track == t:
			sel_idx = i
	if sel_idx >= 0:
		_list.select(sel_idx)
	_detail.text = _detail_text(map.selected_track if map != null else null, ref, now)


func _reference_unit() -> Unit:
	if map != null and not map.selected.is_empty():
		return map.selected[0]
	if map != null and map.unit_manager != null:
		var own := map.unit_manager.get_faction_units(player_faction)
		if not own.is_empty():
			return own[0]
	return null


func _detail_text(t: Track, ref: Unit, now: float) -> String:
	if t == null:
		return "Click a contact on the map or in the list.\n\nUnknown contacts classify with observation time: UNK → SURF → class → identity."
	var lines := PackedStringArray()
	lines.append("%s — %s" % [t.id, t.description()])
	lines.append("IDENTITY   %s" % t.identity)
	lines.append("STATUS     %s (seen %s ago)" % [t.status_text(now), Track._fmt_age(t.age_s(now))])
	lines.append("SOURCE     %s%s" % [t.source.to_upper().replace("_", " "), "" if t.networked else "  (not on the link)"])
	if t.bearing_only:
		lines.append("POS        %s  %s" % [Geo.format_axis(t.position.x, "E", "W"), Geo.format_axis(t.position.y, "N", "S")])
		lines.append("           ±%.1f nm along brg %s, ±%.1f across" % [t.error_major_nm, Geo.format_bearing(t.error_axis_deg), t.error_minor_nm])
		lines.append("SOLUTION   %.0f%%%s" % [t.tma_quality * 100.0, "  (manoeuvre to refine)" if t.tma_quality < 0.6 else ""])
	else:
		lines.append("POS        %s  %s  ±%.1f nm" % [Geo.format_axis(t.position.x, "E", "W"), Geo.format_axis(t.position.y, "N", "S"), t.position_error_nm])
	if t.has_kinematics:
		lines.append("CSE/SPD    %s / %.0f kn (est)" % [Geo.format_bearing(t.course_deg), t.speed_kn])
	else:
		lines.append("CSE/SPD    estimating…")
	if ref != null:
		lines.append("FROM %s" % ref.callsign)
		lines.append("           BRG %s  RNG %.1f nm" % [Geo.format_bearing(Geo.bearing_deg(ref.position, t.position)), Geo.distance_nm(ref.position, t.position)])
	lines.append("OBS TIME   %s" % Track._fmt_age(t.observation_time_s))
	return "\n".join(lines)


func _on_item_selected(i: int) -> void:
	if i >= 0 and i < _rows.size():
		track_chosen.emit(_rows[i])
