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
# Raw bearing evidence; no hidden target range enters the estimator. Empty key means a
# legacy approximate contact with no usable bearing geometry.
var bearing_origin := Vector2.ZERO
var bearing_accuracy_deg := 1.0
var bearing_key := ""
var bearing_range_limit_nm := 100.0
var bearing_speed_limit_kn := 70.0
var solution_quality := 0.0
var tma_gain := 0.0  # legacy save/fixture compatibility; never accumulated
var visual_identification := false
var altitude_m := -1.0
var source := "radar"  # radar | sonar_passive | sonar_active | sonar_cz | esm | sonobuoy
## The set that made this observation: its catalogue id and display name. Empty when it came from
## something that is not a fitted sensor; a sonobuoy report names the buoys instead.
var sensor_id := ""
var sensor_name := ""


static func make(target_unit: Unit, pos: Vector2, error_nm: float, quality_value: float, rate: float, range_value: float, source_name := "radar", observer_unit: Unit = null, sensor: SensorSpec = null) -> SensorContact:
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
	c.set_sensor(sensor)
	if source_name == "radar" and target_unit.in_flight():
		c.altitude_m = target_unit.altitude_m
	return c


func set_sensor(sensor: SensorSpec) -> void:
	if sensor == null:
		return
	sensor_id = sensor.id
	sensor_name = sensor.display_name
