class_name DefenceBoard
extends Control
## Threat evaluation and weapons assignment board. Reads only friendly readiness and already
## detected threats: no ground-truth enemy access.

var contacts: ContactPanel
var _timer := 0.0
var _font: Font


func _ready() -> void:
	_font = UITheme.body_font()
	tooltip_text = "Detected inbound weapons only. Channel load counts anti-aircraft and missile interception engagements. Magazine counts are rounds, not VLS cells. Emissions and damage affect readiness."


func _process(delta: float) -> void:
	_timer += delta
	if _timer > 0.2:
		_timer = 0
		queue_redraw()


## "USS Gettysburg" reads as "Gettysburg" where the row is tight.
func _short_name(callsign: String) -> String:
	for prefix in ["USS ", "HMS ", "HNoMS ", "HDMS ", "FGS ", "MV ", "Carrier "]:
		if callsign.begins_with(prefix):
			return callsign.trim_prefix(prefix)
	return callsign


func _draw() -> void:
	var frame := StyleBoxFlat.new()
	frame.bg_color = UITheme.COL_PANEL_DEEP
	frame.border_color = UITheme.COL_HAIRLINE
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(UITheme.RADIUS)
	draw_style_box(frame, Rect2(Vector2.ZERO, size))
	draw_string(UITheme.eyebrow_font(), Vector2(12, 20), "AIR DEFENCE", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.SIZE_EYEBROW, UITheme.COL_MUTED)
	if contacts == null or contacts.map == null or contacts.map.unit_manager == null:
		return
	var m := contacts.map
	var threats := AirDefence.inbound_threats(m.unit_manager, m.threat_manager, m.player_faction, m.reference_unit())
	var loads := AirDefence._channels_in_use(m.weapon_manager)
	var rounds := 0
	var bmd_rounds := 0
	var channels := 0
	var used := 0
	var ships: Array = []
	for u in m.unit_manager.get_faction_units(m.player_faction):
		if not u.alive or u.is_aircraft():
			continue
		if u.spec.fire_control_channels > 0:
			ships.append(u)
		if u.can_fire():
			channels += u.spec.fire_control_channels
		used += int(loads.get(u, 0))
		for w in u.defensive_weapons():
			if w.type != "sam":
				continue
			rounds += u.magazine_count(w.id)
			if w.target_types.has("ballistic") and w.type == "sam":
				bmd_rounds += u.magazine_count(w.id)
	var status_col := UITheme.COL_AMBER if not threats.is_empty() else UITheme.COL_ACCENT
	var right := "%d SAM" % rounds
	var rw := _font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(_font, Vector2(size.x - rw - 12, 19), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.COL_DIM)
	var y := 38.0
	if threats.is_empty():
		draw_string(_font, Vector2(12, y), "NO DETECTED INBOUND WEAPONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.COL_DIM)
		y += 18.0
	else:
		draw_string(_font, Vector2(12, y), "%02d INBOUND" % threats.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, status_col)
		y += 6.0
		var committed := AirDefence._count_committed(m.weapon_manager)
		for i in mini(4, threats.size()):
			var t: Dictionary = threats[i]
			var w: Weapon = t["weapon"]
			var tti := float(t["time_s"])
			var assigned := int(committed.get(w.id, 0))
			var col := UITheme.COL_RED if tti < 30.0 else UITheme.COL_AMBER
			y += 16.0
			var kind := "BM" if w.threat_class() == "ballistic" else ("TORP" if w.spec.is_torpedo() else "MSL")
			draw_rect(Rect2(12, y - 10, 3, 12), col)
			var tail := "%ds · %d up" % [int(tti), assigned]
			var tw := _font.get_string_size(tail, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(_font, Vector2(20, y), "%s %s" % [kind, w.spec.family.left(12)], HORIZONTAL_ALIGNMENT_LEFT, int(size.x * 0.42), 11, col)
			draw_string(_font, Vector2(size.x * 0.44, y), "→ %s" % _short_name((t["target"] as Unit).callsign), HORIZONTAL_ALIGNMENT_LEFT, int(size.x - size.x * 0.44 - tw - 20), 10, UITheme.COL_TEXT)
			draw_string(_font, Vector2(size.x - tw - 12, y), tail, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		if threats.size() > 4:
			y += 14.0
			draw_string(_font, Vector2(20, y), "+%d more" % (threats.size() - 4), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.COL_DIM)
		y += 12.0
	# Per-shooter channel load.
	y += 8.0
	draw_string(_font, Vector2(12, y), "CHANNELS %d / %d" % [used, channels], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.COL_DIM)
	y += 6.0
	for u: Unit in ships:
		if y > size.y - 14.0:
			break
		y += 14.0
		var total := u.spec.fire_control_channels
		var busy := int(loads.get(u, 0))
		var name := _short_name(u.callsign)
		if name.length() > 16:
			name = name.get_slice(" (", 0).left(16)
		draw_string(_font, Vector2(12, y), name, HORIZONTAL_ALIGNMENT_LEFT, 118, 10, UITheme.COL_TEXT if u.can_fire() else UITheme.COL_RED)
		var bx := 136.0
		var bw := size.x - bx - 12.0
		var seg := bw / maxf(float(total), 1.0)
		for i in total:
			var filled := i < busy
			var c := UITheme.COL_ACCENT if filled else UITheme.COL_HAIRLINE.lightened(0.08)
			if not u.can_fire():
				c = Color(UITheme.COL_RED, 0.4)
			draw_rect(Rect2(bx + i * seg, y - 8, maxf(seg - 2.0, 1.0), 8), c)
