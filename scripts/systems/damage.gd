class_name Damage
## Damage application. The hull is a pool; on top of it a hit can knock out propulsion, sensors or
## weapons, which is usually what actually takes a ship out of the fight. All values here are
## GAMEPLAY tuning, not a survivability model.
##
## A hit is also where a fight for the ship begins rather than ends. A missile brings its warhead
## and its unspent fuel inboard and usually starts a fire; a torpedo under the keel lets the sea in.
## Both keep costing hull until the damage-control parties win or lose:
##
## * Fire grows on its own and is beaten back by damage control, both in proportion to its size.
##   Above a critical level of damage control it dies away; below it, it grows. It burns hull the
##   whole time, and a burning ship's crew gets weaker, so a sound ship contains a single hit while
##   a crippled one can be lost an hour after the missile that started it.
## * Flooding is pumped and shored down, and runs away only when damage control has collapsed. Water
##   aboard also slows the ship.
## * Damage control is stronger in a bigger ship, weaker in a badly hurt one, split when it has fire
##   and flooding at once, and takes a few minutes to organise after the hit. Each hit also draws
##   its own fortune: a fire main cut or intact, a space reachable or not. A consort alongside lends
##   hoses and pumps.
## * Knocked-out systems are only worked on once the ship is safe: fire and flooding come first.
##
## Shapes after public damage-control history (Stark 1987, Sheffield 1982, Moskva 2022) in the
## most general sense; every constant is GAMEPLAY_ESTIMATE.

const COMPONENT_HIT_SCALE := 1.6  # chance of a subsystem hit, per fraction of hull lost
const COMPONENT_LOSS_SCALE := 1.3  # how hard that subsystem is knocked about

## Damage control. Crews restore knocked-out subsystems over time, but a jury-rigged repair at
## sea never gets a system back to new, and the hull itself is not patched. GAMEPLAY_ESTIMATE.
const REPAIR_RATE_PER_S := 1.0 / 1500.0  # a subsystem climbs from 0 to the cap in ~25 minutes
const REPAIR_CAP := 0.85

## Fire. Per second, intensity f in [0, 1]: df = (SPREAD - FIGHT * dc) * f. Critical dc is 0.375.
const FIRE_SPREAD := 0.0015
const FIRE_FIGHT := 0.004
const FIRE_BURN := 0.00012  # fraction of full hull lost per second at intensity 1
const FIRE_SYSTEM_WEAR := 0.00015  # a burning ship loses systems as well as hull
const FIRE_OUT_BELOW := 0.02
## Flooding. Per second, severity w in [0, 1]: dw = PROGRESS * w - CONTROL * dc.
const FLOOD_PROGRESS := 0.0003
const FLOOD_CONTROL := 0.0009
const FLOOD_SINK := 0.0002  # fraction of full hull lost per second at severity 1
const FLOOD_SPEED_LOSS := 0.4  # full flooding costs this fraction of top speed
const FLOOD_OUT_BELOW := 0.02
## Damage-control capacity.
const DC_ORGANISE_S := 480.0  # time for the parties to reach full effect after a hit
const DC_EARLY := 0.65  # effect straight after the hit
const DC_SPLIT := 0.75  # each casualty gets this share when a ship has both
const DC_CONDITION_FLOOR := 0.35  # most of a crew survives a hit that wrecks half the hull
const DC_FORTUNE_MIN := 0.55  # per-hit draw on how well the fight can go
const DC_FORTUNE_MAX := 1.2
const ASSIST_RANGE_NM := 1.0
const ASSIST_BONUS := 0.35  # per consort alongside, up to two
## How likely each kind of hit is to start a fire or let water in, and how badly.
const FIRE_CHANCE := {"asm": 0.45, "gun": 0.15, "sam": 0.2, "torpedo": 0.1}
const FLOOD_CHANCE := {"asm": 0.25, "gun": 0.05, "sam": 0.05, "torpedo": 0.95}

static var rng := RandomNumberGenerator.new()


## Damage-control tick for every living unit. Aircraft carry no repair parties. Returns the
## casualty events this tick produced, as {unit, event}, for the simulation to report: `fire`,
## `fire_out`, `flooding_controlled`, `lost` (sunk by fire or flooding).
static func tick(units: Array, dt: float) -> Array:
	var events: Array = []
	for u: Unit in units:
		if not u.alive or u.is_aircraft():
			continue
		if u.fire > 0.0 or u.flooding > 0.0:
			_fight_casualties(u, units, dt, events)
			if not u.alive:
				continue
		if u.fire > 0.0 or u.flooding > 0.0:
			continue  # every hand is on the fire or the pumps; systems wait
		for name in Unit.COMPONENTS:
			var v := u.component(name)
			if v < REPAIR_CAP:
				u.components[name] = minf(v + REPAIR_RATE_PER_S * dt, REPAIR_CAP)
	return events


static func _fight_casualties(u: Unit, units: Array, dt: float, events: Array) -> void:
	u.casualty_time_s += dt
	var dc := damage_control(u, units)
	var both := u.fire > 0.0 and u.flooding > 0.0
	var share := DC_SPLIT if both else 1.0
	var hull := maxf(u.spec.health, 1.0)
	if u.fire > 0.0:
		u.fire = clampf(u.fire + (FIRE_SPREAD - FIRE_FIGHT * dc * share) * u.fire * dt, 0.0, 1.0)
		u.health -= FIRE_BURN * u.fire * hull * dt
		var which: String = Unit.COMPONENTS[rng.randi() % Unit.COMPONENTS.size()]
		u.components[which] = maxf(u.component(which) - FIRE_SYSTEM_WEAR * u.fire * dt, 0.0)
		if u.fire < FIRE_OUT_BELOW:
			u.fire = 0.0
			events.append({"unit": u, "event": "fire_out"})
	if u.flooding > 0.0:
		u.flooding = clampf(u.flooding + (FLOOD_PROGRESS * u.flooding - FLOOD_CONTROL * dc * share) * dt, 0.0, 1.0)
		u.health -= FLOOD_SINK * u.flooding * hull * dt
		if u.flooding < FLOOD_OUT_BELOW:
			u.flooding = 0.0
			events.append({"unit": u, "event": "flooding_controlled"})
	if u.fire <= 0.0 and u.flooding <= 0.0:
		u.casualty_time_s = 0.0
	u.ordered_speed_kn = minf(u.ordered_speed_kn, u.effective_max_speed())
	if u.health <= 0.0:
		_sink(u)
		events.append({"unit": u, "event": "lost"})


## How hard this ship's crew can fight fire and flooding right now, before splitting the effort.
static func damage_control(u: Unit, units: Array = []) -> float:
	var crew := clampf(sqrt(maxf(u.spec.health, 1.0) / 100.0), 0.6, 1.4)
	var condition := lerpf(DC_CONDITION_FLOOR, 1.0, clampf(health_fraction(u) * 1.3, 0.0, 1.0))
	var organised := lerpf(DC_EARLY, 1.0, clampf(u.casualty_time_s / DC_ORGANISE_S, 0.0, 1.0))
	var assist := 0.0
	for other: Unit in units:
		if other == u or not other.alive or other.faction != u.faction or other.spec.domain != "surface":
			continue
		if other.position.distance_to(u.position) <= ASSIST_RANGE_NM:
			assist = minf(assist + ASSIST_BONUS, ASSIST_BONUS * 2.0)
	return crew * condition * organised * u.dc_fortune + assist


## True when any subsystem is being worked on right now.
static func repairing(u: Unit) -> bool:
	if not u.alive or u.is_aircraft():
		return false
	if u.fire > 0.0 or u.flooding > 0.0:
		return true
	for name in Unit.COMPONENTS:
		if u.component(name) < REPAIR_CAP:
			return true
	return false


## Applies damage and returns true if the unit was destroyed by this hit. `kind` is the attacking
## weapon's type (asm, gun, torpedo...) and decides whether the hit starts a fire or lets water in;
## `attacker` is the firing faction, remembered so a ship that later sinks is credited to it.
static func apply(target: Unit, amount: float, kind := "", attacker := "") -> bool:
	if not target.alive:
		return false
	var fraction := amount / maxf(target.spec.health, 1.0)
	target.health = maxf(target.health - amount, 0.0)
	if attacker != "":
		target.last_attacker = attacker
	if target.health > 0.0 and rng.randf() < clampf(fraction * COMPONENT_HIT_SCALE, 0.0, 0.95):
		var which: String = Unit.COMPONENTS[rng.randi() % Unit.COMPONENTS.size()]
		var loss := clampf(fraction * COMPONENT_LOSS_SCALE * rng.randf_range(0.5, 1.5), 0.0, 1.0)
		target.components[which] = clampf(target.component(which) - loss, 0.0, 1.0)
	if target.health > 0.0 and kind != "" and target.needs_sea_room():
		_start_casualties(target, fraction, kind)
	target.ordered_speed_kn = minf(target.ordered_speed_kn, target.effective_max_speed())
	if target.health <= 0.0:
		_sink(target)
		return true
	return false


static func _start_casualties(target: Unit, fraction: float, kind: String) -> void:
	var started := false
	# A submarine has little to burn outside a pressure hull that is already flooding.
	if not target.is_submarine() and rng.randf() < clampf(float(FIRE_CHANCE.get(kind, 0.0)) + fraction * 0.8, 0.0, 0.95):
		target.fire = clampf(target.fire + 0.12 + fraction * rng.randf_range(0.4, 1.1), 0.0, 1.0)
		started = true
	if rng.randf() < clampf(float(FLOOD_CHANCE.get(kind, 0.0)) + fraction * 0.5, 0.0, 0.98):
		var base := 0.35 if kind == "torpedo" else 0.05
		target.flooding = clampf(target.flooding + base + fraction * rng.randf_range(0.3, 0.9), 0.0, 1.0)
		started = true
	if started:
		target.casualty_time_s = 0.0  # a fresh hit disorganises the parties again
		target.dc_fortune = rng.randf_range(DC_FORTUNE_MIN, DC_FORTUNE_MAX)


static func _sink(target: Unit) -> void:
	target.health = 0.0
	target.alive = false
	target.speed_kn = 0.0
	target.ordered_speed_kn = 0.0
	target.waypoints.clear()
	target.radar_on = false
	target.active_sonar_on = false
	target.fire = 0.0
	target.flooding = 0.0


static func health_fraction(u: Unit) -> float:
	if u.spec.health <= 0.0:
		return 0.0
	return clampf(u.health / u.spec.health, 0.0, 1.0)


## Subsystems that are meaningfully degraded, for the unit panel.
static func damage_report(u: Unit) -> String:
	var parts := PackedStringArray()
	if u.fire > 0.0:
		parts.append("FIRE %d%%" % int(round(u.fire * 100.0)))
	if u.flooding > 0.0:
		parts.append("FLOODING %d%%" % int(round(u.flooding * 100.0)))
	for name in Unit.COMPONENTS:
		var v := u.component(name)
		if v < 0.99:
			parts.append("%s %d%%" % [name, int(round(v * 100.0))])
	return ", ".join(parts) if not parts.is_empty() else "all systems"


## Whether the fire aboard is past the point the crew can put it out on their own right now.
static func fire_out_of_control(u: Unit, units: Array = []) -> bool:
	if u.fire <= 0.0:
		return false
	var share := DC_SPLIT if u.flooding > 0.0 else 1.0
	return FIRE_SPREAD > FIRE_FIGHT * damage_control(u, units) * share


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
