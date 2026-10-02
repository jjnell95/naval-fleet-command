class_name GroupAttackManager
extends Node
## Coordinated attacks: several platforms told to put a set number of rounds on held contacts
## between them, instead of each firing its own salvo blind to what the others have in the air.
##
## The commander names the platforms, the contacts in priority order and a round budget, and may
## set the rounds per volley and the first volley itself (from the firing board). The manager
## splits the budget between the contacts, gives each round to the shooter that would put it on
## the contact soonest (the launcher free first plus the flight time, so a volley spreads across
## ships and favours fast missiles; guns only once no missile can take a round), and fires them as
## crew ENGAGE orders tagged with the group's id. Each shooter is checked on its own held picture
## of the contact with the same ROE, envelope, guidance, fire-control and magazine checks as the
## commander's own orders. One that cannot fire is passed over and its share offered to the rest.
## A round that leaves the queue unfired (a cancel, a lost shooter, a solution gone stale) returns
## to the pool. When a volley has resolved, the whole group waits out one shared assessment before
## it spends more on that contact. The budget counts every round fired and every round queued, and
## is never exceeded.
##
## The group fires from where its shooters are and never steers them: closing to range stays with
## the commander, or with a platform's own standing attack, whose rounds are its own and not the
## group's. The manager reads only the faction's track picture; the one association with ground
## truth is the destroyed-target check UnitManager makes for the standing attack.

signal group_report(group: GroupAttack, message: String, good: bool)
signal group_ended(group: GroupAttack, reason: String)

const CYCLE_DT := 1.0
## The look at the plot between volleys, shared by every shooter in the group: the pause the
## standing attack takes between its own salvos.
const ASSESS_S := UnitManager.ATTACK_ASSESS_S
## Nothing in the air and no shooter able to fire for this long: the attack ends and says why,
## rather than holding a budget no one can spend. GAMEPLAY.
const STALL_S := UnitManager.ATTACK_STALL_S

var unit_manager: UnitManager
var track_manager: TrackManager
var weapon_manager: WeaponManager:
	set(value):
		if weapon_manager != null:
			if weapon_manager.weapon_fired.is_connected(_on_weapon_fired):
				weapon_manager.weapon_fired.disconnect(_on_weapon_fired)
			if weapon_manager.queued_round_dropped.is_connected(_on_round_dropped):
				weapon_manager.queued_round_dropped.disconnect(_on_round_dropped)
			if weapon_manager.unit_destroyed.is_connected(_on_unit_destroyed):
				weapon_manager.unit_destroyed.disconnect(_on_unit_destroyed)
		weapon_manager = value
		if weapon_manager != null:
			weapon_manager.weapon_fired.connect(_on_weapon_fired)
			weapon_manager.queued_round_dropped.connect(_on_round_dropped)
			weapon_manager.unit_destroyed.connect(_on_unit_destroyed)
## Every group attack ordered since the scenario began, ended ones included, in order of issue.
var groups: Array[GroupAttack] = []
var now_s := 0.0
var _next_id := 1
var _accum := 0.0


func clear() -> void:
	groups.clear()
	_next_id = 1
	_accum = 0.0
	now_s = 0.0


func group_by_id(group_id: int) -> GroupAttack:
	for g in groups:
		if g.id == group_id:
			return g
	return null


func active_groups(faction: String) -> Array[GroupAttack]:
	var out: Array[GroupAttack] = []
	for g in groups:
		if g.active and g.faction == faction:
			out.append(g)
	return out


## The attack a platform is firing in, or null. A platform may be in more than one; the first
## ordered answers.
func group_for(u: Unit) -> GroupAttack:
	for g in groups:
		if not g.active:
			continue
		var mi := g.member_index(u)
		if mi >= 0 and g.member_withdrawn[mi] == "":
			return g
	return null


## Active group attacks of the faction that include this contact.
func groups_on(faction: String, track: Track) -> Array[GroupAttack]:
	var out: Array[GroupAttack] = []
	var key := WeaponManager.contact_key(track)
	for g in groups:
		if g.active and g.faction == faction and g.target_keys.has(key):
			out.append(g)
	return out


# --- Requests and cancellation -----------------------------------------------------------

## Routed here by Simulation for a GROUP_ATTACK order on its lead. Accepts what the group can do
## and says what it cannot: a shooter out of range, a magazine short of the budget. Refused only
## when no shooter can put a single round on any of the contacts now.
func request(lead: Unit, order: Order) -> GroupAttack:
	var g := _build(lead, order)
	if g.members.is_empty():
		return _refuse(order, "No platform in the group can fire")
	if g.targets.is_empty():
		return _refuse(order, "Choose a held contact")
	if g.budget <= 0:
		return _refuse(order, "No rounds to commit")
	# A second order for the same platforms on the same contact would spend a second budget. The
	# commander changes a running attack by cancelling it, not by stacking another on top.
	var running := overlapping(g.faction, g.members, g.targets)
	if running != null:
		return _refuse(order, "Group attack %d is already on track %s (%d of %d rounds); cancel it to order another" % [running.id, running.target_label(), _spent(running), running.budget])
	var reasons := {}
	var feasible := false
	for ti in g.targets.size():
		var found := _candidates(g, ti)
		if not (found["candidates"] as Array).is_empty():
			feasible = true
		for row: Array in found["refused"]:
			if not reasons.has(row[0]):
				reasons[row[0]] = row[1]
	if not feasible:
		var why := PackedStringArray()
		for mi: int in reasons:
			why.append("%s: %s" % [g.members[mi].callsign, reasons[mi]])
		return _refuse(order, "No shooter has a solution on track %s%s" % [g.target_label(), (" — " + "; ".join(why)) if not why.is_empty() else ""])
	g.id = _next_id
	_next_id += 1
	groups.append(g)
	# What this pass placed ([member index, weapon name, rounds] rows), who was refused and why
	# (member index -> reason), and how far the volleys fell short: the makings of the receipt.
	var tally := {"placed": [], "refused": {}, "short": 0}
	for ti in g.targets.size():
		var rows := _plan_rows(g, order, ti)
		var size := _volley_size(g, ti)
		if not rows.is_empty():
			size = mini(_rounds_in(rows), size)
		_open_volley(g, ti, size)
		if not rows.is_empty():
			_fire_plan(g, ti, rows, tally)
		_fill(g, ti, tally)
		tally["short"] = int(tally["short"]) + maxi(g.target_mark[ti] - _spent_at(g, ti), 0)
	order.receipt = _receipt(g, tally)
	if _spent(g) == 0:
		# Every shooter that looked able was refused at the launcher: nothing to coordinate, and
		# nothing to report beyond the refusal.
		groups.erase(g)
		order.execution_accepted = false
		return null
	order.execution_accepted = true
	g.note = order.receipt
	return g


## The rows of the board's plan for contact `ti`: [platform, weapon id, contact index, rounds]. A row
## names its contact by its place in the order's own list, which may hold contacts the group left out.
static func _plan_rows(g: GroupAttack, order: Order, ti: int) -> Array:
	var rows: Array = []
	for row: Array in order.group_plan:
		if row.size() < 4 or int(row[2]) < 0 or int(row[2]) >= order.group_targets.size():
			continue
		if WeaponManager.contact_key(order.group_targets[int(row[2])]) == g.target_keys[ti] and g.member_index(row[0]) >= 0 and int(row[3]) > 0:
			rows.append(row)
	return rows


static func _rounds_in(rows: Array) -> int:
	var n := 0
	for row: Array in rows:
		n += int(row[3])
	return n


## An active attack by the faction that already has one of these platforms firing at one of these
## contacts, or null.
func overlapping(faction: String, members: Array, targets: Array) -> GroupAttack:
	for g in groups:
		if not g.active or g.faction != faction:
			continue
		var shares_target := false
		for t: Track in targets:
			if t != null and g.target_keys.has(WeaponManager.contact_key(t)) and g.target_done[g.target_keys.find(WeaponManager.contact_key(t))] == "":
				shares_target = true
		if not shares_target:
			continue
		for u: Unit in members:
			var mi := g.member_index(u)
			if mi >= 0 and g.member_withdrawn[mi] == "":
				return g
	return null


func _refuse(order: Order, why: String) -> GroupAttack:
	order.execution_accepted = false
	order.receipt = why
	return null


## The record for an order, before anything is fired: the members able to take part, the contacts
## the faction holds, and each contact's share of the budget.
func _build(lead: Unit, order: Order) -> GroupAttack:
	var g := GroupAttack.new()
	g.faction = lead.faction
	g.lead = lead
	g.lead_id = lead.id
	g.created_at_s = now_s
	g.volley = maxi(order.volley, 0)
	for u: Unit in order.group_members:
		if u == null or not u.alive or u.faction != lead.faction or not u.is_engageable() or u.weapons.is_empty() or g.members.has(u):
			continue
		g.members.append(u)
		g.member_ids.append(u.id)
		g.member_fired.append(0)
		g.member_withdrawn.append("")
	for t: Track in order.group_targets:
		if t == null or t.status == Track.Status.LOST or (t.owner_faction != "" and t.owner_faction != lead.faction):
			continue
		var key := WeaponManager.contact_key(t)
		if g.target_keys.has(key):
			continue
		g.targets.append(t)
		g.target_keys.append(key)
		g.target_ids.append(t.id)
		g.target_share.append(0)
		g.target_fired.append(0)
		g.target_mark.append(-1)
		g.target_volley_fired.append(0)
		g.target_assess_until.append(-1.0)
		g.target_done.append("")
	g.budget = order.salvo_budget if order.salvo_budget > 0 else (default_budget(g.members, g.targets[0], weapon_manager) if not g.targets.is_empty() else 0)
	if order.group_allocation.size() == g.targets.size() and not g.targets.is_empty():
		var left := g.budget
		for ti in g.targets.size():
			g.target_share[ti] = clampi(order.group_allocation[ti], 0, left)
			left -= g.target_share[ti]
	else:
		_split(g, g.budget, g.live_targets())
	return g


## An even split of `rounds` over the given contacts, any remainder to the earlier (higher
## priority) ones.
static func _split(g: GroupAttack, rounds: int, among: Array[int]) -> void:
	if among.is_empty() or rounds <= 0:
		return
	var each := rounds / among.size()
	var extra := rounds % among.size()
	for i in among.size():
		g.target_share[among[i]] += each + (1 if i < extra else 0)


## Ends a group attack: its queued rounds return to the magazines; rounds already away fly on.
func cancel(group_id: int, by: Unit, order: Order = null) -> bool:
	var g := group_by_id(group_id)
	if g == null or not g.active or (by != null and by.faction != g.faction):
		if order != null:
			order.receipt = "That group attack has already ended."
		return false
	var queued := weapon_manager.group_rounds(g.id, "", true)
	var away := weapon_manager.group_rounds(g.id) - queued
	_end(g, "Cancelled")
	if order != null:
		order.receipt = "Group attack on track %s cancelled: %d queued round%s back in the magazines%s." % [g.target_label(), queued, "" if queued == 1 else "s", ", %d already away fly on" % away if away > 0 else ""]
	return true


## A CANCEL_FIRE to a member: it leaves the attack on that contact (on every contact when the
## order names none) and its queued group rounds there go back aboard. The rest of the group
## carries on, and the rounds it gave up return to the pool for the others at the next cycle.
func withdraw(u: Unit, track: Track) -> bool:
	var any := false
	var key := WeaponManager.contact_key(track) if track != null else ""
	for g in groups:
		if not g.active:
			continue
		var mi := g.member_index(u)
		if mi < 0 or g.member_withdrawn[mi] != "":
			continue
		var touched := false
		var returned := 0
		for ti in g.targets.size():
			if key != "" and g.target_keys[ti] != key:
				continue
			if not g.excluded.has([mi, ti]):
				g.excluded.append([mi, ti])
				touched = true
			returned += weapon_manager.cancel_group(g.id, u, g.target_keys[ti])
		if not touched:
			continue
		any = true
		var out_of_all := true
		for ti in g.targets.size():
			if not g.excluded.has([mi, ti]):
				out_of_all = false
		if out_of_all:
			g.member_withdrawn[mi] = "fire cancelled"
		if g.members_in_attack() == 0:
			_end(g, "Fire cancelled")
		else:
			_report(g, "Group attack %s: %s withdrawn%s; the others carry on" % [g.target_label(), u.callsign, ", %d queued round%s back aboard" % [returned, "" if returned == 1 else "s"] if returned > 0 else ""], true)
	return any


# --- The cycle ---------------------------------------------------------------------------

func tick(dt: float, now: float) -> void:
	now_s = now
	_accum += dt
	while _accum >= CYCLE_DT - 1e-6:
		_accum -= CYCLE_DT
		for g in groups:
			if g.active:
				_step(g)


func _step(g: GroupAttack) -> void:
	for mi in g.members.size():
		if g.member_withdrawn[mi] == "" and not g.members[mi].alive:
			_lose_member(g, mi)
	if not g.active:
		return
	if g.members_in_attack() == 0:
		_end(g, "No shooters left")
		return
	var tally := {"placed": [], "refused": {}, "short": 0}
	for ti in g.targets.size():
		if g.target_done[ti] == "":
			_step_target(g, ti, tally)
		if not g.active:
			return
	if not (tally["placed"] as Array).is_empty():
		_report(g, "Group attack %s: %s" % [g.target_label(), _placements_text(g, tally)], true)
	if g.live_targets().is_empty():
		_end(g, _targets_done_reason(g))
		return
	var live := 0
	var assessing := false
	var share_left := 0
	for ti in g.live_targets():
		live += weapon_manager.group_rounds(g.id, g.target_keys[ti])
		assessing = assessing or g.target_assess_until[ti] >= 0.0
		share_left += _share_left(g, ti)
	if live > 0 or assessing:
		g.stall_s = 0.0
		return
	if _budget_left(g) <= 0 or share_left <= 0:
		_end(g, "Budget fired")
		return
	g.stall_s += CYCLE_DT
	var refused: Dictionary = tally["refused"]
	if not refused.is_empty():
		g.note = "awaiting solution: " + str(refused.values()[0])
	if _all_out_of_rounds(g):
		_end(g, "Magazines empty")
	elif g.stall_s >= STALL_S:
		_end(g, "Cannot engage: " + (str(refused.values()[0]) if not refused.is_empty() else "no solution"))


## One contact: drop the queue a shooter can no longer aim, keep the open volley filled, close it
## when everything in it has resolved, wait out the shared look, then open the next.
func _step_target(g: GroupAttack, ti: int, tally: Dictionary) -> void:
	var t := g.targets[ti]
	var key := g.target_keys[ti]
	if t.status == Track.Status.LOST:
		_close_target(g, ti, "Contact lost")
		return
	if t.identity in ["NEUTRAL", "FRIENDLY"]:
		_close_target(g, ti, "Protected identity")
		return
	# Automation never fires at a stale plot. A round waiting on a launcher for a contact its
	# shooter no longer holds fresh goes back aboard, and back into the pool.
	for mi in g.members.size():
		var u := g.members[mi]
		if u.alive and weapon_manager.group_rounds(g.id, key, true, u) > 0:
			var held := held_track(u, t)
			if held == null or held.status != Track.Status.ACTIVE:
				weapon_manager.cancel_group(g.id, u, key, "CONTACT STALE" if held != null else "TRACK NOT HELD")
	if g.target_mark[ti] >= 0:
		var live := weapon_manager.group_rounds(g.id, key)
		if live == 0 and g.target_volley_fired[ti] > 0:
			# The volley has arrived. Read the plot before anyone spends more on it, unless there
			# is nothing more to spend. Checked before the volley is topped up: a round it is still
			# short of, fired now, would be more expenditure without a look.
			g.target_mark[ti] = -1
			g.target_volley_fired[ti] = 0
			if _volley_size(g, ti) <= 0:
				_close_target(g, ti, "Budget fired" if _budget_left(g) <= 0 else "Allocation fired")
			else:
				g.target_assess_until[ti] = now_s + ASSESS_S
			return
		# Part of the volley has already arrived and the rest is still on its way. A round the
		# volley is short of (a shooter late into range, a share handed back) waits for the shared
		# look too, rather than going on top of rounds whose result is not yet read.
		var away := live - weapon_manager.group_rounds(g.id, key, true)
		if g.target_volley_fired[ti] > away:
			return
		_fill(g, ti, tally)
		return
	if g.target_assess_until[ti] >= 0.0:
		if now_s < g.target_assess_until[ti]:
			return
		g.target_assess_until[ti] = -1.0
	var size := _volley_size(g, ti)
	if size <= 0:
		_close_target(g, ti, "Budget fired" if _budget_left(g) <= 0 else "Allocation fired")
		return
	_open_volley(g, ti, size)
	_fill(g, ti, tally)


func _open_volley(g: GroupAttack, ti: int, size: int) -> void:
	g.target_mark[ti] = _spent_at(g, ti) + maxi(size, 0)
	g.target_volley_fired[ti] = 0
	g.volleys_opened += 1


## The rounds the next volley on a contact may take: the group's volley size, or the contact's
## whole remaining share, within what is left of the budget.
func _volley_size(g: GroupAttack, ti: int) -> int:
	var share := _share_left(g, ti)
	var size := share if g.volley <= 0 else mini(g.volley, share)
	return clampi(size, 0, _budget_left(g))


func _share_left(g: GroupAttack, ti: int) -> int:
	return maxi(g.target_share[ti] - _spent_at(g, ti), 0)


func _budget_left(g: GroupAttack) -> int:
	return maxi(g.budget - _spent(g), 0)


## Rounds the group has committed in all: fired, plus still waiting on a launcher.
func _spent(g: GroupAttack) -> int:
	return g.fired_total + weapon_manager.group_rounds(g.id, "", true)


func _spent_at(g: GroupAttack, ti: int) -> int:
	return g.target_fired[ti] + weapon_manager.group_rounds(g.id, g.target_keys[ti], true)


## No more rounds go to this contact. Its queued rounds return to the magazines, rounds in the air
## fly on, and its unspent share goes to the contacts still under attack.
func _close_target(g: GroupAttack, ti: int, reason: String) -> void:
	if g.target_done[ti] != "":
		return
	g.target_done[ti] = reason
	g.target_mark[ti] = -1
	g.target_assess_until[ti] = -1.0
	var returned := weapon_manager.cancel_group(g.id, null, g.target_keys[ti], reason.to_upper())
	var unspent := maxi(g.target_share[ti] - g.target_fired[ti], 0)
	g.target_share[ti] = g.target_fired[ti]
	_split(g, unspent, g.live_targets())
	# The last contact's outcome is the attack's, and the end of the attack says it.
	if g.live_targets().is_empty() or reason in ["Budget fired", "Allocation fired"]:
		return
	_report(g, "Group attack %s: track %s %s%s; its share goes to the others" % [g.target_label(), GroupAttack.track_number(g.target_ids[ti]), reason.to_lower(), " · %d queued round%s returned" % [returned, "" if returned == 1 else "s"] if returned > 0 else ""], reason == "Target destroyed")


func _lose_member(g: GroupAttack, mi: int) -> void:
	var u := g.members[mi]
	g.member_withdrawn[mi] = "lost"
	var dropped := weapon_manager.cancel_group(g.id, u, "", "UNIT LOST")
	_report(g, "Group attack %s: %s lost%s" % [g.target_label(), u.callsign, " · %d unfired round%s back in the pool" % [dropped, "" if dropped == 1 else "s"] if dropped > 0 else ""], false)
	if g.members_in_attack() == 0:
		_end(g, "No shooters left")


func _end(g: GroupAttack, reason: String) -> void:
	if not g.active:
		return
	# An ended attack leaves nothing waiting on a launcher in its name.
	weapon_manager.cancel_group(g.id, null, "", "GROUP ATTACK ENDED")
	g.active = false
	g.ended_reason = reason
	for ti in g.targets.size():
		g.target_mark[ti] = -1
		g.target_assess_until[ti] = -1.0
	g.note = "Group attack %s ended: %s · %d of %d rounds fired" % [g.target_label(), reason.to_lower(), g.fired_total, g.budget]
	group_ended.emit(g, reason)


func _targets_done_reason(g: GroupAttack) -> String:
	var reasons := PackedStringArray()
	for reason in g.target_done:
		if reason != "" and not reasons.has(reason):
			reasons.append(reason)
	if reasons.size() == 1:
		return "Targets destroyed" if reasons[0] == "Target destroyed" and g.targets.size() > 1 else reasons[0]
	return ", ".join(reasons)


## Every member out of every round that suits a contact still under attack.
func _all_out_of_rounds(g: GroupAttack) -> bool:
	for mi in g.members.size():
		for ti in g.live_targets():
			if not g.member_available(mi, ti):
				continue
			var held := held_track(g.members[mi], g.targets[ti])
			if held == null:
				continue
			for spec: WeaponSpec in g.members[mi].weapons:
				if g.members[mi].magazine_count(spec.id) > 0 and Combat.suits_track(spec, held):
					return false
	return true


# --- Allocation --------------------------------------------------------------------------

## The member's own picture of the contact: the group's track when the member can see it, else the
## track the member holds under the same number (a platform off the link keeps its own copy).
func held_track(u: Unit, target: Track) -> Track:
	if target == null:
		return null
	if target.visible_to(u):
		return target
	if track_manager == null:
		return null
	var key := WeaponManager.contact_key(target)
	for t: Track in track_manager.tracks_for(u):
		if WeaponManager.contact_key(t) == key and t.status != Track.Status.LOST and t.visible_to(u):
			return t
	return null


## Who can fire at contact `ti` now, and with what: one entry per member and weapon that holds a
## solution on the member's own picture, plus the reason for each member that has none.
func _candidates(g: GroupAttack, ti: int) -> Dictionary:
	var out: Array = []
	var refused: Array = []
	for mi in g.members.size():
		if not g.member_available(mi, ti):
			continue
		var u := g.members[mi]
		var held := held_track(u, g.targets[ti])
		if held == null:
			refused.append([mi, "contact not held"])
			continue
		var why := UnitManager.attack_rejection(u, held)
		if why != "":
			refused.append([mi, why.to_lower()])
			continue
		if held.status != Track.Status.ACTIVE:
			refused.append([mi, "contact stale"])
			continue
		var first_reason := ""
		var able := false
		for spec: WeaponSpec in u.weapons_for_track(held):
			var check := weapon_manager.engagement_check(u, spec, held, now_s)
			if not bool(check["ok"]):
				if first_reason == "":
					first_reason = str(check["reason"]).to_lower()
				continue
			able = true
			out.append({"member": mi, "spec": spec, "track": held, "cap": u.magazine_count(spec.id),
				"ready": float(check.get("ready_in_s", 0.0)), "spacing": WeaponManager.launch_spacing(u, spec),
				"flight": float(check.get("flight_time_s", 0.0)), "gun": spec.is_gun(),
				"launcher": "%d|%s" % [mi, WeaponManager.launcher_key(u, spec)]})
		if not able:
			refused.append([mi, first_reason if first_reason != "" else "no suitable weapon"])
	return {"candidates": out, "refused": refused}


## How many of `want` rounds each candidate takes. Each round goes to the candidate that would
## reach the contact first: the time its launcher is free (rounds already given to that launcher
## in this volley included) plus the flight time. A gun takes a round only when no missile can.
## Ties go to the earlier member and the weapon it lists first, so the result is repeatable.
static func _place(candidates: Array, want: int) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(candidates.size())
	counts.fill(0)
	var free_at := {}
	for c: Dictionary in candidates:
		if not free_at.has(c["launcher"]):
			free_at[c["launcher"]] = float(c["ready"])
	for r in want:
		var best := -1
		var best_score := INF
		for i in candidates.size():
			var c: Dictionary = candidates[i]
			if counts[i] >= int(c["cap"]):
				continue
			var score := float(free_at[c["launcher"]]) + float(c["flight"]) + (1.0e9 if bool(c["gun"]) else 0.0)
			if score < best_score - 1e-6:
				best = i
				best_score = score
		if best < 0:
			break
		counts[best] += 1
		var chosen: Dictionary = candidates[best]
		free_at[chosen["launcher"]] = float(free_at[chosen["launcher"]]) + float(chosen["spacing"])
	return counts


## Fills the open volley on contact `ti` up to its mark, within the budget and the contact's share.
## A shooter that comes up short (a refusal, a magazine clamp) is passed over and its rounds offered
## to the rest straight away.
func _fill(g: GroupAttack, ti: int, tally: Dictionary) -> int:
	var placed := 0
	var passed_over := {}
	for attempt in 8:
		var need := mini(g.target_mark[ti] - _spent_at(g, ti), mini(_budget_left(g), _share_left(g, ti)))
		if need <= 0:
			break
		var found := _candidates(g, ti)
		var refused: Dictionary = tally["refused"]
		for row: Array in found["refused"]:
			if not refused.has(row[0]):
				refused[row[0]] = row[1]
		var candidates: Array = (found["candidates"] as Array).filter(func(c: Dictionary) -> bool: return not passed_over.has("%d|%s" % [c["member"], c["spec"].id]))
		var counts := _place(candidates, need)
		var any := false
		for i in candidates.size():
			if counts[i] <= 0:
				continue
			any = true
			var c: Dictionary = candidates[i]
			var u := g.members[c["member"]]
			var spec: WeaponSpec = c["spec"]
			var before := _spent(g)
			var o := Order.engage(c["track"], spec.id, counts[i])
			o.origin = "crew"
			o.group_id = g.id
			unit_manager.issue_order(u, o)
			var got := _spent(g) - before
			placed += got
			if got > 0:
				(tally["placed"] as Array).append([c["member"], spec.compact_name(), got])
			if got < counts[i]:
				passed_over["%d|%s" % [c["member"], spec.id]] = true
				if got == 0 and not refused.has(c["member"]):
					refused[c["member"]] = str(weapon_manager.engagement_check(u, spec, c["track"], now_s)["reason"]).to_lower()
		if not any:
			break
	return placed


## The board's first volley as the commander set it: these platforms, these weapons, these numbers.
## A row that cannot be fired in full is made up by the ordinary allocation afterwards.
func _fire_plan(g: GroupAttack, ti: int, rows: Array, tally: Dictionary) -> void:
	for row: Array in rows:
		var mi := g.member_index(row[0])
		if mi < 0 or not g.member_available(mi, ti):
			continue
		var u := g.members[mi]
		var spec := u.get_weapon(str(row[1]))
		var need := mini(int(row[3]), mini(g.target_mark[ti] - _spent_at(g, ti), mini(_budget_left(g), _share_left(g, ti))))
		if spec == null or need <= 0:
			continue
		var held := held_track(u, g.targets[ti])
		if held == null:
			(tally["refused"] as Dictionary)[mi] = "contact not held"
			continue
		var before := _spent(g)
		var o := Order.engage(held, spec.id, need)
		o.origin = "crew"
		o.group_id = g.id
		unit_manager.issue_order(u, o)
		var got := _spent(g) - before
		if got > 0:
			(tally["placed"] as Array).append([mi, spec.compact_name(), got])
		elif not (tally["refused"] as Dictionary).has(mi):
			(tally["refused"] as Dictionary)[mi] = str(weapon_manager.engagement_check(u, spec, held, now_s)["reason"]).to_lower()


# --- What the commander reads ------------------------------------------------------------

## "12-round group attack on track 1077: USS Paul Ignatius 4 × Tomahawk, Nansen refused: out of
## range · 4 held for after the assessment".
func _receipt(g: GroupAttack, tally: Dictionary) -> String:
	var spent := _spent(g)
	var head := "%d-round group attack on track %s" % [g.budget, g.target_label()]
	if g.targets.size() > 1:
		var numbers := PackedStringArray()
		for id in g.target_ids:
			numbers.append(GroupAttack.track_number(id))
		head = "%d-round group attack on tracks %s" % [g.budget, ", ".join(numbers)]
	var text := head + ": " + _placements_text(g, tally)
	var short := int(tally["short"])
	if short > 0:
		# A shooter that could have taken them but is refused is named above; otherwise every
		# shooter able to reach has given all it has aboard.
		var why := "no more rounds aboard in reach"
		var refused: Dictionary = tally["refused"]
		for mi: int in refused:
			if not _placed_by(tally, mi) and refused[mi] != "magazines empty":
				why = "no other shooter can take them"
		text += " · %d not placed: %s" % [short, why]
	var held := g.budget - spent - short
	if held > 0:
		text += " · %d held for after the assessment" % held
	return text


## "USS Paul Ignatius 4 × Tomahawk + 2 × Mk 45, Nansen refused: out of range".
func _placements_text(g: GroupAttack, tally: Dictionary) -> String:
	var parts := PackedStringArray()
	for mi in g.members.size():
		var by_weapon := {}
		var names: Array[String] = []
		for row: Array in tally["placed"]:
			if int(row[0]) != mi:
				continue
			if not by_weapon.has(row[1]):
				names.append(row[1])
				by_weapon[row[1]] = 0
			by_weapon[row[1]] += int(row[2])
		if names.is_empty():
			continue
		var fired := PackedStringArray()
		for name in names:
			fired.append("%d × %s" % [by_weapon[name], name])
		parts.append("%s %s" % [g.members[mi].callsign, " + ".join(fired)])
	var refused: Dictionary = tally["refused"]
	for mi in g.members.size():
		if refused.has(mi) and not _placed_by(tally, mi):
			parts.append("%s refused: %s" % [g.members[mi].callsign, refused[mi]])
	return ", ".join(parts) if not parts.is_empty() else "nothing placed"


static func _placed_by(tally: Dictionary, mi: int) -> bool:
	for row: Array in tally["placed"]:
		if int(row[0]) == mi:
			return true
	return false


## Live counts for the boards: what the group may fire, has fired, has queued and has in the air.
func status(g: GroupAttack) -> Dictionary:
	var queued := weapon_manager.group_rounds(g.id, "", true)
	var live := weapon_manager.group_rounds(g.id)
	return {"budget": g.budget, "fired": g.fired_total, "queued": queued, "airborne": live - queued, "spent": g.fired_total + queued, "phase": phase(g)}


## What the group is doing, in the operator's words: "2 queued, 3 away", "assessing 14 s",
## "awaiting solution".
func phase(g: GroupAttack) -> String:
	if not g.active:
		return g.ended_reason.to_lower()
	var queued := weapon_manager.group_rounds(g.id, "", true)
	var away := weapon_manager.group_rounds(g.id) - queued
	var parts := PackedStringArray()
	if queued > 0:
		parts.append("%d queued" % queued)
	if away > 0:
		parts.append("%d away" % away)
	var wait := -1.0
	for ti in g.live_targets():
		if g.target_assess_until[ti] >= 0.0:
			wait = maxf(wait, g.target_assess_until[ti] - now_s)
	if wait >= 0.0:
		parts.append("assessing %ds" % int(ceil(wait)))
	if parts.is_empty():
		return "awaiting solution"
	return ", ".join(parts)


## The orders line of a platform in a group attack: "Group attack 1077 · 5 of 12 rounds · 3 away".
func orders_line(u: Unit) -> String:
	var g := group_for(u)
	if g == null:
		return ""
	var s := status(g)
	return "Group attack %s · %d of %d rounds · %s" % [g.target_label(), int(s["spent"]), g.budget, str(s["phase"])]


## One line for the firing board: "Group 3 · budget 12 · fired 5 · queued 2 · away 3 · assessing 14s".
func summary(g: GroupAttack) -> String:
	var s := status(g)
	return "Group %d on %s · budget %d · fired %d · queued %d · away %d · %s · %d of %d shooters" % [g.id, g.target_label(), g.budget, int(s["fired"]), int(s["queued"]), int(s["airborne"]), str(s["phase"]), g.members_in_attack(), g.members.size()]


## What a group attack would do if ordered now, without firing anything: the first volley (the
## board's plan as it stands, else the allocation) and each refusal. The firing board shows it
## before the commander commits.
func preview(lead: Unit, order: Order) -> String:
	var g := _build(lead, order)
	if g.members.is_empty() or g.targets.is_empty() or g.budget <= 0:
		return ""
	var tally := {"placed": [], "refused": {}, "short": 0}
	var budget_left := g.budget
	for ti in g.targets.size():
		var size := mini(g.target_share[ti] if g.volley <= 0 else mini(g.volley, g.target_share[ti]), budget_left)
		var got := 0
		var rows := _plan_rows(g, order, ti)
		for row: Array in rows:
			var mi := g.member_index(row[0])
			var spec := g.members[mi].get_weapon(str(row[1]))
			var n := mini(int(row[3]), size - got)
			if spec != null and n > 0:
				(tally["placed"] as Array).append([mi, spec.compact_name(), n])
				got += n
		if rows.is_empty():
			var found := _candidates(g, ti)
			for row: Array in found["refused"]:
				if not (tally["refused"] as Dictionary).has(row[0]):
					tally["refused"][row[0]] = row[1]
			var counts := _place(found["candidates"], size)
			for i in counts.size():
				if counts[i] > 0:
					var c: Dictionary = found["candidates"][i]
					(tally["placed"] as Array).append([c["member"], (c["spec"] as WeaponSpec).compact_name(), counts[i]])
					got += counts[i]
		budget_left -= got
		tally["short"] = int(tally["short"]) + size - got
	var text := _placements_text(g, tally)
	if int(tally["short"]) > 0:
		text += " · %d not placed" % int(tally["short"])
	return text


## One ordinary salvo from each platform that can fire on the contact now: the default salvo of
## the weapon it would choose, clamped by its magazine. What the contact menu offers.
static func default_budget(members: Array, target: Track, wm: WeaponManager) -> int:
	var total := 0
	if target == null:
		return 0
	for u: Unit in members:
		if u == null or not u.is_engageable():
			continue
		for spec: WeaponSpec in u.weapons_for_track(target):
			var check := wm.engagement_check(u, spec, target, wm.now_s) if wm != null else Combat.check_engagement(u, spec, target)
			if bool(check["ok"]):
				total += mini(maxi(spec.salvo_default, 1), u.magazine_count(spec.id))
				break
	return total


# --- Signals from the weapons ------------------------------------------------------------

func _on_weapon_fired(w: Weapon) -> void:
	if w.group_id < 0:
		return
	var g := group_by_id(w.group_id)
	if g == null:
		return
	g.fired_total += 1
	var mi := g.member_index(w.shooter)
	if mi >= 0:
		g.member_fired[mi] += 1
	var ti := g.target_index_for_key(WeaponManager.contact_key(w.target_track))
	if ti >= 0:
		g.target_fired[ti] += 1
		g.target_volley_fired[ti] += 1


func _on_round_dropped(_shooter: Unit, _spec: WeaponSpec, _track: Track, group_id: int, refunded: bool, _reason: String) -> void:
	if group_id < 0:
		return
	var g := group_by_id(group_id)
	if g == null:
		return
	if refunded:
		g.refunded_total += 1
	else:
		g.lost_total += 1


## A member sunk or shot down leaves the attack and its unfired rounds return to the pool. A
## contact destroyed takes no more rounds. That needs the plot's association with the unit under
## it, the same one UnitManager consults to end a standing attack on a sunk target; nothing else
## here reads it.
func _on_unit_destroyed(unit: Unit, _killer_faction: String) -> void:
	for g in groups:
		if not g.active:
			continue
		var mi := g.member_index(unit)
		if mi >= 0 and g.member_withdrawn[mi] == "":
			_lose_member(g, mi)
		if not g.active:
			continue
		for ti in g.targets.size():
			if g.target_done[ti] == "" and g.targets[ti].truth == unit:
				_close_target(g, ti, "Target destroyed")
		if g.live_targets().is_empty():
			_end(g, _targets_done_reason(g))


func _report(g: GroupAttack, message: String, good: bool) -> void:
	g.note = message
	group_report.emit(g, message, good)
