class_name Damage
## Damage application. The hull is a pool; on top of it a hit can knock out propulsion, sensors or
## weapons, which is usually what actually takes a ship out of the fight. All values here are
## GAMEPLAY tuning, not a survivability model.

const COMPONENT_HIT_SCALE := 1.6  # chance of a subsystem hit, per fraction of hull lost
const COMPONENT_LOSS_SCALE := 1.3  # how hard that subsystem is knocked about

## Damage control. Crews restore knocked-out subsystems over time, but a jury-rigged repair at
## sea never gets a system back to new, and the hull itself is not patched. GAMEPLAY_ESTIMATE.
const REPAIR_RATE_PER_S := 1.0 / 1500.0  # a subsystem climbs from 0 to the cap in ~25 minutes
const REPAIR_CAP := 0.85

static var rng := RandomNumberGenerator.new()


## Damage-control tick for every living unit. Aircraft carry no repair parties.
static func tick(units: Array, dt: float) -> void:
	for u: Unit in units:
		if not u.alive or u.is_aircraft():
			continue
		for name in Unit.COMPONENTS:
			var v := u.component(name)
			if v < REPAIR_CAP:
				u.components[name] = minf(v + REPAIR_RATE_PER_S * dt, REPAIR_CAP)


## True when any subsystem is being worked on right now.
static func repairing(u: Unit) -> bool:
	if not u.alive or u.is_aircraft():
		return false
	for name in Unit.COMPONENTS:
		if u.component(name) < REPAIR_CAP:
			return true
	return false


## Applies damage and returns true if the unit was destroyed by this hit.
static func apply(target: Unit, amount: float) -> bool:
	if not target.alive:
		return false
	var fraction := amount / maxf(target.spec.health, 1.0)
	target.health = maxf(target.health - amount, 0.0)
	if target.health > 0.0 and rng.randf() < clampf(fraction * COMPONENT_HIT_SCALE, 0.0, 0.95):
		var which: String = Unit.COMPONENTS[rng.randi() % Unit.COMPONENTS.size()]
		var loss := clampf(fraction * COMPONENT_LOSS_SCALE * rng.randf_range(0.5, 1.5), 0.0, 1.0)
		target.components[which] = clampf(target.component(which) - loss, 0.0, 1.0)
		target.ordered_speed_kn = minf(target.ordered_speed_kn, target.effective_max_speed())
	if target.health <= 0.0:
		target.alive = false
		target.speed_kn = 0.0
		target.ordered_speed_kn = 0.0
		target.waypoints.clear()
		target.radar_on = false
		target.active_sonar_on = false
		return true
	return false


static func health_fraction(u: Unit) -> float:
	if u.spec.health <= 0.0:
		return 0.0
	return clampf(u.health / u.spec.health, 0.0, 1.0)


## Subsystems that are meaningfully degraded, for the unit panel.
static func damage_report(u: Unit) -> String:
	var parts := PackedStringArray()
	for name in Unit.COMPONENTS:
		var v := u.component(name)
		if v < 0.99:
			parts.append("%s %d%%" % [name, int(round(v * 100.0))])
	return ", ".join(parts) if not parts.is_empty() else "all systems"


static func condition_text(u: Unit) -> String:
	if not u.alive:
		return "DESTROYED"
	var f := health_fraction(u)
	if f > 0.85:
		return "OPERATIONAL"
	if f > 0.55:
		return "LIGHT DAMAGE"
	if f > 0.25:
		return "HEAVY DAMAGE"
	return "CRITICAL"
