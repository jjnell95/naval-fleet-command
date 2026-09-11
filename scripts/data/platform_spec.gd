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


func flight_requirement() -> String:
	if launch_requirement != "auto":
		return launch_requirement
	if can_hover:
		return "helicopter"
	if id in ["usn_aew_e2d", "usn_fighter_fa18e", "usn_ea_ea18g"]:
		return "catobar"
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
