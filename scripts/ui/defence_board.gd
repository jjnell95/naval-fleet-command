class_name DefenceBoard
extends Control
## Reads only friendly readiness and already detected threats. No ground-truth enemy access.
var contacts: ContactPanel
var _timer := 0.0

func _ready() -> void:
	tooltip_text = "Detected inbound weapons only. Channel load counts active missile interception engagements. Magazine counts are rounds, not VLS cells. Emissions and damage affect readiness."

func _process(delta: float) -> void:
	_timer += delta
	if _timer > 0.25:
		_timer = 0
		queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	var cyan := Color("70e2d3")
	draw_rect(Rect2(Vector2.ZERO,size),Color("091722"))
	draw_string(font,Vector2(12,22),"AIR / MISSILE DEFENCE",HORIZONTAL_ALIGNMENT_LEFT,-1,14,cyan)
	if contacts == null or contacts.map == null: return
	var m := contacts.map
	var threats := AirDefence.inbound_threats(m.unit_manager,m.threat_manager,m.player_faction)
	var rounds := 0
	var channels := 0
	var used := 0
	var loads := AirDefence._channels_in_use(m.weapon_manager)
	for u in m.unit_manager.get_faction_units(m.player_faction):
		if u.can_fire(): channels += u.spec.fire_control_channels
		used += int(loads.get(u,0))
		for w in u.defensive_weapons(): rounds += u.magazine_count(w.id)
	draw_string(font,Vector2(12,47),"%02d INBOUND   /   %d DEFENCE RDS" % [threats.size(),rounds],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("ffbe77") if not threats.is_empty() else cyan)
	draw_string(font,Vector2(12,68),"CHANNELS %d / %d ACTIVE" % [used,channels],HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("9fb7c7"))
	draw_rect(Rect2(12,79,size.x-24,3),Color("294552"))
	draw_rect(Rect2(12,79,(size.x-24)*clampf(float(used)/maxi(channels,1),0,1),3),cyan)
	if threats.is_empty():
		draw_string(font,Vector2(12,108),"NO DETECTED INBOUND WEAPONS",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("7d96a7"))
	else:
		for i in mini(3,threats.size()):
			var t: Dictionary = threats[i]
			draw_string(font,Vector2(12,106+i*19),"%s / %.0fs" % [t.target.callsign,t.time_s],HORIZONTAL_ALIGNMENT_LEFT,int(size.x-24),12,Color("ff977f"))
	draw_string(font,Vector2(12,size.y-10),"SHARED PICTURE · GAMEPLAY ESTIMATES",HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color("7d96a7"))
