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
const REACH_JOBS := [["STRIKE", "asm"], ["AAM", "aam"], ["AAW", "sam"], ["CIWS", "ciws"], ["GUN", "gun"], ["ASW", "asw_rocket"], ["TORP", "torpedo"], ["BOMB", "bomb"]]

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
var _row_tooltips: Array[Dictionary] = []
var _details_button: Button
var _more_button: Button
var _details: Window
var _details_text: RichTextLabel
var _details_alert: Label
var _details_clock: Label
var _details_close: Button
var _details_signature := ""
var _details_focus: Control
var _hidden_rows := 0
var _more_drawn := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	SimClock.paused_changed.connect(func(_p: bool) -> void: queue_redraw())
	SimClock.speed_changed.connect(func(_i: int, _m: float) -> void: queue_redraw())
	_details_button = Button.new()
	_details_button.text = "DETAILS"
	_details_button.accessibility_name = "Expand selected platform or contact details"
	_details_button.tooltip_text = "Expand the complete live readout, including all weapons and sensor reports. The clock keeps its current state."
	_details_button.add_theme_font_size_override("font_size", 11)
	_details_button.pressed.connect(open_details)
	add_child(_details_button)
	_more_button = Button.new()
	_more_button.flat = true
	_more_button.add_theme_font_size_override("font_size", _font_size())
	_more_button.add_theme_color_override("font_color", COL_LABEL)
	_more_button.add_theme_color_override("font_hover_color", COL_WHITE)
	for state in ["normal", "hover", "pressed"]:
		_more_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var more_focus := StyleBoxFlat.new()
	more_focus.draw_center = false
	more_focus.border_color = COL_WHITE
	more_focus.set_border_width_all(1)
	_more_button.add_theme_stylebox_override("focus", more_focus)
	_more_button.tooltip_text = "Show every weapon system and its remaining rounds"
	_more_button.pressed.connect(open_details)
	_more_button.hide()
	add_child(_more_button)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree(): close_details())


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
	accessibility_name = "Command data readout"
	accessibility_description = rows_text(_rows)
	if _details != null and _details.visible:
		_refresh_details()
	queue_redraw()


## Rows for the inspected hook, retaining the selected shooter when a contact is inspected.
func build_rows() -> Array:
	if map == null or simulation == null:
		return []
	var ref := map.reference_unit()
	var inspected := map.inspection_track()
	if inspected != null:
		var rows := track_rows(inspected, ref, SimClock.sim_time)
		if not map.selected.is_empty():
			var shooter := (map.selected[0] as Unit).callsign if map.selected.size() == 1 else "%d platforms" % map.selected.size()
			rows.insert(4, _kv("COMMAND", shooter))
		return rows
	if map.selected.size() == 1:
		var u: Unit = map.selected[0]
		if u != null and is_instance_valid_unit(u):
			return unit_rows(u, simulation.weapon_manager, map.track_number_text(u), simulation.group_attack_manager)
	if map.selected.size() > 1:
		return group_rows(map.selected, simulation.group_attack_manager)
	if map.selected_track != null:
		return track_rows(map.selected_track, ref, SimClock.sim_time)
	# Nothing hooked: a contact under the cursor reads out here until the cursor moves off it.
	var hovered := map.hovered_track()
	if hovered != null:
		return track_rows(hovered, ref, SimClock.sim_time)
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
static func unit_rows(u: Unit, weapon_manager: WeaponManager = null, number := "", group_attacks: GroupAttackManager = null) -> Array:
	var rows: Array = []
	rows.append([[u.callsign, TITLE]])
	rows.append(_kv("CLASS", u.spec.display_name.to_upper()))
	if number != "":
		rows.append(_kv("TRACK #", number))
	if SubmarineComms.restricted(u) and not SubmarineComms.connected(u):
		# A disconnected boat reports its last known state, not a live view of its crew. Even
		# internal sensor, magazine and damage changes wait for the next communication window.
		rows.append(_kv("COMMS", SubmarineComms.status(u, SimClock.sim_time)))
		rows.append(_kv("LAST COURSE", "%03d" % (int(round(SubmarineComms.reported_heading(u))) % 360)) + [["   SPEED: ", LABEL], ["%d KTS" % int(round(SubmarineComms.reported_speed(u))), VALUE]])
		rows.append(_kv("LAST DEPTH", "%d FT" % int(round(SubmarineComms.reported_depth(u) * 3.28084))))
		var reported_health := float(u.comms_report.get("health", u.spec.health))
		rows.append(_kv("LAST %DAMAGE", str(clampi(int(round(100.0 * (1.0 - reported_health / maxf(u.spec.health, 1.0)))), 0, 100))))
		rows.append(_kv("ORDERS", "%d queued for next check-in; crew continues its standing task" % u.comms_pending.size()))
		rows.append(_kv("CHECK-IN", SubmarineComms.detail(u, SimClock.sim_time)))
		return rows
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
	rows.append(_kv("ORDERS", orders_text(u, weapon_manager, group_attacks)))
	if u.comms_enabled and u.is_submarine():
		rows.append(_kv("COMMS", SubmarineComms.status(u, SimClock.sim_time)))
		rows.append(_kv("CHECK-IN", SubmarineComms.detail(u, SimClock.sim_time)))
	var response := DefensiveResponse.status(u)
	if response != "":
		rows.append(_kv("DEFENCE", response, ALERT))
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


## Several hooked platforms. A group attack any of them is firing in leads the list, with its budget
## and what it has fired, queued and in the air, so the commander reads the shared state at once.
static func group_rows(units: Array, group_attacks: GroupAttackManager = null) -> Array:
	var rows: Array = []
	rows.append([["%d units hooked" % units.size(), TITLE]])
	if group_attacks != null:
		var shown: Array[GroupAttack] = []
		for u: Unit in units:
			var g := group_attacks.group_for(u) if u != null else null
			if g != null and not shown.has(g):
				shown.append(g)
				var s := group_attacks.status(g)
				rows.append(_kv("GROUP ATTACK %s" % g.target_label(), "%d of %d rds · %d fired · %d queued · %d away · %s" % [int(s["spent"]), g.budget, int(s["fired"]), int(s["queued"]), int(s["airborne"]), str(s["phase"])]))
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
static func orders_text(u: Unit, weapon_manager: WeaponManager = null, group_attacks: GroupAttackManager = null) -> String:
	if u.evasion_remaining_s > 0:
		return "Evade %03d (%ds), then resume plan" % [int(u.evasion_course_deg), int(ceil(u.evasion_remaining_s))]
	if u.attack_track != null:
		# The standing attack narrates itself: INTERCEPT TRACK while closing, ENGAGE while rounds
		# are away, and what is holding it up otherwise.
		var number := track_number_for_track(u.attack_track)
		if u.attack_phase.begins_with("Intercept track"):
			return "Intercept track %s%s" % [number, u.attack_phase.trim_prefix("Intercept track")]
		if u.attack_phase.begins_with("Engaging track"):
			return "Engage track %s%s" % [number, u.attack_phase.trim_prefix("Engaging track")]
		if u.attack_phase.begins_with("Attack track"):
			return "Attack track %s%s" % [number, u.attack_phase.trim_prefix("Attack track")]
		return "Attack track %s · %s" % [number, u.attack_phase.to_lower()]
	# A platform firing in a group attack reports the group's state: the shared budget, what has
	# gone, and the shared assessment, rather than only its own rounds.
	if group_attacks != null:
		var group_line := group_attacks.orders_line(u)
		if group_line != "":
			return group_line
	if weapon_manager != null:
		for w in weapon_manager.in_flight:
			if w.phase != Weapon.Phase.DEAD and w.shooter == u and w.target_track != null and not w.is_interceptor():
				return "Engage track %s" % track_number_for_track(w.target_track)
		for spec: WeaponSpec in u.weapons:
			var queued := weapon_manager.committed_rounds(u, spec, null, true)
			if queued > 0:
				return "Engage (%d × %s queued)" % [queued, spec.compact_name()]
	if u.investigation_track != null:
		return "Investigate track %s%s" % [track_number_for_track(u.investigation_track), " · then station" if u.auto_return and u.has_station() else ""]
	if u.investigation_result != "":
		return "Track %s: %s%s" % [MapSymbols.track_number(u.investigation_track_id), u.investigation_result, _off_station_hint(u)]
	if u.attack_result != "":
		return "Track %s: %s%s" % [MapSymbols.track_number(u.attack_track_id), u.attack_result, _off_station_hint(u)]
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
		if u.patrol_active:
			if u.station_kind == "patrol" and u.station_label not in ["", "PATROL"]:
				return "%s (%d legs flown)" % [station_name(u.station_label), u.patrol_legs_completed]
			return "Patrol circuit (%d legs flown)" % u.patrol_legs_completed
		if u.has_station():
			return "Off station" + _off_station_hint(u)
		return "Transit" if not u.waypoints.is_empty() else "On station"
	if u.in_formation():
		return "Station on %s" % u.formation_leader.callsign
	if u.patrol_active:
		return "Patrol circuit (%d legs sailed)" % u.patrol_legs_completed
	if not u.waypoints.is_empty():
		return "Transit (%d wpt%s)" % [u.waypoints.size(), "" if u.waypoints.size() == 1 else "s"]
	if u.has_station():
		return "Off station" + _off_station_hint(u)
	if u.station_note != "":
		return u.station_note
	if u.ordered_speed_kn <= 0.1 and u.spec.max_speed_kn > 0.0:
		return "Hold position"
	if u.spec.max_speed_kn <= 0.0:
		return "Weapons %s" % ["hold", "tight", "free"][u.roe]
	return "Steady on %03d" % (int(round(u.ordered_heading_deg)) % 360)


## A platform away from a standing assignment it still holds says how to get back to it.
static func _off_station_hint(u: Unit) -> String:
	if u.station_note != "" and not u.on_station():
		return " · " + u.station_note.to_lower()
	if not u.has_station() or u.on_station():
		return ""
	return " · S returns to %s" % (station_name(u.station_label, false) if u.station_label != "" else "station")


## "CAP STATION" reads "CAP station"; "SCREEN STATION" reads "Screen station". Acronyms stay up.
static func station_name(label: String, sentence_case := true) -> String:
	var words := PackedStringArray()
	for word: String in label.split(" ", false):
		words.append(word if word in ["CAP", "ASW", "AEW"] else word.to_lower())
	var text := " ".join(words)
	if sentence_case and text != "" and not words[0] in ["CAP", "ASW", "AEW"]:
		text = text[0].to_upper() + text.substr(1)
	return text


static func sensors_text(u: Unit) -> String:
	var parts := PackedStringArray()
	if u.has_radar():
		parts.append("Radar %s" % ("on" if u.radar_emitting() else "off"))
	if u.has_sonar():
		parts.append(DippingSonar.status(u) if DippingSonar.capable(u) else "Sonar %s" % ("active" if u.active_sonar_on else "passive"))
		if TowedArray.capable(u): parts.append(TowedArray.status(u))
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
	rows.append(_kv("PLOT", plot_text(t, now), ALERT if t.status != Track.Status.ACTIVE else VALUE))
	# Held kinematics read plainly, as the own platform's do; POSITION states the uncertainty.
	if t.has_kinematics and not t.is_bearing_only():
		rows.append(_kv("LAST COURSE" if t.status != Track.Status.ACTIVE else "COURSE", "%03d" % (int(round(t.course_deg)) % 360)) + [["   SPEED: ", LABEL], ["%d KTS" % int(round(t.speed_kn)), VALUE]])
	else:
		rows.append(_kv("COURSE", "unknown"))
	if t.is_bearing_only():
		rows.append(_kv("POSITION", "bearing only - range unresolved"))
	else:
		rows.append(_kv("POSITION", "+/-%.1f nm (sensor estimate)" % t.position_error_nm))
	rows.append(_kv("SOURCE", source_readout(t)))
	rows.append(_kv("CLASSIFICATION", t.class_confidence_text()))
	rows.append(_kv("FIX", t.solution_text()))
	if t.class_evidence != "": rows.append(_kv("CLASS EVIDENCE", t.class_evidence))
	if t.identity_evidence != "": rows.append(_kv("IDENTITY EVIDENCE", t.identity_evidence))
	rows.append(_kv("%DAMAGE", damage_text(t)))
	if ref != null and ref.alive:
		var brg := Geo.format_bearing(Geo.bearing_deg(ref.position, t.position))
		if t.is_bearing_only():
			rows.append(_kv("BEARING", "%s from %s" % [brg, ref.callsign]))
		else:
			rows.append(_kv("RANGE", "~%.1f nm, bearing %s from %s" % [ref.position.distance_to(t.position), brg, ref.callsign]))
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


## Freshness is independent of identification: a known class can still be an old report.
static func plot_text(t: Track, now: float) -> String:
	var age := Track._fmt_age(t.age_s(now))
	if t.status == Track.Status.LOST:
		return "LOST - last report %s ago" % age
	if t.status == Track.Status.STALE:
		return "STALE - last report %s ago" % age
	if t.reported:
		return "CONTACT REPORT - %s ago" % age
	return "LIVE - updated %s ago" % age


static func identity_key(identity: String) -> String:
	match identity:
		"HOSTILE":
			return "hostile"
		"NEUTRAL":
			return "neutral"
		"FRIENDLY":
			return "friendly"
	return "unknown"


## The battle damage assessment as the data display states it: an estimate from our own hits.
static func damage_text(t: Track) -> String:
	# No assessed hit is not evidence of an undamaged hull.
	if t.damage_estimate <= 0.0:
		return "not assessed"
	return "%d (est)" % int(round(clampf(t.damage_estimate, 0.0, 100.0)))


## Where the plot came from, as specifically as the side's records say: the observing platform's
## class and the set ("MH-60R APS-153 multi-mode radar"), the buoys ("Sonobuoy field"), "Link"
## for a plot that reached us from nothing we operate, else the sensor category ("Radar"). A
## contact report says so and who made it, because it is a datum to investigate, not a plot.
static func source_readout(t: Track) -> String:
	if t.source == "intel":
		return "Contact report" + (", " + t.source_sensor if t.source_sensor != "" else "")
	var sensor := sensor_label(t.source_sensor)
	if sensor != "" and t.source_platform != "":
		return "%s %s%s" % [t.source_platform, sensor, _sonar_mode(t.source)]
	if sensor != "":
		return sensor + _sonar_mode(t.source)
	if t.source_platform != "":
		return "%s %s" % [t.source_platform, source_text(t.source).to_lower()]
	if t.contributors.is_empty() and t.source not in ["sonobuoy", "buoy"] and t.networked:
		return "Link"
	return source_text(t.source)


## A catalogue sensor name trimmed for a readout line: no "AN/" prefix and no fit note in
## brackets ("AN/SPS-48 air-search radar (representative carrier fit)" -> "SPS-48 air-search radar").
static func sensor_label(display_name: String) -> String:
	var text := display_name.strip_edges()
	if text.begins_with("AN/"):
		text = text.substr(3)
	var open := text.find(" (")
	while open >= 0:
		var close := text.find(")", open)
		if close < 0:
			break
		text = (text.substr(0, open) + text.substr(close + 1)).strip_edges()
		open = text.find(" (")
	return text


static func _sonar_mode(source: String) -> String:
	match source:
		"sonar_passive":
			return ", passive"
		"sonar_active":
			return ", active"
		"sonar_cz":
			return ", CZ"
	return ""


static func source_text(source: String) -> String:
	match source:
		"radar":
			return "Radar"
		"esm":
			return "ESM"
		"sonar", "passive_sonar", "sonar_passive":
			return "Sonar passive"
		"active_sonar", "sonar_active":
			return "Sonar active"
		"sonar_cz":
			return "Sonar CZ"
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

## Plain text is also the accessible description and the unabridged tooltip. Structural markers
## belong to the renderer, never to what a commander reads or copies.
static func rows_text(rows: Array) -> String:
	var lines := PackedStringArray()
	for row: Array in rows:
		var line := ""
		for span: Array in row:
			if str(span[0]) not in [CELL, "FLOW"]:
				line += str(span[0])
		lines.append(line)
	return "\n".join(lines)


## Wrap at words while retaining each span's colour. Very long identifiers break at characters;
## neither a long platform class nor an unbroken callsign can escape the pane at larger scales.
static func wrap_spans(spans: Array, font: Font, font_size: int, width: float) -> Array:
	var lines: Array = []
	var line: Array = []
	var used := 0.0
	var available := maxf(width, 1.0)
	for span: Array in spans:
		var key := str(span[1])
		var text := str(span[0])
		if text in [CELL, "FLOW"]: continue
		var tokens := PackedStringArray()
		var token := ""
		for character in text:
			if character in [" ", "\t", "\n"]:
				if token != "": tokens.append(token)
				tokens.append(character)
				token = ""
			else:
				token += character
		if token != "": tokens.append(token)
		var fs := font_size + (1 if key == TITLE else 0)
		for word: String in tokens:
			if word == "\n":
				lines.append(line)
				line = []
				used = 0.0
				continue
			if line.is_empty() and word.strip_edges() == "": continue
			var word_width := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if used > 0.0 and used + word_width > available:
				lines.append(line)
				line = []
				used = 0.0
				if word.strip_edges() == "": continue
			# A single word wider than the pane must still be readable in a narrow window.
			if word_width > available:
				for character in word:
					var char_width := font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					if used > 0.0 and used + char_width > available:
						lines.append(line)
						line = []
						used = 0.0
					_append_span(line, character, key)
					used += char_width
			else:
				_append_span(line, word, key)
				used += word_width
	if not line.is_empty(): lines.append(line)
	return lines


static func _append_span(line: Array, text: String, key: String) -> void:
	if not line.is_empty() and str(line.back()[1]) == key:
		line.back()[0] += text
	else:
		line.append([text, key])


## Current orders, defences and contact uncertainty remain on the summary even when long
## equipment names wrap. The expanded view retains the familiar full readout order.
static func summary_rows(rows: Array) -> Array:
	if rows.is_empty(): return []
	var result: Array = [rows[0]]
	var priority := ["STATUS: ", "DEFENCE: ", "COMMS: ", "ORDERS: ", "IDENTITY: ", "PLOT: ", "POSITION: ", "%DAMAGE: "]
	for label: String in priority:
		for index in range(1, rows.size()):
			if rows[index].size() > 0 and str(rows[index][0][0]) == label:
				result.append(rows[index])
	for index in range(1, rows.size()):
		if rows[index].is_empty() or str(rows[index][0][0]) not in priority:
			result.append(rows[index])
	return result


func open_details() -> void:
	if not is_inside_tree(): return
	if _details == null: _create_details()
	_details_focus = get_viewport().gui_get_focus_owner()
	refresh()
	_refresh_details()
	# Embedded subwindow placement is in physical window pixels; the command canvas may have
	# a different logical extent. Size and centre against the actual window to avoid a clipped
	# footer at 720p, then apply the same effective font scale as the command canvas.
	var available := Vector2(get_window().size)
	var effective_scale := get_viewport().get_stretch_transform().get_scale().x
	_details.content_scale_factor = effective_scale
	_details.size = Vector2i(minf(760.0 * effective_scale, available.x - 32.0), minf(620.0 * effective_scale, available.y - 64.0))
	_details.position = Vector2i((available - Vector2(_details.size)) * 0.5)
	_details.show()
	_details_close.grab_focus()


func close_details() -> void:
	if _details == null or not _details.visible: return
	_details.hide()
	if is_instance_valid(_details_focus) and _details_focus.is_visible_in_tree() and _details_focus.focus_mode != Control.FOCUS_NONE:
		_details_focus.grab_focus()
	elif _details_button != null and is_visible_in_tree() and _details_button.focus_mode != Control.FOCUS_NONE:
		_details_button.grab_focus()


func _create_details() -> void:
	_details = load("res://scripts/ui/readout_window.gd").new()
	_details.name = "ReadoutDetails"
	_details.title = "Command readout"
	_details.borderless = true
	_details.visible = false
	_details.transient = true
	_details.exclusive = true
	_details.min_size = Vector2i(280, 200)
	_details.theme = UITheme.data_theme()
	_details.close_requested.connect(close_details)
	add_child(_details)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", UITheme.bevel_frame(12.0))
	_details.add_child(panel)
	var background := StyleBoxFlat.new()
	background.bg_color = COL_BG
	background.set_content_margin_all(12.0)
	panel.add_theme_stylebox_override("panel", background)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = "COMMAND READOUT"
	heading.add_theme_color_override("font_color", COL_LABEL)
	box.add_child(heading)
	_details_alert = Label.new()
	_details_alert.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_alert.add_theme_color_override("font_color", COL_ALERT)
	box.add_child(_details_alert)
	_details_text = RichTextLabel.new()
	_details_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details_text.selection_enabled = true
	_details_text.focus_mode = Control.FOCUS_ALL
	_details_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_text.add_theme_font_override("normal_font", UITheme.data_font())
	_details_text.add_theme_font_size_override("normal_font_size", 15)
	_details_text.accessibility_name = "Complete live command readout"
	box.add_child(_details_text)
	var footer := HBoxContainer.new()
	box.add_child(footer)
	_details_clock = Label.new()
	_details_clock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_details_clock)
	_details_close = Button.new()
	_details_close.text = "CLOSE  [Esc]"
	_details_close.pressed.connect(close_details)
	footer.add_child(_details_close)


func _refresh_details() -> void:
	var signature := rows_text(_rows)
	if signature != _details_signature:
		var scroll := _details_text.get_v_scroll_bar().value
		_details_text.clear()
		for row: Array in _rows:
			for span: Array in row:
				if str(span[0]) in [CELL, "FLOW"]: continue
				_details_text.push_color(_color(str(span[1])))
				_details_text.add_text(str(span[0]))
				_details_text.pop()
			_details_text.newline()
		_details_text.get_v_scroll_bar().set_deferred("value", scroll)
		_details_text.accessibility_description = signature
		_details_signature = signature
	_details_alert.text = threat_text
	_details_alert.visible = threat_text != ""
	_details_clock.text = "%s · %s" % [clock_text(), "PAUSED" if SimClock.paused else "%dx — simulation running" % int(SimClock.multiplier())]

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
	var y := MARGIN.y
	var index := 0
	var rows := summary_rows(_rows)
	grid_hidden = 0
	_hidden_rows = 0
	_row_tooltips.clear()
	_more_drawn = false
	if _details_button != null:
		_details_button.position = Vector2(maxf(MARGIN.x, size.x - MARGIN.x - 94.0), MARGIN.y)
		_details_button.size = Vector2(94.0, 24.0)
	while index < rows.size():
		var row: Array = rows[index]
		index += 1
		if _is_cell(row):
			var block: Array = [row]
			while index < rows.size() and _is_cell(rows[index]):
				block.append(rows[index])
				index += 1
			var free := int(floor((limit_y - y) / line_h))
			y = _draw_grid(block, y, maxi(free - (rows.size() - index), mini(free, 1)), font, fs, line_h, ascent)
			continue
		var width := size.x - 2.0 * MARGIN.x
		if index == 1: width -= 104.0
		var wrapped := wrap_spans(row, font, fs, width)
		var free_lines := int(floor((limit_y - y) / line_h))
		# Preserve at least one line of ammunition and its actionable +N MORE control. Long
		# class names and range summaries may use the expanded view, but never erase readiness.
		if rows.slice(index).any(func(next: Array) -> bool: return _is_cell(next)):
			free_lines -= 1
		var max_lines := mini(1 if index == 1 else 2, free_lines)
		if max_lines <= 0:
			_hidden_rows += 1
			continue
		var visible_lines := mini(max_lines, wrapped.size())
		var clipped := wrapped.size() > visible_lines
		_row_tooltips.append({"rect": Rect2(MARGIN.x, y, width, visible_lines * line_h), "text": rows_text([row])})
		for line_index in visible_lines:
			var line: Array = wrapped[line_index].duplicate(true)
			if clipped and line_index == visible_lines - 1:
				_ellipsize(line, font, fs, width)
			var x := MARGIN.x
			for span: Array in line:
				var span_fs := fs + (1 if str(span[1]) == TITLE else 0)
				draw_string(font, Vector2(x, y + ascent), str(span[0]), HORIZONTAL_ALIGNMENT_LEFT, width - (x - MARGIN.x), span_fs, _color(str(span[1])))
				x += font.get_string_size(str(span[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, span_fs).x
			y += line_h
		if clipped: _hidden_rows += 1
		if index == 1: y = maxf(y, MARGIN.y + 28.0)
	if _details_button != null:
		_details_button.text = "DETAILS +" if _hidden_rows > 0 or grid_hidden > 0 else "DETAILS"
		_details_button.tooltip_text = "Expand the complete live readout" + (" (%d shortened or hidden rows, %d additional weapon systems)" % [_hidden_rows, grid_hidden] if _hidden_rows > 0 or grid_hidden > 0 else "") + ". The clock keeps its current state."
	# Toggling visibility off and on during every redraw cancels a mouse press before release.
	# Keep the native button alive across refreshes and only hide it when overflow disappears.
	if _more_button != null: _more_button.visible = _more_drawn
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


func _ellipsize(line: Array, font: Font, fs: int, width: float) -> void:
	var ellipsis_width := font.get_string_size("…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while not line.is_empty():
		var used := 0.0
		for span: Array in line:
			used += font.get_string_size(str(span[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs + (1 if str(span[1]) == TITLE else 0)).x
		if used + ellipsis_width <= width: break
		line.back()[0] = str(line.back()[0]).substr(0, str(line.back()[0]).length() - 1)
		if str(line.back()[0]) == "": line.pop_back()
	line.append(["…", LABEL])


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
			_more_drawn = true
			if _more_button != null:
				_more_button.text = "+%d MORE" % int(fit["more"])
				_more_button.accessibility_name = "Show %d more weapon systems" % int(fit["more"])
				_more_button.position = Vector2(cx, cy - ascent)
				_more_button.size = Vector2(col_w, line_h)
				_more_button.show()
			break
		var spans: Array = block[k]
		var count := str(spans[1][0]).strip_edges()
		var count_w := font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_row_tooltips.append({"rect": Rect2(cx, cy - ascent, col_w, line_h), "text": rows_text([spans])})
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
	for row: Dictionary in _row_tooltips:
		if (row["rect"] as Rect2).has_point(at_position):
			return str(row["text"])
	return ""
