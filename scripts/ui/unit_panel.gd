class_name UnitPanel
extends PanelContainer
## Left panel: details of the selected unit(s). Refreshed each frame from ground truth for
## player-owned units (the player has perfect knowledge of their own ships).

var _header: Label
var _body: Label
var _units: Array = []


func _ready() -> void:
	var v := VBoxContainer.new()
	add_child(v)
	_header = Label.new()
	_header.text = "SELECTED UNIT"
	v.add_child(_header)
	_body = Label.new()
	_body.clip_text = true
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)
	set_units([])


func set_units(units: Array) -> void:
	_units = units.duplicate()
	_refresh()


func _process(_delta: float) -> void:
	if not _units.is_empty():
		_refresh()


func _flight_state_text(a: Unit) -> String:
	if not a.alive:
		return "LOST"
	match a.flight_state:
		Unit.FlightState.STOWED:
			return "ready"
		Unit.FlightState.LAUNCHING:
			return "launching, %.0f s" % a.state_timer_s
		Unit.FlightState.RECOVERING:
			return "recovering, %.0f s" % a.state_timer_s
	return "airborne, RTB" if a.returning else "airborne"


func _first_active_range(u: Unit) -> float:
	for s in u.sensors:
		if s.kind == "sonar":
			return s.active_range_nm
	return 0.0


func _refresh() -> void:
	if _units.is_empty():
		_header.text = "SELECTED UNIT"
		_body.text = "None.\n\nLeft click: select\nShift+click: add\nDrag: box select\nRight click: move\nShift+right click: add waypoint\nWheel: zoom  ·  Mid/right drag: pan\nSpace: pause  ·  1-6: time speed\nR: radar  ·  P: ping  ·  E: emissions  ·  F3: debug"
		return
	if _units.size() == 1:
		var u: Unit = _units[0]
		_header.text = u.callsign
		var lines := PackedStringArray()
		lines.append(u.spec.display_name)
		lines.append("%s  ·  %s" % [u.spec.nation, u.faction])
		lines.append("")
		lines.append("STATE %s  (%.0f%%)" % [Damage.condition_text(u), Damage.health_fraction(u) * 100.0])
		lines.append("SYS   %s" % Damage.damage_report(u))
		lines.append("EMCON %s  ·  WEAPONS %s" % [
			"RADIATING" if (u.radar_on or u.active_sonar_on) else "SILENT",
			["HOLD", "TIGHT", "FREE"][u.roe]])
		if u.in_formation():
			lines.append("STATN on %s  %.1f nm off" % [u.formation_leader.callsign, u.position.distance_to(Formation.station_for(u))])
		if not u.datalink_connected():
			lines.append("LINK  off the network")
		lines.append("POS   %s  %s" % [Geo.format_axis(u.position.x, "E", "W"), Geo.format_axis(u.position.y, "N", "S")])
		lines.append("HDG   %s   (ordered %s)" % [Geo.format_bearing(u.heading_deg), Geo.format_bearing(u.ordered_heading_deg)])
		lines.append("SPD   %.1f kn  (ordered %.0f, max %.0f)" % [u.speed_kn, u.ordered_speed_kn, u.spec.max_speed_kn])
		if u.spec.max_depth_m > 0.0:
			lines.append("DEP   %.0f m  (ordered %.0f, max %.0f)" % [u.depth_m, u.ordered_depth_m, u.spec.max_depth_m])
		if u.is_aircraft():
			lines.append("ALT   %.0f m  (ordered %.0f, ceiling %.0f)" % [u.altitude_m, u.ordered_altitude_m, u.spec.max_altitude_m])
			lines.append("FUEL  %.0f%%  (%s)" % [u.fuel_fraction() * 100.0, _flight_state_text(u)])
			if u.spec.sonobuoy_count > 0:
				lines.append("BUOYS %d" % u.sonobuoys)
		if u.spec.aircraft_capacity > 0:
			lines.append("AIR   %d of %d ready" % [u.stowed_aircraft().size(), u.embarked.size()])
			for a in u.embarked:
				lines.append("   %-16s %s" % [a.callsign, _flight_state_text(a)])
		if u.has_sonar():
			lines.append("NOISE %.2f%s" % [Detection.acoustic_noise(u), "  CAVITATING" if Detection.is_cavitating(u) else ""])
		lines.append("WPTS  %d" % u.waypoints.size())
		if not u.waypoints.is_empty():
			var wp: Vector2 = u.waypoints[0]
			lines.append("NEXT  BRG %s  RNG %.1f nm" % [Geo.format_bearing(Geo.bearing_deg(u.position, wp)), Geo.distance_nm(u.position, wp)])
		lines.append("")
		if u.has_radar():
			lines.append("RADAR  %s" % ("ACTIVE" if u.radar_on else "SILENT (EMCON)"))
			for s in u.sensors:
				if s.kind == "radar":
					lines.append("   %s" % s.display_name)
			lines.append("   ~%.0f nm vs surface (horizon-limited)" % Detection.nominal_radar_ring_nm(u))
		else:
			lines.append("RADAR  none")
		if u.has_esm():
			lines.append("ESM   passive, ~%.0f nm against a radiating ship" % Detection.nominal_esm_ring_nm(u))
		if u.has_sonar():
			lines.append("SONAR  %s" % ("ACTIVE — PINGING" if u.active_sonar_on else "PASSIVE"))
			for s in u.sensors:
				if s.kind == "sonar":
					lines.append("   %s" % s.display_name)
			lines.append("   ~%.0f nm passive  ·  %.0f nm active" % [Detection.nominal_passive_ring_nm(u), Detection.best_active_sonar_nm(u) if u.active_sonar_on else _first_active_range(u)])
		lines.append("")
		if u.weapons.is_empty():
			lines.append("MAGAZINES  none")
		else:
			var offensive: Array[WeaponSpec] = []
			var defensive: Array[WeaponSpec] = []
			for w in u.weapons:
				if w.is_interceptor():
					defensive.append(w)
				else:
					offensive.append(w)
			if not offensive.is_empty():
				lines.append("STRIKE")
				for w in offensive:
					lines.append("   %-20s %4d  %.0f nm" % [w.display_name, u.magazine_count(w.id), w.max_range_nm])
			if not defensive.is_empty():
				lines.append("DEFENCE")
				for w in defensive:
					lines.append("   %-20s %4d  %.1f nm" % [w.display_name, u.magazine_count(w.id), w.max_range_nm])
			lines.append("   %-20s %4d" % ["Decoys", u.decoys])
		lines.append("")
		lines.append("LEN %.0f m  ·  %.0f t" % [u.spec.length_m, u.spec.displacement_t])
		_body.text = "\n".join(lines)
		return
	_header.text = "%d UNITS SELECTED" % _units.size()
	var lines := PackedStringArray()
	for u: Unit in _units:
		lines.append("%s\n   %s\n   %s" % [u.callsign, u.status_line(), Damage.condition_text(u)])
	_body.text = "\n".join(lines)
