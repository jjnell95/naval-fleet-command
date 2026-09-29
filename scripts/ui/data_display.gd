class_name DataDisplay
extends Control
## The CDS data display: the bottom-right pane of the command screen, in the manner of the late
## 1990s fleet-command games. A navy board of plain facts about whatever is hooked: the name in
## blue, then LABEL: value lines with white labels and yellow values, and a footer with the watch
## time and the time scale. Nothing hooked shows the mission's tasking instead.
##
## It reads the same state the rest of the deck reads and adds no knowledge: a contact is described
## only as its track holds it, never through `Track.truth`. The text is built by static functions
## that return rows of coloured spans, so the wording is testable without a renderer.

signal pause_requested
signal scale_step_requested(step: int)
signal messages_requested
signal threat_requested

const COL_BG := Color("0f1837")
const COL_TITLE := Color("3a7fff")
const COL_LABEL := Color("e6e6e6")
const COL_VALUE := Color("ffff55")
const COL_ALERT := Color("ff4040")
const COL_BARS := Color("30e030")
const COL_WHITE := Color("ffffff")
const COL_LAMP_OFF := Color("27305a")

## Span colour keys, resolved at draw time so tests can compare plain strings.
const TITLE := "title"
const LABEL := "label"
const VALUE := "value"
const ALERT := "alert"
const WHITE := "white"
const GREEN := "green"

const MARGIN := Vector2(9.0, 6.0)
const REFRESH_S := 0.25
## The weapons block is a grid of cells, one per system: its short name and the rounds left, the
## count set flush right in the cell. A cell is wide enough for an eleven-letter name and three
## figures; the pane takes as many columns as it has room for, up to three.
const CELL := "CELL"
const CELL_MIN_PX := 136.0
const CELL_GAP_PX := 14.0
const MAX_COLUMNS := 3
## The jobs the WEAPONS line states a reach for, in reading order: the label, and the weapon type it covers.
const REACH_JOBS := [["STRIKE", "asm"], ["AAM", "aam"], ["AAW", "sam"], ["CIWS", "ciws"], ["GUN", "gun"], ["TORP", "torpedo"]]

var map: TacticalMap
var simulation: Simulation
## Set by the shell: unread warning and alert messages light the lamp until the comms board opens.
var unread_alerts := 0
## Set by the shell: the inbound-threat line ("MISSILE INBOUND - 2 - 34 s"), empty when clear.
var threat_text := ""
## Weapons the last drawing had no room for (0 when every system was shown), for the screen checks.
var grid_hidden := 0

var _rows: Array = []
var _accum := 0.0
var _blink := 0.0
var _lamp_drawn := false
var _pulse_drawn := -1
var _time_rect := Rect2()
var _scale_rect := Rect2()
var _lamp_rect := Rect2()
var _threat_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	SimClock.paused_changed.connect(func(_p: bool) -> void: queue_redraw())
	SimClock.speed_changed.connect(func(_i: int, _m: float) -> void: queue_redraw())


func _process(delta: float) -> void:
	_blink += delta
	_accum += delta
	if _accum >= REFRESH_S:
		_accum = 0.0
		refresh()
	# The lamp and the threat line blink and pulse; redraw when they visibly change, not every frame.
	elif unread_alerts > 0 and _lamp_lit() != _lamp_drawn:
		queue_redraw()
	elif threat_text != "" and _pulse_step() != _pulse_drawn:
		queue_redraw()


func _lamp_lit() -> bool:
	return unread_alerts > 0 and fmod(_blink, 1.0) < 0.6


func _pulse_step() -> int:
	return int(_blink * 12.0)


func refresh() -> void:
	_rows = build_rows()
	queue_redraw()


## Rows for the current hook: an own unit, else a held contact, else the mission.
func build_rows() -> Array:
	if map == null or simulation == null:
		return []
	var ref := map.reference_unit()
	if map.selected.size() == 1:
		var u: Unit = map.selected[0]
		if u != null and is_instance_valid_unit(u):
			return unit_rows(u, simulation.weapon_manager, map.track_number_text(u))
	if map.selected.size() > 1:
		return group_rows(map.selected)
	if map.selected_track != null:
		return track_rows(map.selected_track, ref, SimClock.sim_time)
	return mission_rows(simulation, map)


static func is_instance_valid_unit(u: Unit) -> bool:
	return u != null and u.spec != null


# --- Content ------------------------------------------------------------------------------

## A contact's four-digit track number, as the chart prints it beside the symbol.
static func track_number_for_track(t: Track) -> String:
	return MapSymbols.track_number(t.id)


static func _row(parts: Array) -> Array:
	return parts


static func _kv(label: String, value: String, value_key := VALUE) -> Array:
	return [[label + ": ", LABEL], [value, value_key]]


## `number` is the unit's own track number as the chart shows it (TacticalMap.track_number_text).
static func unit_rows(u: Unit, weapon_manager: WeaponManager = null, number := "") -> Array:
	var rows: Array = []
	rows.append([[u.callsign, TITLE]])
	rows.append(_kv("CLASS", u.spec.display_name.to_upper()))
	if number != "":
		rows.append(_kv("TRACK #", number))
	if not u.alive:
		rows.append(_kv("STATUS", "DESTROYED", ALERT))
		return rows
	# Course and speed share a line, which leaves the weapons grid one line more.
	rows.append(_kv("COURSE", "%03d" % (int(round(u.heading_deg)) % 360)) + [["   SPEED: ", LABEL], ["%d KTS" % int(round(u.speed_kn)), VALUE]])
	if u.is_aircraft() and u.in_flight():
		rows.append(_kv("ALTITUDE", "%.1f KFT" % (u.altitude_m * 3.28084 / 1000.0)))
	elif u.spec.max_depth_m > 0.0:
		rows.append(_kv("DEPTH", "%d FT" % int(round(u.depth_m * 3.28084))))
	var damage := damage_percent(u)
	var damage_row := _kv("%DAMAGE", str(damage), ALERT if damage > 0 else VALUE)
	if u.fire > 0.0:
		damage_row.append(["   FIRE", ALERT])
	if u.flooding > 0.0:
		damage_row.append(["   FLOODING", ALERT])
	rows.append(damage_row)
	if u.is_aircraft():
		var fuel := int(round(u.fuel_fraction() * 100.0))
		rows.append(_kv("%FUEL", str(fuel), ALERT if fuel <= 20 else VALUE))
	rows.append(_kv("ORDERS", orders_text(u, weapon_manager)))
	var sensors := sensors_text(u)
	if sensors != "":
		rows.append(_kv("SENSORS", sensors))
	if not u.weapons.is_empty():
		rows.append([["WEAPONS:", LABEL]] + reach_spans(u))
		for w in weapons_by_job(u):
			var n := u.magazine_count(w.id)
			rows.append([[w.compact_name(), ALERT if n == 0 else VALUE], [" %d" % n, WHITE], [CELL, ""]])
	if u.spec.aircraft_capacity > 0 and not u.embarked.is_empty():
		rows.append(_kv("AIR WING", "%d of %d ready" % [u.stowed_aircraft().size(), u.embarked.size()]))
	return rows


## What a hull can reach, one figure per job, for the head of the weapons block: the farthest missile
## that strikes, the farthest that shoots down aircraft, the close-in mount, the gun, the torpedo.
## The rows below list every system with its count; this line is what tells a ship that carries a
## single close-in gun from one that carries a cruise missile. A job the hull cannot do is left out.
static func reach_spans(u: Unit) -> Array:
	var best := {}
	for w in u.weapons:
		best[w.type] = maxf(float(best.get(w.type, 0.0)), w.max_range_nm)
	var spans: Array = []
	for job: Array in REACH_JOBS:
		if best.has(job[1]):
			spans.append(["  " + str(job[0]) + " ", LABEL])
			spans.append([Geo.format_nm(float(best[job[1]])), WHITE])
	if not spans.is_empty():
		spans.append([" NM", LABEL])
	return spans


## The hull's weapons in the order the reach line names their jobs (strike, air-to-air, air
## defence, close-in, gun, anti-submarine), the farthest-reaching first within each job.
static func weapons_by_job(u: Unit) -> Array:
	var order := {}
	for i in REACH_JOBS.size():
		order[REACH_JOBS[i][1]] = i
	var out: Array = u.weapons.duplicate()
	out.sort_custom(func(a: WeaponSpec, b: WeaponSpec) -> bool:
		var ja := int(order.get(a.type, REACH_JOBS.size()))
		var jb := int(order.get(b.type, REACH_JOBS.size()))
		if ja != jb:
			return ja < jb
		if not is_equal_approx(a.max_range_nm, b.max_range_nm):
			return a.max_range_nm > b.max_range_nm
		return a.id < b.id)
	return out


## How many columns of weapon cells fit across `width_px`.
static func grid_columns(width_px: float) -> int:
	return clampi(int((width_px + CELL_GAP_PX) / (CELL_MIN_PX + CELL_GAP_PX)), 1, MAX_COLUMNS)


## How a block of `count` weapon cells lays out in `columns` columns with `lines` lines free:
## {shown, more, lines}. When they cannot all fit, the last cell is given to "+N MORE", so the
## display never drops a system without saying so.
static func grid_fit(count: int, columns: int, lines: int) -> Dictionary:
	var cols := maxi(columns, 1)
	var need := ceili(float(count) / float(cols))
	if need <= lines:
		return {"shown": count, "more": 0, "lines": need}
	var slots := maxi(lines, 0) * cols
	if slots <= 0:
		return {"shown": 0, "more": count, "lines": 0}
	return {"shown": slots - 1, "more": count - slots + 1, "lines": lines}


static func group_rows(units: Array) -> Array:
	var rows: Array = []
	rows.append([["%d units hooked" % units.size(), TITLE]])
	for u: Unit in units:
		if u == null or u.spec == null:
			continue
		rows.append([[u.callsign, VALUE], ["  %03d  %d KTS" % [int(round(u.heading_deg)) % 360, int(round(u.speed_kn))], WHITE]])
	return rows


static func damage_percent(u: Unit) -> int:
	if not u.alive:
		return 100
	return clampi(int(round(100.0 - Damage.health_fraction(u) * 100.0)), 0, 100)


## Plain words for what the unit is doing, the way an operator would report it.
static func orders_text(u: Unit, weapon_manager: WeaponManager = null) -> String:
	if weapon_manager != null:
		for w in weapon_manager.in_flight:
			if w.shooter == u and w.target_track != null and not w.is_interceptor():
				return "Engage track %s" % track_number_for_track(w.target_track)
	if u.is_aircraft():
		match u.flight_state:
			Unit.FlightState.STOWED:
				return "Ready on deck"
			Unit.FlightState.LAUNCHING:
				return "Launching"
			Unit.FlightState.RECOVERING:
				return "Recovering"
			Unit.FlightState.TURNAROUND:
				return "Refuel and rearm"
			Unit.FlightState.RESERVE:
				return "Reserve preparation"
		if u.returning:
			return "Return to base" if u.recovery_base == null else "Return to %s" % u.recovery_base.callsign
		if u.tanking_on != null:
			return "Tanking on %s" % u.tanking_on.callsign
		return "Transit" if not u.waypoints.is_empty() else "Patrol"
	if u.in_formation():
		return "Station on %s" % u.formation_leader.callsign
	if not u.waypoints.is_empty():
		return "Transit (%d wpt%s)" % [u.waypoints.size(), "" if u.waypoints.size() == 1 else "s"]
	if u.ordered_speed_kn <= 0.1 and u.spec.max_speed_kn > 0.0:
		return "Hold position"
	if u.spec.max_speed_kn <= 0.0:
		return "Weapons %s" % ["hold", "tight", "free"][u.roe]
	return "Steady on %03d" % (int(round(u.ordered_heading_deg)) % 360)


static func sensors_text(u: Unit) -> String:
	var parts := PackedStringArray()
	if u.has_radar():
		parts.append("Radar %s" % ("on" if u.radar_emitting() else "off"))
	if u.has_sonar():
		parts.append("Sonar %s" % ("active" if u.active_sonar_on else "passive"))
	if u.emcon == Unit.Emcon.SILENT:
		parts.append("EMCON silent")
	if u.jamming():
		parts.append("Jamming")
	return "  ".join(parts)


static func track_rows(t: Track, ref: Unit, now: float) -> Array:
	var rows: Array = []
	var title := t.description()
	rows.append([[title.capitalize() if title == title.to_upper() else title, TITLE]])
	rows.append(_kv("TRACK #", track_number_for_track(t)))
	rows.append(_kv("IDENTITY", t.identity, identity_key(t.identity)))
	if t.has_kinematics and not t.is_bearing_only():
		rows.append(_kv("COURSE", "%03d (est)" % (int(round(t.course_deg)) % 360)))
		rows.append(_kv("SPEED", "%d KTS (est)" % int(round(t.speed_kn))))
	else:
		rows.append(_kv("COURSE", "unknown"))
	rows.append(_kv("SOURCE", source_text(t.source)))
	var status := "active" if t.status == Track.Status.ACTIVE else t.status_text(now).to_lower()
	if t.is_bearing_only():
		rows.append(_kv("POSITION", "bearing only, %s" % status))
	else:
		rows.append(_kv("POSITION", "+/-%.1f nm, %s" % [t.position_error_nm, status]))
	if ref != null and ref.alive:
		var brg := Geo.format_bearing(Geo.bearing_deg(ref.position, t.position))
		if t.is_bearing_only():
			rows.append(_kv("BEARING", "%s from %s" % [brg, ref.callsign]))
		else:
			rows.append(_kv("RANGE", "%.1f nm, bearing %s from %s" % [ref.position.distance_to(t.position), brg, ref.callsign]))
		# The relative-motion solution from the track as held: a planning aid, never truth.
		var solution := RelativeMotion.solution(ref, t, now)
		if bool(solution.get("valid", false)):
			rows.append(_kv("CPA", "%.1f nm in %s" % [float(solution["distance_nm"]), Track._fmt_age(float(solution["time_s"]))]))
		elif solution.has("closing_kn") and not t.is_bearing_only():
			rows.append(_kv("CPA", str(solution["reason"]).capitalize()))
		if solution.has("closing_kn") and not t.is_bearing_only():
			var closing := float(solution["closing_kn"])
			rows.append(_kv("CLOSING" if closing >= 0.0 else "OPENING", "%d KTS" % int(round(absf(closing)))))
	return rows


static func identity_key(identity: String) -> String:
	match identity:
		"HOSTILE":
			return "hostile"
		"NEUTRAL":
			return "neutral"
		"FRIENDLY":
			return "friendly"
	return "unknown"


static func source_text(source: String) -> String:
	match source:
		"radar":
			return "Radar"
		"esm":
			return "ESM"
		"sonar", "passive_sonar":
			return "Sonar passive"
		"active_sonar":
			return "Sonar active"
		"link", "datalink":
			return "Link"
		"visual":
			return "Visual"
		"sonobuoy", "buoy":
			return "Sonobuoy"
	return source.capitalize()


static func mission_rows(sim: Simulation, m: TacticalMap) -> Array:
	var rows: Array = []
	var title := str(sim.scenario.get("name", sim.scenario_name))
	rows.append([[title if title != "" else "No operation loaded", TITLE]])
	var mm := sim.mission_manager
	if mm != null and not mm.victory_objectives.is_empty():
		rows.append([["TASKING:", LABEL]])
		for o in mm.victory_objectives:
			var progress := o.progress(sim.unit_manager, SimClock.sim_time)
			var text := o.text if progress == "" else "%s (%s)" % [o.text, progress]
			rows.append([[("Done: " if o.complete else "") + text, WHITE if o.complete else VALUE], ["FLOW", ""]])
	var tracks: Array = m._visible_tracks() if m != null else []
	var hostile := 0
	for t: Track in tracks:
		if t.identity == "HOSTILE":
			hostile += 1
	rows.append(_kv("CONTACTS", "%d held - %d hostile" % [tracks.size(), hostile]))
	var flying := 0
	var ready := 0
	if sim.unit_manager != null:
		for u: Unit in sim.unit_manager.units:
			if u.faction != sim.player_faction or not u.alive or not u.is_aircraft():
				continue
			if u.in_flight():
				flying += 1
			elif u.ready_to_launch():
				ready += 1
	rows.append(_kv("AIR", "%d flying - %d ready" % [flying, ready]))
	return rows


# --- Drawing ------------------------------------------------------------------------------

func _font() -> Font:
	return UITheme.data_font()


func _font_size() -> int:
	return 14


func _color(key: String) -> Color:
	match key:
		TITLE:
			return COL_TITLE
		LABEL:
			return COL_LABEL
		VALUE:
			return COL_VALUE
		ALERT:
			return COL_ALERT
		WHITE:
			return COL_WHITE
		GREEN:
			return COL_BARS
		"hostile":
			return TacticalMap.COL_HOSTILE
		"neutral":
			return TacticalMap.COL_NEUTRAL
		"friendly":
			return TacticalMap.COL_FRIENDLY
		"unknown":
			return TacticalMap.COL_UNKNOWN
	return COL_VALUE


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	var font := _font()
	var fs := _font_size()
	var line_h := float(fs) + 4.0
	var ascent := font.get_ascent(fs)
	var footer_y := size.y - MARGIN.y - line_h
	var limit_y := footer_y - (line_h if threat_text != "" else 0.0) - 2.0
	var x := MARGIN.x
	var y := MARGIN.y
	var flow_x := -1.0  # where the next flowing item may start on the current line, or -1
	var index := 0
	grid_hidden = 0
	while index < _rows.size():
		var row: Array = _rows[index]
		index += 1
		if _is_cell(row):
			var block: Array = [row]
			while index < _rows.size() and _is_cell(_rows[index]):
				block.append(_rows[index])
				index += 1
			# Rows after the grid (a carrier's air wing) keep their lines, unless that would leave the
			# grid none: its "+N MORE" matters more than they do.
			var free := int(floor((limit_y - y) / line_h))
			y = _draw_grid(block, y, maxi(free - (_rows.size() - index), mini(free, 1)), font, fs, line_h, ascent)
			flow_x = -1.0
			continue
		var flowing: bool = row.size() > 0 and str(row[row.size() - 1][0]) == "FLOW"
		var spans: Array = row.slice(0, row.size() - 1) if flowing else row
		var width := 0.0
		for s: Array in spans:
			width += font.get_string_size(str(s[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if flowing and flow_x >= 0.0 and flow_x + width <= size.x - MARGIN.x:
			x = flow_x
			y -= line_h
		else:
			x = MARGIN.x
		if y + line_h > limit_y:
			for rest in range(index - 1, _rows.size()):
				grid_hidden += 1 if _is_cell(_rows[rest]) else 0
			break
		for s: Array in spans:
			var text := str(s[0])
			var key := str(s[1])
			var title := key == TITLE
			draw_string(font, Vector2(x, y + ascent), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - MARGIN.x, fs + (1 if title else 0), _color(key))
			x += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + (1 if title else 0)).x
		flow_x = x + 16.0 if flowing else -1.0
		y += line_h
	# Inbound threat line, above the footer.
	_threat_rect = Rect2()
	if threat_text != "":
		var ty := footer_y - line_h
		var bright := 0.65 + 0.35 * absf(sin(_blink * 4.0))
		draw_string(font, Vector2(MARGIN.x, ty + ascent), threat_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 2.0 * MARGIN.x, fs, Color(COL_ALERT, bright))
		_threat_rect = Rect2(MARGIN.x, ty, font.get_string_size(threat_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, line_h)
	# Footer: TIME and SCALE, with the message lamp in the corner.
	var fx := MARGIN.x
	var label := "TIME: "
	draw_string(font, Vector2(fx, footer_y + ascent), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_TITLE)
	var tx := fx + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var clock := clock_text()
	draw_string(font, Vector2(tx, footer_y + ascent), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_WHITE)
	var clock_end := tx + font.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_time_rect = Rect2(fx, footer_y, clock_end - fx, line_h)
	var sx := clock_end + 28.0
	draw_string(font, Vector2(sx, footer_y + ascent), "SCALE: ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_TITLE)
	var bx := sx + font.get_string_size("SCALE: ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var scale_end := bx
	if SimClock.paused:
		draw_string(font, Vector2(bx, footer_y + ascent), "PAUSED", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_VALUE)
		scale_end = bx + font.get_string_size("PAUSED", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	else:
		var bars := SimClock.speed_index + 1
		for i in bars:
			draw_rect(Rect2(bx + i * 9.0, footer_y + line_h * 0.5 - 3.0, 6.0, 6.0), COL_BARS)
		scale_end = bx + bars * 9.0
		draw_string(font, Vector2(scale_end + 6.0, footer_y + ascent), "%dx" % int(SimClock.multiplier()), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, Color(COL_BARS, 0.85))
		scale_end += 6.0 + font.get_string_size("%dx" % int(SimClock.multiplier()), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2).x
	_scale_rect = Rect2(sx, footer_y, scale_end - sx, line_h)
	_lamp_rect = Rect2(size.x - MARGIN.x - 11.0, footer_y + line_h * 0.5 - 5.5, 11.0, 11.0)
	var lit := _lamp_lit()
	draw_rect(_lamp_rect, COL_ALERT if lit else COL_LAMP_OFF)
	_lamp_drawn = lit
	_pulse_drawn = _pulse_step()
	Debug.time_add("data", Time.get_ticks_usec() - t0)


static func _is_cell(row: Array) -> bool:
	return row.size() > 0 and str(row[row.size() - 1][0]) == CELL


## Lays the weapon cells out in columns from `y`, in `lines` lines at most; returns the next line.
func _draw_grid(block: Array, y: float, lines: int, font: Font, fs: int, line_h: float, ascent: float) -> float:
	grid_hidden = block.size()
	if lines <= 0:
		return y
	var width := size.x - 2.0 * MARGIN.x
	var columns := grid_columns(width)
	var col_w := (width + CELL_GAP_PX) / float(columns) - CELL_GAP_PX
	var fit := grid_fit(block.size(), columns, lines)
	grid_hidden = int(fit["more"])
	var slots := int(fit["shown"]) + (1 if int(fit["more"]) > 0 else 0)
	for k in slots:
		var cx := MARGIN.x + float(k % columns) * (col_w + CELL_GAP_PX)
		var cy := y + float(k / columns) * line_h + ascent
		if k >= int(fit["shown"]):
			draw_string(font, Vector2(cx, cy), "+%d MORE" % int(fit["more"]), HORIZONTAL_ALIGNMENT_LEFT, col_w, fs, COL_LABEL)
			break
		var spans: Array = block[k]
		var count := str(spans[1][0]).strip_edges()
		var count_w := font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(cx, cy), str(spans[0][0]), HORIZONTAL_ALIGNMENT_LEFT, col_w - count_w - 6.0, fs, _color(str(spans[0][1])))
		draw_string(font, Vector2(cx + col_w - count_w, cy), count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _color(str(spans[1][1])))
	return y + float(fit["lines"]) * line_h


## The watch time without the date, as the old data displays showed it: "05:38:00Z".
static func clock_text() -> String:
	var s := SimClock.datetime_string()
	var cut := maxi(s.rfind(" "), s.rfind("T"))
	return s.substr(cut + 1) if cut >= 0 else s


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if _time_rect.grow(3.0).has_point(mb.position) and mb.button_index == MOUSE_BUTTON_LEFT:
		pause_requested.emit()
		accept_event()
	elif _scale_rect.grow(3.0).has_point(mb.position) and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		scale_step_requested.emit(1 if mb.button_index == MOUSE_BUTTON_LEFT else -1)
		accept_event()
	elif _lamp_rect.grow(6.0).has_point(mb.position):
		messages_requested.emit()
		accept_event()
	elif _threat_rect.grow(3.0).has_point(mb.position):
		threat_requested.emit()
		accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	if _time_rect.grow(3.0).has_point(at_position):
		return "Watch time. Click to pause or resume [Space]"
	if _scale_rect.grow(3.0).has_point(at_position):
		return "Time scale. Click to speed up, right-click to slow down [1-6]"
	if _lamp_rect.grow(6.0).has_point(at_position):
		return "Messages. Click for the comms board"
	if _threat_rect.grow(3.0).has_point(at_position):
		return "Frame the inbound threat"
	return ""
