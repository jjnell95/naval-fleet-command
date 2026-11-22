class_name SubmarineInitiative
extends RefCounted
## A boat out of touch under Classic communications still looks after herself. The commander's
## orders wait for a check-in, but her captain does not wait for orders to save the boat: she turns
## away from a torpedo she hears homing on her (her decoys are already the crew's, through
## TorpedoDefence, under the countermeasures setting), and with the battery CRITICAL she comes up
## to snorkel. Each is recorded and reported with her next check-in. A boat in touch, or under
## immediate communications, is the commander's to handle and is left alone.


## One defence cycle for every boat that is out of touch.
static func run_cycle(um: UnitManager, tm: ThreatManager) -> void:
	for u: Unit in um.units:
		if not u.alive or not SubmarineComms.restricted(u) or SubmarineComms.connected(u) or not u.is_engageable():
			continue
		var torpedo := _torpedo_heard(u, tm)
		if torpedo != null and u.evasion_remaining_s <= 0.0:
			if DefensiveResponse.start_evasion(u, um, tm):
				note(u, um.now_s, "turned away from a torpedo bearing %03d" % int(round(Geo.bearing_deg(u.position, torpedo.position))))
		if torpedo == null and u.evasion_remaining_s <= 0.0 and SubmarinePower.fitted(u) and u.battery <= SubmarinePower.CRITICAL and SubmarinePower.snorkel_rejection(u, true) == "":
			var order := Order.snorkel(true)
			order.origin = "crew"
			if um.issue_order(u, order):
				note(u, um.now_s, "came up to snorkel at %d%% battery" % int(round(u.battery * 100.0)))


## A torpedo homing on this boat that she hears herself. Off the link, her own ears are all she has.
static func _torpedo_heard(u: Unit, tm: ThreatManager) -> Weapon:
	for w: Weapon in tm.get_threats(u.faction):
		if w.phase != Weapon.Phase.DEAD and w.spec != null and w.spec.is_torpedo() and w.acquired == u and tm.visible_to(u, w):
			return w
	return null


## Records what the crew did, for the next report.
static func note(u: Unit, now: float, what: String) -> void:
	if u.comms_initiative.size() < 16:
		u.comms_initiative.append("%s %s" % [_clock(now), what])


static func _clock(seconds: float) -> String:
	var s := maxi(int(seconds), 0)
	return "%02d%02d" % [(s / 3600) % 24, (s % 3600) / 60]
