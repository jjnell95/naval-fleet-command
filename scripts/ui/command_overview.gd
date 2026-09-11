class_name CommandOverview
extends Control
## Watch summary. Every contact count comes from the current console's held picture.
var map: TacticalMap
var _font: Font
var _elapsed := 0.0

func _ready() -> void:
	_font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > 0.3:
		_elapsed = 0.0
		queue_redraw()

func _draw() -> void:
	if map == null or map.unit_manager == null:
		return
	var own := map.unit_manager.get_faction_units(map.player_faction)
	var air := 0
	var ready := 0
	var sam := 0
	var linked := 0
	for u: Unit in own:
		if not u.alive:
			continue
		if u.airborne():
			air += 1
		if u.is_aircraft() and u.flight_state == Unit.FlightState.STOWED:
			ready += 1
		if u.datalink_connected():
			linked += 1
		for w in u.weapons:
			if w.type == "sam":
				sam += u.magazine_count(w.id)
	var ref := map.reference_unit()
	var tracks := map._visible_tracks()
	var hostile := 0
	for t: Track in tracks:
		if t.identity == "HOSTILE":
			hostile += 1
	var inbound := AirDefence.inbound_threats(map.unit_manager, map.threat_manager, map.player_faction, ref).size()
	var load := map.weapon_manager.channel_targets(ref).size() if ref != null else 0
	var channel_cap := ref.spec.fire_control_channels if ref != null else 0
	var cols := [UITheme.COL_BLUE, UITheme.COL_ACCENT, UITheme.COL_RED if inbound else UITheme.COL_GREEN, UITheme.COL_BLUE, UITheme.COL_ACCENT, UITheme.COL_AMBER if load >= channel_cap and channel_cap > 0 else UITheme.COL_ACCENT]
	var labels := ["NETWORK PARTICIPANTS", "HELD TRACKS", "INBOUND WEAPONS", "AIR OPERATIONS", "DEFENSIVE MISSILES", "CONSOLE CHANNELS"]
	var values := ["%02d" % linked, "%02d" % tracks.size(), "%02d" % inbound, "%02d / %02d" % [air, ready], "%03d" % sam, "%d / %d" % [load, channel_cap]]
	var captions := ["%s PICTURE" % ("SHARED" if ref == null or ref.datalink_connected() else "LOCAL ONLY"), "%d classified hostile" % hostile, "No detected inbound" if inbound == 0 else "Threat evaluation active", "airborne / ready on deck", "SAM rounds across task group", "active / available on selection"]
	var width := size.x / 6.0
	for i in 6:
		var x := width * i
		draw_rect(Rect2(x + 2, 0, width - 4, size.y), UITheme.COL_PANEL)
		draw_line(Vector2(x + 16, 0), Vector2(x + width - 16, 0), Color(cols[i], 0.6), 2)
		draw_string(_font, Vector2(x + 16, 20), labels[i], HORIZONTAL_ALIGNMENT_LEFT, int(width - 28), 10, UITheme.COL_DIM)
		draw_string(_font, Vector2(x + 16, 50), values[i], HORIZONTAL_ALIGNMENT_LEFT, int(width - 28), 28, cols[i])
		draw_string(_font, Vector2(x + 16, 69), captions[i], HORIZONTAL_ALIGNMENT_LEFT, int(width - 28), 10, UITheme.COL_DIM)
