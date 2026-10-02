extends RefCounted
## Opening plans for the operations, each flown headless to the end of the mission against the AI.
##
## A plan is what a commander orders in the first minutes, given as real orders through
## UnitManager.issue_order (moves, formations, air missions), plus the few standing rules a
## commander keeps afterwards: engage a contact the plot calls hostile once a weapon reaches it,
## send something to look at a contact report, steer for a box a tasking update moved. A plan reads
## only what the player's side may read: its own units, its own track picture and the published
## objectives. The opposing side is flown by its AI, so the plans meet the seeded variations.
##
## Arguments after --:
##   --scenario=<id> --plan=<name> --seed=N [--cap=S]   one trial; prints one "[plan] {json}" line
##   --list                                             every plan, one "<scenario> <plan>" a line
##   --trace                                            also print launches, hits and losses

const PLANS := {
	"cold_war_01_convoy": ["close_escort", "scout_ahead"],
	"cold_war_02_barrier": ["forward_barrier", "gate_defence"],
	"cold_war_03_carrier": ["all_cap", "strike_slava"],
	"aegis_bastion": ["forward_picket", "close_screen"],
	"pacific_02_taiwan_strait": ["forward_cap", "strike_group"],
	"gulf_01_hormuz": ["close_convoy", "sweep_ahead"],
	"med_01_tartus": ["direct_transit", "screen_first"],
}
## A trial that has not ended by the operation's own watch or deadline, plus a margin, stops there.
const CAP_S := {
	"cold_war_01_convoy": 10860.0, "cold_war_02_barrier": 10860.0, "cold_war_03_carrier": 7260.0,
	"aegis_bastion": 14460.0, "pacific_02_taiwan_strait": 18060.0, "gulf_01_hormuz": 36060.0,
	"med_01_tartus": 30000.0,
}
## How often the standing rules are applied, in sim seconds.
const STEP_S := 5.0

const CONVOY_CARGO := "MV North Star"
const ELROD := "USS Elrod (FFG 55)"
const NICHOLAS := "USS Nicholas (FFG 47)"
const DALLAS := "USS Dallas (SSN 700)"
const SPRUANCE := "USS Spruance (DD 963)"
const KEFLAVIK := "Keflavik Air Base"
const EISENHOWER := "USS Dwight D. Eisenhower (CVN 69)"
const LUCAS := "USS Jack H. Lucas (DDG 125)"
const GETTYSBURG := "USS Gettysburg (CG 64)"
const TRUXTUN := "USS Truxtun (DDG 103)"
const NANSEN := "HNoMS Fridtjof Nansen (F 310)"
const MAUD := "HNoMS Maud (A 530)"
const REAGAN := "USS Ronald Reagan (CVN 76)"
const KADENA := "Kadena Air Base"
const TAIWAN_SHIPS := ["USS Robert Smalls (CG 62)", "USS Rafael Peralta (DDG 115)", "USS Jack H. Lucas (DDG 125)", "JS Maya (DDG 179)", "JS Akizuki (DD 115)"]
const TANKERS := ["MT Gulf Horizon", "MT Ras Laffan Pride", "MT Aegean Dawn"]
const IGNATIUS := "USS Paul Ignatius (DDG 117)"
const DUNCAN := "HMS Duncan (D 37)"
const LANGUEDOC := "FS Languedoc (D 653)"
const AL_DHAFRA := "Al Dhafra Air Base"
const HORMUZ_LANE: Array[Vector2] = [Vector2(-13.4, 12.0), Vector2(13.4, -3.0), Vector2(48.4, -45.0)]
const MISTRAL := "FS Mistral (L 9013)"
const DE_GAULLE := "FS Charles de Gaulle (R 91)"
const DORIA := "ITS Andrea Doria (D 553)"
const PROVENCE := "FS Provence (D 652)"
const SUFFREN := "FS Suffren (S 635)"
const AKROTIRI := "RAF Akrotiri"

var sim: Simulation
var clock: Node
var scenario := ""
var plan := ""
var player := "BLUE"
var _done := {}
var _notes: Array = []
var _ended := ""
var _ended_at := -1.0
var _origin := Vector2.ZERO


func run(tree: SceneTree) -> int:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			args[a.get_slice("=", 0).trim_prefix("--")] = a.get_slice("=", 1)
	if OS.get_cmdline_user_args().has("--list"):
		for id: String in PLANS:
			for name: String in PLANS[id]:
				print("%s %s" % [id, name])
		return 0
	scenario = str(args.get("scenario", ""))
	plan = str(args.get("plan", ""))
	if not PLANS.has(scenario) or not (PLANS[scenario] as Array).has(plan):
		print("[plan] FAIL unknown scenario or plan: %s / %s" % [scenario, plan])
		return 1
	clock = tree.root.get_node("SimClock")
	var debug: Node = tree.root.get_node_or_null("Debug")
	if debug != null:
		debug.log_events = false
	clock.set_paused(true)
	sim = Simulation.new()
	sim.seed_override = int(args.get("seed", "2"))
	tree.root.add_child(sim)
	if not sim.load_scenario("res://data/scenarios/%s.json" % scenario):
		print("[plan] FAIL cannot load %s" % scenario)
		return 1
	player = sim.player_faction
	sim.mission_manager.mission_ended.connect(func(_result: String, summary: String) -> void:
		_ended = summary
		_ended_at = clock.sim_time)
	if OS.get_cmdline_user_args().has("--trace"):
		_trace()
	var cap := float(args.get("cap", str(CAP_S[scenario])))
	_open()
	while sim.mission_manager.result == MissionManager.Result.RUNNING and clock.sim_time < cap:
		clock.advance(STEP_S)
		if sim.mission_manager.result == MissionManager.Result.RUNNING:
			_step()
	var a := sim.mission_manager.assessment()
	var out := {
		"scenario": scenario, "plan": plan, "seed": sim.base_seed,
		"result": ["RUNNING", "VICTORY", "DEFEAT"][sim.mission_manager.result],
		"end_s": snappedf(_ended_at if _ended_at >= 0.0 else clock.sim_time, 1.0), "summary": _ended,
		"percent": a["percent"], "task": snappedf(float(a["task"]), 0.1), "force": snappedf(float(a["force"]), 0.1),
		"attrition": snappedf(float(a["attrition"]), 0.1), "bonus": snappedf(float(a["bonus"]), 0.1),
		"civilian": snappedf(float(a["civilian"]), 0.1), "bonus_done": a["bonus_done"], "bonus_total": a["bonus_total"],
		"variants": sim.director.variant, "fired": sim.director.fired, "skipped": sim.director.skipped,
		"losses": _losses(), "notes": _notes,
	}
	print("[plan] " + JSON.stringify(out))
	return 0


# --- The plans ---------------------------------------------------------------------------

func _open() -> void:
	match "%s/%s" % [scenario, plan]:
		"cold_war_01_convoy/close_escort":
			# Both frigates tight on the cargo ship, the Seahawk looking down the route.
			var cargo := _u(CONVOY_CARGO)
			var box := _box("handover")
			_order(cargo, Order.move(box))
			_order(_u(ELROD), Order.form_up(cargo, Vector2(0.0, 3.0)))
			_order(_u(NICHOLAS), Order.form_up(cargo, Vector2(3.0, 0.0)))
			_air(ELROD, AirMission.Kind.RECON, "cw90_sh60b", 1, cargo.position.lerp(box, 0.5), 10.0)
		"cold_war_01_convoy/scout_ahead":
			# Elrod and its Seahawk run ahead to find the corvette; Nicholas stays on the cargo.
			var cargo := _u(CONVOY_CARGO)
			var box := _box("handover")
			_order(cargo, Order.move(box))
			_order(_u(NICHOLAS), Order.form_up(cargo, Vector2(0.0, 2.0)))
			_order(_u(ELROD), Order.move(box + Vector2(2.0, -6.0)))
			_order(_u(ELROD), Order.set_speed(26.0))
			_air(ELROD, AirMission.Kind.RECON, "cw90_sh60b", 1, box, 12.0)
		"cold_war_02_barrier/forward_barrier":
			# Dallas walks a slow line across the lanes north of the barrier; the helicopters and
			# the Orion search ahead of it; Spruance keeps back.
			_order(_u(DALLAS), Order.patrol([Vector2(-4.0, 4.0), Vector2(9.0, 4.0)] as Array[Vector2]))
			_order(_u(DALLAS), Order.set_speed(5.0))
			_order(_u(SPRUANCE), Order.move(Vector2(3.0, -3.0)))
			_air(SPRUANCE, AirMission.Kind.ASW, "cw90_sh60b", 2, Vector2(2.0, 7.0), 8.0, null, true)
			_air(KEFLAVIK, AirMission.Kind.ASW, "cw90_p3c", 1, Vector2(3.0, 9.0), 12.0)
		"cold_war_02_barrier/gate_defence":
			# Everything on the gate itself; the Orion waits for the array's cue.
			var gate := _box("breakout")
			_order(_u(DALLAS), Order.move(gate + Vector2(1.0, 3.0)))
			_order(_u(SPRUANCE), Order.move(gate + Vector2(8.0, 2.0)))
			_air(SPRUANCE, AirMission.Kind.ASW, "cw90_sh60b", 2, gate + Vector2(0.0, 4.0), 6.0, null, true)
		"cold_war_03_carrier/all_cap", "cold_war_03_carrier/strike_slava":
			# The Hawkeye and four Tomcats north of the group, toward the raid axes but outside the
			# cruiser's SA-N-6 wherever she waits, with relief from the reserve.
			var cv := _u(EISENHOWER)
			_origin = cv.position
			_air(EISENHOWER, AirMission.Kind.RECON, "cw90_e2c", 1, _origin + Vector2(30.0, 50.0), 20.0)
			_air(EISENHOWER, AirMission.Kind.CAP, "cw90_f14a", 4, _origin + Vector2(0.0, 60.0), 15.0, null, true)
		"aegis_bastion/forward_picket":
			# The two Aegis ships keep their picket line; the carrier and Maud stand off west.
			var cv := _u(EISENHOWER)
			_air(EISENHOWER, AirMission.Kind.RECON, "usn_aew_e2d", 1, Vector2(40.0, 20.0), 30.0)
			_air(EISENHOWER, AirMission.Kind.CAP, "usn_fighter_fa18e", 4, Vector2(60.0, 15.0), 20.0, null, true)
			_air(EISENHOWER, AirMission.Kind.ASW, "usn_helo_mh60r", 2, Vector2(15.0, 28.0), 12.0, null, true)
			_order(cv, Order.move(Vector2(-60.0, 40.0)))
			_order(_u(MAUD), Order.form_up(cv, Vector2(-3.0, -3.0)))
		"aegis_bastion/close_screen":
			# One tight group under the umbrella; the reserve Super Hornets strike the surface group.
			var cv := _u(EISENHOWER)
			_origin = cv.position
			_order(_u(LUCAS), Order.form_up(cv, Vector2(-4.0, 8.0)))
			_order(_u(GETTYSBURG), Order.form_up(cv, Vector2(4.0, 8.0)))
			_order(_u(TRUXTUN), Order.form_up(cv, Vector2(0.0, 4.0)))
			_order(_u(NANSEN), Order.form_up(cv, Vector2(-6.0, 0.0)))
			_order(_u(MAUD), Order.form_up(cv, Vector2(0.0, -4.0)))
			_air(EISENHOWER, AirMission.Kind.RECON, "usn_aew_e2d", 1, _origin + Vector2(50.0, -10.0), 30.0)
			_air(EISENHOWER, AirMission.Kind.CAP, "usn_fighter_fa18f", 4, _origin + Vector2(40.0, -15.0), 20.0, null, true)
			_air(EISENHOWER, AirMission.Kind.ASW, "usn_helo_mh60r", 2, _origin + Vector2(10.0, 0.0), 10.0, null, true)
		"pacific_02_taiwan_strait/forward_cap":
			var rp := _u(REAGAN).position
			_air(REAGAN, AirMission.Kind.RECON, "usn_aew_e2d", 1, rp + Vector2(-60.0, 40.0), 30.0)
			_air(REAGAN, AirMission.Kind.CAP, "usn_fighter_fa18e", 4, rp + Vector2(-90.0, 50.0), 20.0, null, true)
			_air(REAGAN, AirMission.Kind.CAP, "usn_fighter_f35c", 4, rp + Vector2(-30.0, 90.0), 20.0, null, true)
			_air(KADENA, AirMission.Kind.RECON, "usn_mpa_p8a", 1, Vector2(140.0, 170.0), 40.0)
		"pacific_02_taiwan_strait/strike_group":
			var rp := _u(REAGAN).position
			_air(REAGAN, AirMission.Kind.RECON, "usn_aew_e2d", 1, rp + Vector2(-60.0, 40.0), 30.0)
			_air(REAGAN, AirMission.Kind.CAP, "usn_fighter_fa18f", 4, rp + Vector2(-90.0, 50.0), 20.0, null, true)
			_air(KADENA, AirMission.Kind.RECON, "usn_mpa_p8a", 1, Vector2(140.0, 170.0), 40.0)
			_air(KADENA, AirMission.Kind.CAP, "usaf_fighter_f16c", 4, Vector2(130.0, 60.0), 20.0, null, true)
		"gulf_01_hormuz/close_convoy":
			# The tankers in column down the lane with the escorts around the lead.
			_convoy_lane(15.0)
			var lead := _u(TANKERS[0])
			_order(_u(IGNATIUS), Order.form_up(lead, Vector2(0.0, 4.0)))
			_order(_u(DUNCAN), Order.form_up(lead, Vector2(-3.0, 0.0)))
			_order(_u(LANGUEDOC), Order.form_up(lead, Vector2(0.0, -6.0)))
			_air(AL_DHAFRA, AirMission.Kind.RECON, "usn_mpa_p8a", 1, Vector2(0.0, 10.0), 20.0)
		"gulf_01_hormuz/sweep_ahead":
			# The destroyers run ahead to Larak, where the swarm comes out, and hold the lane there;
			# the tankers wait a quarter of an hour with Languedoc, then follow at best speed.
			_order(_u(IGNATIUS), Order.move(HORMUZ_LANE[0]))
			_order(_u(IGNATIUS), Order.set_speed(22.0))
			_order(_u(DUNCAN), Order.move(HORMUZ_LANE[0] + Vector2(3.0, -4.0)))
			_order(_u(DUNCAN), Order.set_speed(22.0))
			for name: String in TANKERS:
				_order(_u(name), Order.set_speed(0.0))
			_order(_u(LANGUEDOC), Order.form_up(_u(TANKERS[0]), Vector2(0.0, -2.0)))
			_air(AL_DHAFRA, AirMission.Kind.RECON, "usn_mpa_p8a", 1, Vector2(-10.0, 20.0), 20.0)
		"med_01_tartus/direct_transit":
			# Mistral goes at once behind Andrea Doria, under the carrier's and Akrotiri's fighters.
			_tartus_transit()
			_air(DE_GAULLE, AirMission.Kind.RECON, "fra_aew_e2c", 1, Vector2(-40.0, 0.0), 30.0)
			_air(DE_GAULLE, AirMission.Kind.CAP, "fra_fighter_rafale_m", 4, Vector2(-40.0, -10.0), 20.0, null, true)
			_air(AKROTIRI, AirMission.Kind.CAP, "raf_fighter_typhoon", 2, Vector2(-10.0, 10.0), 20.0, null, true)
		"med_01_tartus/screen_first":
			# Air cover, the Poseidon and Suffren go first; Mistral waits for the picture.
			_air(DE_GAULLE, AirMission.Kind.RECON, "fra_aew_e2c", 1, Vector2(-40.0, 0.0), 30.0)
			_air(DE_GAULLE, AirMission.Kind.CAP, "fra_fighter_rafale_m", 4, Vector2(-40.0, -10.0), 20.0, null, true)
			_air(AKROTIRI, AirMission.Kind.CAP, "raf_fighter_typhoon", 4, Vector2(-10.0, 10.0), 20.0, null, true)
			_air(AKROTIRI, AirMission.Kind.RECON, "usn_mpa_p8a", 1, Vector2(-10.0, -20.0), 25.0)
			_order(_u(SUFFREN), Order.move(Vector2(-20.0, -20.0)))
			_order(_u(MISTRAL), Order.set_speed(0.0))


func _step() -> void:
	var now: float = clock.sim_time
	match "%s/%s" % [scenario, plan]:
		"cold_war_01_convoy/close_escort":
			_follow_box("handover", [CONVOY_CARGO])
			_engage([ELROD, NICHOLAS], "surface", 60.0)
		"cold_war_01_convoy/scout_ahead":
			_follow_box("handover", [CONVOY_CARGO])
			_engage([ELROD, NICHOLAS], "surface", 60.0)
			_look_at_reports(ELROD)
		"cold_war_02_barrier/forward_barrier":
			_engage([DALLAS, SPRUANCE], "subsurface", 20.0)
		"cold_war_02_barrier/gate_defence":
			for t in _reports():
				if _once("orion_to_cue"):
					_air(KEFLAVIK, AirMission.Kind.ASW, "cw90_p3c", 1, t.position, 12.0)
			if now >= 2400.0 and _once("orion_late"):
				_air(KEFLAVIK, AirMission.Kind.ASW, "cw90_p3c", 1, Vector2(2.0, 4.0), 12.0)
			_engage([DALLAS, SPRUANCE], "subsurface", 20.0)
		"cold_war_03_carrier/all_cap":
			if now >= 1800.0 and _once("second_cap"):
				_air(EISENHOWER, AirMission.Kind.CAP, "cw90_f14a", 4, _origin + Vector2(25.0, 5.0), 15.0, null, true)
		"cold_war_03_carrier/strike_slava":
			# A Viking looks at the Norwegian report; a classified hostile ship is struck by
			# whichever Intruders are ready, while the CAP stays where it is.
			for t in _reports():
				if _once("viking_to_report"):
					_air(EISENHOWER, AirMission.Kind.RECON, "cw90_s3a", 1, t.position, 15.0)
			_strike(EISENHOWER, "cw90_a6e", 4, func(t: Track) -> bool: return t.domain == "surface", 4)
			if now >= 1800.0 and _once("second_cap"):
				_air(EISENHOWER, AirMission.Kind.CAP, "cw90_f14a", 4, _origin + Vector2(25.0, 5.0), 15.0, null, true)
		"aegis_bastion/forward_picket":
			_engage([LUCAS, GETTYSBURG, TRUXTUN], "surface", 80.0)
		"aegis_bastion/close_screen":
			if now >= 1800.0:
				_strike(EISENHOWER, "usn_fighter_fa18e", 4, func(t: Track) -> bool: return t.domain == "surface")
			_engage([LUCAS, GETTYSBURG, TRUXTUN], "surface", 80.0)
		"pacific_02_taiwan_strait/forward_cap":
			_engage(TAIWAN_SHIPS, "surface", 100.0)
		"pacific_02_taiwan_strait/strike_group":
			if now >= 1800.0:
				_strike(REAGAN, "usn_fighter_fa18e", 4, func(t: Track) -> bool: return t.domain == "surface" and t.known_category != "replenishment ship")
			_engage(TAIWAN_SHIPS, "surface", 100.0)
		"gulf_01_hormuz/close_convoy":
			_relead()
			_engage([IGNATIUS, DUNCAN, LANGUEDOC], "surface", 8.0)
			_engage([LANGUEDOC, IGNATIUS], "subsurface", 6.0)
		"gulf_01_hormuz/sweep_ahead":
			if now >= 900.0 and _once("convoy_sails"):
				_convoy_lane(15.0)
				var lead := _u(TANKERS[0])
				_order(_u(IGNATIUS), Order.form_up(lead, Vector2(0.0, 6.0)))
				_order(_u(DUNCAN), Order.form_up(lead, Vector2(-4.0, 0.0)))
			if _done.has("convoy_sails"):
				_relead()
			_engage([IGNATIUS, DUNCAN, LANGUEDOC], "surface", 8.0)
			_engage([LANGUEDOC, IGNATIUS], "subsurface", 6.0)
		"med_01_tartus/direct_transit":
			_follow_box("holding_box", [MISTRAL])
			_engage([DORIA, PROVENCE], "surface", 60.0)
			_engage([SUFFREN], "subsurface", 15.0)
		"med_01_tartus/screen_first":
			if now >= 2400.0 and _once("mistral_sails"):
				_tartus_transit()
			if _done.has("mistral_sails"):
				_follow_box("holding_box", [MISTRAL])
			_engage([DORIA, PROVENCE], "surface", 60.0)
			_engage([SUFFREN], "subsurface", 15.0)
			_engage([PROVENCE, SUFFREN], "land", 600.0, func(t: Track) -> bool: return t.known_category.contains("battery"))


# --- Shared pieces of plans --------------------------------------------------------------

func _convoy_lane(speed_kn: float) -> void:
	var lead := _u(TANKERS[0])
	for i in HORMUZ_LANE.size():
		_order(lead, Order.move(HORMUZ_LANE[i], i > 0))
	_order(lead, Order.set_speed(speed_kn))
	_order(_u(TANKERS[1]), Order.form_up(lead, Vector2(0.0, -1.5)))
	_order(_u(TANKERS[2]), Order.form_up(lead, Vector2(0.0, -3.0)))


## A convoy whose lead tanker is lost re-forms on the next one, which takes the rest of the lane.
func _relead() -> void:
	var lead := _u(TANKERS[0])
	if lead != null and lead.alive:
		return
	for name: String in TANKERS:
		var u := _u(name)
		if u == null or not u.alive or not _once("lead:" + name):
			continue
		var rest := HORMUZ_LANE.filter(func(p: Vector2) -> bool: return p.x > u.position.x)
		for i in rest.size():
			_order(u, Order.move(rest[i], i > 0))
		_order(u, Order.set_speed(15.0))
		for other: String in TANKERS + [IGNATIUS, DUNCAN, LANGUEDOC]:
			var f := _u(other)
			if f != null and f.alive and f != u and f.formation_leader == lead:
				_order(f, Order.form_up(u, f.formation_offset))
		return


func _tartus_transit() -> void:
	var mistral := _u(MISTRAL)
	_order(mistral, Order.move(Vector2(-60.0, -34.0)))
	_order(mistral, Order.move(_box("holding_box"), true))
	_order(mistral, Order.set_speed(18.0))
	_done["box:holding_box"] = _box("holding_box")
	_order(_u(DORIA), Order.form_up(mistral, Vector2(0.0, 4.0)))
	_order(_u(PROVENCE), Order.form_up(mistral, Vector2(3.0, -2.0)))


## The box an objective names, as the briefing and the chart show it.
func _box(objective_id: String) -> Vector2:
	var o := sim.mission_manager.objective(objective_id)
	return o.center if o != null else Vector2.ZERO


## A tasking update moved the box: steer the named ships for the new one.
func _follow_box(objective_id: String, ships: Array) -> void:
	var box := _box(objective_id)
	var key := "box:" + objective_id
	if _done.has(key) and (_done[key] as Vector2).is_equal_approx(box):
		return
	var first := not _done.has(key)
	_done[key] = box
	if first:
		return
	for name: String in ships:
		_order(_u(name), Order.move(box))
	_note("%.0f box %s moved, ships re-routed" % [clock.sim_time, objective_id])


## Each named shooter not already on an attack takes the nearest contact its picture calls hostile
## in the domain, within reach, that it may attack.
func _engage(shooters: Array, domain: String, reach_nm: float, accept := Callable()) -> void:
	for name: String in shooters:
		var u := _u(name)
		if u == null or not u.alive or u.attack_track != null:
			continue
		var best: Track = null
		var best_d := reach_nm
		for t in _hostiles(domain, u):
			if accept.is_valid() and not accept.call(t):
				continue
			var d := u.position.distance_to(t.position)
			if d <= best_d and UnitManager.attack_rejection(u, t) == "":
				best = t
				best_d = d
		if best != null and _order(u, Order.attack(best)):
			_note("%.0f %s attacks %s" % [clock.sim_time, name, best.label()])


## A strike by `count` of a type on the nearest acceptable hostile contact, one strike at a time,
## once at least `min_ready` of them are on deck: a salvo is what gets through a cruiser's defence.
func _strike(base: String, type: String, count: int, accept: Callable, min_ready := 1) -> void:
	var b := _u(base)
	if b == null or not b.alive:
		return
	var running = _done.get("strike:" + base)
	if running != null:
		var m: AirMission = sim.air_mission_manager.mission_by_id(int(running))
		if m != null and m.active:
			return
	var targets: Array = []
	for t in _hostiles("surface") + _hostiles("land"):
		if accept.call(t):
			targets.append(t)
	if targets.is_empty():
		return
	targets.sort_custom(func(x: Track, y: Track) -> bool: return b.position.distance_to(x.position) < b.position.distance_to(y.position))
	if sim.air_mission_manager.mission_rejection(b, AirMission.Kind.STRIKE, type, Vector2.INF, targets[0]) != "":
		return
	var ready := 0
	for a in b.stowed_aircraft():
		if a.spec.id == type and AirMissionManager.airframe_fit(a, AirMission.Kind.STRIKE, targets[0]):
			ready += 1
	if ready < min_ready:
		return
	var o := Order.air_mission(AirMission.Kind.STRIKE, type, mini(count, ready), Vector2.INF, 0.0, targets[0])
	if sim.unit_manager.issue_order(b, o):
		var missions := sim.air_mission_manager.active_missions(player)
		_done["strike:" + base] = missions.back().id
	_note("%.0f %s strike on %s: %s" % [clock.sim_time, base, targets[0].label(), o.receipt])


## A ship sent to look at the newest contact report it is not already looking at.
func _look_at_reports(name: String) -> void:
	var u := _u(name)
	if u == null or not u.alive or u.attack_track != null or u.investigation_track != null:
		return
	for t in _reports():
		if _once("looked:" + t.id) and _order(u, Order.investigate(t)):
			_note("%.0f %s investigates report %s" % [clock.sim_time, name, t.id])
			return


func _air(base: String, kind: int, type: String, count: int, station: Vector2, radius := 0.0, target: Track = null, relief := false) -> bool:
	var b := _u(base)
	if b == null or not b.alive:
		return false
	var o := Order.air_mission(kind, type, count, station, radius, target, relief)
	var ok := sim.unit_manager.issue_order(b, o)
	_note("%.0f %s: %s" % [clock.sim_time, base, o.receipt])
	return ok


func _order(u: Unit, o: Order) -> bool:
	if u == null or not u.alive:
		return false
	var ok := sim.unit_manager.issue_order(u, o)
	if not ok and o.receipt != "":
		_note("%.0f %s refused: %s" % [clock.sim_time, u.callsign, o.receipt])
	return ok


## Contacts the plot calls hostile in a domain: the side's networked plot, or what one unit holds,
## which for a submerged submarine off the link is its own sonar picture.
func _hostiles(domain: String, holder: Unit = null) -> Array[Track]:
	var out: Array[Track] = []
	var held: Array = sim.track_manager.tracks_for(holder) if holder != null else sim.track_manager.get_tracks(player)
	for t: Track in held:
		if t.status == Track.Status.ACTIVE and t.identity == "HOSTILE" and t.domain == domain:
			out.append(t)
	return out


## Contact reports on the plot that nothing of ours has seen yet.
func _reports() -> Array[Track]:
	var out: Array[Track] = []
	for t: Track in sim.track_manager.get_tracks(player):
		if t.reported and t.status != Track.Status.LOST:
			out.append(t)
	return out


func _u(callsign: String) -> Unit:
	for u in sim.unit_manager.units:
		if u.callsign == callsign:
			return u
	return null


func _once(key: String) -> bool:
	if _done.has(key):
		return false
	_done[key] = true
	return true


func _note(text: String) -> void:
	if _notes.size() < 60:
		_notes.append(text)


## --trace: launches, impacts, losses and ended attacks as they happen, for reading a trial.
func _trace() -> void:
	var wm := sim.weapon_manager
	wm.weapon_launched.connect(func(shooter: Unit, spec: WeaponSpec, track: Track, rounds: int) -> void:
		print("[trace] %.0f %s fires %d × %s at %s" % [clock.sim_time, shooter.callsign, rounds, spec.short_name, track.label() if track != null else "?"]))
	wm.weapon_impact.connect(func(faction: String, spec: WeaponSpec, target: Unit, hit: bool) -> void:
		print("[trace] %.0f %s %s %s %s" % [clock.sim_time, faction, spec.short_name, "hits" if hit else "misses", target.callsign]))
	wm.weapon_defeated.connect(func(threat: Weapon, reason: String, by_unit: Unit) -> void:
		print("[trace] %.0f %s round from %s defeated (%s) by %s" % [clock.sim_time, threat.spec.short_name, threat.shooter.callsign if threat.shooter != null else "?", reason, by_unit.callsign if by_unit != null else "?"]))
	wm.weapon_resolved.connect(func(w: Weapon) -> void:
		if not w.spec.is_interceptor():
			print("[trace] %.0f %s from %s ended: %s" % [clock.sim_time, w.spec.short_name, w.shooter.callsign if w.shooter != null else "?", w.dead_reason]))
	wm.unit_destroyed.connect(func(u: Unit, killer: String) -> void:
		print("[trace] %.0f %s destroyed by %s" % [clock.sim_time, u.callsign, killer]))
	sim.aviation_manager.aircraft_lost.connect(func(a: Unit, reason: String) -> void:
		print("[trace] %.0f %s lost: %s" % [clock.sim_time, a.callsign, reason]))
	sim.unit_manager.attack_ended.connect(func(u: Unit, t: Track, reason: String) -> void:
		print("[trace] %.0f %s attack on %s ended: %s" % [clock.sim_time, u.callsign, t.label() if t != null else "?", reason]))
	sim.director.message.connect(func(text: String) -> void: print("[trace] %.0f radio: %s" % [clock.sim_time, text]))


## What each side lost, by name for ships and by count for aircraft. The player's own side is
## known; the other side's losses are the referee's, reported after the trial like a debrief.
func _losses() -> Dictionary:
	var out := {}
	for u in sim.unit_manager.units:
		if u.alive or u.departed:
			continue
		var side: Dictionary = out.get(u.faction, {"ships": [], "aircraft": 0})
		if u.is_aircraft():
			side["aircraft"] = int(side["aircraft"]) + 1
		else:
			(side["ships"] as Array).append(u.callsign)
		out[u.faction] = side
	return out
