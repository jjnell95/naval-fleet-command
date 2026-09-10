class_name SensorContact
extends RefCounted
## One observation handed from SensorManager to TrackManager. Bundling it keeps the track API
## readable now that a contact can be a firm radar plot, a firm active-sonar plot, or a bearing
## with almost no idea of range.

var target: Unit
## Which of our units reported this. Null means it came in over the network from something that
## is not a unit, such as a sonobuoy, which is always relayed.
var observer: Unit
var position := Vector2.ZERO  # best estimate of where the contact is
var error_major_nm := 0.5  # uncertainty along `error_axis_deg`
var error_minor_nm := 0.5  # uncertainty across it
var error_axis_deg := 0.0
var bearing_only := false
var quality := 0.0  # 0..1, drives classification speed
var classify_rate := 1.0
var range_nm := 0.0
var tma_gain := 0.0  # how much this observation improves the range solution
var source := "radar"  # radar | sonar_passive | sonar_active


static func make(target_unit: Unit, pos: Vector2, error_nm: float, quality_value: float, rate: float, range_value: float, source_name := "radar", observer_unit: Unit = null) -> SensorContact:
	var c := SensorContact.new()
	c.target = target_unit
	c.position = pos
	c.error_major_nm = error_nm
	c.error_minor_nm = error_nm
	c.quality = quality_value
	c.classify_rate = rate
	c.range_nm = range_value
	c.source = source_name
	c.observer = observer_unit
	return c
