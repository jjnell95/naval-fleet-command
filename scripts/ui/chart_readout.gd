class_name ChartReadout
## Text for the chart's bottom-left readout: position in whole minutes, depth or height in feet,
## and the scale bar's length. Pure functions, so the formats are pinned by tests.

const FEET_PER_METRE := 3.28084
## The scale bar is a round number of nautical miles between these lengths on screen.
const SCALE_MIN_PX := 60.0
const SCALE_MAX_PX := 160.0
const SCALE_STEPS_NM: Array[float] = [0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 250.0, 500.0, 1000.0, 2000.0]


## "30-49 N / 015-46 E": degrees and zero-padded whole minutes, rounded to the nearest minute.
static func format_position(lat: float, lon: float) -> String:
	return "%s / %s" % [_dm(lat, 2, "N", "S"), _dm(lon, 3, "E", "W")]


static func _dm(value: float, width: int, positive: String, negative: String) -> String:
	var total := int(roundf(absf(value) * 60.0))
	@warning_ignore("integer_division")
	var degrees := total / 60
	var degree_text := str(degrees).lpad(width, "0")
	return "%s-%02d %s" % [degree_text, total % 60, positive if value >= 0.0 or total == 0 else negative]


## Position with no geographic anchor: nautical miles from the chart origin.
static func format_offset(w: Vector2) -> String:
	return "%s nm %s / %s nm %s" % [_nm(absf(w.y)), "N" if w.y >= 0.0 else "S", _nm(absf(w.x)), "E" if w.x >= 0.0 else "W"]


static func _nm(v: float) -> String:
	return "%.1f" % v


## "1,014 ft": metres to whole feet with a thousands separator.
static func format_feet(metres: float) -> String:
	var feet := int(roundf(maxf(metres, 0.0) * FEET_PER_METRE))
	var s := str(feet)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out + " ft"


## "Depth: 1,014 ft" over water, "Height: 337 ft" over land, "" when the chart does not know.
static func depth_line(over_land: bool, height_m: float, depth_m: float) -> String:
	if over_land:
		return "Height: %s" % format_feet(height_m) if height_m >= 0.0 else ""
	return "Depth: %s" % format_feet(depth_m) if depth_m >= 0.0 else ""


## The scale bar's length in nautical miles: the shortest round step at least SCALE_MIN_PX long,
## which keeps it under SCALE_MAX_PX at every zoom the chart allows.
static func scale_step_nm(ppn: float) -> float:
	for s in SCALE_STEPS_NM:
		if s * ppn >= SCALE_MIN_PX:
			return s
	return SCALE_STEPS_NM[-1]


## "10 nmi", "0.5 nmi", "0.02 nmi".
static func format_nmi(nm: float) -> String:
	var text := "%d" % int(roundf(nm)) if is_equal_approx(nm, roundf(nm)) else ("%.3f" % nm).rstrip("0")
	return "%s nmi" % text


## The quick range circle's label: "7.4 nmi" under ten miles, "23 nmi" beyond.
static func format_range_nmi(nm: float) -> String:
	return ("%.1f nmi" % nm) if nm < 9.95 else ("%d nmi" % int(roundf(nm)))
