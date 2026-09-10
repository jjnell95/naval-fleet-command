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
