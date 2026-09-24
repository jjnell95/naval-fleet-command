class_name Sonobuoy
extends RefCounted
## A passive listener dropped in the water and left behind. One buoy tells you something is
## inside its circle; two or more overlapping tell you roughly where.

var id := -1
var faction := ""
var position := Vector2.ZERO
var sensitivity_nm := 12.0
var expires_at := 0.0
## Where the hydrophone hangs, chosen at the drop from the water under it. See Acoustics.
var bottom_m := -1.0
var hydrophone_depth_m := 27.0


func alive_at(now: float) -> bool:
	return now < expires_at


## Range at which this buoy hears a given unit, from the same acoustics as everything else.
func reach_against(target: Unit) -> float:
	var noise := Detection.acoustic_noise(target)
	return sensitivity_nm * sqrt(maxf(noise, 0.0)) * Acoustics.buoy_path_factor(hydrophone_depth_m, bottom_m, target)


## Chooses the hydrophone setting for the water the buoy has landed in.
func settle(at: Vector2) -> void:
	position = at
	bottom_m = Bathymetry.depth_at(at)
	hydrophone_depth_m = Acoustics.buoy_depth_m(bottom_m)
