extends TestCase
## Plots on bearings that stay where the evidence put them, passive ranges that own up to what a
## manoeuvre may have done to them, and a small drone a warship's air-search radar can hold.

const SCENARIO_PATH := "user://test_fix_sensors_f.json"

var _sim: Simulation


func _load(units: Array, environment := {"sea_state": 2, "visibility_nm": 10}) -> Simulation:
	var scenario := {
		"id": "fix_sensors_f", "name": "FIXTURE", "seed": 5, "player_faction": "BLUE",
		"map": {"center_nm": [0, 0], "extent_nm": 300}, "environment": environment,
		"objectives": {"text": "", "victory": [{"id": "watch", "type": "time_elapsed", "seconds": 90000, "text": "Keep the watch"}], "loss": []},
		"units": units,
	}
	var f := FileAccess.open(SCENARIO_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(scenario))
	f.close()
	SimClock.set_paused(true)
	_sim = Simulation.new()
	_sim.seed_override = 5
	(Engine.get_main_loop() as SceneTree).root.add_child(_sim)
	assert_true(_sim.load_scenario(SCENARIO_PATH), "the fixture loads")
	_sim.ai_enabled = false
	return _sim


func _free() -> void:
	if _sim == null:
		return
	_sim.unit_manager.clear()
	_sim.free()
	_sim = null


func _unit(callsign: String) -> Unit:
	for u in _sim.unit_manager.units:
		if u.callsign == callsign:
			return u
	return null


func _run(seconds: float) -> void:
	for i in int(seconds * 4.0):
		SimClock.advance(0.25)


const BURKE := "usn_ddg_arleigh_burke_iia"
const MOHAJER := "irn_uav_mohajer6"


# --- A drone on radar ---------------------------------------------------------------------------

## A radiating destroyer and a Mohajer-6 at its cruising height, well inside the reach a
## fourth-root radar law gives a drone of its size and well outside the old 16 nm.
func test_a_radiating_destroyer_holds_a_small_drone_on_radar() -> void:
	for distance: float in [22.0, 40.0]:
		_load([{"platform": BURKE, "callsign": "Defender", "faction": "BLUE", "position_nm": [0, 0], "heading_deg": 0, "speed_kn": 12, "radar_on": true, "air_wing": []},
			{"platform": MOHAJER, "callsign": "Drone", "faction": "RED", "position_nm": [0, distance], "heading_deg": 90, "speed_kn": 90}])
		var drone := _unit("Drone")
		_run(20.0)
		var t := _sim.track_manager.find_track("BLUE", drone)
		assert_true(t != null, "the drone is held at %.0f nm" % distance)
		if t != null:
			assert_true(not t.is_bearing_only() and t.source == "radar", "by radar, with a range, at %.0f nm (source %s, bearing only %s)" % [distance, t.source, t.is_bearing_only()])
			assert_true(t.position.distance_to(drone.position) < 2.0, "where the drone is (%.1f nm off)" % t.position.distance_to(drone.position))
		_free()
	_load([{"platform": BURKE, "callsign": "Defender", "faction": "BLUE", "position_nm": [0, 0], "heading_deg": 0, "speed_kn": 12, "radar_on": true, "air_wing": []},
		{"platform": MOHAJER, "callsign": "Drone", "faction": "RED", "position_nm": [0, 75], "heading_deg": 90, "speed_kn": 90}])
	_run(20.0)
	var far := _sim.track_manager.find_track("BLUE", _unit("Drone"))
	assert_true(far == null or far.source != "radar", "a drone is still a small target: not held by radar at 75 nm")
	_free()
