class_name UITheme
## Builds the command-screen skin in code so no hand-edited .tres theme is needed.
##
## The look is the late-1990s naval command screen, drawn at modern quality. There are two
## surface families, and a control's text colours follow the surface it sits on:
##   grey chrome   — in-mission dialogs, pop-up menus, buttons, fields and the front-end panels.
##                   Navy bold text; bevelled light-grey buttons; LED lamps for on/off state.
##                   build() is this family, so any control placed on the screen gets it.
##   navy data     — the data display and the status boards. White-grey labels, yellow values,
##                   blue titles, red alerts. data_theme() is this family; a panel that holds data
##                   sets it as its own theme and every control inside follows.
## The COL_* / HEX_* tokens are colours on the navy data surface, as they always were. The JFC_*,
## INK_* and front-end tokens are the grey chrome's. Identity colours (own, allied, hostile,
## unknown, neutral) belong to TacticalMap and mean identity only; nothing here reuses them for
## anything else.

# --- Grey chrome: in-mission dialogs, pop-up menus, buttons and fields --------------------
const JFC_GREY := Color("c8c8cc")
const JFC_GREY_BORDER := Color("6b6b78")
const JFC_GREY_HI := Color("ececf2")
const JFC_FACE := Color("c4c4cc")
const JFC_FACE_HOVER := Color("d4d4dc")
const JFC_FACE_DOWN := Color("b2b2bc")
const JFC_BEVEL_HI := Color("f4f4f8")
const JFC_BEVEL_LO := Color("6b678c")
const JFC_FIELD := Color("dadae0")
const JFC_NAVY := Color("141450")
const JFC_SELECT := Color("1010c0")
const JFC_DISABLED := Color("8a8a96")
const LED_ON := Color("e02020")
const LED_OFF := Color("9a9aa4")

# --- Ink: text and marks on the grey chrome ------------------------------------------------
const INK := Color("141450")
const INK_DIM := Color("34346a")
const INK_FAINT := Color("5c5c80")
const INK_BLUE := Color("1010c0")
const INK_RED := Color("a80c0c")
const INK_GREEN := Color("0b661a")
const INK_AMBER := Color("7a4800")
const HEX_INK := "#141450"
const HEX_INK_DIM := "#34346a"
const HEX_INK_FAINT := "#5c5c80"
const HEX_INK_BLUE := "#1010c0"
const HEX_INK_RED := "#a80c0c"
const HEX_INK_GREEN := "#0b661a"
const HEX_INK_AMBER := "#7a4800"

# --- Front end: the operations desk, briefing, editor and reference over the backdrop -------
const METAL := Color(150.0 / 255.0, 152.0 / 255.0, 160.0 / 255.0, 0.78)
const METAL_EDGE := Color(1.0, 1.0, 1.0, 0.55)
const MENU_INK := Color("10106a")
const CAPTION := Color("ffd21e")
const LIST_FIELD := Color("c8c8d0")
const STAR := Color("22b822")
const TITLE_FILL := Color("dcdee6")
const TITLE_EDGE := Color("1a1c26")
const BACKDROP_PATH := "res://assets/ui/frontend_backdrop.jpg"

# --- The data display and the command screen's own text ------------------------------------
const DATA_PANEL := Color("0f1837")
const DATA_TITLE := Color("3a7fff")
const DATA_LABEL := Color("e6e6e6")
const DATA_VALUE := Color("ffff55")
const DATA_ALERT := Color("ff4040")
const DATA_BARS := Color("30e030")
const CDS_CAMERA := Color("e02020")
const HEX_DATA_TITLE := "#3a7fff"
const HEX_DATA_LABEL := "#e6e6e6"
const HEX_DATA_VALUE := "#ffff55"
const HEX_DATA_ALERT := "#ff4040"

# --- Small charts on the front end (mission previews, the editor): the chart's own palette ---
const CHART_SEA := Color8(0, 0, 108)
const CHART_SHALLOW := Color8(30, 32, 150)
const CHART_LAND := Color8(10, 106, 4)
const CHART_COAST := Color8(0, 58, 6)

# --- The three-line 1999 frame between the command screen's panes --------------------------
const BEVEL_OUTER := Color("edf3f1")
const BEVEL_MID := Color("c9ccdb")
const BEVEL_INNER := Color("6b678c")
const BEVEL_WIDTH := 3

# --- Navy data surfaces, darkest to lightest (the status boards and data wells) -------------
const COL_BG := Color("080e26")
const COL_PANEL_DEEP := Color("0b1330")
const COL_PANEL := Color("0f1837")
const COL_RAISED := Color("16204a")
const COL_HOVER := Color("1c2a5e")
const COL_SELECTED := Color("1010c0")
const COL_HAIRLINE := Color("2a3668")
const COL_BORDER := Color("3a4678")
const COL_BORDER_LIGHT := Color("56629a")

# --- Text on the navy data surface ---------------------------------------------------------
const COL_TEXT := Color("e6e6e6")
const COL_DIM := Color("b4bad2")
const COL_MUTED := Color("8890b4")
const COL_FAINT := Color("5a6490")

# --- Meaning on the navy data surface ------------------------------------------------------
const COL_ACCENT := Color("3a7fff")
const COL_ACCENT_HOVER := Color("6c9fff")
const COL_ON_ACCENT := Color("ffffff")
const COL_BRASS := Color("ffd21e")
const COL_AMBER := Color("ffc83c")
const COL_RED := Color("ff4040")
const COL_GREEN := Color("30e030")
const COL_BLUE := Color("40c8ff")

const HEX_TEXT := "#e6e6e6"
const HEX_DIM := "#b4bad2"
const HEX_MUTED := "#8890b4"
const HEX_ACCENT := "#3a7fff"
const HEX_BRASS := "#ffd21e"
const HEX_AMBER := "#ffc83c"
const HEX_RED := "#ff4040"
const HEX_GREEN := "#30e030"
const HEX_BLUE := "#40c8ff"

# --- Type scale (px at the 1600 × 900 reference canvas) ------------------------------------
const SIZE_EYEBROW := 11
const SIZE_SMALL := 12
const SIZE_BODY := 13
const SIZE_LEAD := 15
const SIZE_TITLE := 24
const SIZE_DISPLAY := 44
const SIZE_DATA := 13
const SIZE_CAPTION := 20
const SIZE_MENU := 22

## Corner radii: the grey chrome's small rounding, and the dialogs' and front-end panels' larger one.
const RADIUS := 3
const RADIUS_SMALL := 2
const RADIUS_DIALOG := 10

## Rows of a pop-up menu, in pixels.
const MENU_ROW := 22

const FONT_DATA := "res://assets/fonts/DejaVuSans-Bold.ttf"
const FONT_UI := "res://assets/fonts/DejaVuSansCondensed-Bold.ttf"
const FONT_TITLE := "res://assets/fonts/BarlowSemiCondensed-BlackItalic.ttf"
const FONT_CAPTION := "res://assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf"


static var _data: Font = null
static var _ui: Font = null
static var _eyebrow: Font = null
static var _title: Font = null
static var _caption: Font = null
static var _data_theme: Theme = null
static var _backdrop: Texture2D = null
static var _icons: Dictionary = {}


# --- Fonts ---------------------------------------------------------------------------------

## The data face: a wide, bold humanist sans with even-width figures. The data display, the
## chart's readouts and track numbers, and anything read as a number.
static func data_font() -> Font:
	if _data == null:
		var font := FontVariation.new()
		font.base_font = load(FONT_DATA)
		_data = font
	return _data

## The interface face: the same design condensed, for dialogs, menus, lists and buttons.
static func ui_font() -> Font:
	if _ui == null:
		var font := FontVariation.new()
		font.base_font = load(FONT_UI)
		font.fallbacks = [data_font()]
		_ui = font
	return _ui

## The wordmark: a heavy italic sans. It has no arrows or check marks, so it falls back.
static func title_font() -> Font:
	if _title == null:
		var font := FontVariation.new()
		font.base_font = load(FONT_TITLE)
		font.fallbacks = [ui_font()]
		_title = font
	return _title

## Captions and the big front-end buttons: a heavy condensed italic.
static func caption_font() -> Font:
	if _caption == null:
		var font := FontVariation.new()
		font.base_font = load(FONT_CAPTION)
		font.fallbacks = [ui_font()]
		_caption = font
	return _caption

## Retired names, kept so every panel keeps compiling: each maps to the nearest face above.
static func heading_font() -> Font:
	return caption_font()

static func body_font() -> Font:
	return ui_font()

static func semibold_font() -> Font:
	return ui_font()

## Small tracked capitals for section labels.
static func eyebrow_font() -> Font:
	if _eyebrow == null:
		var font := FontVariation.new()
		font.base_font = load(FONT_UI)
		font.fallbacks = [data_font()]
		font.set_spacing(TextServer.SPACING_GLYPH, 1)
		_eyebrow = font
	return _eyebrow

static func mono_font() -> Font:
	return data_font()


# --- Helpers -------------------------------------------------------------------------------

## BBCode for a section heading inside a RichTextLabel. On the navy data surface it is quiet
## tracked capitals; on the grey chrome it is navy-blue bold capitals.
static func section_bb(text: String, on_grey := false) -> String:
	if on_grey:
		return "[b][color=%s]%s[/color][/b]" % [HEX_INK_BLUE, text.to_upper()]
	return "[font_size=%d][color=%s]%s[/color][/font_size]" % [SIZE_EYEBROW, HEX_MUTED, text.to_upper()]


## A section label node, the Label counterpart of section_bb(). Clipping is for labels that fill
## a column; inside a row a clipped label would shrink to nothing.
static func eyebrow(text: String, clip := false) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = "HeaderLabel"
	l.clip_text = clip
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## A yellow front-end caption: heavy italic with a black outline, as over a list or beside the
## ACCEPT and CANCEL buttons.
static func caption(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = "MenuCaption"
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## A caption beside the empty bevel button it names ("ACCEPT [   ]"). Clicking the caption
## presses the button; the button carries the name for keyboard and screen-reader users.
static func caption_pair(text: String, button: Button) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := caption(text)
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	label.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.button_index == MOUSE_BUTTON_LEFT and click.pressed and not button.disabled:
			button.pressed.emit())
	row.add_child(label)
	button.text = ""
	button.custom_minimum_size = Vector2(maxf(button.custom_minimum_size.x, 64.0), maxf(button.custom_minimum_size.y, 36.0))
	button.accessibility_name = text.capitalize()
	if button.tooltip_text == "":
		button.tooltip_text = text.capitalize()
	row.add_child(button)
	return row


## A one-pixel divider in the hairline colour of the navy data surface.
static func hairline(vertical := false) -> ColorRect:
	var r := ColorRect.new()
	r.color = COL_HAIRLINE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		r.custom_minimum_size.x = 1
		r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		r.custom_minimum_size.y = 1
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


## The front-end backdrop: the project's own dusk render of a task group at sea, darkened and
## softly blurred, covering the whole rect. Put it first in a full-screen PanelContainer.
static func backdrop() -> TextureRect:
	var r := TextureRect.new()
	r.name = "Backdrop"
	r.texture = backdrop_texture()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func backdrop_texture() -> Texture2D:
	if _backdrop == null and ResourceLoader.exists(BACKDROP_PATH):
		_backdrop = load(BACKDROP_PATH)
	return _backdrop


## Makes `control` a navy data surface: it and everything inside it take the data family's
## text, list and panel colours. Buttons, fields and menus stay grey chrome.
static func use_data_surface(control: Control) -> void:
	control.theme = data_theme()


## Draws the three-line 1999 frame round `rect` on `item`, for panes drawn in code.
static func draw_bevel_frame(item: CanvasItem, rect: Rect2) -> void:
	bevel_frame().draw(item.get_canvas_item(), rect)


static func bevel_frame(margin := float(BEVEL_WIDTH)) -> JfcStyle:
	var s := JfcStyle.new()
	s.kind = JfcStyle.Kind.FRAME
	s.rings = PackedColorArray([BEVEL_OUTER, BEVEL_MID, BEVEL_INNER])
	s.set_content_margin_all(margin)
	return s


## A bevelled face: raised by default, sunken when pressed or for a field.
static func bevel(face: Color, sunken := false, radius := float(RADIUS), outline := JFC_GREY_BORDER, edge := 1.0) -> JfcStyle:
	var s := JfcStyle.new()
	s.face = face
	s.light = JFC_BEVEL_HI
	s.dark = JFC_BEVEL_LO
	s.outline = outline
	s.sunken = sunken
	s.radius = radius
	s.edge = edge
	return s


## The grey in-mission dialog: light grey, a one-pixel border, rounded, a two-pixel highlight.
static func dialog_style(margin := 14.0) -> JfcStyle:
	var s := bevel(JFC_GREY, false, RADIUS_DIALOG, JFC_GREY_BORDER, 2.0)
	s.light = JFC_GREY_HI
	s.dark = Color(JFC_BEVEL_LO, 0.35)
	s.set_content_margin_all(margin)
	return s


## The front end's translucent grey-metal panel with a light edge.
static func metal_panel(margin := 22.0) -> StyleBoxFlat:
	var metal := _box(METAL, METAL_EDGE, 1, RADIUS_DIALOG)
	metal.set_content_margin_all(margin)
	metal.shadow_color = Color(0, 0, 0, 0.35)
	metal.shadow_size = 18
	metal.shadow_offset = Vector2(0, 6)
	return metal


## A lamp: red and glossy when on, grey when off. `left` sits it at the left of a labelled button.
static func led_style(on: bool, disabled := false, left := false) -> JfcStyle:
	var s := JfcStyle.new()
	s.kind = JfcStyle.Kind.LED
	s.lamp = LED_ON if on else LED_OFF
	if disabled:
		s.lamp = Color(s.lamp.lerp(JFC_GREY, 0.5), 0.8)
	s.lamp_left = left
	s.lamp_size = 16.0
	s.set_content_margin_all(3)
	if left:
		s.content_margin_left = 24
	return s


## A card with a coloured stripe down its left edge. Kept for older panels; on the navy data
## surface it is a raised well with a coloured left rule.
static func stripe_card(color: Color, margin := 16.0) -> StyleBoxFlat:
	var s := _box(COL_RAISED, color, 0, 0)
	s.border_width_left = 3
	s.set_content_margin_all(margin)
	s.content_margin_left = margin + 4
	return s


## A surface floating over the chart: the grey dialog's face and border as a plain StyleBoxFlat,
## for older callers that tint or resize it.
static func floating_panel(margin := 10.0) -> StyleBoxFlat:
	var s := _box(JFC_GREY, JFC_GREY_BORDER, 1, RADIUS_DIALOG)
	s.set_content_margin_all(margin)
	return s


static func _box(bg: Color, border := Color.TRANSPARENT, border_w := 0, radius := RADIUS) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


static func _pad(s: StyleBox, h: float, v: float) -> StyleBox:
	s.content_margin_left = h
	s.content_margin_right = h
	s.content_margin_top = v
	s.content_margin_bottom = v
	return s


static func _focus_ring(color := JFC_SELECT, radius := RADIUS) -> StyleBoxFlat:
	var f := _box(Color.TRANSPARENT, color, 1, radius + 1)
	f.draw_center = false
	f.set_expand_margin_all(2)
	return f


# --- Theme icons, drawn as SVG and rasterised at whatever scale the window needs ------------

static func _svg(key: String, width: int, height: int, body: String) -> Texture2D:
	if _icons.has(key):
		return _icons[key]
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 %d %d'>%s</svg>" % [width, height, width, height, body]
	var tex: Texture2D = DPITexture.create_from_string(svg, 1.0)
	_icons[key] = tex
	return tex


static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


## A sunken square check box; `checked` puts a bold X in it.
static func check_icon(checked: bool, disabled := false) -> Texture2D:
	var ink := JFC_DISABLED if disabled else Color.BLACK
	var body := "<rect x='0.5' y='0.5' width='15' height='15' rx='2' fill='%s' stroke='%s'/>" % [_hex(JFC_FIELD if not disabled else JFC_GREY), _hex(JFC_GREY_BORDER)]
	body += "<path d='M1.5 14.5V1.5h13' fill='none' stroke='%s'/><path d='M1.5 14.5h13V1.5' fill='none' stroke='%s'/>" % [_hex(JFC_BEVEL_LO), _hex(JFC_BEVEL_HI)]
	if checked:
		body += "<path d='M4.2 4.2l7.6 7.6M11.8 4.2l-7.6 7.6' stroke='%s' stroke-width='2.6' stroke-linecap='round'/>" % _hex(ink)
	return _svg("check|%s|%s" % [checked, disabled], 16, 16, body)


## A glossy LED lamp for a CheckButton: red with a white specular dot when on, grey when off.
static func led_icon(on: bool, disabled := false, size := 16) -> Texture2D:
	var base := LED_ON if on else LED_OFF
	if disabled:
		base = base.lerp(JFC_GREY, 0.5)
	var r := size * 0.5
	var body := "<defs><radialGradient id='g' cx='0.38' cy='0.34' r='0.72'><stop offset='0' stop-color='%s'/><stop offset='0.55' stop-color='%s'/><stop offset='1' stop-color='%s'/></radialGradient></defs>" % [_hex(base.lightened(0.45)), _hex(base), _hex(base.darkened(0.6))]
	body += "<circle cx='%.1f' cy='%.1f' r='%.1f' fill='%s'/>" % [r, r, r - 0.5, _hex(base.darkened(0.72))]
	body += "<circle cx='%.1f' cy='%.1f' r='%.1f' fill='url(#g)'/>" % [r, r, r - 1.6]
	body += "<ellipse cx='%.1f' cy='%.1f' rx='%.1f' ry='%.1f' fill='#ffffff' fill-opacity='0.9'/>" % [r * 0.72, r * 0.66, r * 0.24, r * 0.2]
	return _svg("led|%s|%s|%d" % [on, disabled, size], size, size, body)


## A small black triangle: `dir` is "down", "up", "left" or "right".
static func arrow_icon(dir: String, color := Color.BLACK, size := 10) -> Texture2D:
	var s := float(size)
	var pts := {"down": "1,2.5 %.1f,2.5 %.1f,%.1f" % [s - 1, s * 0.5, s - 2.5], "up": "1,%.1f %.1f,%.1f %.1f,2.5" % [s - 2.5, s - 1, s - 2.5, s * 0.5], "right": "2.5,1 %.1f,%.1f 2.5,%.1f" % [s - 2.5, s * 0.5, s - 1], "left": "%.1f,1 2.5,%.1f %.1f,%.1f" % [s - 2.5, s * 0.5, s - 2.5, s - 1]}
	return _svg("arrow|%s|%s|%d" % [dir, color.to_html(), size], size, size, "<polygon points='%s' fill='%s' fill-opacity='%.2f'/>" % [pts[dir], _hex(color), color.a])


## A square bevelled scroll button with a black triangle, as at each end of a 1999 scroll bar.
static func scroll_button_icon(dir: String, pressed := false) -> Texture2D:
	var lit := JFC_BEVEL_LO if pressed else JFC_BEVEL_HI
	var shade := JFC_BEVEL_HI if pressed else JFC_BEVEL_LO
	var body := "<rect x='0.5' y='0.5' width='15' height='15' fill='%s' stroke='%s'/>" % [_hex(JFC_FACE_DOWN if pressed else JFC_FACE), _hex(JFC_GREY_BORDER)]
	body += "<path d='M1.5 14.5V1.5h13' fill='none' stroke='%s'/><path d='M1.5 14.5h13V1.5' fill='none' stroke='%s'/>" % [_hex(lit), _hex(shade)]
	var tri := {"down": "4,6 12,6 8,11", "up": "4,10.5 12,10.5 8,5.5", "left": "10.5,4 10.5,12 5.5,8", "right": "5.5,4 5.5,12 10.5,8"}
	body += "<polygon points='%s' fill='#000000'/>" % tri[dir]
	return _svg("scroll|%s|%s" % [dir, pressed], 16, 16, body)


static func _blank_icon() -> Texture2D:
	return _svg("blank", 1, 1, "")


# --- The themes ----------------------------------------------------------------------------

## The root theme: the grey chrome family. Main assigns it to the whole tree.
static func build() -> Theme:
	return _build(false)


## The navy data family: the same controls, with light text, navy panels and navy list wells.
## Cached; every data panel shares one.
static func data_theme() -> Theme:
	if _data_theme == null:
		_data_theme = _build(true)
	return _data_theme


static func _build(on_navy: bool) -> Theme:
	var t := Theme.new()
	t.default_font_size = SIZE_BODY
	t.default_font = ui_font()
	# Text colours for this surface family.
	var text := COL_TEXT if on_navy else INK
	var dim := COL_DIM if on_navy else INK_DIM
	var muted := COL_MUTED if on_navy else INK_DIM
	var faint := COL_FAINT if on_navy else JFC_DISABLED
	_panels(t, on_navy)
	_buttons(t, on_navy)
	_labels(t, on_navy, text, dim, muted)
	_fields(t)
	_lists(t, on_navy, text, faint)
	_menus(t)
	_rich_text(t, text)
	_scrollbars(t)
	_tabs(t, on_navy)
	_toggles(t, text, faint)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_stylebox("background", "ProgressBar", bevel(COL_PANEL_DEEP if on_navy else JFC_FIELD, true, 0))
	t.set_stylebox("fill", "ProgressBar", _box(DATA_BARS if on_navy else JFC_SELECT, Color.TRANSPARENT, 0, 0))
	return t


static func _panels(t: Theme, on_navy: bool) -> void:
	# The base panel is the grey dialog on the chrome and the navy panel on a data surface.
	var data_panel := _box(DATA_PANEL, Color.TRANSPARENT, 0, 0)
	data_panel.set_content_margin_all(8)
	data_panel.content_margin_top = 6
	t.set_stylebox("panel", "PanelContainer", data_panel if on_navy else dialog_style(14))

	t.set_type_variation("DataPanel", "PanelContainer")
	t.set_stylebox("panel", "DataPanel", data_panel)
	t.set_type_variation("JfcDialog", "PanelContainer")
	t.set_stylebox("panel", "JfcDialog", dialog_style(14))
	t.set_type_variation("BevelFrame", "PanelContainer")
	t.set_stylebox("panel", "BevelFrame", bevel_frame())

	t.set_type_variation("MenuPanel", "PanelContainer")
	t.set_stylebox("panel", "MenuPanel", metal_panel())

	# A full-screen front-end surface: near-black behind the backdrop picture.
	var overlay := _box(Color("05070c"), Color.TRANSPARENT, 0, 0)
	overlay.set_content_margin_all(0)
	t.set_type_variation("OverlayPanel", "PanelContainer")
	t.set_stylebox("panel", "OverlayPanel", overlay)

	# A card: a sunken text box on the chrome, a raised well on a data surface.
	var card: StyleBox
	if on_navy:
		card = _box(COL_RAISED, COL_HAIRLINE, 1, RADIUS_SMALL)
	else:
		card = bevel(LIST_FIELD, true, RADIUS_SMALL, Color("30304a"))
	card.set_content_margin_all(12)
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", card)

	t.set_type_variation("ToolbarPanel", "PanelContainer")
	t.set_stylebox("panel", "ToolbarPanel", dialog_style(4))
	t.set_type_variation("FloatingPanel", "PanelContainer")
	t.set_stylebox("panel", "FloatingPanel", dialog_style(12))
	var rail := _box(COL_PANEL_DEEP, Color.TRANSPARENT, 0, 0)
	_pad(rail, 0, 0)
	t.set_type_variation("RailPanel", "PanelContainer")
	t.set_stylebox("panel", "RailPanel", rail)
	t.set_type_variation("SegmentedPanel", "PanelContainer")
	t.set_stylebox("panel", "SegmentedPanel", StyleBoxEmpty.new())

	for type in ["PopupPanel", "TooltipPanel"]:
		var p := bevel(JFC_GREY, false, 0, JFC_GREY_BORDER)
		p.set_content_margin_all(6 if type == "TooltipPanel" else 4)
		t.set_stylebox("panel", type, p)
	var window := dialog_style(0)
	window.content_margin_top = 26
	t.set_stylebox("embedded_border", "Window", window)
	t.set_stylebox("embedded_unfocused_border", "Window", window)
	t.set_color("title_color", "Window", INK)
	t.set_font("title_font", "Window", ui_font())
	t.set_stylebox("panel", "AcceptDialog", _box(JFC_GREY, Color.TRANSPARENT, 0, 0))


## Sets every state of a bevelled button on `type` with its padding.
static func _bevel_button(t: Theme, type: String, face: Color, h: float, v: float, radius := float(RADIUS), ink := INK) -> void:
	t.set_stylebox("normal", type, _pad(bevel(face, false, radius), h, v))
	t.set_stylebox("hover", type, _pad(bevel(face.lerp(Color.WHITE, 0.25), false, radius), h, v))
	t.set_stylebox("pressed", type, _pad(bevel(JFC_FACE_DOWN, true, radius), h, v))
	t.set_stylebox("hover_pressed", type, _pad(bevel(JFC_FACE_DOWN.lerp(Color.WHITE, 0.12), true, radius), h, v))
	var off := bevel(face.lerp(JFC_GREY, 0.5), false, radius, Color(JFC_GREY_BORDER, 0.6))
	off.light = Color(JFC_BEVEL_HI, 0.6)
	off.dark = Color(JFC_BEVEL_LO, 0.4)
	t.set_stylebox("disabled", type, _pad(off, h, v))
	t.set_stylebox("focus", type, _focus_ring(JFC_SELECT, int(radius)))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		t.set_color(key, type, ink)
	t.set_color("font_disabled_color", type, JFC_DISABLED)
	t.set_color("icon_disabled_color", type, JFC_DISABLED)


static func _buttons(t: Theme, on_navy: bool) -> void:
	_bevel_button(t, "Button", JFC_FACE, 12, 5)
	t.set_font("font", "Button", ui_font())
	t.set_font_size("font_size", "Button", SIZE_SMALL)
	t.set_constant("h_separation", "Button", 7)

	# Primary: the one action a screen asks for. The same bevel with a firm navy outline.
	t.set_type_variation("PrimaryButton", "Button")
	_bevel_button(t, "PrimaryButton", JFC_FACE_HOVER, 18, 7)
	for state in ["normal", "hover"]:
		var s: JfcStyle = t.get_stylebox(state, "PrimaryButton")
		s.outline = INK
	t.set_font_size("font_size", "PrimaryButton", SIZE_BODY)

	# Danger: an alert that wants attention, or an irreversible action.
	t.set_type_variation("DangerButton", "Button")
	_bevel_button(t, "DangerButton", JFC_FACE, 12, 5, RADIUS, INK_RED)

	# Quiet: utility buttons with no resting chrome; the bevel appears under the pointer.
	t.set_type_variation("QuietButton", "Button")
	_bevel_button(t, "QuietButton", JFC_FACE, 9, 5)
	var quiet := _pad(StyleBoxEmpty.new(), 9, 5)
	t.set_stylebox("normal", "QuietButton", quiet)
	t.set_stylebox("disabled", "QuietButton", quiet)
	var quiet_ink := COL_DIM if on_navy else INK
	for key in ["font_color", "icon_normal_color"]:
		t.set_color(key, "QuietButton", quiet_ink)

	# Segment and tab buttons: a row of bevel buttons, the chosen one pressed in.
	for type in ["SegmentButton", "TabButton"]:
		t.set_type_variation(type, "Button")
		_bevel_button(t, type, JFC_FACE, 10, 5)
		var down := _pad(bevel(JFC_FIELD, true, RADIUS), 10, 5)
		t.set_stylebox("pressed", type, down)
		t.set_stylebox("hover_pressed", type, down)
		t.set_color("font_pressed_color", type, JFC_SELECT)
		t.set_color("font_hover_pressed_color", type, JFC_SELECT)

	# The big front-end buttons: a grey bevel with a metal sheen, navy heavy italic. MenuButton is
	# a native class and cannot be a variation, so the variation is MenuBigButton and native
	# MenuButtons get the same look.
	var big := bevel(Color("b4b6c0"), false, 5, Color("20202c"), 2.0)
	big.face_top = Color("e2e4ea")
	var big_hover := bevel(Color("c2c4ce"), false, 5, Color("20202c"), 2.0)
	big_hover.face_top = Color("f0f2f6")
	var big_down := bevel(Color("6c6e7c"), true, 5, Color("20202c"), 2.0)
	big_down.face_top = Color("8a8c98")
	var big_off := bevel(Color("9ea0a8"), false, 5, Color(0.12, 0.12, 0.18, 0.6), 2.0)
	var faces := {"normal": big, "hover": big_hover, "pressed": big_down, "hover_pressed": big_down, "disabled": big_off}
	t.set_type_variation("MenuBigButton", "Button")
	for type in ["MenuBigButton", "MenuButton"]:
		for state: String in faces:
			t.set_stylebox(state, type, _pad(faces[state], 18, 6))
		t.set_stylebox("focus", type, _focus_ring(CAPTION, 5))
		t.set_font("font", type, caption_font())
		t.set_font_size("font_size", type, SIZE_MENU)
		for key in ["font_color", "font_hover_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_focus_color"]:
			t.set_color(key, type, MENU_INK)
		# The chosen one of a row (a shelf, a page) is pressed in, darker, its words in white.
		for key in ["font_pressed_color", "font_hover_pressed_color", "icon_pressed_color"]:
			t.set_color(key, type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color("5a5a70"))

	# LED toggles: a toggle button that is only a lamp, red when pressed.
	t.set_type_variation("LedToggle", "Button")
	t.set_stylebox("normal", "LedToggle", led_style(false))
	t.set_stylebox("hover", "LedToggle", led_style(false))
	t.set_stylebox("pressed", "LedToggle", led_style(true))
	t.set_stylebox("hover_pressed", "LedToggle", led_style(true))
	t.set_stylebox("disabled", "LedToggle", led_style(false, true))
	t.set_stylebox("focus", "LedToggle", _focus_ring(JFC_SELECT, 10))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(key, "LedToggle", COL_TEXT if on_navy else INK)


static func _labels(t: Theme, on_navy: bool, text: Color, dim: Color, muted: Color) -> void:
	t.set_color("font_color", "Label", text)
	t.set_font_size("font_size", "Label", SIZE_BODY)
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font("font", "HeaderLabel", eyebrow_font())
	t.set_font_size("font_size", "HeaderLabel", SIZE_EYEBROW)
	t.set_color("font_color", "HeaderLabel", muted)
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", dim)
	t.set_font_size("font_size", "DimLabel", SIZE_SMALL)
	# A title is heavy italic on the chrome and the data display's blue name line on navy.
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", data_font() if on_navy else caption_font())
	t.set_font_size("font_size", "TitleLabel", SIZE_LEAD if on_navy else SIZE_TITLE)
	t.set_color("font_color", "TitleLabel", DATA_TITLE if on_navy else text)
	t.set_type_variation("DisplayLabel", "Label")
	t.set_font("font", "DisplayLabel", title_font())
	t.set_font_size("font_size", "DisplayLabel", SIZE_DISPLAY)
	t.set_color("font_color", "DisplayLabel", text)
	t.set_type_variation("ValueLabel", "Label")
	t.set_font("font", "ValueLabel", data_font())
	t.set_font_size("font_size", "ValueLabel", SIZE_SMALL)
	t.set_color("font_color", "ValueLabel", text)
	t.set_type_variation("MapHintLabel", "Label")
	t.set_font("font", "MapHintLabel", data_font())
	t.set_font_size("font_size", "MapHintLabel", SIZE_SMALL)
	t.set_color("font_color", "MapHintLabel", Color.WHITE)
	t.set_color("font_shadow_color", "MapHintLabel", Color(0, 0, 0, 0.9))
	t.set_constant("shadow_offset_x", "MapHintLabel", 1)
	t.set_constant("shadow_offset_y", "MapHintLabel", 1)

	# The data display: blue title, white-grey labels, yellow values, red alerts, blue footer.
	for entry in [["DataTitle", DATA_TITLE], ["DataLabel", DATA_LABEL], ["DataValue", DATA_VALUE], ["DataAlert", DATA_ALERT], ["DataFooterLabel", DATA_TITLE]]:
		t.set_type_variation(entry[0], "Label")
		t.set_font("font", entry[0], data_font())
		t.set_font_size("font_size", entry[0], SIZE_DATA)
		t.set_color("font_color", entry[0], entry[1])
		t.set_constant("line_spacing", entry[0], 2)
	# Text drawn straight on the chart or the 3D view: white bold with a one-pixel black shadow,
	# and the camera mode in red.
	t.set_type_variation("CdsReadout", "Label")
	t.set_font("font", "CdsReadout", data_font())
	t.set_font_size("font_size", "CdsReadout", SIZE_DATA)
	t.set_color("font_color", "CdsReadout", Color.WHITE)
	t.set_color("font_shadow_color", "CdsReadout", Color(0, 0, 0, 0.9))
	t.set_constant("shadow_offset_x", "CdsReadout", 1)
	t.set_constant("shadow_offset_y", "CdsReadout", 1)
	t.set_type_variation("CdsCameraLabel", "Label")
	t.set_font("font", "CdsCameraLabel", data_font())
	t.set_font_size("font_size", "CdsCameraLabel", 14)
	t.set_color("font_color", "CdsCameraLabel", CDS_CAMERA)

	# Front end: yellow heavy italic captions with a black outline, and the wordmark.
	t.set_type_variation("MenuCaption", "Label")
	t.set_font("font", "MenuCaption", caption_font())
	t.set_font_size("font_size", "MenuCaption", SIZE_CAPTION)
	t.set_color("font_color", "MenuCaption", CAPTION)
	t.set_color("font_outline_color", "MenuCaption", Color.BLACK)
	t.set_constant("outline_size", "MenuCaption", 5)
	t.set_color("font_shadow_color", "MenuCaption", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "MenuCaption", 2)
	t.set_constant("shadow_offset_y", "MenuCaption", 2)
	t.set_type_variation("TitleMark", "Label")
	t.set_font("font", "TitleMark", title_font())
	t.set_font_size("font_size", "TitleMark", 56)
	t.set_color("font_color", "TitleMark", TITLE_FILL)
	t.set_color("font_outline_color", "TitleMark", TITLE_EDGE)
	t.set_constant("outline_size", "TitleMark", 6)
	t.set_color("font_shadow_color", "TitleMark", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "TitleMark", 4)
	t.set_constant("shadow_offset_y", "TitleMark", 4)
	t.set_constant("shadow_outline_size", "TitleMark", 8)
	# Front-end body text on the metal panel: navy, as on the grey chrome.
	t.set_type_variation("MenuLabel", "Label")
	t.set_color("font_color", "MenuLabel", MENU_INK)

	t.set_font("font", "TooltipLabel", ui_font())
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", SIZE_SMALL)


static func _fields(t: Theme) -> void:
	# Light fields with a one-pixel navy border; focus thickens it in the selection blue.
	var field := _pad(_box(JFC_FIELD, INK, 1, 0), 8, 4)
	var field_focus := _pad(_box(JFC_FIELD, JFC_SELECT, 2, 0), 8, 4)
	var field_readonly := _pad(_box(JFC_GREY, JFC_GREY_BORDER, 1, 0), 8, 4)
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, field_focus)
		t.set_stylebox("read_only", type, field_readonly)
		t.set_font("font", type, ui_font())
		t.set_color("font_color", type, INK)
		t.set_color("font_selected_color", type, Color.WHITE)
		t.set_color("font_uneditable_color", type, INK_FAINT)
		t.set_color("font_placeholder_color", type, INK_FAINT)
		t.set_color("caret_color", type, INK)
		t.set_color("selection_color", type, JFC_SELECT)
		t.set_color("clear_button_color", type, INK)
		t.set_color("clear_button_color_pressed", type, JFC_SELECT)

	# Drop-down lists: a field with a square bevelled arrow button at its right end.
	for state: String in ["normal", "hover", "pressed", "disabled", "normal_mirrored", "hover_mirrored", "pressed_mirrored", "disabled_mirrored"]:
		var off := state.begins_with("disabled")
		var s := JfcStyle.new()
		s.face = JFC_GREY if off else JFC_FIELD
		s.outline = JFC_GREY_BORDER if off else INK
		s.dropdown = true
		s.arrow_color = JFC_DISABLED if off else Color.BLACK
		s.content_margin_left = 8
		s.content_margin_right = 34
		s.content_margin_top = 4
		s.content_margin_bottom = 4
		t.set_stylebox(state, "OptionButton", s)
	t.set_stylebox("focus", "OptionButton", _focus_ring(JFC_SELECT, 0))
	t.set_icon("arrow", "OptionButton", _blank_icon())
	t.set_constant("arrow_margin", "OptionButton", 4)
	t.set_font("font", "OptionButton", ui_font())
	t.set_font_size("font_size", "OptionButton", SIZE_BODY)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(key, "OptionButton", INK)
	t.set_color("font_disabled_color", "OptionButton", JFC_DISABLED)

	# Spin boxes: the field with two stacked bevel buttons.
	t.set_stylebox("normal", "SpinBox", field)
	for part in ["up", "down"]:
		t.set_stylebox(part + "_background", "SpinBox", bevel(JFC_FACE, false, 0))
		t.set_stylebox(part + "_background_hovered", "SpinBox", bevel(JFC_FACE_HOVER, false, 0))
		t.set_stylebox(part + "_background_pressed", "SpinBox", bevel(JFC_FACE_DOWN, true, 0))
		t.set_stylebox(part + "_background_disabled", "SpinBox", bevel(JFC_GREY, false, 0, Color(JFC_GREY_BORDER, 0.6)))
		for suffix in ["", "_hover", "_pressed"]:
			t.set_icon(part + suffix, "SpinBox", arrow_icon(part, Color.BLACK, 9))
		t.set_icon(part + "_disabled", "SpinBox", arrow_icon(part, JFC_DISABLED, 9))
	t.set_stylebox("field_and_buttons_separator", "SpinBox", StyleBoxEmpty.new())
	t.set_stylebox("up_down_buttons_separator", "SpinBox", StyleBoxEmpty.new())
	t.set_constant("buttons_width", "SpinBox", 18)
	t.set_constant("field_and_buttons_separation", "SpinBox", 0)
	t.set_constant("buttons_vertical_separation", "SpinBox", 0)
	t.set_constant("set_min_buttons_width_from_icons", "SpinBox", 0)


static func _lists(t: Theme, on_navy: bool, text: Color, faint: Color) -> void:
	var well: StyleBox
	if on_navy:
		well = _box(COL_PANEL_DEEP, COL_HAIRLINE, 1, 0)
	else:
		well = bevel(JFC_FIELD, true, 0, INK)
	well.set_content_margin_all(3)
	var row_sel := _box(JFC_SELECT, Color.TRANSPARENT, 0, 0)
	var row_hover := _box(Color(COL_HOVER, 0.9) if on_navy else Color(JFC_SELECT, 0.12), Color.TRANSPARENT, 0, 0)
	for type in ["ItemList", "Tree"]:
		t.set_stylebox("panel", type, well)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		for state in ["selected", "selected_focus", "hovered_selected", "hovered_selected_focus"]:
			t.set_stylebox(state, type, row_sel)
		t.set_stylebox("hovered", type, row_hover)
		t.set_stylebox("cursor", type, StyleBoxEmpty.new())
		t.set_stylebox("cursor_unfocused", type, StyleBoxEmpty.new())
		t.set_font("font", type, ui_font())
		t.set_font_size("font_size", type, SIZE_BODY)
		t.set_color("font_color", type, text)
		t.set_color("font_hovered_color", type, text)
		t.set_color("font_selected_color", type, Color.WHITE)
		t.set_color("font_hovered_selected_color", type, Color.WHITE)
		t.set_color("guide_color", type, Color(COL_HAIRLINE if on_navy else JFC_GREY_BORDER, 0.4))
	t.set_constant("v_separation", "ItemList", 4)
	t.set_constant("h_separation", "ItemList", 8)
	t.set_color("font_disabled_color", "Tree", faint)
	t.set_stylebox("hovered_dimmed", "Tree", row_hover)
	var head := _pad(bevel(JFC_FACE, false, 0), 8, 4)
	t.set_stylebox("title_button_normal", "Tree", head)
	t.set_stylebox("title_button_hover", "Tree", head)
	t.set_stylebox("title_button_pressed", "Tree", _pad(bevel(JFC_FACE_DOWN, true, 0), 8, 4))
	t.set_font("title_button_font", "Tree", ui_font())
	t.set_font_size("title_button_font_size", "Tree", SIZE_SMALL)
	t.set_color("title_button_color", "Tree", INK)
	t.set_constant("v_separation", "Tree", 4)
	t.set_constant("draw_guides", "Tree", 0)
	t.set_constant("draw_relationship_lines", "Tree", 0)

	# The front-end list: a light field, navy text, the chosen row in selection blue.
	t.set_type_variation("MenuList", "ItemList")
	var menu_well := bevel(LIST_FIELD, true, 0, Color.BLACK)
	menu_well.set_content_margin_all(3)
	t.set_stylebox("panel", "MenuList", menu_well)
	t.set_color("font_color", "MenuList", MENU_INK)
	t.set_color("font_hovered_color", "MenuList", MENU_INK)
	t.set_stylebox("hovered", "MenuList", _box(Color(JFC_SELECT, 0.12), Color.TRANSPARENT, 0, 0))

	# Colours for lists that draw their own rows (RowList and the Actions palette), per surface.
	t.set_color("title_color", "RowListText", text)
	t.set_color("detail_color", "RowListText", COL_MUTED if on_navy else INK_FAINT)
	t.set_color("selected_color", "RowListText", Color.WHITE)
	t.set_color("selected_detail_color", "RowListText", Color("dcdcff"))
	t.set_color("badge_color", "RowListText", COL_GREEN if on_navy else STAR)


static func _menus(t: Theme) -> void:
	var panel := bevel(JFC_GREY, false, 0, Color("30303c"))
	panel.set_content_margin_all(3)
	t.set_stylebox("panel", "PopupMenu", panel)
	t.set_stylebox("hover", "PopupMenu", _box(JFC_SELECT, Color.TRANSPARENT, 0, 0))
	var sep := StyleBoxLine.new()
	sep.color = JFC_BEVEL_LO
	sep.thickness = 1
	sep.grow_begin = -4
	sep.grow_end = -4
	t.set_stylebox("separator", "PopupMenu", sep)
	t.set_stylebox("labeled_separator_left", "PopupMenu", sep)
	t.set_stylebox("labeled_separator_right", "PopupMenu", sep)
	t.set_font("font", "PopupMenu", ui_font())
	t.set_font("font_separator", "PopupMenu", ui_font())
	t.set_font_size("font_size", "PopupMenu", SIZE_BODY)
	t.set_font_size("font_separator_size", "PopupMenu", SIZE_SMALL)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", JFC_DISABLED)
	t.set_color("font_accelerator_color", "PopupMenu", INK_FAINT)
	t.set_color("font_separator_color", "PopupMenu", INK_BLUE)
	t.set_constant("v_separation", "PopupMenu", MENU_ROW - 15)
	t.set_constant("h_separation", "PopupMenu", 8)
	t.set_constant("item_start_padding", "PopupMenu", 8)
	t.set_constant("item_end_padding", "PopupMenu", 10)
	t.set_icon("submenu", "PopupMenu", arrow_icon("right", INK, 10))
	t.set_icon("submenu_mirrored", "PopupMenu", arrow_icon("left", INK, 10))
	t.set_icon("checked", "PopupMenu", check_icon(true))
	t.set_icon("unchecked", "PopupMenu", check_icon(false))
	t.set_icon("checked_disabled", "PopupMenu", check_icon(true, true))
	t.set_icon("unchecked_disabled", "PopupMenu", check_icon(false, true))
	t.set_icon("radio_checked", "PopupMenu", led_icon(true, false, 14))
	t.set_icon("radio_unchecked", "PopupMenu", led_icon(false, false, 14))
	t.set_icon("radio_checked_disabled", "PopupMenu", led_icon(true, true, 14))
	t.set_icon("radio_unchecked_disabled", "PopupMenu", led_icon(false, true, 14))


static func _rich_text(t: Theme, text: Color) -> void:
	t.set_font("normal_font", "RichTextLabel", ui_font())
	t.set_font("bold_font", "RichTextLabel", data_font())
	t.set_font("italics_font", "RichTextLabel", caption_font())
	t.set_font("mono_font", "RichTextLabel", data_font())
	t.set_font_size("normal_font_size", "RichTextLabel", SIZE_BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", SIZE_BODY)
	t.set_font_size("italics_font_size", "RichTextLabel", SIZE_LEAD)
	t.set_font_size("mono_font_size", "RichTextLabel", SIZE_SMALL)
	t.set_color("default_color", "RichTextLabel", text)
	t.set_color("selection_color", "RichTextLabel", Color(JFC_SELECT, 0.45))
	t.set_constant("line_separation", "RichTextLabel", 3)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	var rt_focus := _box(Color.TRANSPARENT, Color(JFC_SELECT, 0.7), 1, 0)
	rt_focus.draw_center = false
	rt_focus.set_expand_margin_all(3)
	t.set_stylebox("focus", "RichTextLabel", rt_focus)


static func _scrollbars(t: Theme) -> void:
	# Square bevel arrow buttons at each end of a sunken track, and a raised thumb.
	for bar in ["VScrollBar", "HScrollBar"]:
		var track := bevel(Color("b0b0ba"), true, 0, Color.TRANSPARENT)
		track.set_content_margin_all(0)
		var thumb := bevel(JFC_FACE, false, 0)
		thumb.set_content_margin_all(7)
		var thumb_hi := bevel(JFC_FACE_HOVER, false, 0)
		thumb_hi.set_content_margin_all(7)
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("scroll_focus", bar, track)
		t.set_stylebox("grabber", bar, thumb)
		t.set_stylebox("grabber_highlight", bar, thumb_hi)
		t.set_stylebox("grabber_pressed", bar, thumb_hi)
		var ends: Array = ["up", "down"] if bar == "VScrollBar" else ["left", "right"]
		t.set_icon("decrement", bar, scroll_button_icon(ends[0]))
		t.set_icon("decrement_highlight", bar, scroll_button_icon(ends[0]))
		t.set_icon("decrement_pressed", bar, scroll_button_icon(ends[0], true))
		t.set_icon("increment", bar, scroll_button_icon(ends[1]))
		t.set_icon("increment_highlight", bar, scroll_button_icon(ends[1]))
		t.set_icon("increment_pressed", bar, scroll_button_icon(ends[1], true))

	# Separators: an engraved line.
	var sep := StyleBoxLine.new()
	sep.color = JFC_BEVEL_LO
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 2)
	var vsep := StyleBoxLine.new()
	vsep.color = JFC_BEVEL_LO
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)


static func _tabs(t: Theme, on_navy: bool) -> void:
	# Tabs across the top as grey bevel buttons; the open one is pressed in.
	var tab := _pad(bevel(JFC_FACE, false, RADIUS), 12, 5)
	var tab_hover := _pad(bevel(JFC_FACE_HOVER, false, RADIUS), 12, 5)
	var tab_on := _pad(bevel(JFC_FIELD, true, RADIUS), 12, 5)
	var tab_off := _pad(bevel(JFC_GREY, false, RADIUS, Color(JFC_GREY_BORDER, 0.5)), 12, 5)
	var panel: StyleBox
	if on_navy:
		panel = _box(DATA_PANEL, COL_HAIRLINE, 1, 0)
	else:
		panel = bevel(JFC_GREY, true, 0, JFC_GREY_BORDER)
	panel.set_content_margin_all(10)
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, tab_on)
		t.set_stylebox("tab_unselected", type, tab)
		t.set_stylebox("tab_hovered", type, tab_hover)
		t.set_stylebox("tab_disabled", type, tab_off)
		t.set_stylebox("tab_focus", type, _focus_ring(JFC_SELECT, RADIUS))
		t.set_font("font", type, ui_font())
		t.set_color("font_selected_color", type, JFC_SELECT)
		t.set_color("font_unselected_color", type, INK)
		t.set_color("font_hovered_color", type, INK)
		t.set_color("font_disabled_color", type, JFC_DISABLED)
		t.set_font_size("font_size", type, SIZE_SMALL)
	t.set_stylebox("panel", "TabContainer", panel)
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_constant("side_margin", "TabContainer", 0)
	t.set_constant("h_separation", "TabBar", 3)


static func _toggles(t: Theme, text: Color, faint: Color) -> void:
	for type in ["CheckBox", "CheckButton"]:
		var plain := _pad(StyleBoxEmpty.new(), 2, 3)
		for state in ["normal", "pressed", "hover", "hover_pressed", "disabled"]:
			t.set_stylebox(state, type, plain)
		t.set_stylebox("focus", type, _focus_ring(JFC_SELECT, RADIUS))
		t.set_font("font", type, ui_font())
		for key in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(key, type, text)
		t.set_color("font_disabled_color", type, faint)
		t.set_constant("h_separation", type, 7)
	# Check boxes are sunken squares with an X; switches are LED lamps.
	t.set_icon("checked", "CheckBox", check_icon(true))
	t.set_icon("unchecked", "CheckBox", check_icon(false))
	t.set_icon("checked_disabled", "CheckBox", check_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckBox", check_icon(false, true))
	t.set_icon("radio_checked", "CheckBox", led_icon(true))
	t.set_icon("radio_unchecked", "CheckBox", led_icon(false))
	t.set_icon("radio_checked_disabled", "CheckBox", led_icon(true, true))
	t.set_icon("radio_unchecked_disabled", "CheckBox", led_icon(false, true))
	for suffix in ["", "_mirrored"]:
		t.set_icon("checked" + suffix, "CheckButton", led_icon(true))
		t.set_icon("unchecked" + suffix, "CheckButton", led_icon(false))
		t.set_icon("checked_disabled" + suffix, "CheckButton", led_icon(true, true))
		t.set_icon("unchecked_disabled" + suffix, "CheckButton", led_icon(false, true))
