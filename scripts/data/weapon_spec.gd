class_name WeaponSpec
extends Resource
## Data-driven weapon. Real weapon families are named, but every performance number here is a
## GAMEPLAY tuning parameter derived from broad public range bands — not a capability claim.
## Guidance is modelled as an abstraction (aim point + terminal seeker radius), never as real
## seeker logic or engagement doctrine.

@export var id := ""
@export var display_name := ""
@export var family := ""
@export var type := "asm"  # asm | sam | ciws | gun | torpedo
@export var guidance := "inertial_active"  # abstraction label only
@export var profile := "sea_skimming"  # sea_skimming | high | direct | subsurface | ballistic | exoatmospheric
@export var target_types: PackedStringArray = ["surface"]
@export var max_range_nm := 60.0
@export var min_range_nm := 2.0
@export var speed_kn := 480.0
@export var turn_rate_deg_s := 15.0
@export var seeker_range_nm := 8.0  # terminal acquisition radius; <=0 means unguided (gun)
@export var damage := 40.0
@export var base_pk := 0.8  # hit probability once terminal acquisition succeeds
@export var salvo_default := 2
@export var launch_interval_s := 4.0  # spacing between rounds of one salvo
@export var defensive_difficulty := 1.0  # how hard this round is to shoot down (higher = harder)
@export var signature_factor := 0.15  # radar signature vs a ship-sized target (GAMEPLAY_ESTIMATE)
@export var altitude_m := 10.0  # flight altitude used for detection horizon (GAMEPLAY_ESTIMATE)
@export var soft_kill_resistance := 1.0  # resistance to decoys and chaff (higher = harder)

## Torpedoes. A torpedo runs out to `run_to_enable_nm` before its seeker comes on, so a shot at
## very short range can pass a target without ever looking at it. Delivery by rocket is abstracted
## into `speed_kn` rather than modelled as a separate flight phase.
@export var run_to_enable_nm := 0.0
@export var acoustic_signature := 0.6  # how loud the weapon itself is while running
@export var source_status := ""


func is_gun() -> bool:
	return type == "gun"


## True for weapons whose job is shooting down other weapons.
func is_interceptor() -> bool:
	return type == "sam" or type == "ciws"


func is_torpedo() -> bool:
	return type == "torpedo"


func acquisition_radius_nm() -> float:
	return seeker_range_nm if seeker_range_nm > 0.0 else 0.5
