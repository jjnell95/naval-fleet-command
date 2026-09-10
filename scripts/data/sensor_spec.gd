class_name SensorSpec
extends Resource
## Data-driven sensor. Ranges are gameplay abstractions (GAMEPLAY_ESTIMATE), not real performance.
## Radar detection of surface targets is additionally limited by the radar horizon (see Detection).

@export var id := ""
@export var display_name := ""
@export var kind := "radar"  # radar | sonar | esm
@export var emits := true
@export var range_surface_nm := 30.0  # vs baseline large surface combatant, before horizon
@export var range_air_nm := 100.0  # reserved for aviation milestone
@export var antenna_height_m := 20.0
@export var classify_rate := 1.0  # multiplier on classification progress

## Sonar. One SensorSpec covers a whole suite: the passive array and the active transmitter are
## the same physical system, and a unit chooses which to use. Both numbers are GAMEPLAY_ESTIMATE.
@export var passive_sensitivity_nm := 0.0  # scales with the square root of target noise
@export var active_range_nm := 0.0  # firm range and bearing, but announces the sender
@export var bearing_accuracy_deg := 1.5  # passive bearing error, one sigma
@export var self_noise_tolerance := 0.5  # how well the array works while the ship is moving fast
## A dipping set only works with the aircraft stopped and low. That is the whole helicopter ASW
## cycle: fly, stop, listen, move on.
@export var requires_hover := false

## Electronic support. An ESM set hears a radar transmit. It only needs the signal one way, where
## the radar needs it out and back, so it hears further than the radar reaches, and it does not
## care how small the emitter is. What it gives back is a bearing, not a position.
@export var esm_gain := 2.0  # multiplier on the emitter's radar power

## Electronic attack. A `kind = "jammer"` set radiates noise into hostile radars. Any enemy radar
## within `jam_range_nm` of the jammer loses part of its reach against targets that lie in the
## jammer's direction, which is how a stand-off jammer screens a strike package. Jamming is itself
## an emission and is heard by ESM further out than the radar it is protecting against.
## Both values are GAMEPLAY_ESTIMATE abstractions, not a claim about any real system.
@export var jam_range_nm := 0.0
@export var jam_strength := 0.0  # 1.0 halves an affected radar's reach; 3.0 quarters it
@export var source_status := ""
