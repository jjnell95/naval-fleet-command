extends TestCase
## Coordinated group attacks: real catalogue warships share one round budget on a held contact,
## through the real order route, launcher queues and flight model. The plot holds each contact in
## open water with nothing afloat under it, so every round resolves on empty water and the contact
## survives to be attacked again: what is under test is who fires, how much and when, not whether
## the rounds hit. A destroyed contact is sunk by hand, as Simulation reports a loss to fire.

const DT := 0.25
const NSM := "nsm_strike_missile"
const TOMAHAWK := "tomahawk_block_v"

var _sim: Simulation
var _held: Array[Track] = []
## Group id -> the most rounds that group ever had fired and queued at once, sampled every tick.
var _peak: Dictionary = {}


func _setup() -> void:
	Terrain.clear()
	SimClock.set_paused(true)
	_sim = Simulation.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_sim)
	_sim.ai_enabled = false
	_sim.weapon_manager.rng.seed = 7
	_held.clear()
	_peak.clear()
	if not SimClock.tick.is_connected(_watch):
		SimClock.tick.connect(_watch)


func _done() -> void:
	if SimClock.tick.is_connected(_watch):
		SimClock.tick.disconnect(_watch)
	_sim.weapon_manager.clear()
	_sim.group_attack_manager.clear()
	_sim.unit_manager.clear()
	_sim.free()
	_sim = null


## Contacts the test puts on the plot stay fresh, as if a sensor still held them; and every group's
## expenditure is sampled after each tick, so a budget overrun at any moment is seen.
func _watch(_dt: float) -> void:
	for t in _held:
		t.last_seen_time = SimClock.sim_time
		t.status = Track.Status.ACTIVE
	for g in _sim.group_attack_manager.groups:
		_sample(g)


func _sample(g: GroupAttack) -> void:
	_peak[g.id] = maxi(int(_peak.get(g.id, 0)), _spent(g))


func _spent(g: GroupAttack) -> int:
	return g.fired_total + _sim.weapon_manager.group_rounds(g.id, "", true)


func _ship(platform: String, callsign: String, pos: Vector2, faction := "BLUE") -> Unit:
	var u := Unit.new()
	u.spec = DataDB.platform(platform)
	u.faction = faction
	u.callsign = callsign
	u.health = u.spec.health
	u.position = pos
	for sid in u.spec.sensor_ids:
		u.sensors.append(DataDB.sensor(sid))
	for wid in u.spec.weapon_loadout:
		u.weapons.append(DataDB.weapon(wid))
		u.magazines[wid] = u.spec.weapon_loadout[wid]
	_sim.unit_manager.add_unit(u)
	return u


func _plot(id: String, pos: Vector2, faction := "BLUE", truth: Unit = null) -> Track:
	var t := Track.new()
	t.id = id
	t.owner_faction = faction
	t.identity = "HOSTILE"
	t.domain = "surface"
	t.classification = Track.Classification.SURFACE
	t.position = pos
	t.truth = truth
	t.last_seen_time = SimClock.sim_time
	if not _sim.track_manager._tracks.has(faction):
		_sim.track_manager._tracks[faction] = []
	_sim.track_manager._tracks[faction].append(t)
	_held.append(t)
	return t


func _order(lead: Unit, members: Array, targets: Array, budget: int, volley := 0) -> Order:
	var o := Order.group_attack(members, targets, budget, volley)
	_sim.unit_manager.issue_order(lead, o)
	return o


func _group() -> GroupAttack:
	var groups := _sim.group_attack_manager.groups
	return groups[groups.size() - 1] if not groups.is_empty() else null


func _until(done: Callable, limit_s: float) -> bool:
	var waited := 0.0
	while waited < limit_s:
		if done.call():
			return true
		SimClock.advance(DT)
		waited += DT
	return done.call()


## Group rounds one platform has queued or in the air, plus those it has already seen resolve.
func _committed_by(g: GroupAttack, u: Unit) -> int:
	return g.member_fired[g.member_index(u)] + _sim.weapon_manager.group_rounds(g.id, "", true, u)


func _in_flight_of(spec_id: String) -> int:
	var n := 0
	for w in _sim.weapon_manager.in_flight:
		if w.phase != Weapon.Phase.DEAD and w.spec.id == spec_id:
			n += 1
	return n


func _kill(u: Unit, by := "BLUE") -> void:
	u.health = 0.0
	u.alive = false
	_sim.weapon_manager.unit_destroyed.emit(u, by)


func test_mixed_speed_volley_shares_one_budget_and_one_assessment() -> void:
	_setup()
	# A Russian pair: Oniks at 1,100 kn from one, Kalibr at 500 kn from the other. The Gorshkov has
	# already spent most of its load, so the fast missile cannot take the whole volley.
	var gorshkov := _ship("rfn_ffg_admiral_gorshkov", "Admiral Gorshkov", Vector2(0, 0), "RED")
	var essen := _ship("rfn_ffg_admiral_grigorovich", "Admiral Essen", Vector2(3, 0), "RED")
	gorshkov.magazines["p800_oniks"] = 2
	var t := _plot("T1077", Vector2(0, 40), "RED")
	var o := _order(gorshkov, [gorshkov, essen], [t], 6, 4)
	var g := _group()
	assert_true(o.execution_accepted, o.receipt)
	assert_true(o.receipt.begins_with("6-round group attack on track 1077: Admiral Gorshkov 2 × Oniks, Admiral Essen 2 × Kalibr"), o.receipt)
	assert_true(o.receipt.contains("2 held for after the assessment"), o.receipt)
	assert_eq(_spent(g), 4, "the first volley is four rounds across both ships")
	assert_eq(_committed_by(g, gorshkov), 2, "the fast missile is preferred while it lasts")
	assert_eq(_committed_by(g, essen), 2)
	var wm := _sim.weapon_manager
	assert_true(_until(func() -> bool: return _in_flight_of("p800_oniks") == 0 and g.member_fired[0] == 2, 400.0), "the Oniks pair arrives first")
	assert_true(_in_flight_of("kalibr_asm") > 0, "the Kalibr pair is still on its way")
	assert_eq(g.target_assess_until[0], -1.0, "no assessment while any round of the volley is still flying")
	assert_eq(_spent(g), 4, "and nothing more is spent")
	assert_true(_sim.group_attack_manager.phase(g).contains("away"), _sim.group_attack_manager.phase(g))
	assert_true(_until(func() -> bool: return wm.group_rounds(g.id) == 0, 600.0), "the slow pair resolves")
	SimClock.advance(1.0)
	assert_true(g.target_assess_until[0] > SimClock.sim_time, "the shared assessment starts once every round has resolved")
	assert_true(_sim.group_attack_manager.phase(g).begins_with("assessing"), _sim.group_attack_manager.phase(g))
	SimClock.advance(GroupAttackManager.ASSESS_S - 3.0)
	assert_eq(_spent(g), 4, "no shooter spends during the shared look")
	SimClock.advance(4.0)
	assert_eq(_spent(g), 6, "the second volley takes what is left of the budget")
	assert_eq(_committed_by(g, essen), 4, "and the Gorshkov, out of Oniks, leaves it to the Kalibr")
	assert_true(_until(func() -> bool: return not g.active, 900.0), "the attack ends")
	assert_eq(g.ended_reason, "Budget fired")
	assert_eq(g.fired_total, 6)
	assert_true(int(_peak.get(g.id, 0)) <= 6, "the budget was never exceeded at any moment")
	assert_eq(gorshkov.magazine_count("p800_oniks") + essen.magazine_count("kalibr_asm"), 4, "exactly six rounds left the magazines")
	_done()


func test_a_budget_beyond_the_magazines_fires_what_is_aboard_and_says_why() -> void:
	_setup()
	var ignatius := _ship("usn_ddg_arleigh_burke_iia", "USS Paul Ignatius", Vector2(0, 0))
	var nansen := _ship("rnon_ffg_fridtjof_nansen", "Fridtjof Nansen", Vector2(4, 0))
	var t := _plot("T1077", Vector2(0, 40))
	var o := _order(ignatius, [ignatius, nansen], [t], 24)
	var g := _group()
	assert_true(o.execution_accepted, o.receipt)
	assert_true(o.receipt.contains("USS Paul Ignatius 8 × Tomahawk"), o.receipt)
	assert_true(o.receipt.contains("Fridtjof Nansen 8 × NSM"), o.receipt)
	assert_true(o.receipt.contains("8 not placed: no more rounds aboard in reach"), o.receipt)
	assert_eq(_spent(g), 16, "every round aboard that can reach, and no more")
	assert_eq(ignatius.magazine_count(TOMAHAWK) + nansen.magazine_count(NSM), 0)
	assert_true(_until(func() -> bool: return not g.active, 900.0), "the attack ends once nothing is left to fire")
	# Both still carry gun rounds that suit the contact, but neither gun reaches forty miles.
	assert_eq(g.ended_reason, "Cannot engage: out of range")
	assert_eq(g.fired_total, 16)
	assert_true(int(_peak.get(g.id, 0)) <= 16)
	_done()


func test_cancelling_a_member_withdraws_only_it_and_cancelling_the_group_refunds_every_queued_round() -> void:
	_setup()
	var ignatius := _ship("usn_ddg_arleigh_burke_iia", "USS Paul Ignatius", Vector2(0, 0))
	var nansen := _ship("rnon_ffg_fridtjof_nansen", "Fridtjof Nansen", Vector2(4, 10))
	var t := _plot("T1077", Vector2(0, 40))
	var wm := _sim.weapon_manager
	_order(ignatius, [ignatius, nansen], [t], 12)
	var g := _group()
	assert_eq(_committed_by(g, nansen), 8, "the NSM arrives first, so the frigate takes its whole load")
	assert_eq(_committed_by(g, ignatius), 4)
	var ignatius_queued := wm.group_rounds(g.id, "", true, ignatius)
	var nansen_queued := wm.group_rounds(g.id, "", true, nansen)
	assert_true(nansen_queued > 0 and ignatius_queued > 0)
	var cancel := Order.cancel_fire(t)
	assert_true(_sim.unit_manager.issue_order(nansen, cancel), "the cancel is carried out")
	assert_eq(wm.group_rounds(g.id, "", true, nansen), 0, "the frigate's queued rounds are withdrawn")
	assert_eq(nansen.magazine_count(NSM), nansen_queued, "and back in its magazine")
	assert_eq(wm.group_rounds(g.id, "", true, ignatius), ignatius_queued, "the destroyer's queue is untouched")
	assert_true(g.active, "the group carries on")
	assert_eq(g.member_withdrawn[g.member_index(nansen)], "fire cancelled")
	SimClock.advance(1.0)
	assert_eq(wm.group_rounds(g.id, "", true, nansen), 0, "a withdrawn ship is never given group rounds again")
	assert_eq(_committed_by(g, ignatius), 8, "the destroyer takes up what it can of the frigate's share")
	assert_true(_spent(g) <= 12)
	var in_air := wm.group_rounds(g.id) - wm.group_rounds(g.id, "", true)
	var queued := wm.group_rounds(g.id, "", true)
	var before := ignatius.magazine_count(TOMAHAWK)
	var end := Order.cancel_group_attack(g.id)
	assert_true(_sim.unit_manager.issue_order(ignatius, end), end.receipt)
	assert_true(end.receipt.contains("%d queued rounds back in the magazines" % queued), end.receipt)
	assert_true(not g.active)
	assert_eq(g.ended_reason, "Cancelled")
	assert_eq(wm.group_rounds(g.id, "", true), 0, "nothing of the group is left on a launcher")
	assert_eq(ignatius.magazine_count(TOMAHAWK), before + queued)
	assert_eq(wm.group_rounds(g.id), in_air, "rounds already away fly on")
	var again := Order.cancel_group_attack(g.id)
	assert_true(not _sim.unit_manager.issue_order(ignatius, again), "an ended attack cannot be cancelled twice")
	_done()


func test_a_lost_shooter_hands_its_unfired_share_to_the_others_and_the_budget_still_holds() -> void:
	_setup()
	var nansen := _ship("rnon_ffg_fridtjof_nansen", "Fridtjof Nansen", Vector2(4, 10))
	var ignatius := _ship("usn_ddg_arleigh_burke_iia", "USS Paul Ignatius", Vector2(0, 0))
	var roosevelt := _ship("usn_ddg_arleigh_burke_iia", "USS Roosevelt", Vector2(-4, 0))
	var t := _plot("T1077", Vector2(0, 40))
	var wm := _sim.weapon_manager
	_order(ignatius, [nansen, ignatius, roosevelt], [t], 10)
	var g := _group()
	assert_eq(_committed_by(g, nansen), 8)
	assert_eq(_committed_by(g, ignatius) + _committed_by(g, roosevelt), 2)
	SimClock.advance(3.0)
	var fired_by_nansen := g.member_fired[g.member_index(nansen)]
	var stranded := wm.group_rounds(g.id, "", true, nansen)
	assert_true(fired_by_nansen > 0 and stranded > 0, "lost part way through its ripple")
	var reports: Array = []
	_sim.group_attack_manager.group_report.connect(func(_g: GroupAttack, message: String, _good: bool) -> void: reports.append(message))
	_kill(nansen)
	assert_eq(wm.group_rounds(g.id, "", true, nansen), 0, "its unfired rounds go down with it")
	assert_eq(g.lost_total, stranded)
	assert_eq(nansen.magazine_count(NSM), 0, "nothing is refunded to a ship that has sunk")
	assert_eq(g.member_withdrawn[g.member_index(nansen)], "lost")
	assert_true(reports.size() > 0 and str(reports[0]).contains("Fridtjof Nansen lost") and str(reports[0]).contains("%d unfired rounds back in the pool" % stranded), str(reports))
	SimClock.advance(1.0)
	assert_eq(_committed_by(g, ignatius) + _committed_by(g, roosevelt), 2 + stranded, "the survivors take the lost share")
	assert_eq(_spent(g), 10)
	assert_true(_until(func() -> bool: return not g.active, 900.0))
	assert_eq(g.ended_reason, "Budget fired")
	assert_eq(g.fired_total, 10, "exactly the budget, the lost ship's rounds included")
	assert_true(int(_peak.get(g.id, 0)) <= 10, "never more than the budget at any moment")
	_done()


func test_a_destroyed_contact_takes_no_more_rounds() -> void:
	_setup()
	var ignatius := _ship("usn_ddg_arleigh_burke_iia", "USS Paul Ignatius", Vector2(0, 0))
	var nansen := _ship("rnon_ffg_fridtjof_nansen", "Fridtjof Nansen", Vector2(4, 10))
	var enemy := _ship("rfn_ffg_admiral_gorshkov", "Hidden Name", Vector2(300, 300), "RED")
	enemy.roe = Unit.Roe.HOLD
	var t := _plot("T1077", Vector2(0, 40), "BLUE", enemy)
	var wm := _sim.weapon_manager
	_order(ignatius, [ignatius, nansen], [t], 12, 4)
	var g := _group()
	var queued := wm.group_rounds(g.id, "", true)
	var fired := g.fired_total
	assert_true(queued > 0)
	var nansen_left := nansen.magazine_count(NSM)
	_kill(enemy)
	assert_true(not g.active, "the attack is over the moment its contact is")
	assert_eq(g.ended_reason, "Target destroyed")
	assert_eq(wm.group_rounds(g.id, "", true), 0, "nothing more leaves a launcher for it")
	assert_eq(nansen.magazine_count(NSM), nansen_left + queued, "the queued rounds go back aboard")
	SimClock.advance(60.0)
	assert_eq(g.fired_total, fired, "no further expenditure")
	_done()


func test_a_stale_contact_holds_fire_and_a_lost_one_ends_the_attack() -> void:
	_setup()
	var ignatius := _ship("usn_ddg_arleigh_burke_iia", "USS Paul Ignatius", Vector2(0, 0))
	var nansen := _ship("rnon_ffg_fridtjof_nansen", "Fridtjof Nansen", Vector2(4, 10))
	var t := _plot("T1078", Vector2(0, 40))
	var wm := _sim.weapon_manager
	_order(ignatius, [ignatius, nansen], [t], 8)
	var g := _group()
	assert_eq(_committed_by(g, nansen), 8)
	SimClock.advance(DT)
	# The plot has had nothing on it for a minute.
	_held.erase(t)
	t.last_seen_time = SimClock.sim_time - Track.STALE_AFTER_S - 1.0
	t.status = Track.Status.STALE
	SimClock.advance(1.0)
	assert_eq(wm.group_rounds(g.id, "", true), 0, "no round waits on a launcher for a stale plot")
	var fired := g.fired_total
	assert_eq(nansen.magazine_count(NSM), 8 - fired, "the held rounds went back aboard")
	assert_true(g.active, "the attack holds rather than ends")
	SimClock.advance(10.0)
	assert_eq(g.fired_total, fired, "nothing fires at a stale plot")
	assert_eq(_sim.group_attack_manager.phase(g).contains("awaiting solution") or _sim.group_attack_manager.phase(g).contains("away"), true, _sim.group_attack_manager.phase(g))
	_held.append(t)
	t.status = Track.Status.ACTIVE
	t.last_seen_time = SimClock.sim_time
	SimClock.advance(1.0)
	assert_eq(_spent(g), 8, "a fresh plot again: the volley is filled")
	# Now the plot loses it altogether.
	_held.erase(t)
	t.status = Track.Status.LOST
	SimClock.advance(1.0)
	assert_true(not g.active)
	assert_eq(g.ended_reason, "Contact lost")
	assert_eq(wm.group_rounds(g.id, "", true), 0)
	fired = g.fired_total
	SimClock.advance(30.0)
	assert_eq(g.fired_total, fired, "no further expenditure on a lost contact")
	assert_true(int(_peak.get(g.id, 0)) <= 8)
	_done()


func test_individual_fire_still_works_beside_a_group() -> void:
	_setup()
	var ignatius := _ship("usn_ddg_arleigh_burke_iia", "USS Paul Ignatius", Vector2(0, 0))
	var nansen := _ship("rnon_ffg_fridtjof_nansen", "Fridtjof Nansen", Vector2(4, 10))
	var t := _plot("T1077", Vector2(0, 40))
	var other := _plot("T1078", Vector2(20, 40))
	var wm := _sim.weapon_manager
	_order(ignatius, [ignatius, nansen], [t], 4)
	var g := _group()
	assert_eq(_spent(g), 4)
	var tomahawk := ignatius.get_weapon(TOMAHAWK)
	var nsm := nansen.get_weapon(NSM)
	assert_true(_sim.unit_manager.issue_order(ignatius, Order.engage(other, TOMAHAWK, 2)), "a member can still fire on its own order")
	assert_eq(wm.committed_rounds(ignatius, tomahawk, other), 2)
	assert_true(_sim.unit_manager.issue_order(nansen, Order.engage(t, NSM, 2)), "even at the group's own contact")
	assert_eq(_spent(g), 4, "its own rounds are not the group's")
	assert_eq(wm.faction_commitment("BLUE", t), 6, "but the side counts every round at the contact")
	var own_queued := wm.committed_rounds(ignatius, tomahawk, other, true)
	var nansen_own_queued := wm.committed_rounds(nansen, nsm, t, true) - wm.group_rounds(g.id, "", true, nansen)
	assert_true(_sim.unit_manager.issue_order(ignatius, Order.cancel_group_attack(g.id)))
	assert_eq(wm.committed_rounds(ignatius, tomahawk, other, true), own_queued, "cancelling the group leaves a member's own fire alone")
	assert_eq(wm.committed_rounds(nansen, nsm, t, true), nansen_own_queued)
	assert_true(_sim.unit_manager.issue_order(nansen, Order.cancel_fire(t)), "and the ordinary cancel still refunds it")
	assert_eq(wm.committed_rounds(nansen, nsm, t, true), 0)
	_done()


func test_a_group_with_no_solution_is_refused_and_a_partial_one_names_who_cannot_fire() -> void:
	_setup()
	var ignatius := _ship("usn_ddg_arleigh_burke_iia", "USS Paul Ignatius", Vector2(0, 0))
	var nansen := _ship("rnon_ffg_fridtjof_nansen", "Fridtjof Nansen", Vector2(0, -80))
	var t := _plot("T1077", Vector2(0, 40))
	ignatius.roe = Unit.Roe.HOLD
	var o := _order(ignatius, [ignatius, nansen], [t], 8)
	assert_true(not o.execution_accepted, "no shooter can put a round on it")
	assert_true(o.receipt.contains("USS Paul Ignatius: weapons hold"), o.receipt)
	assert_true(o.receipt.contains("Fridtjof Nansen: out of range"), o.receipt)
	assert_eq(_sim.group_attack_manager.groups.size(), 0, "nothing is created for a refused order")
	assert_eq(ignatius.magazine_count(TOMAHAWK) + nansen.magazine_count(NSM), 16)
	ignatius.roe = Unit.Roe.FREE
	o = _order(ignatius, [ignatius, nansen], [t], 8)
	assert_true(o.execution_accepted, o.receipt)
	assert_eq(o.receipt, "8-round group attack on track 1077: USS Paul Ignatius 8 × Tomahawk, Fridtjof Nansen refused: out of range")
	_done()


func test_allocation_uses_the_plot_never_the_unit_under_it() -> void:
	_setup()
	var nansen := _ship("rnon_ffg_fridtjof_nansen", "Fridtjof Nansen", Vector2(0, 0))
	var ignatius := _ship("usn_ddg_arleigh_burke_iia", "USS Paul Ignatius", Vector2(0, -2))
	var decoy := _ship("rfn_ffg_admiral_gorshkov", "Hidden Name", Vector2(0, 150), "RED")
	decoy.roe = Unit.Roe.HOLD
	var near := _plot("T1077", Vector2(0, 40), "BLUE", decoy)
	var o := _order(nansen, [nansen, ignatius], [near], 2)
	assert_true(o.receipt.contains("Fridtjof Nansen 2 × NSM"), "the plot is in NSM range whatever is really there: " + o.receipt)
	var far_plot := _plot("T1078", Vector2(0, 150), "BLUE", null)
	decoy.position = Vector2(0, 40)
	far_plot.truth = decoy
	o = _order(nansen, [nansen, ignatius], [far_plot], 2)
	assert_true(o.receipt.contains("Fridtjof Nansen refused: out of range"), "and out of range when the plot is, though the unit is close: " + o.receipt)
	_done()


func test_two_contacts_split_the_budget_by_priority_and_a_destroyed_one_hands_on_its_share() -> void:
	_setup()
	var ignatius := _ship("usn_ddg_arleigh_burke_iia", "USS Paul Ignatius", Vector2(0, 0))
	var roosevelt := _ship("usn_ddg_arleigh_burke_iia", "USS Roosevelt", Vector2(-4, 0))
	var enemy := _ship("rfn_ffg_admiral_gorshkov", "Hidden Name", Vector2(300, 300), "RED")
	enemy.roe = Unit.Roe.HOLD
	var first := _plot("T1077", Vector2(0, 40), "BLUE", enemy)
	var second := _plot("T1078", Vector2(10, 40))
	var o := _order(ignatius, [ignatius, roosevelt], [first, second], 7, 2)
	var g := _group()
	assert_true(o.receipt.begins_with("7-round group attack on tracks 1077, 1078"), o.receipt)
	assert_eq(g.target_share[0], 4, "an even split, the odd round to the first contact")
	assert_eq(g.target_share[1], 3)
	var wm := _sim.weapon_manager
	assert_eq(wm.group_rounds(g.id, g.target_keys[0]), 2, "one volley of two at each")
	assert_eq(wm.group_rounds(g.id, g.target_keys[1]), 2)
	_kill(enemy)
	assert_true(g.active, "the other contact is still under attack")
	assert_eq(g.target_done[0], "Target destroyed")
	assert_eq(g.target_share[1], 3 + 4 - g.target_fired[0], "the sunk contact's unspent share goes to the other")
	assert_true(_until(func() -> bool: return not g.active, 1800.0))
	assert_eq(g.target_fired[0] + g.target_fired[1], g.fired_total)
	assert_true(g.fired_total <= 7)
	assert_true(int(_peak.get(g.id, 0)) <= 7)
	_done()
