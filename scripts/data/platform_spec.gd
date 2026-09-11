class_name PlatformSpec
extends Resource
## Data-driven platform specification. Instances live in data/platforms/**/*.tres.
## Public figures (dimensions, speed band) are used as-is; uncertain performance values are
## GAMEPLAY_ESTIMATE tuning parameters and must be marked in `source_status`.

@export var id := ""
@export var display_name := ""
@export var short_name := ""
@export var nation := ""
@export var category := ""  # carrier, cruiser, destroyer, frigate, corvette, ...
@export var domain := "surface"  # surface | subsurface | air
@export var max_speed_kn := 25.0
@export var cruise_speed_kn := 15.0
@export var turn_rate_deg_s := 3.0  # GAMEPLAY_ESTIMATE
@export var accel_kn_s := 0.25  # GAMEPLAY_ESTIMATE
@export var length_m := 0.0
@export var displacement_t := 0.0
@export var source_status := ""
@export var sensor_ids: PackedStringArray = []  # resolved via DataDB.sensor()
@export var signature_factor := 1.0  # radar signature vs baseline large combatant (GAMEPLAY_ESTIMATE)
@export var mast_height_m := 25.0  # radar-horizon geometry (GAMEPLAY_ESTIMATE)
@export var health := 100.0  # abstract damage pool (GAMEPLAY_ESTIMATE)

## Acoustics. `acoustic_signature` is radiated noise at a crawl, relative to a noisy surface
## combatant at 1.0. Everything here is a GAMEPLAY_ESTIMATE: real signature figures are not public
## and are not being claimed.
@export var acoustic_signature := 1.0
@export var max_depth_m := 0.0  # 0 for anything that cannot submerge
@export var patrol_depth_m := 0.0  # depth the AI holds when nothing is happening
@export var depth_rate_m_s := 0.0  # how fast it changes depth

## Aviation. All GAMEPLAY_ESTIMATE. `endurance_s` is time airborne at cruise; burn scales with
## speed, so a dash costs more than the clock suggests.
@export var cruise_altitude_m := 0.0
@export var max_altitude_m := 0.0
@export var altitude_rate_m_s := 0.0
@export var endurance_s := 0.0
@export var can_hover := false
@export var launch_time_s := 120.0
@export var recovery_time_s := 180.0
@export var aircraft_capacity := 0  # how many airframes a ship or base can operate
@export var sonobuoy_count := 0

## Deck cycle. A carrier is not a frigate with a bigger hangar: it launches off several catapults
## at once and recovers down a single angled deck, and everything it recovers has to be refuelled,
## rearmed and respotted before it can go again. Zero means "derive from the flight facility",
## so an ordinary escort needs no entry. GAMEPLAY_ESTIMATE: spot counts stand in for deck handling,
## not for real cyclic operations, air plans or pilot qualification.
@export var launch_spots := 0  # airframes that can be on the catapults / spots at once
@export var recovery_spots := 0  # airframes that can be in the groove at once
@export var turnaround_s := 0.0  # deck time to refuel, rearm and respot after a recovery

## Air-to-air refuelling. `tanker_offload_s` is fuel a tanker can give away, counted in the
## receiver's own endurance-seconds; `can_refuel` says the airframe has a probe or receptacle.
## GAMEPLAY_ESTIMATE: a single transfer rate stands in for basket work, tanker tracks and give.
@export var tanker_offload_s := 0.0
@export var can_refuel := false

## Aircraft a ship or base sails with when a scenario does not say otherwise: platform id -> count.
## This is what puts a helicopter in a destroyer's hangar without every scenario listing it.
@export var default_air_wing: Dictionary = {}
@export var sonobuoy_sensitivity_nm := 0.0
@export var sonobuoy_life_s := 1800.0
@export var weapon_loadout: Dictionary = {}  # weapon id -> rounds carried
@export var has_datalink := true  # a merchant or a boat under water is not on the network
@export var fire_control_channels := 4  # simultaneous air-defence engagements (GAMEPLAY_ESTIMATE)
@export var decoy_count := 12  # chaff / decoy launches carried (GAMEPLAY_ESTIMATE)
@export var decoy_effectiveness := 0.35  # base chance one salvo of decoys defeats a seeker

## Recognition and configuration metadata. Performance remains estimated; capacity is physical.
@export var role := ""
@export var service_note := ""
@export var aviation_facility := "auto"  # auto | none | helicopter | stovl | catobar | airfield
@export var launch_requirement := "auto"  # auto | helicopter | stovl | catobar | runway
@export var vls_cells := 0


func flight_facility() -> String:
	if aviation_facility != "auto":
		return aviation_facility
	if aircraft_capacity <= 0:
		return "none"
	if domain == "land":
		return "airfield"
	return "catobar" if category.contains("carrier") else "helicopter"


## How many airframes can be going off at once. A CATOBAR deck works several catapults in
## parallel; a frigate has one spot and that is the whole story.
func launch_capacity() -> int:
	if launch_spots > 0:
		return launch_spots
	match flight_facility():
		"catobar": return 4
		"stovl": return 2
		"airfield": return 4
		"helicopter": return 1
	return 0


## How many can be coming aboard at once. One angled deck means one at a time however big the
## ship is; a field with parallel runways and a STOVL deck with several landing spots do better.
func recovery_capacity() -> int:
	if recovery_spots > 0:
		return recovery_spots
	match flight_facility():
		"catobar": return 1
		"stovl": return 2
		"airfield": return 3
		"helicopter": return 1
	return 0


## Deck time between coming aboard and being fit to launch again. An airframe that lands is not
## a round in a magazine: it has to be struck below, fuelled, rearmed and brought back up.
func turnaround_time_s() -> float:
	if turnaround_s > 0.0:
		return turnaround_s
	match flight_facility():
		"catobar": return 2700.0
		"stovl": return 2700.0
		"airfield": return 3600.0
		"helicopter": return 1800.0
	return 0.0


## What kind of deck this airframe needs. Carrier aircraft say so on their own spec; anything
## that can hover works off a flight deck, and everything else needs a runway. There is
## deliberately no list of ids here: a new carrier aircraft that forgot to declare itself would
## quietly become a land-based one, and nothing would fail until a scenario refused to launch it.
func flight_requirement() -> String:
	if launch_requirement != "auto":
		return launch_requirement
	if can_hover:
		return "helicopter"
	return "runway"


func can_operate(aircraft: PlatformSpec) -> bool:
	if aircraft == null or aircraft_capacity <= 0 or aircraft.domain != "air":
		return false
	var facility := flight_facility()
	var required := aircraft.flight_requirement()
	if facility == "airfield":
		return true
	if required == "helicopter":
		return facility in ["helicopter", "stovl", "catobar"]
	return facility == required or (facility == "catobar" and required == "stovl")


func occupied_vls_cells() -> int:
	var count := 0
	for wid in weapon_loadout:
		var w := DataDB.weapon(wid)
		if w != null and w.vls_pack > 0:
			count += ceili(float(weapon_loadout[wid]) / float(w.vls_pack))
	return count
