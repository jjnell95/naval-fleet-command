class_name MapSymbols
## Original vector symbology in the spirit of the APP-6 / NTDS conventions used on real command
## displays, drawn with primitives. The frame carries identity and domain, a two-letter glyph
## inside carries the platform category, and a tick outside carries heading. Sizes are in screen
## pixels and independent of zoom, so a symbol never becomes a blob or a speck.
##
##   identity  surface      air (frame open below)   subsurface (frame open above)
##   friendly  circle       dome                      bowl
##   hostile   diamond      chevron up                chevron down
##   unknown   quatrefoil   two lobes up              two lobes down
##   neutral   square       bracket up                bracket down

enum Frame { FRIENDLY, HOSTILE, UNKNOWN, NEUTRAL }

const RADIUS := 9.0
const HEADING_TICK := 9.0
const GLYPH_SIZE := 8


static func frame_for_identity(identity: String) -> Frame:
	match identity:
		"HOSTILE":
			return Frame.HOSTILE
		"NEUTRAL":
			return Frame.NEUTRAL
		"FRIENDLY":
			return Frame.FRIENDLY
	return Frame.UNKNOWN


## Two-letter category glyph, in the spirit of an NTDS readout. Derived from the platform's
## declared category and domain, so new data files pick up a glyph without any code change.
static func category_glyph(category: String, domain: String) -> String:
	var c := category.to_lower()
	if domain == "air":
		if c.contains("early") or c.contains("aew"):
			return "E"
		if c.contains("electronic"):
			return "EA"
		if c.contains("patrol"):
			return "P"
		if c.contains("bomber"):
			return "B"
		if c.contains("helicopter") or c.contains("helo"):
			return "H"
		if c.contains("strike"):
			return "A"
		if c.contains("fighter"):
			return "F"
		return "AC"
	if domain == "subsurface":
		return "SN" if c.contains("nuclear") else "SS"
	if domain == "land":
		return "AB"
	if c.contains("carrier"):
		return "CV"
	if c.contains("cruiser"):
		return "CG"
	if c.contains("destroyer"):
		return "DD"
	if c.contains("frigate"):
		return "FF"
	if c.contains("corvette"):
		return "FS"
	if c.contains("replenish") or c.contains("auxiliar") or c.contains("support") or c.contains("logistic"):
		return "AO"
	if c.contains("merchant") or c.contains("bulk") or c.contains("tanker") or c.contains("civil"):
		return "M"
	return "SU"


## Draws a full symbol: soft glow, translucent fill, frame, heading tick and category glyph.
static func draw_symbol(ci: CanvasItem, pos: Vector2, color: Color, frame: Frame, domain: String,
		heading_deg: float, has_heading: bool, glyph: String, font: Font, scale := 1.0, dim := false) -> void:
	var r := RADIUS * scale
	var line_w := 2.0 if not dim else 1.5
	var fill := Color(color, 0.16 if not dim else 0.08)
	var glow := Color(color, 0.10 if not dim else 0.05)
	ci.draw_circle(pos, r + 4.0, glow)
	var pts := _frame_points(frame, domain, r)
	for i in pts.size():
		pts[i] += pos
	if pts.size() >= 3:
		ci.draw_colored_polygon(pts, fill)
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, color, line_w, true)
	if has_heading:
		var h := Vector2(sin(deg_to_rad(heading_deg)), -cos(deg_to_rad(heading_deg)))
		ci.draw_line(pos + h * (r + 1.0), pos + h * (r + HEADING_TICK), color, line_w, true)
	if glyph != "" and font != null:
		var gs := int(GLYPH_SIZE * scale)
		var w := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs).x
		var dy := 0.0
		if domain == "air":
			dy = -1.0
		elif domain == "subsurface":
			dy = 1.0
		ci.draw_string(font, pos + Vector2(-w * 0.5, gs * 0.38 + dy), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, color)


## Polygon outline for one frame/domain combination, centred on the origin.
static func _frame_points(frame: Frame, domain: String, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match frame:
		Frame.FRIENDLY:
			if domain == "air":
				pts = _arc(r, PI, TAU, 14)
				pts.append(Vector2(r, r * 0.55))
				pts.append(Vector2(-r, r * 0.55))
			elif domain == "subsurface":
				pts = _arc(r, 0.0, PI, 14)
				pts.append(Vector2(-r, -r * 0.55))
				pts.append(Vector2(r, -r * 0.55))
			else:
				pts = _arc(r, 0.0, TAU, 28)
		Frame.HOSTILE:
			var d := r + 2.0
			if domain == "air":
				pts = PackedVector2Array([Vector2(-d, d * 0.7), Vector2(0, -d), Vector2(d, d * 0.7)])
			elif domain == "subsurface":
				pts = PackedVector2Array([Vector2(-d, -d * 0.7), Vector2(0, d), Vector2(d, -d * 0.7)])
			else:
				pts = PackedVector2Array([Vector2(0, -d), Vector2(d, 0), Vector2(0, d), Vector2(-d, 0)])
		Frame.UNKNOWN:
			var lobe := r * 0.55
			if domain == "air":
				pts = _arc_at(Vector2(-lobe, -lobe * 0.4), lobe, PI, TAU * 0.75, 8)
				pts.append_array(_arc_at(Vector2(lobe, -lobe * 0.4), lobe, TAU * 0.75, TAU, 8))
				pts.append(Vector2(r, r * 0.5))
				pts.append(Vector2(-r, r * 0.5))
			elif domain == "subsurface":
				pts = _arc_at(Vector2(lobe, lobe * 0.4), lobe, 0.0, PI * 0.5, 8)
				pts.append_array(_arc_at(Vector2(-lobe, lobe * 0.4), lobe, PI * 0.5, PI, 8))
				pts.append(Vector2(-r, -r * 0.5))
				pts.append(Vector2(r, -r * 0.5))
			else:
				pts = _arc_at(Vector2(0, -lobe), lobe, PI * 1.25, PI * 1.75, 8)
				pts.append_array(_arc_at(Vector2(lobe, 0), lobe, PI * 1.75, PI * 2.25, 8))
				pts.append_array(_arc_at(Vector2(0, lobe), lobe, PI * 0.25, PI * 0.75, 8))
				pts.append_array(_arc_at(Vector2(-lobe, 0), lobe, PI * 0.75, PI * 1.25, 8))
		Frame.NEUTRAL:
			if domain == "air":
				pts = PackedVector2Array([Vector2(-r, r * 0.6), Vector2(-r, -r), Vector2(r, -r), Vector2(r, r * 0.6)])
			elif domain == "subsurface":
				pts = PackedVector2Array([Vector2(r, -r * 0.6), Vector2(r, r), Vector2(-r, r), Vector2(-r, -r * 0.6)])
			else:
				pts = PackedVector2Array([Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)])
	return pts


static func _arc(r: float, from: float, to: float, steps: int) -> PackedVector2Array:
	return _arc_at(Vector2.ZERO, r, from, to, steps)


static func _arc_at(c: Vector2, r: float, from: float, to: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(from, to, float(i) / float(steps))
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## Selection hook: four corner brackets that slowly breathe, the way a console shows a hooked
## track without hiding the symbol underneath.
static func draw_selection(ci: CanvasItem, pos: Vector2, color: Color, t := 0.0) -> void:
	var r := RADIUS + 8.0 + sin(t * 3.0) * 1.0
	var arm := 6.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := pos + Vector2(sx * r, sy * r)
			ci.draw_line(c, c + Vector2(-sx * arm, 0), color, 1.5, true)
			ci.draw_line(c, c + Vector2(0, -sy * arm), color, 1.5, true)


## A hostile weapon closing on somebody: a small ring that pulses.
static func draw_threat_ring(ci: CanvasItem, pos: Vector2, color: Color, t: float) -> void:
	var r := 11.0 + fmod(t * 14.0, 8.0)
	ci.draw_arc(pos, r, 0.0, TAU, 24, Color(color, 0.7 - (r - 11.0) / 8.0 * 0.6), 1.5, true)


## A small missile or torpedo in flight: an arrow with a short exhaust trail.
static func draw_round(ci: CanvasItem, pos: Vector2, heading_deg: float, color: Color, trail_px: float, torpedo: bool) -> void:
	var dir := Vector2(sin(deg_to_rad(heading_deg)), -cos(deg_to_rad(heading_deg)))
	var side := dir.orthogonal() * 2.5
	if trail_px > 0.0:
		ci.draw_line(pos - dir * 4.0, pos - dir * (4.0 + trail_px), Color(color, 0.0), 1.0)
		var steps := 5
		for i in steps:
			var a := pos - dir * (4.0 + trail_px * float(i) / steps)
			var b := pos - dir * (4.0 + trail_px * float(i + 1) / steps)
			ci.draw_line(a, b, Color(color, 0.55 * (1.0 - float(i) / steps)), 1.5)
	if torpedo:
		ci.draw_line(pos - dir * 5.0, pos + dir * 5.0, color, 2.0)
		ci.draw_circle(pos + dir * 5.0, 2.0, color)
	else:
		ci.draw_polyline(PackedVector2Array([pos + dir * 6.0, pos - dir * 3.0 + side, pos - dir * 1.0, pos - dir * 3.0 - side, pos + dir * 6.0]), color, 1.5, true)


## Legend helper: one symbol with a caption beside it.
static func draw_key_entry(ci: CanvasItem, pos: Vector2, color: Color, frame: Frame, domain: String, glyph: String, caption: String, font: Font, text_color: Color) -> void:
	draw_symbol(ci, pos, color, frame, domain, 30.0, true, glyph, font, 0.85)
	ci.draw_string(font, pos + Vector2(18.0, 4.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_color)
