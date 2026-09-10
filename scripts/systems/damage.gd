class_name Damage
## Damage application. The hull is a pool; on top of it a hit can knock out propulsion, sensors or
## weapons, which is usually what actually takes a ship out of the fight. All values here are
## GAMEPLAY tuning, not a survivability model.

const COMPONENT_HIT_SCALE := 1.6  # chance of a subsystem hit, per fraction of hull lost
const COMPONENT_LOSS_SCALE := 1.3  # how hard that subsystem is knocked about

static var rng := RandomNumberGenerator.new()


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
