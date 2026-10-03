extends TestCase
## Exercise the real Main event handlers without creating the full application scene. Silent
## submarine facts may enter the after-action counters, never the live commander's telemetry.

class RecordingVoice extends CrewVoice:
	var reported_events: Array[String] = []
	func say(event: String, _speaker: Variant = null, _fields := {}) -> void:
		reported_events.append(event)

var _main: Main
var _voice: RecordingVoice
var _boat: Unit
var _sound_was_enabled := true
var _old_scales: Array[float] = []
var _old_speed := 0


func _setup() -> void:
	Terrain.clear()
	Bathymetry.clear()
	_sound_was_enabled = SoundFx.enabled
	SoundFx.enabled = false
	_old_scales.assign(SimClock.speeds())
	_old_speed = SimClock.speed_index
	SimClock.set_speeds(GameOptions.NORMAL_SCALES)
	SimClock.set_speed_index(2)
	_main = Main.new()
	_main.simulation = Simulation.new()
	_main.simulation.unit_manager = UnitManager.new()
	_main.simulation.track_manager = TrackManager.new()
	_main.simulation.threat_manager = ThreatManager.new()
	_main.simulation.weapon_manager = WeaponManager.new()
	_main.simulation.weapon_manager.unit_manager = _main.simulation.unit_manager
	_main.map = TacticalMap.new()
	_main.map.unit_manager = _main.simulation.unit_manager
	_main.map.track_manager = _main.simulation.track_manager
	_main.map.threat_manager = _main.simulation.threat_manager
	_main._world_view = WorldView.new()
	_voice = RecordingVoice.new()
	_main.voice = _voice
	_main._stats = {"launched": 0, "intercepted": 0, "decoyed": 0, "hits": 0, "leaked": 0, "hostile_rounds": 0, "hits_taken": 0, "own_rounds": 0, "hits_scored": 0, "decoys_used": 0, "contacts": 0, "classified": 0}
	_boat = Unit.new()
	_boat.spec = DataDB.platform("usn_ssn_virginia")
	_boat.faction = "BLUE"
	_boat.callsign = "Silent boat"
	_boat.position = Vector2(80, 80)
	_boat.depth_m = 120.0
	_boat.ordered_depth_m = 120.0
	_main.simulation.unit_manager.add_unit(_boat)
	_main.simulation.unit_manager.configure_submarine_comms("BLUE", true)
	_main.map.selected.assign([_boat])


func _done() -> void:
	_main.simulation.weapon_manager.clear()
	_main.simulation.weapon_manager.free()
	_main.simulation.threat_manager.free()
	_main.simulation.track_manager.clear()
	_main.simulation.track_manager.free()
	_main.simulation.unit_manager.free()
	_main.simulation.free()
	_main.map.free()
	_main._world_view.free()
	_voice.free()
	_main.free()
	SoundFx.enabled = _sound_was_enabled
	SimClock.set_speeds(_old_scales)
	SimClock.set_speed_index(_old_speed)


func _torpedo(faction := "RED", shooter: Unit = null) -> Weapon:
	var w := Weapon.new()
	w.id = 31
	w.spec = DataDB.weapon("cw90_mk46")
	w.faction = faction
	w.shooter = shooter
	w.position = _boat.position + Vector2(1, 0)
	return w


func _assert_no_live_reports() -> void:
	assert_true(_main.radio.journal.is_empty(), "no radio traffic from a disconnected crew")
	assert_true(_voice.reported_events.is_empty(), "no private crew acknowledgment or warning")
	assert_true(_main.map._effects.is_empty(), "no position-revealing chart flash")
	assert_eq(SimClock.speed_index, 2, "hidden events do not reveal themselves by slowing the clock")


func test_silent_submarine_defence_and_damage_stay_out_of_live_telemetry() -> void:
	_setup()
	var threat := _torpedo()
	_main._on_interceptor_launched(_boat, threat.spec, threat, 1)
	_main._on_decoys_spent(_boat, 2)
	_main._on_weapon_defeated(threat, "DECOYED", _boat)
	_main._on_casualty_event(_boat, "fire_out")
	_main._on_casualty_event(_boat, "flooding_controlled")
	_main._on_engagement_rejected(_boat, threat.spec, "MAGAZINE EMPTY")
	_main._on_weapon_impact("RED", threat.spec, _boat, false)
	_main._on_weapon_impact("RED", threat.spec, _boat, true)
	_assert_no_live_reports()
	assert_eq(_main._stats["hits_taken"], 1, "debrief retains actual damage")
	assert_eq(_main._stats["decoys_used"], 2)
	_done()


func test_unreported_loss_has_no_live_position_effect_voice_or_slowdown() -> void:
	_setup()
	_boat.alive = false
	_main._on_unit_destroyed(_boat, "RED")
	_assert_no_live_reports()
	assert_true(_main._losses.has(_boat.callsign), "loss remains in after-action accounting")
	_done()


func test_private_detection_waits_then_announces_once_when_checkin_reports_it() -> void:
	_setup()
	var threat := _torpedo()
	_main.simulation.threat_manager.mark_detected("BLUE", threat, SimClock.sim_time, _boat)
	_main._on_threat_detected("BLUE", threat)
	_assert_no_live_reports()
	assert_eq(_main._unannounced.size(), 1)
	_boat.depth_m = SubmarineComms.DEPTH_M
	_main._announce_unannounced_threats()
	assert_true(_main.radio.journal.size() == 1 and _main.radio.journal[0].contains("TORPEDO IN THE WATER"))
	assert_eq(_main._unannounced.size(), 0)
	assert_eq(_voice.reported_events, ["torpedo_inbound"])
	_main._announce_unannounced_threats()
	assert_eq(_main.radio.journal.size(), 1, "repeated frames do not duplicate the check-in report")
	_main._on_casualty_event(_boat, "fire_out")
	assert_true(_main.radio.journal[-1].contains("Fire out"), "the reporting crew can speak again")
	_done()


func test_world_hides_private_own_rounds_and_private_hostile_detections_until_reported() -> void:
	_setup()
	var own_round := _torpedo("BLUE", _boat)
	var hostile := _torpedo()
	hostile.id = 32
	var wm := _main.simulation.weapon_manager
	var threats := _main.simulation.threat_manager
	wm.in_flight.assign([own_round, hostile])
	threats.mark_detected("BLUE", hostile, 0.0, _boat)
	assert_true(WorldPresentation.weapon_entries(wm, threats, "BLUE", _boat).is_empty())
	assert_eq(WorldPresentation.witness_point(_boat.position, [_boat], [], {}, _boat), Vector2.INF)
	_boat.depth_m = SubmarineComms.DEPTH_M
	var entries := WorldPresentation.weapon_entries(wm, threats, "BLUE", _boat)
	assert_eq(entries.size(), 2, "both the launch and the contact are reportable at check-in")
	assert_eq(WorldPresentation.witness_point(_boat.position, [_boat], [], {}, _boat), _boat.position)
	_done()


func test_shared_detection_still_reaches_commander_while_silent_boat_is_selected() -> void:
	_setup()
	var escort := Unit.new()
	escort.spec = DataDB.platform("usn_ddg_burke_iii")
	escort.faction = "BLUE"
	escort.callsign = "Reporting escort"
	escort.position = Vector2(5, 5)
	_main.simulation.unit_manager.add_unit(escort)
	var threat := _torpedo()
	_main.simulation.threat_manager.mark_detected("BLUE", threat, 0.0, escort)
	_main._on_threat_detected("BLUE", threat)
	assert_eq(_main.radio.journal.size(), 1)
	assert_true(_main._unannounced.is_empty())
	assert_true(WorldPresentation.weapon_visible(threat, "BLUE", _boat, _main.simulation.threat_manager, _main.simulation.unit_manager))
	assert_eq(_main._nearest_own_unit(threat), escort, "the connected watch makes the report")
	_done()


func test_queued_order_has_shore_receipt_but_no_crew_acknowledgment() -> void:
	_setup()
	_main._apply_order_to_selection(Order.set_speed(12.0))
	assert_eq(_boat.comms_pending.size(), 1)
	assert_true(_main.radio.journal[-1].contains("Queued for submarine check-in"))
	assert_true(_voice.reported_events.is_empty())
	assert_eq(_boat.ordered_speed_kn, 0.0, "queued control does not reach the crew immediately")
	_boat.depth_m = SubmarineComms.DEPTH_M
	_main.simulation.unit_manager.tick(0.0)
	assert_eq(_boat.comms_pending.size(), 0)
	assert_eq(_boat.ordered_speed_kn, 12.0)
	_done()


func test_receive_only_summons_has_no_unavailable_crew_acknowledgment() -> void:
	_setup()
	_main._apply_order_to_selection(Order.request_sub_checkin())
	assert_eq(_boat.comms_phase, "ascending")
	assert_true(_main.radio.journal[-1].contains("Check-in requested"))
	assert_true(_voice.reported_events.is_empty(), "a receive-only summons cannot manufacture a return voice channel")
	_done()


func test_per_unit_orders_and_escort_drag_both_report_queue_without_moving_silent_boat() -> void:
	_setup()
	_main._apply_unit_orders([[_boat, Order.set_depth(200.0)]])
	assert_eq(_boat.ordered_depth_m, 120.0)
	assert_eq(_boat.comms_pending.size(), 1)
	assert_true(_main.radio.journal[-1].contains("Queued for submarine check-in"))
	var leader := Unit.new()
	leader.spec = DataDB.platform("usn_ssn_virginia")
	leader.faction = "BLUE"
	leader.callsign = "Guide"
	_main.simulation.unit_manager.add_unit(leader)
	_boat.station_leader = leader
	_boat.station_kind = "formation"
	_main._move_escort_station(_boat, Vector2(5, 8))
	assert_eq(_boat.comms_pending.size(), 2)
	assert_eq(_boat.formation_leader, null, "station assignment is pending receipt")
	assert_true(_main.radio.journal[-1].contains("Queued for submarine check-in"))
	assert_true(_voice.reported_events.is_empty())
	_done()
