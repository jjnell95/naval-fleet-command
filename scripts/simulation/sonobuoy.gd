class_name Sonobuoy
extends RefCounted
## A passive listener dropped in the water and left behind. One buoy tells you something is
## inside its circle; two or more overlapping tell you roughly where.

var id := -1
var faction := ""
var position := Vector2.ZERO
var sensitivity_nm := 12.0
var expires_at := 0.0


func alive_at(now: float) -> bool:
	return now < expires_at


## Range at which this buoy hears a given unit, from the same acoustics as everything else.
func reach_against(target: Unit) -> float:
	var noise := Detection.acoustic_noise(target)
	return sensitivity_nm * sqrt(maxf(noise, 0.0))
