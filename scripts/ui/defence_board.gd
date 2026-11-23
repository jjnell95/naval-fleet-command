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
	visibility_changed.connect(_sync_visibility)
	_sync_visibility()


func _sync_visibility() -> void:
	set_process(is_visible_in_tree())
	if is_visible_in_tree():
		_timer = 0.0
		queue_redraw()


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


const ROW_H := 16.0
const SHIP_ROW_H := 14.0
## Kept clear under the inbound rows: the "+N more" line, the channel line and one shooter.
const ROWS_RESERVE := 14.0 + 8.0 + 6.0 + 14.0 + SHIP_ROW_H


func _draw() -> void:
	var frame := StyleBoxFlat.new()
	frame.bg_color = UITheme.COL_PANEL_DEEP
	frame.border_color = UITheme.COL_HAIRLINE
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(UITheme.RADIUS)
	draw_style_box(frame, Rect2(Vector2.ZERO, size))
	draw_string(UITheme.eyebrow_font(), Vector2(12, 20), "AIR DEFENCE", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.SIZE_EYEBROW, UITheme.COL_MUTED)
	var board := layout()
	if board.is_empty():
		return
	var right: String = board["rounds"]
	var rw := _font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(_font, Vector2(size.x - rw - 12, 19), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.COL_DIM)
	var y := 38.0
	var rows: Array = board["rows"]
	if int(board["inbound"]) == 0:
		draw_string(_font, Vector2(12, y), "NO DETECTED INBOUND WEAPONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.COL_DIM)
		y += 18.0
	else:
		draw_string(_font, Vector2(12, y), "%02d INBOUND" % int(board["inbound"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.COL_AMBER)
		y += 6.0
		for row: Dictionary in rows:
			var col: Color = row["colour"]
			y += ROW_H
			draw_rect(Rect2(12, y - 10, 3, 12), col)
			var tw := _font.get_string_size(row["tail"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(_font, Vector2(20, y), row["weapon"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
			draw_string(_font, Vector2(size.x * 0.44, y), row["target"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.COL_TEXT)
			draw_string(_font, Vector2(size.x - tw - 12, y), row["tail"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		if int(board["more"]) > 0:
			y += 14.0
			draw_string(_font, Vector2(20, y), "+%d more" % int(board["more"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.COL_DIM)
		y += 12.0
	# Per-shooter channel load.
	y += 8.0
	draw_string(_font, Vector2(12, y), board["channels"], HORIZONTAL_ALIGNMENT_LEFT, int(size.x - 24.0), 10, UITheme.COL_ACCENT if bool(board["networked"]) else UITheme.COL_DIM)
	y += 6.0
	var loads: Dictionary = board["loads"]
	for u: Unit in board["ships"]:
		if y > size.y - SHIP_ROW_H:
			break
		y += SHIP_ROW_H
		var total := u.spec.fire_control_channels
		var busy := int(loads.get(u, 0))
		draw_string(_font, Vector2(12, y), fit_words(_short_name(u.callsign), 118.0, 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.COL_TEXT if u.can_fire() else UITheme.COL_RED)
		var bx := 136.0
		var bw := size.x - bx - 12.0
		var seg := bw / maxf(float(total), 1.0)
		for i in total:
			var filled := i < busy
			var c := UITheme.COL_ACCENT if filled else UITheme.COL_HAIRLINE.lightened(0.08)
			if not u.can_fire():
				c = Color(UITheme.COL_RED, 0.4)
			draw_rect(Rect2(bx + i * seg, y - 8, maxf(seg - 2.0, 1.0), 8), c)


## What the board shows at its present size: the interceptor count, as many inbound rows as fit
## (each already cut to its column at a word), how many more there are, and the shooters' channel
## load. Empty when there is no picture to read.
func layout() -> Dictionary:
	if contacts == null or contacts.map == null or contacts.map.unit_manager == null:
		return {}
	if _font == null:
		_font = UITheme.body_font()
	var m := contacts.map
	var threats := CommanderPicture.inbound(m.unit_manager, m.threat_manager, m.player_faction)
	var loads := m.weapon_manager.channel_loads()
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
			if w.target_types.has("ballistic"):
				bmd_rounds += u.magazine_count(w.id)
	var rows: Array = []
	var fit := maxi(1, int(floor((size.y - 44.0 - ROWS_RESERVE) / ROW_H)))
	var shown := threats.size() if threats.size() <= fit else maxi(1, fit - 1)
	var committed := AirDefence._count_committed(m.weapon_manager)
	var name_w := size.x * 0.42 - 20.0
	for i in mini(shown, threats.size()):
		var t: Dictionary = threats[i]
		var w: Weapon = t["weapon"]
		var tti := float(t["time_s"])
		var tail := "%ds · %d up" % [int(tti), int(committed.get(w.id, 0))]
		var engaging := AirDefence.engaging_units(m.weapon_manager, w)
		if not engaging.is_empty():
			# Who has the round: the first shooter, and how many more ships are on it.
			var who := fit_words(_short_name(engaging[0].callsign), 80.0, 10)
			tail = "%ds · %s%s" % [int(tti), who, "" if engaging.size() == 1 else " +%d" % (engaging.size() - 1)]
		if w.spec.is_torpedo():
			tail = "%ds · %s" % [int(tti), torpedo_answer(t["target"])]
		var tw := _font.get_string_size(tail, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var target_w := size.x - size.x * 0.44 - tw - 20.0
		rows.append({
			"weapon": fit_words("%s %s" % [threat_kind(w), w.spec.compact_name()], name_w, 11),
			"target": fit_words("→ %s" % _short_name((t["target"] as Unit).callsign), target_w, 10),
			"tail": tail,
			"colour": UITheme.COL_RED if tti < 30.0 else UITheme.COL_AMBER,
		})
	var networked := 0
	for u: Unit in ships:
		if u.spec.cooperative_engagement and u.datalink_connected():
			networked += 1
	var channel_line := "CHANNELS %d / %d" % [used, channels]
	if networked >= 2:
		# Two or more fitted ships on the link fight as one: each can take a shot a consort guides.
		channel_line += " · NETWORKED FIRE CONTROL %d SHIPS" % networked
	return {
		"rounds": "%d SAM / %d BMD" % [rounds, bmd_rounds] if bmd_rounds > 0 else "%d SAM" % rounds,
		"inbound": threats.size(),
		"rows": rows,
		"more": threats.size() - rows.size(),
		"channels": channel_line,
		"networked": networked >= 2,
		"ships": ships,
		"loads": loads,
	}


## The short word for what a round is, for the threat row.
static func threat_kind(w: Weapon) -> String:
	match w.threat_class():
		"ballistic":
			return "BM"
		"torpedo":
			return "TORP"
		"shell":
			return "GUN"
	return "MSL"


## As much of `text` as fits `width` px, cut between words: a hull number in brackets goes first,
## then words from the end; a single word too long for the space ends in an ellipsis.
func fit_words(text: String, width: float, font_size: int) -> String:
	if _font == null:
		_font = UITheme.body_font()
	var fits := func(t: String) -> bool: return _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width
	if fits.call(text):
		return text
	var words := text.get_slice(" (", 0).split(" ", false)
	while words.size() > 1:
		var cut := " ".join(words)
		if fits.call(cut):
			return cut
		words.resize(words.size() - 1)
	var word := words[0] if not words.is_empty() else ""
	while word.length() > 1 and not fits.call(word + "…"):
		word = word.left(-1)
	return word + "…"


## What the ship a torpedo is running at has against it, in a word for the threat row: no SAM is ever
## "up" against a torpedo, so the row says whether anti-torpedo rounds, decoys or only her speed are.
static func torpedo_answer(u: Unit) -> String:
	if u == null:
		return "EVADE"
	if TorpedoDefence.hard_kill_weapon(u) != null:
		return "ATT + DECOY" if u.spec.towed_torpedo_decoy or u.torpedo_decoys > 0 else "ATT"
	if u.spec.towed_torpedo_decoy or u.torpedo_decoys > 0:
		return "DECOY"
	return "EVADE"
