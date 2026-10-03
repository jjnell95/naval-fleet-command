class_name CommandTraining
extends RefCounted
## Referee for the two short command exercises. Credit comes from accepted PLAYER orders and
## subsequent simulation state, never from elapsed time or the guide being clicked. It neither
## fires weapons nor changes sensors. All state belongs to saved MissionObjective progress.
const IDS := ["training_missile_defence", "training_asw"]

static func active(sim: Simulation) -> bool:
	return sim != null and str(sim.scenario.get("id", "")) in IDS and sim.mission_manager.result == MissionManager.Result.RUNNING

static func _task(sim: Simulation, practice: String) -> MissionObjective:
	for objective: MissionObjective in sim.mission_manager.victory_objectives:
		if objective.kind == MissionObjective.Kind.TRAINING_TASK and objective.practice == practice:
			return objective
	return null

static func _available(sim: Simulation, objective: MissionObjective) -> bool:
	return objective != null and not objective.complete and sim.mission_manager.prerequisites_complete(objective.after)

static func _complete(sim: Simulation, objective: MissionObjective, status: String) -> void:
	objective.practice_state["status"] = status
	sim.mission_manager.apply_update({"complete": [objective.id]}, SimClock.sim_time)

static func record_order(sim: Simulation, u: Unit, order: Order) -> void:
	if not active(sim) or u == null or u.faction != sim.player_faction or order.origin != "player" or not order.execution_accepted:
		return
	var task: MissionObjective
	match order.type:
		Order.Type.SET_AIR_DEFENCE_MODE:
			task = _task(sim, "manual_defence")
			if _available(sim, task) and not u.auto_air_defence:
				task.practice_state["unit_id"] = u.id
				_complete(sim, task, "Manual missile defence selected")
		Order.Type.INTERCEPT:
			task = _task(sim, "manual_intercept")
			if _available(sim, task) and not u.auto_air_defence:
				var ids: Array = []
				for weapon: Weapon in sim.threat_manager.get_threats(u.faction):
					if sim.threat_manager.visible_to(u, weapon) and (order.threat == null or weapon == order.threat): ids.append(weapon.id)
				if not ids.is_empty():
					task.practice_state["weapon_ids"] = ids
					task.practice_state["unit_id"] = u.id
					_complete(sim, task, "Detected inbound engaged on your order")
		Order.Type.DEPLOY_DIPPING_SONAR:
			task = _task(sim, "dip_listen")
			if _available(sim, task) and DippingSonar.capable(u):
				task.practice_state = {"unit_id": u.id, "status": "Crew positioning and lowering; wait for LISTENING"}
		Order.Type.ACTIVE_SONAR:
			task = _task(sim, "active_fix")
			if _available(sim, task) and DippingSonar.capable(u):
				task.practice_state = {"unit_id": u.id, "status": "Active sonar ordered; wait for a measured report"}
		Order.Type.ENGAGE, Order.Type.ATTACK:
			task = _task(sim, "authorize_attack")
			var fix := _task(sim, "active_fix")
			if _available(sim, task) and fix != null and order.track != null and order.track.id == str(fix.practice_state.get("track_id", "")):
				task.practice_state = {"unit_id": u.id, "track_id": order.track.id, "ordered_at_s": SimClock.sim_time, "status": "Attack authorized; waiting for a torpedo away"}
		Order.Type.RECOVER_DIPPING_SONAR:
			task = _task(sim, "recover_array")
			if _available(sim, task) and DippingSonar.capable(u):
				task.practice_state = {"unit_id": u.id, "status": "Crew raising; wait for STOWED"}

static func record_inspection(sim: Simulation, track: Track) -> void:
	if not active(sim) or track == null: return
	var task := _task(sim, "passive_datum")
	if _available(sim, task) and track.status == Track.Status.ACTIVE and track.is_bearing_only() and track.source in ["sonar_passive", "sonar_cz"]:
		task.practice_state["track_id"] = track.id
		_complete(sim, task, "Passive bearing inspected: range unresolved")

static func tick(sim: Simulation) -> void:
	if not active(sim): return
	for task: MissionObjective in sim.mission_manager.victory_objectives:
		if task.kind != MissionObjective.Kind.TRAINING_TASK or not _available(sim, task): continue
		var u: Unit
		for unit: Unit in sim.unit_manager.units:
			if unit.id == int(task.practice_state.get("unit_id", -1)): u = unit
		match task.practice:
			"dip_listen":
				if u != null and u.alive and DippingSonar.listening(u): _complete(sim, task, "Hover and lowering cycle complete; array listening")
			"active_fix":
				if u == null or not u.alive or not DippingSonar.listening(u) or not u.active_sonar_on: continue
				for track: Track in sim.track_manager.tracks_for(u):
					if track.status == Track.Status.ACTIVE and track.source == "sonar_active" and not track.is_bearing_only() and track.position_error_nm <= 1.0 and track.contributors.has(u) and track.domain == "subsurface" and track.identity == "HOSTILE":
						task.practice_state["track_id"] = track.id
						_complete(sim, task, "Measured fix and briefed submarine identification established")
						break
			"authorize_attack":
				if u == null: continue
				for weapon: Weapon in sim.weapon_manager.in_flight:
					if weapon.shooter == u and weapon.spec.is_torpedo() and weapon.target_track != null and weapon.target_track.id == str(task.practice_state.get("track_id", "")) and SimClock.sim_time - weapon.time_alive_s >= float(task.practice_state.get("ordered_at_s", INF)) - 0.01:
						_complete(sim, task, "Authorized torpedo away against the held fix")
						break
			"recover_array":
				if u != null and u.alive and u.dip_phase == DippingSonar.Phase.STOWED: _complete(sim, task, "Array safely recovered before departure")
			"defence_resolved":
				var interception := _task(sim, "manual_intercept")
				if interception == null or not interception.complete: continue
				var ids: Array = interception.practice_state.get("weapon_ids", [])
				if ids.is_empty(): continue
				var still_flying := false
				for weapon: Weapon in sim.weapon_manager.in_flight:
					if weapon.phase != Weapon.Phase.DEAD and ids.has(weapon.id): still_flying = true
				if not still_flying:
					for defender: Unit in sim.unit_manager.get_faction_units(sim.player_faction):
						if defender.id == int(interception.practice_state.get("unit_id", -1)) and defender.alive:
							_complete(sim, task, "Inbound resolved and the defended ship survived")
