class_name UnitPanel
extends PanelContainer
## Left panel: details of the selected unit(s), and the event log underneath. Refreshed from
## ground truth for player-owned units (the player has perfect knowledge of their own ships).

signal inspect_requested(platform_id: String)

const MAX_EVENTS := 60

var _header: Label
var _subtitle: Label
var _bars: ReadinessBars
var _body: RichTextLabel
var _log: RichTextLabel
var _log_header: Label
var _units: Array = []
var _events: PackedStringArray = []
var _accum := 0.0
var roster: FleetRoster
var _portrait: PlatformPortrait


func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var hl := Label.new()
	hl.text = "TASK GROUP  /  SELECT TO COMMAND"
	hl.theme_type_variation = "HeaderLabel"
	v.add_child(hl)
	roster = FleetRoster.new()
	roster.custom_minimum_size.y = 144
	v.add_child(roster)
	_header = Label.new()
	_header.text = "—"
	_header.theme_type_variation = "TitleLabel"
	_header.clip_text = true
	v.add_child(_header)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = "DimLabel"
	_subtitle.clip_text = true
	v.add_child(_subtitle)
	_portrait = PlatformPortrait.new()
	_portrait.panel = self
	_portrait.custom_minimum_size.y = 128
	v.add_child(_portrait)
	var inspect := Button.new()
	inspect.text = "INSPECT PLATFORM  /  3D"
	inspect.add_theme_font_size_override("font_size", 11)
	inspect.pressed.connect(func() -> void:
		if not _units.is_empty():
			inspect_requested.emit(_units[0].spec.id))
	v.add_child(inspect)
	_bars = ReadinessBars.new()
	_bars.custom_minimum_size.y = 0
	v.add_child(_bars)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	_body = RichTextLabel.new()
	_body.name = "PLATFORM"
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = true
	_body.selection_enabled = false
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.size_flags_stretch_ratio = 1.6
	tabs.add_child(_body)
	_log_header = Label.new()
	_log_header.text = "EVENT LOG"
	_log_header.theme_type_variation = "HeaderLabel"
	_log_header.hide()
	v.add_child(_log_header)
	_log = RichTextLabel.new()
	_log.name = "EVENT LOG"
	_log.bbcode_enabled = true
	_log.fit_content = false
	_log.scroll_active = true
	_log.scroll_following = true
	_log.selection_enabled = false
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size.y = 120
	_log.add_theme_font_size_override("normal_font_size", 11)
	tabs.add_child(_log)
	set_units([])


## The ships that could lend a hand alongside, for the fire state. Read from the roster's map, which
## already holds the unit manager; empty before a scenario is loaded.
func _units_near(u: Unit) -> Array:
	if roster == null or roster.map == null or roster.map.unit_manager == null:
		return [u]
	return roster.map.unit_manager.get_faction_units(u.faction)


func set_units(units: Array) -> void:
	_units = units.duplicate()
	_refresh()


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= 0.25:
		_accum = 0.0
		_refresh()


## Severity: "info", "warn", "alert", "good".
func add_event(text: String, severity := "info") -> void:
	var col := UITheme.HEX_DIM
	match severity:
		"warn":
			col = UITheme.HEX_AMBER
		"alert":
			col = UITheme.HEX_RED
		"good":
			col = UITheme.HEX_GREEN
		"info":
			col = UITheme.HEX_TEXT
	_events.append("[color=%s]%s[/color]  [color=%s]%s[/color]" % [UITheme.HEX_MUTED, SimClock.datetime_string().substr(11), col, text])
	if _events.size() > MAX_EVENTS:
		_events.remove_at(0)
	_log.text = "\n".join(_events)


func clear_events() -> void:
	_events = PackedStringArray()
	_log.text = ""


func _flight_state_text(a: Unit) -> String:
	if not a.alive:
		return "[color=%s]LOST[/color]" % UITheme.HEX_RED
	match a.flight_state:
		Unit.FlightState.STOWED:
			return "[color=%s]ready[/color]" % UITheme.HEX_GREEN
		Unit.FlightState.LAUNCHING:
			return "launching, %.0f s" % a.state_timer_s
		Unit.FlightState.RECOVERING:
			return "landing approach"
		Unit.FlightState.TURNAROUND:
			return "[color=%s]turnaround, %s[/color]" % [UITheme.HEX_DIM, _mmss(a.state_timer_s)]
	if a.tanking_on != null:
		return "[color=%s]airborne, tanking on %s[/color]" % [UITheme.HEX_AMBER, a.tanking_on.callsign]
	return "[color=%s]airborne, RTB[/color]" % UITheme.HEX_AMBER if a.returning else "[color=%s]airborne[/color]" % UITheme.HEX_BLUE


func _mmss(seconds: float) -> String:
	var s := maxi(int(roundf(seconds)), 0)
	return "%d:%02d" % [s / 60, s % 60]


func _first_active_range(u: Unit) -> float:
	for s in u.sensors:
		if s.kind == "sonar":
			return s.active_range_nm
	return 0.0


func _chip(text: String, hex: String) -> String:
	return "[bgcolor=#12222e][color=%s] %s [/color][/bgcolor]" % [hex, text]


func _h(text: String) -> String:
	return "\n[color=%s][b]%s[/b][/color]" % [UITheme.HEX_ACCENT, text]


func _kv(k: String, v: String) -> String:
	return "[color=%s]%-6s[/color] %s" % [UITheme.HEX_DIM, k, v]


func _refresh() -> void:
	if _units.is_empty():
		_header.text = "No selection"
		_subtitle.text = "Click a symbol on the tactical picture"
		_bars.unit = null
		_bars.custom_minimum_size.y = 0
		_body.text = "\n".join([
			_h("CONTROLS"),
			_kv("Click", "select   ·   Shift+click add"),
			_kv("G / Move", "arm route   ·   left-click water   ·   Shift chains"),
			_kv("Pan", "middle/right/Option-drag"),
			_kv("Wheel", "zoom   ·   WASD pan"),
			_kv("Space", "pause   ·   1–6 time speed"),
			_kv("R / P / E", "radar · ping · emissions control"),
			_kv("F1", "briefing   ·   F2 key   ·   F4 rings"),
			_kv("F5", "trails   ·   F6 land   ·   F3 debug truth"),
			_h("HOW TO FIGHT"),
			"Build the picture first: launch the E-2D, keep the fighters on the threat axis, and let contacts classify before you shoot. Ships defend themselves; you decide emissions, posture, station and magazines.",
		])
		return
	if _units.size() == 1:
		var u: Unit = _units[0]
		_header.text = u.callsign
		_subtitle.text = "%s  ·  %s" % [u.spec.display_name, u.spec.nation]
		_bars.unit = u
		_bars.custom_minimum_size.y = _bars.preferred_height(u)
		var lines := PackedStringArray()
		var chips := PackedStringArray()
		var cond := Damage.condition_text(u)
		chips.append(_chip(cond, UITheme.HEX_GREEN if cond == "OPERATIONAL" else (UITheme.HEX_AMBER if cond == "LIGHT DAMAGE" else UITheme.HEX_RED)))
		chips.append(_chip("RADIATING" if (u.radar_emitting() or u.active_sonar_on) else "EMCON SILENT", UITheme.HEX_ACCENT if (u.radar_emitting() or u.active_sonar_on) else UITheme.HEX_DIM))
		var roe_text: String = ["WPNS HOLD", "WPNS TIGHT", "WPNS FREE"][u.roe]
		chips.append(_chip(roe_text, [UITheme.HEX_RED, UITheme.HEX_AMBER, UITheme.HEX_GREEN][u.roe]))
		if not u.datalink_connected():
			chips.append(_chip("OFF LINK", UITheme.HEX_AMBER))
		if u.jamming():
			chips.append(_chip("JAMMING", "#f08cf0"))
		if u.fire > 0.0:
			chips.append(_chip("FIRE %d%%%s" % [int(round(u.fire * 100.0)), " SPREADING" if Damage.fire_out_of_control(u, _units_near(u)) else ""], UITheme.HEX_RED))
		if u.flooding > 0.0:
			chips.append(_chip("FLOODING %d%%" % int(round(u.flooding * 100.0)), "#5aa0ff"))
		if Damage.repairing(u):
			chips.append(_chip("DAMAGE CONTROL", UITheme.HEX_AMBER))
		lines.append(" ".join(chips))
		lines.append("[color=%s]%s[/color]" % [UITheme.HEX_DIM, u.spec.role])
		if u.spec.vls_cells > 0:
			lines.append(_kv("VLS", "%d / %d cells allocated" % [u.spec.occupied_vls_cells(), u.spec.vls_cells]))
		if u.spec.aircraft_capacity > 0:
			lines.append(_kv("DECK", u.spec.flight_facility().to_upper()))
		lines.append(_h("NAVIGATION"))
		lines.append(_kv("POS", "%s  %s" % [Geo.format_axis(u.position.x, "E", "W"), Geo.format_axis(u.position.y, "N", "S")]))
		lines.append(_kv("HDG", "%s   ordered %s" % [Geo.format_bearing(u.heading_deg), Geo.format_bearing(u.ordered_heading_deg)]))
		lines.append(_kv("SPD", "%.1f kn   ordered %.0f · max %.0f" % [u.speed_kn, u.ordered_speed_kn, u.effective_max_speed()]))
		if u.spec.max_depth_m > 0.0:
			var limit := Acoustics.max_operating_depth_m(u)
			var limit_text := "max %.0f" % u.spec.max_depth_m if limit >= u.spec.max_depth_m - 0.5 else "[color=%s]floor-limited %.0f[/color]" % [UITheme.HEX_AMBER, limit]
			var side := ""
			if Acoustics.layer_present_at(Acoustics.bottom_m(u)):
				side = "   [color=%s]%s LAYER[/color]" % [UITheme.HEX_GREEN if not Acoustics.is_above_layer(u.depth_m) else UITheme.HEX_DIM, "UNDER" if not Acoustics.is_above_layer(u.depth_m) else "ABOVE"]
			lines.append(_kv("DEPTH", "%.0f m   ordered %.0f · %s%s" % [u.depth_m, u.ordered_depth_m, limit_text, side]))
		if (u.has_sonar() or u.spec.max_depth_m > 0.0) and u.needs_sea_room():
			var water := Acoustics.column_summary(u)
			if water != "":
				lines.append(_kv("WATER", water))
		if u.is_aircraft():
			lines.append(_kv("ALT", "%.0f m   ordered %.0f · ceiling %.0f" % [u.altitude_m, u.ordered_altitude_m, u.spec.max_altitude_m]))
			lines.append(_kv("FLIGHT", _flight_state_text(u)))
			if u.recovery_base != null:
				lines.append(_kv("LAND AT", u.recovery_base.callsign))
			if u.spec.sonobuoy_count > 0:
				lines.append(_kv("BUOYS", "%d" % u.sonobuoys))
		if u.in_formation():
			lines.append(_kv("STATN", "on %s, %.1f nm off station" % [u.formation_leader.callsign, u.position.distance_to(Formation.station_for(u))]))
		if not u.waypoints.is_empty():
			var wp: Vector2 = u.waypoints[0]
			lines.append(_kv("NEXT", "BRG %s  RNG %.1f nm  (%d wpts)" % [Geo.format_bearing(Geo.bearing_deg(u.position, wp)), Geo.distance_nm(u.position, wp), u.waypoints.size()]))
		if u.has_sonar():
			lines.append(_kv("NOISE", "%.2f%s" % [Detection.acoustic_noise(u), "  [color=%s]CAVITATING[/color]" % UITheme.HEX_RED if Detection.is_cavitating(u) else ""]))
		if u.spec.aircraft_capacity > 0 and not u.embarked.is_empty():
			var turning := u.turnaround_aircraft().size()
			var header := "AIR WING  %d of %d ready" % [u.stowed_aircraft().size(), u.embarked.size()]
			if turning > 0:
				header += "  ·  %d on the deck" % turning
			lines.append(_h(header))
			# A deck's throughput is what makes a carrier a carrier, so say what it is rather than
			# leaving the player to work it out from how slowly aircraft appear.
			lines.append("  [color=%s]%d launch %s · %d recovery %s · %s turnaround[/color]" % [
				UITheme.HEX_DIM, u.spec.launch_capacity(),
				"spots" if u.spec.launch_capacity() != 1 else "spot",
				u.spec.recovery_capacity(),
				"spots" if u.spec.recovery_capacity() != 1 else "spot",
				_mmss(u.spec.turnaround_time_s())])
			for a in u.embarked:
				var squadron := "" if a.squadron == "" else " [color=%s]%s[/color]" % [UITheme.HEX_DIM, a.squadron]
				var fuel := "" if not a.in_flight() else "  [color=%s]%.0f%% fuel[/color]" % [UITheme.HEX_DIM, a.fuel_fraction() * 100.0]
				lines.append("  %s%s [color=%s]%s[/color] · %s%s" % [a.callsign, squadron, UITheme.HEX_DIM, a.spec.short_name, _flight_state_text(a), fuel])
		lines.append(_h("SENSORS"))
		if u.has_radar():
			for s in u.sensors:
				if s.kind == "radar":
					lines.append("  %s  [color=%s]%s[/color]" % [s.display_name, UITheme.HEX_ACCENT if u.radar_emitting() else UITheme.HEX_DIM, "ACTIVE" if u.radar_emitting() else "SILENT"])
			lines.append("  [color=%s]~%.0f nm vs surface (horizon) · %.0f nm vs air[/color]" % [UITheme.HEX_DIM, Detection.nominal_radar_ring_nm(u), _best_air_range(u)])
		for s in u.sensors:
			if s.kind == "jammer":
				lines.append("  %s  [color=%s]%s[/color]" % [s.display_name, "#f08cf0" if u.jamming() else UITheme.HEX_DIM, "RADIATING %.0f nm" % s.jam_range_nm if u.jamming() else "OFF"])
		if u.has_esm():
			lines.append("  ESM passive, ~%.0f nm against a radiating ship" % Detection.nominal_esm_ring_nm(u))
		if u.has_sonar():
			for s in u.sensors:
				if s.kind == "sonar":
					var where := ""
					if not u.is_submarine() and s.array_depth_m > 0.0 and (not s.requires_hover or u.is_hovering()):
						var d := Acoustics.sensor_depth_m(u, s)
						var under := Acoustics.layer_present_at(Acoustics.bottom_m(u)) and not Acoustics.is_above_layer(d)
						where = "  [color=%s]%s %d m%s[/color]" % [UITheme.HEX_DIM, "DIPPED" if s.requires_hover else "STREAMED", int(d), " · under layer" if under else ""]
					lines.append("  %s  [color=%s]%s[/color]%s" % [s.display_name, UITheme.HEX_GREEN if u.active_sonar_on else UITheme.HEX_DIM, "PINGING" if u.active_sonar_on else "PASSIVE", where])
			lines.append("  [color=%s]~%.0f nm passive · %.0f nm active · sea state %d[/color]" % [UITheme.HEX_DIM, Detection.nominal_passive_ring_nm(u), Detection.best_active_sonar_nm(u) if u.active_sonar_on else _first_active_range(u), Detection.sea_state])
		if u.weapons.is_empty():
			lines.append(_h("MAGAZINES"))
			lines.append("  none")
		else:
			var offensive: Array[WeaponSpec] = []
			var defensive: Array[WeaponSpec] = []
			for w in u.weapons:
				if w.is_interceptor():
					defensive.append(w)
				else:
					offensive.append(w)
			if not offensive.is_empty():
				lines.append(_h("STRIKE"))
				for w in offensive:
					lines.append(_mag_line(u, w))
			if not defensive.is_empty():
				lines.append(_h("DEFENCE"))
				for w in defensive:
					lines.append(_mag_line(u, w))
		lines.append("\n[color=%s]%.0f m · %.0f t · %s[/color]" % [UITheme.HEX_MUTED, u.spec.length_m, u.spec.displacement_t, u.spec.category])
		_body.text = "\n".join(lines)
		return
	_header.text = "%d units selected" % _units.size()
	_subtitle.text = "Orders apply to all selected units"
	_bars.unit = null
	_bars.custom_minimum_size.y = 0
	var lines := PackedStringArray()
	for u: Unit in _units:
		var cond := Damage.condition_text(u)
		lines.append("[b]%s[/b]  [color=%s]%s[/color]" % [u.callsign, UITheme.HEX_DIM, u.spec.short_name])
		lines.append("   %s   [color=%s]%s[/color]" % [u.status_line(), UITheme.HEX_GREEN if cond == "OPERATIONAL" else UITheme.HEX_AMBER, cond])
	_body.text = "\n".join(lines)


func _mag_line(u: Unit, w: WeaponSpec) -> String:
	var n := u.magazine_count(w.id)
	var col := UITheme.HEX_TEXT
	if n == 0:
		col = UITheme.HEX_RED
	elif n <= 4:
		col = UITheme.HEX_AMBER
	var tag := ""
	if w.target_types.has("ballistic") and w.type == "sam":
		tag = "  [color=%s]BMD[/color]" % UITheme.HEX_ACCENT
	return "  [color=%s]%3d[/color]  %s  [color=%s]%.0f nm[/color]%s" % [col, n, w.display_name, UITheme.HEX_DIM, w.max_range_nm, tag]


func _best_air_range(u: Unit) -> float:
	var best := 0.0
	for s in u.sensors:
		if s.kind == "radar":
			best = maxf(best, s.range_air_nm)
	return best
