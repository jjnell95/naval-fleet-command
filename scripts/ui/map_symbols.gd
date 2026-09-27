class_name MapSymbols
## NTDS symbology the way the classic naval command display drew it: an open frame in the identity
## colour whose shape carries identity and domain, with nothing inside it but the neutral's cross.
## No fill, no glow, no glyph. Strokes are 2 px and the symbol box is 16 px at 1x, independent of
## zoom, so a symbol never becomes a blob or a speck.
##
##   identity          air (open below)     surface     subsurface (open above)
##   friendly, allied  upper semicircle     circle      lower semicircle
##   hostile           chevron ^            diamond     chevron v
##   unknown           upper half-square    square      lower half-square
##   neutral           the friendly shapes with a small + in the middle
##
## A land installation is an X in the identity colour; a helicopter is its air frame with a short
## bar over it. Weapons in flight are small filled arrowheads (torpedoes a filled dot), sonobuoys a
## 3 px dot. Graphic symbols (the platform's plan view tinted toward the identity colour) are the
## alternative the chart's symbol mode cycles to.

enum Frame { FRIENDLY, HOSTILE, UNKNOWN, NEUTRAL, ALLIED }

## Half the 16 px symbol box: where a frame's edge lies, for leaders and hit radii.
const RADIUS := 8.0
const STROKE := 2.0
## The fixed heading tick the scenario editor and preview draw; the chart draws velocity leaders.
const HEADING_TICK := 9.0
## Velocity leader: the distance covered in this much game time, clamped to this many pixels.
const LEADER_MINUTES := 6.0
const LEADER_MIN_PX := 6.0
const LEADER_MAX_PX := 48.0
const LEADER_MIN_KN := 0.5
## Hook: four corner brackets round a 24 px box.
const BRACKET_BOX := 24.0
const BRACKET_ARM := 7.0
## Graphic symbols: the plan view is greyed and brightened this much once (a draw modulate cannot
## go past white), then tinted this far toward the identity colour, so a dark hull still reads
## over deep water in its allegiance.
const GRAPHIC_LIFT := 2.4
const GRAPHIC_TINT := 0.85

static var _class_platforms: Dictionary = {}
static var _graphics: Dictionary = {}  # "platform@px" -> Texture2D or null


static func frame_for_identity(identity: String) -> Frame:
	match identity:
		"HOSTILE":
			return Frame.HOSTILE
		"NEUTRAL":
			return Frame.NEUTRAL
		"FRIENDLY":
			return Frame.FRIENDLY
		"ALLIED":
			return Frame.ALLIED
	return Frame.UNKNOWN


## Rotorcraft carry a bar over their air frame. Read from the declared (or, for a contact, the
## reported) category, so a new data file needs no code change.
static func is_rotary(category: String) -> bool:
	var c := category.to_lower()
	return c.contains("helicopter") or c.contains("helo") or c.contains("rotary")


## Two-letter category abbreviation. The chart no longer prints it inside the frame; the scenario
## editor's palette list still uses it, and "H" tells draw_symbol a helicopter is meant.
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
		if c.contains("ballistic"):
			return "BM"
		if c.contains("surface-to-air") or c.contains("sam"):
			return "SA"
		if c.contains("drone"):
			return "DR"
		if c.contains("battery") or c.contains("missile"):
			return "CB"
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


## A contact's four-digit track number from its track id: "T1001" reads "1001". Only the trailing
## digits count, and only the last four of them.
static func track_number(track_id: String) -> String:
	var digits := ""
	for i in range(track_id.length() - 1, -1, -1):
		var ch := track_id[i]
		if ch < "0" or ch > "9":
			break
		digits = ch + digits
	if digits == "":
		return ""
	return "%04d" % int(digits.right(4))


## An own platform's track number, zero-padded to four digits.
static func own_track_number(n: int) -> String:
	return "%04d" % posmod(n, 10000) if n > 0 else ""


## Velocity leader length in pixels: the distance covered in LEADER_MINUTES at this speed and
## scale, clamped so a slow hull still shows its course and a jet does not cross the chart. Zero
## for something effectively stopped.
static func leader_px(speed_kn: float, px_per_nm: float) -> float:
	if speed_kn < LEADER_MIN_KN:
		return 0.0
	return clampf(speed_kn * LEADER_MINUTES / 60.0 * px_per_nm, LEADER_MIN_PX, LEADER_MAX_PX)


## The platform whose plan view stands for a contact of this reported class. Keyed on what the
## plot holds (short class name and category), never on the contact's hidden truth.
static func platform_for_class(known_class: String, known_category: String) -> String:
	if known_class == "":
		return ""
	if _class_platforms.is_empty():
		for spec: PlatformSpec in DataDB.all_platforms():
			if PlatformArt.plan(spec.id) == null:
				continue
			var key := "%s|%s" % [spec.short_name, spec.category]
			if not _class_platforms.has(key):
				_class_platforms[key] = spec.id
			if not _class_platforms.has(spec.short_name):
				_class_platforms[spec.short_name] = spec.id
	return _class_platforms.get("%s|%s" % [known_class, known_category], _class_platforms.get(known_class, ""))


## The NTDS symbol: frame only, in the identity colour. `rotary` adds the helicopter bar to an air
## frame. `domain` "land" draws the installation X whatever the frame.
static func draw_ntds(ci: CanvasItem, pos: Vector2, color: Color, frame: Frame, domain: String, rotary := false, scale := 1.0) -> void:
	var w := maxf(STROKE * minf(scale, 1.0), 1.5)
	if domain == "land":
		var x := 6.0 * scale
		ci.draw_line(pos + Vector2(-x, -x), pos + Vector2(x, x), color, w, true)
		ci.draw_line(pos + Vector2(-x, x), pos + Vector2(x, -x), color, w, true)
		return
	var stroke := frame_stroke(frame, domain, scale)
	for i in stroke.size():
		stroke[i] += pos
	ci.draw_polyline(stroke, color, w, true)
	if frame == Frame.NEUTRAL:
		# The cross sits in the frame's hollow: the circle's middle, or low under an air arc and
		# high over a subsurface one, a little smaller there.
		var round_frame := domain != "air" and domain != "subsurface"
		var arm := (2.5 if round_frame else 2.0) * scale
		var c := pos + Vector2(0.0, 0.0 if round_frame else (1.0 if domain == "air" else -1.0) * scale)
		var cw := w if round_frame else 1.5
		ci.draw_line(c + Vector2(-arm, 0.0), c + Vector2(arm, 0.0), color, cw, true)
		ci.draw_line(c + Vector2(0.0, -arm), c + Vector2(0.0, arm), color, cw, true)
	if rotary and domain == "air":
		var y := pos.y + (air_top(frame) - 3.0) * scale
		ci.draw_line(Vector2(pos.x - 5.0 * scale, y), Vector2(pos.x + 5.0 * scale, y), color, w, true)


## The frame's stroke, centred on the origin: an open polyline (a closed shape repeats its first
## point). Air and subsurface frames are shifted so their visual centre sits on the position.
static func frame_stroke(frame: Frame, domain: String, scale := 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match frame:
		Frame.HOSTILE:
			if domain == "air":
				pts = PackedVector2Array([Vector2(-7.5, 4.5), Vector2(0.0, -6.0), Vector2(7.5, 4.5)])
			elif domain == "subsurface":
				pts = PackedVector2Array([Vector2(-7.5, -4.5), Vector2(0.0, 6.0), Vector2(7.5, -4.5)])
			else:
				pts = PackedVector2Array([Vector2(0.0, -8.5), Vector2(8.5, 0.0), Vector2(0.0, 8.5), Vector2(-8.5, 0.0), Vector2(0.0, -8.5)])
		Frame.UNKNOWN:
			if domain == "air":
				pts = PackedVector2Array([Vector2(-6.5, 3.5), Vector2(-6.5, -4.0), Vector2(6.5, -4.0), Vector2(6.5, 3.5)])
			elif domain == "subsurface":
				pts = PackedVector2Array([Vector2(-6.5, -3.5), Vector2(-6.5, 4.0), Vector2(6.5, 4.0), Vector2(6.5, -3.5)])
			else:
				pts = PackedVector2Array([Vector2(-6.5, -6.5), Vector2(6.5, -6.5), Vector2(6.5, 6.5), Vector2(-6.5, 6.5), Vector2(-6.5, -6.5)])
		_:
			# Friendly, allied and neutral share the round frames.
			if domain == "air":
				pts = _arc_at(Vector2(0.0, 3.5), 7.0, PI, TAU, 16)
			elif domain == "subsurface":
				pts = _arc_at(Vector2(0.0, -3.5), 7.0, 0.0, PI, 16)
			else:
				pts = _arc_at(Vector2.ZERO, 7.0, 0.0, TAU, 32)
				pts[pts.size() - 1] = pts[0]
	if scale != 1.0:
		for i in pts.size():
			pts[i] *= scale
	return pts


## The top of an air frame, for the helicopter bar.
static func air_top(frame: Frame) -> float:
	match frame:
		Frame.HOSTILE:
			return -6.0
		Frame.UNKNOWN:
			return -4.0
	return -3.5


static func _arc_at(c: Vector2, r: float, from: float, to: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(from, to, float(i) / float(steps))
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## Compatibility entry point for the scenario editor and the mission preview: the NTDS frame plus,
## with `has_heading`, a short fixed heading tick (they have no speed to lead with). `glyph` is only
## read to recognise a helicopter ("H"); the font is unused. `dim` fades the symbol.
static func draw_symbol(ci: CanvasItem, pos: Vector2, color: Color, frame: Frame, domain: String,
		heading_deg: float, has_heading: bool, glyph: String, _font: Font, scale := 1.0, dim := false) -> void:
	var col := Color(color, color.a * (0.55 if dim else 1.0))
	draw_ntds(ci, pos, col, frame, domain, glyph == "H", scale)
	if has_heading:
		var h := Vector2(sin(deg_to_rad(heading_deg)), -cos(deg_to_rad(heading_deg)))
		ci.draw_line(pos + h * RADIUS * scale, pos + h * (RADIUS + HEADING_TICK) * scale, col, 1.0, true)


## The velocity leader: a 1 px line from the symbol's edge along the course.
static func draw_leader(ci: CanvasItem, pos: Vector2, course_deg: float, length_px: float, color: Color, edge_px := RADIUS) -> void:
	if length_px <= 0.0:
		return
	var h := Vector2(sin(deg_to_rad(course_deg)), -cos(deg_to_rad(course_deg)))
	ci.draw_line(pos + h * edge_px, pos + h * (edge_px + length_px), color, 1.0, true)


## A graphic symbol: the platform's plan view (bow toward +x in the art) turned to the course and
## `length_px` from bow to stern, tinted toward the identity colour. False when the platform has
## no art, so the caller can fall back to its NTDS frame.
static func draw_graphic(ci: CanvasItem, pos: Vector2, platform_id: String, course_deg: float, length_px: float, color: Color) -> bool:
	var tex := graphic_texture(platform_id, length_px)
	if tex == null:
		return false
	var tex_size := Vector2(tex.get_size())
	var s := length_px * PlatformArt.PLAN_MARGIN / maxf(tex_size.x, 1.0)
	var tint := Color.WHITE.lerp(Color(color, 1.0), GRAPHIC_TINT)
	tint.a = color.a
	ci.draw_set_transform(pos, deg_to_rad(course_deg) - PI * 0.5, Vector2(s, s))
	ci.draw_texture_rect(tex, Rect2(-tex_size * 0.5, tex_size), false, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## The plan view prepared for one symbol size, once: resampled to twice the drawn size (the
## chart samples its mipmaps), greyed and lifted. Null for a platform with no plan art.
static func graphic_texture(platform_id: String, length_px: float) -> Texture2D:
	var key := "%s@%d" % [platform_id, int(length_px)]
	if _graphics.has(key):
		return _graphics[key]
	var tex: Texture2D = null
	var plan := PlatformArt.plan(platform_id) if platform_id != "" else null
	var img := plan.get_image() if plan != null else null
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		var w := maxi(int(roundf(length_px * PlatformArt.PLAN_MARGIN * 2.0)), 8)
		var h := maxi(int(roundf(float(img.get_height()) * float(w) / float(img.get_width()))), 2)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		img.adjust_bcs(GRAPHIC_LIFT, 1.1, 0.0)
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	_graphics[key] = tex
	return tex


## Hook: four static corner brackets round a `box` px square, 2 px strokes, BRACKET_ARM arms.
static func draw_brackets(ci: CanvasItem, pos: Vector2, color: Color, box := BRACKET_BOX) -> void:
	var h := roundf(box * 0.5)
	var c := pos.round()
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := c + Vector2(sx * h, sy * h)
			ci.draw_polyline(PackedVector2Array([corner + Vector2(-sx * BRACKET_ARM, 0.0), corner, corner + Vector2(0.0, -sy * BRACKET_ARM)]), color, STROKE)


## Compatibility name for the hook brackets (the scenario editor's selection). Static: the
## animation time is ignored.
static func draw_selection(ci: CanvasItem, pos: Vector2, color: Color, _t := 0.0) -> void:
	draw_brackets(ci, pos, color)


## A hostile weapon closing on somebody: a thin ring that pulses outward.
static func draw_threat_ring(ci: CanvasItem, pos: Vector2, color: Color, t: float) -> void:
	var r := 12.0 + fmod(t * 14.0, 8.0)
	ci.draw_arc(pos, r, 0.0, TAU, 32, Color(color, 0.7 - (r - 12.0) / 8.0 * 0.6), 1.0, true)


## A weapon in flight: a small filled arrowhead along its course, or a filled dot for a torpedo.
static func draw_weapon(ci: CanvasItem, pos: Vector2, heading_deg: float, color: Color, torpedo: bool) -> void:
	if torpedo:
		ci.draw_circle(pos, 2.5, color, true, -1.0, true)
		return
	var f := Vector2(sin(deg_to_rad(heading_deg)), -cos(deg_to_rad(heading_deg)))
	var s := f.orthogonal()
	var head := PackedVector2Array([pos + f * 6.0, pos - f * 4.0 + s * 3.5, pos - f * 2.0, pos - f * 4.0 - s * 3.5])
	ci.draw_colored_polygon(head, color)
	head.append(head[0])
	ci.draw_polyline(head, color, 1.0, true)


## A sonobuoy: a 3 px dot.
static func draw_buoy(ci: CanvasItem, pos: Vector2, color: Color) -> void:
	ci.draw_circle(pos, 1.5, color, true, -1.0, true)


## Legend helper: one symbol with a caption beside it.
static func draw_key_entry(ci: CanvasItem, pos: Vector2, color: Color, frame: Frame, domain: String, rotary: bool, caption: String, font: Font, text_color: Color) -> void:
	draw_ntds(ci, pos, color, frame, domain, rotary)
	ci.draw_string(font, pos + Vector2(14.0, 4.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_color)
