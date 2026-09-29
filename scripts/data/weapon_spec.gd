class_name WeaponSpec
extends Resource
## Data-driven weapon. Real weapon families are named, but every performance number here is a
## GAMEPLAY tuning parameter derived from broad public range bands — not a capability claim.
## Guidance is modelled as an abstraction (aim point + terminal seeker radius), never as real
## seeker logic or engagement doctrine.

@export var id := ""
@export var display_name := ""
## What an operator would call it on a crowded board: "SM-2", "Harpoon", "H/PJ-11". Eleven letters at
## most, so the data display can lay a big ship's weapons out in columns.
@export var short_name := ""
@export var family := ""
@export var type := "asm"  # asm | sam | aam | ciws | gun | torpedo | asw_rocket | bomb
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
## very short range can pass a target without ever looking at it. Delivery
## by an ASW rocket uses delivery_payload_id and a separate air-to-water transition.
@export var run_to_enable_nm := 0.0
@export var acoustic_signature := 0.6  # how loud the weapon itself is while running
@export var delivery_payload_id := ""  # rocket-delivered ASW payload after water entry
@export var source_status := ""
@export var vls_pack := 0  # rounds per VLS cell; 0 = not modelled as a VLS round
@export var intercept_min_altitude_m := 0.0
@export var intercept_max_altitude_m := 1000000.0

## Public role, not a claim about actual engagement doctrine. Separate budgets let the
## point-defence layer engage a leaker after the outer layer has spent its allowance.
@export var defence_layer := ""  # area | point; empty derives a conservative range band


## The short name where there is one, else the full name.
func compact_name() -> String:
	return short_name if short_name != "" else display_name


func defensive_layer() -> String:
	if type == "ciws":
		return "close_in"
	if defence_layer != "":
		return defence_layer
	return "area" if max_range_nm >= 40.0 else "point"


func requires_radar_support() -> bool:
	return type == "sam" and guidance in ["fire_control_directed", "semi_active_radar", "semi_active_radar_homing"]


func requires_fire_control_channel() -> bool:
	return type == "sam" and guidance not in ["passive_rf_infrared", "infrared", "infrared_homing", "imaging_infrared"]


func seeker_band() -> String:
	if is_torpedo():
		return "acoustic" if guidance.contains("acoustic") else "none"
	if guidance.contains("infrared"):
		return "infrared"
	if guidance.contains("radar") or guidance == "inertial_active":
		return "radar"
	return "none"


func is_gun() -> bool:
	return type == "gun"


## True for weapons whose job is shooting down other weapons.
func is_interceptor() -> bool:
	return type == "sam" or type == "ciws"


func is_torpedo() -> bool:
	return type == "torpedo"


func acquisition_radius_nm() -> float:
	return seeker_range_nm if seeker_range_nm > 0.0 else 0.5
