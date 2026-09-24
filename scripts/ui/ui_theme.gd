class_name UITheme
## Builds the command-console theme in code so no hand-edited .tres theme is needed.
##
## The system is deliberately quiet. Chrome is neutral navy-graphite in four elevation steps and
## hairline dividers; colour is reserved for meaning so it can be read at a glance:
##   teal   — the interface's own voice: selection, focus, the primary action
##   blue   — own force            red   — hostile, damage, danger
##   amber  — unknown, caution     green — neutral traffic, good news
##   brass  — the wordmark and hero titles only
## Section labels are small tracked capitals in a muted tone, not colour.

# --- Surfaces, darkest to lightest ---------------------------------------------------------
const COL_BG := Color("060c12")
const COL_PANEL_DEEP := Color("09121a")
const COL_PANEL := Color("0c161f")
const COL_RAISED := Color("111d28")
const COL_HOVER := Color("182735")
const COL_SELECTED := Color("163238")
const COL_HAIRLINE := Color("1a2833")
const COL_BORDER := Color("243646")
const COL_BORDER_LIGHT := Color("34495c")

# --- Text ----------------------------------------------------------------------------------
const COL_TEXT := Color("e7eef3")
const COL_DIM := Color("a5b4c0")
const COL_MUTED := Color("72879a")
const COL_FAINT := Color("4b5d6d")

# --- Meaning -------------------------------------------------------------------------------
const COL_ACCENT := Color("5fd4c6")
const COL_ACCENT_HOVER := Color("86e3d8")
const COL_ON_ACCENT := Color("03201d")
const COL_BRASS := Color("c9b07f")
const COL_AMBER := Color("f3b45b")
const COL_RED := Color("ff7468")
const COL_GREEN := Color("74d69b")
const COL_BLUE := Color("63b3ff")

const HEX_TEXT := "#e7eef3"
const HEX_DIM := "#a5b4c0"
const HEX_MUTED := "#72879a"
const HEX_ACCENT := "#5fd4c6"
const HEX_BRASS := "#c9b07f"
const HEX_AMBER := "#f3b45b"
const HEX_RED := "#ff7468"
const HEX_GREEN := "#74d69b"
const HEX_BLUE := "#63b3ff"

# --- Type scale (px at the 1600 × 1000 reference canvas) -----------------------------------
const SIZE_EYEBROW := 11
const SIZE_SMALL := 12
const SIZE_BODY := 13
const SIZE_LEAD := 15
const SIZE_TITLE := 26
const SIZE_DISPLAY := 44

const RADIUS := 6
const RADIUS_SMALL := 4


static var _heading: Font = null
static var _body: Font = null
static var _semibold: Font = null
static var _eyebrow: Font = null
static var _mono: Font = null


static func heading_font() -> Font:
	if _heading == null:
		var font := FontVariation.new()
		font.base_font = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
		font.set_spacing(TextServer.SPACING_GLYPH, 0)
		# Barlow has no arrows or check marks; the browser has no system fallback to find them.
		font.fallbacks = [body_font()]
		_heading = font
	return _heading

static func body_font() -> Font:
	if _body == null:
		var font := FontVariation.new()
		font.base_font = load("res://assets/fonts/IBMPlexSans.ttf")
		font.variation_opentype = {"wght": 440.0, "wdth": 100.0}
		_body = font
	return _body

static func semibold_font() -> Font:
	if _semibold == null:
		var font := FontVariation.new()
		font.base_font = load("res://assets/fonts/IBMPlexSans.ttf")
		font.variation_opentype = {"wght": 580.0, "wdth": 100.0}
		_semibold = font
	return _semibold

## Small tracked capitals for section labels.
static func eyebrow_font() -> Font:
	if _eyebrow == null:
		var font := FontVariation.new()
		font.base_font = load("res://assets/fonts/IBMPlexSans.ttf")
		font.variation_opentype = {"wght": 600.0, "wdth": 100.0}
		font.set_spacing(TextServer.SPACING_GLYPH, 1)
		_eyebrow = font
	return _eyebrow

static func mono_font() -> Font:
	if _mono == null:
		_mono = load("res://assets/fonts/IBMPlexMono-Regular.ttf")
	return _mono


## BBCode for a section heading inside a RichTextLabel: quiet tracked capitals.
static func section_bb(text: String) -> String:
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


## A one-pixel divider in the hairline colour.
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


static func _focus_ring(color := COL_ACCENT, radius := RADIUS) -> StyleBoxFlat:
	var f := _box(Color.TRANSPARENT, color, 2, radius + 2)
	f.draw_center = false
	f.set_expand_margin_all(2)
	return f


## A card with a coloured stripe down its left edge, for the one statement a screen leads with.
static func stripe_card(color: Color, margin := 16.0) -> StyleBoxFlat:
	var s := _box(COL_RAISED, COL_HAIRLINE, 1, RADIUS)
	s.border_color = color
	s.border_width_left = 3
	s.border_width_top = 0
	s.border_width_right = 0
	s.border_width_bottom = 0
	s.set_content_margin_all(margin)
	s.content_margin_left = margin + 4
	return s


## A floating surface over the chart: rounded, bordered and lifted by a soft shadow.
static func floating_panel(margin := 10.0) -> StyleBoxFlat:
	var s := _box(Color(COL_PANEL_DEEP, 0.94), COL_BORDER, 1, 8)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 4)
	s.set_content_margin_all(margin)
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = SIZE_BODY
	t.default_font = body_font()

	# --- Panels -----------------------------------------------------------------------
	# Docked panels are flush, square and borderless; the one-pixel gaps between them in
	# Main's layout read as hairline dividers.
	var panel := _box(COL_PANEL, Color.TRANSPARENT, 0, 0)
	panel.set_content_margin_all(14)
	t.set_stylebox("panel", "PanelContainer", panel)

	var overlay := _box(COL_BG, Color.TRANSPARENT, 0, 0)
	overlay.set_content_margin_all(0)
	t.set_type_variation("OverlayPanel", "PanelContainer")
	t.set_stylebox("panel", "OverlayPanel", overlay)

	var card := _box(COL_RAISED, COL_HAIRLINE, 1, RADIUS)
	card.set_content_margin_all(14)
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", card)

	t.set_type_variation("ToolbarPanel", "PanelContainer")
	t.set_stylebox("panel", "ToolbarPanel", floating_panel(4))

	t.set_type_variation("FloatingPanel", "PanelContainer")
	t.set_stylebox("panel", "FloatingPanel", floating_panel(12))

	var rail := _box(COL_PANEL_DEEP, Color.TRANSPARENT, 0, 0)
	_pad(rail, 0, 0)
	t.set_type_variation("RailPanel", "PanelContainer")
	t.set_stylebox("panel", "RailPanel", rail)

	# --- Buttons ----------------------------------------------------------------------
	var btn := _pad(_box(COL_RAISED, COL_BORDER, 1, RADIUS), 12, 6)
	var hover := _pad(_box(COL_HOVER, COL_BORDER_LIGHT, 1, RADIUS), 12, 6)
	var pressed := _pad(_box(COL_SELECTED, Color(COL_ACCENT, 0.55), 1, RADIUS), 12, 6)
	var disabled := _pad(_box(Color(COL_RAISED, 0.45), Color(COL_BORDER, 0.5), 1, RADIUS), 12, 6)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", _focus_ring())
	t.set_font("font", "Button", semibold_font())
	t.set_font_size("font_size", "Button", SIZE_SMALL)
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", COL_ACCENT_HOVER)
	t.set_color("font_hover_pressed_color", "Button", COL_ACCENT_HOVER)
	t.set_color("font_focus_color", "Button", COL_TEXT)
	t.set_color("font_disabled_color", "Button", COL_FAINT)
	t.set_color("icon_normal_color", "Button", COL_DIM)
	t.set_color("icon_hover_color", "Button", Color.WHITE)
	t.set_color("icon_pressed_color", "Button", COL_ACCENT_HOVER)
	t.set_color("icon_hover_pressed_color", "Button", COL_ACCENT_HOVER)
	t.set_color("icon_focus_color", "Button", COL_TEXT)
	t.set_color("icon_disabled_color", "Button", COL_FAINT)
	t.set_constant("h_separation", "Button", 7)

	# Primary: the one action a screen is asking for. Solid teal, dark text.
	var primary := _pad(_box(COL_ACCENT, COL_ACCENT, 1, RADIUS), 20, 9)
	var primary_hover := _pad(_box(COL_ACCENT_HOVER, COL_ACCENT_HOVER, 1, RADIUS), 20, 9)
	var primary_pressed := _pad(_box(Color("48b8ab"), Color("48b8ab"), 1, RADIUS), 20, 9)
	var primary_disabled := _pad(_box(Color(COL_ACCENT, 0.16), Color(COL_ACCENT, 0.2), 1, RADIUS), 20, 9)
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", primary)
	t.set_stylebox("hover", "PrimaryButton", primary_hover)
	t.set_stylebox("pressed", "PrimaryButton", primary_pressed)
	t.set_stylebox("hover_pressed", "PrimaryButton", primary_pressed)
	t.set_stylebox("disabled", "PrimaryButton", primary_disabled)
	t.set_stylebox("focus", "PrimaryButton", _focus_ring(Color(1, 1, 1, 0.6)))
	t.set_font_size("font_size", "PrimaryButton", SIZE_BODY)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		t.set_color(key, "PrimaryButton", COL_ON_ACCENT)
	t.set_color("font_disabled_color", "PrimaryButton", Color(COL_ACCENT, 0.45))

	# Danger: an alert that wants attention, or an irreversible action.
	var danger := _pad(_box(Color("3b1719"), Color(COL_RED, 0.7), 1, RADIUS), 12, 6)
	var danger_hover := _pad(_box(Color("56201f"), COL_RED, 1, RADIUS), 12, 6)
	t.set_type_variation("DangerButton", "Button")
	t.set_stylebox("normal", "DangerButton", danger)
	t.set_stylebox("hover", "DangerButton", danger_hover)
	t.set_stylebox("pressed", "DangerButton", danger_hover)
	t.set_stylebox("focus", "DangerButton", _focus_ring(COL_RED))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(key, "DangerButton", Color("ffe2dd"))

	# Quiet: toolbar and utility buttons with no resting chrome.
	var quiet := _pad(_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS), 9, 6)
	var quiet_hover := _pad(_box(COL_HOVER, Color.TRANSPARENT, 0, RADIUS), 9, 6)
	var quiet_pressed := _pad(_box(COL_SELECTED, Color.TRANSPARENT, 0, RADIUS), 9, 6)
	var quiet_disabled := _pad(_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS), 9, 6)
	t.set_type_variation("QuietButton", "Button")
	t.set_stylebox("normal", "QuietButton", quiet)
	t.set_stylebox("hover", "QuietButton", quiet_hover)
	t.set_stylebox("pressed", "QuietButton", quiet_pressed)
	t.set_stylebox("hover_pressed", "QuietButton", quiet_pressed)
	t.set_stylebox("disabled", "QuietButton", quiet_disabled)
	t.set_color("font_color", "QuietButton", COL_DIM)

	# Segment: one option inside a SegmentedPanel. The selected segment is a lifted chip.
	var seg := _pad(_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS_SMALL), 8, 4)
	var seg_hover := _pad(_box(COL_HOVER, Color.TRANSPARENT, 0, RADIUS_SMALL), 8, 4)
	var seg_on := _pad(_box(Color("22404a"), Color(COL_ACCENT, 0.45), 1, RADIUS_SMALL), 8, 4)
	t.set_type_variation("SegmentButton", "Button")
	t.set_stylebox("normal", "SegmentButton", seg)
	t.set_stylebox("hover", "SegmentButton", seg_hover)
	t.set_stylebox("pressed", "SegmentButton", seg_on)
	t.set_stylebox("hover_pressed", "SegmentButton", seg_on)
	t.set_stylebox("disabled", "SegmentButton", seg)
	t.set_stylebox("focus", "SegmentButton", _focus_ring(COL_ACCENT, RADIUS_SMALL))
	t.set_color("font_color", "SegmentButton", COL_DIM)
	t.set_color("font_pressed_color", "SegmentButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "SegmentButton", Color.WHITE)
	var seg_panel := _box(COL_PANEL_DEEP, COL_BORDER, 1, RADIUS)
	seg_panel.set_content_margin_all(3)
	t.set_type_variation("SegmentedPanel", "PanelContainer")
	t.set_stylebox("panel", "SegmentedPanel", seg_panel)

	# Tab: a page switch drawn as an underline, for tab rows built from buttons.
	var tab_btn := _pad(_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0), 4, 8)
	var tab_btn_hover := _pad(_box(Color.TRANSPARENT, COL_BORDER_LIGHT, 0, 0), 4, 8)
	tab_btn_hover.border_width_bottom = 2
	var tab_btn_on := _pad(_box(Color.TRANSPARENT, COL_ACCENT, 0, 0), 4, 8)
	tab_btn_on.border_width_bottom = 2
	t.set_type_variation("TabButton", "Button")
	t.set_stylebox("normal", "TabButton", tab_btn)
	t.set_stylebox("hover", "TabButton", tab_btn_hover)
	t.set_stylebox("pressed", "TabButton", tab_btn_on)
	t.set_stylebox("hover_pressed", "TabButton", tab_btn_on)
	t.set_stylebox("disabled", "TabButton", tab_btn)
	t.set_stylebox("focus", "TabButton", _focus_ring(COL_ACCENT, 2))
	t.set_color("font_color", "TabButton", COL_MUTED)
	t.set_color("font_hover_color", "TabButton", COL_TEXT)
	t.set_color("font_pressed_color", "TabButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "TabButton", Color.WHITE)
	t.set_color("font_focus_color", "TabButton", COL_TEXT)

	# --- Labels -----------------------------------------------------------------------
	t.set_color("font_color", "Label", COL_TEXT)
	t.set_font_size("font_size", "Label", SIZE_BODY)
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font("font", "HeaderLabel", eyebrow_font())
	t.set_font_size("font_size", "HeaderLabel", SIZE_EYEBROW)
	t.set_color("font_color", "HeaderLabel", COL_MUTED)
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", COL_DIM)
	t.set_font_size("font_size", "DimLabel", SIZE_SMALL)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", heading_font())
	t.set_font_size("font_size", "TitleLabel", SIZE_TITLE)
	t.set_color("font_color", "TitleLabel", Color.WHITE)
	t.set_type_variation("DisplayLabel", "Label")
	t.set_font("font", "DisplayLabel", heading_font())
	t.set_font_size("font_size", "DisplayLabel", SIZE_DISPLAY)
	t.set_color("font_color", "DisplayLabel", Color.WHITE)
	t.set_type_variation("ValueLabel", "Label")
	t.set_font("font", "ValueLabel", mono_font())
	t.set_font_size("font_size", "ValueLabel", SIZE_SMALL)
	t.set_color("font_color", "ValueLabel", COL_TEXT)
	t.set_type_variation("MapHintLabel", "Label")
	t.set_font_size("font_size", "MapHintLabel", SIZE_SMALL)
	t.set_color("font_color", "MapHintLabel", COL_DIM)
	t.set_color("font_shadow_color", "MapHintLabel", Color(0, 0, 0, 0.7))
	t.set_constant("shadow_offset_x", "MapHintLabel", 0)
	t.set_constant("shadow_offset_y", "MapHintLabel", 1)

	# --- Text entry -------------------------------------------------------------------
	var field := _pad(_box(COL_PANEL_DEEP, COL_BORDER, 1, RADIUS), 10, 6)
	var field_focus := _pad(_box(COL_PANEL_DEEP, COL_ACCENT, 1, RADIUS), 10, 6)
	var field_readonly := _pad(_box(Color(COL_PANEL_DEEP, 0.5), COL_HAIRLINE, 1, RADIUS), 10, 6)
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, field_focus)
		t.set_stylebox("read_only", type, field_readonly)
		t.set_color("font_color", type, COL_TEXT)
		t.set_color("font_placeholder_color", type, COL_MUTED)
		t.set_color("caret_color", type, COL_ACCENT)
		t.set_color("selection_color", type, Color(COL_ACCENT, 0.3))
	t.set_stylebox("normal", "SpinBox", field)

	# --- Lists, trees and menus -------------------------------------------------------
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("v_separation", "ItemList", 8)
	t.set_constant("h_separation", "ItemList", 8)
	t.set_font_size("font_size", "ItemList", SIZE_SMALL)
	t.set_color("font_color", "ItemList", COL_TEXT)
	t.set_color("font_hovered_color", "ItemList", Color.WHITE)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_color("guide_color", "ItemList", COL_HAIRLINE)
	var list_panel := _box(COL_PANEL_DEEP, COL_HAIRLINE, 1, RADIUS)
	list_panel.set_content_margin_all(4)
	t.set_stylebox("panel", "ItemList", list_panel)
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	var row_sel := _box(COL_SELECTED, Color.TRANSPARENT, 0, RADIUS_SMALL)
	row_sel.border_color = COL_ACCENT
	row_sel.border_width_left = 2
	t.set_stylebox("selected", "ItemList", row_sel)
	t.set_stylebox("selected_focus", "ItemList", row_sel)
	t.set_stylebox("hovered_selected", "ItemList", row_sel)
	t.set_stylebox("hovered_selected_focus", "ItemList", row_sel)
	t.set_stylebox("hovered", "ItemList", _box(COL_HOVER, Color.TRANSPARENT, 0, RADIUS_SMALL))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())

	var tree_panel := list_panel.duplicate()
	t.set_stylebox("panel", "Tree", tree_panel)
	t.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("selected", "Tree", row_sel)
	t.set_stylebox("selected_focus", "Tree", row_sel)
	t.set_stylebox("hovered", "Tree", _box(COL_HOVER, Color.TRANSPARENT, 0, RADIUS_SMALL))
	t.set_stylebox("cursor", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "Tree", StyleBoxEmpty.new())
	var tree_head := _pad(_box(COL_PANEL_DEEP, Color.TRANSPARENT, 0, 0), 8, 7)
	tree_head.border_color = COL_HAIRLINE
	tree_head.border_width_bottom = 1
	t.set_stylebox("title_button_normal", "Tree", tree_head)
	t.set_stylebox("title_button_hover", "Tree", tree_head)
	t.set_stylebox("title_button_pressed", "Tree", tree_head)
	t.set_font("title_button_font", "Tree", eyebrow_font())
	t.set_font_size("title_button_font_size", "Tree", SIZE_EYEBROW)
	t.set_color("title_button_color", "Tree", COL_MUTED)
	t.set_color("font_color", "Tree", COL_TEXT)
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	t.set_color("guide_color", "Tree", COL_HAIRLINE)
	t.set_font_size("font_size", "Tree", SIZE_SMALL)
	t.set_constant("v_separation", "Tree", 6)
	t.set_constant("draw_guides", "Tree", 1)
	t.set_constant("draw_relationship_lines", "Tree", 0)

	var popup := _box(COL_RAISED, COL_BORDER_LIGHT, 1, RADIUS)
	popup.set_content_margin_all(5)
	popup.shadow_color = Color(0, 0, 0, 0.5)
	popup.shadow_size = 12
	popup.shadow_offset = Vector2(0, 4)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(COL_SELECTED, Color.TRANSPARENT, 0, RADIUS_SMALL))
	t.set_color("font_color", "PopupMenu", COL_TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", COL_FAINT)
	t.set_font_size("font_size", "PopupMenu", SIZE_BODY)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_constant("item_start_padding", "PopupMenu", 8)
	t.set_constant("item_end_padding", "PopupMenu", 8)

	# --- Rich text --------------------------------------------------------------------
	t.set_font("normal_font", "RichTextLabel", body_font())
	t.set_font("bold_font", "RichTextLabel", semibold_font())
	t.set_font("mono_font", "RichTextLabel", mono_font())
	t.set_font_size("normal_font_size", "RichTextLabel", SIZE_BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", SIZE_BODY)
	t.set_font_size("mono_font_size", "RichTextLabel", SIZE_SMALL)
	t.set_color("default_color", "RichTextLabel", COL_TEXT)
	t.set_color("selection_color", "RichTextLabel", Color(COL_ACCENT, 0.3))
	t.set_constant("line_separation", "RichTextLabel", 3)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	var rt_focus := _box(Color.TRANSPARENT, Color(COL_ACCENT, 0.7), 1, RADIUS)
	rt_focus.draw_center = false
	rt_focus.set_expand_margin_all(3)
	t.set_stylebox("focus", "RichTextLabel", rt_focus)

	# --- Tooltips ---------------------------------------------------------------------
	var tip := _box(COL_RAISED, COL_BORDER_LIGHT, 1, RADIUS)
	tip.set_content_margin_all(9)
	tip.shadow_color = Color(0, 0, 0, 0.5)
	tip.shadow_size = 10
	tip.shadow_offset = Vector2(0, 3)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", COL_TEXT)
	t.set_font_size("font_size", "TooltipLabel", SIZE_SMALL)

	# --- Scrollbars: thin, no track --------------------------------------------------
	var scroll_bg := StyleBoxEmpty.new()
	scroll_bg.content_margin_left = 3
	scroll_bg.content_margin_right = 3
	scroll_bg.content_margin_top = 3
	scroll_bg.content_margin_bottom = 3
	var grabber := _box(Color(COL_BORDER_LIGHT, 0.8), Color.TRANSPARENT, 0, 3)
	var grabber_hi := _box(Color("4a6377"), Color.TRANSPARENT, 0, 3)
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, scroll_bg)
		t.set_stylebox("scroll_focus", bar, scroll_bg)
		t.set_stylebox("grabber", bar, grabber)
		t.set_stylebox("grabber_highlight", bar, grabber_hi)
		t.set_stylebox("grabber_pressed", bar, grabber_hi)

	var sep := StyleBoxLine.new()
	sep.color = COL_HAIRLINE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 1)
	var vsep := StyleBoxLine.new()
	vsep.color = COL_HAIRLINE
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)

	# --- Tabs: underline, no boxes ---------------------------------------------------
	var tab := _pad(_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0), 12, 8)
	var tab_on := _pad(_box(Color.TRANSPARENT, COL_ACCENT, 0, 0), 12, 8)
	tab_on.border_width_bottom = 2
	var tab_hover := _pad(_box(Color.TRANSPARENT, COL_BORDER_LIGHT, 0, 0), 12, 8)
	tab_hover.border_width_bottom = 2
	var tab_panel := _box(COL_PANEL, Color.TRANSPARENT, 0, 0)
	tab_panel.border_color = COL_HAIRLINE
	tab_panel.border_width_top = 1
	tab_panel.set_content_margin_all(10)
	var tab_bg := StyleBoxEmpty.new()
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, tab_on)
		t.set_stylebox("tab_unselected", type, tab)
		t.set_stylebox("tab_hovered", type, tab_hover)
		t.set_stylebox("tab_disabled", type, tab)
		t.set_stylebox("tab_focus", type, _focus_ring(COL_ACCENT, 2))
		t.set_font("font", type, semibold_font())
		t.set_color("font_selected_color", type, Color.WHITE)
		t.set_color("font_unselected_color", type, COL_MUTED)
		t.set_color("font_hovered_color", type, COL_TEXT)
		t.set_color("font_disabled_color", type, COL_FAINT)
		t.set_font_size("font_size", type, SIZE_SMALL)
	t.set_stylebox("panel", "TabContainer", tab_panel)
	t.set_stylebox("tabbar_background", "TabContainer", tab_bg)
	t.set_constant("side_margin", "TabContainer", 0)

	# --- Toggles ----------------------------------------------------------------------
	for type in ["CheckBox", "CheckButton"]:
		var plain := _pad(_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, RADIUS), 4, 4)
		t.set_stylebox("normal", type, plain)
		t.set_stylebox("pressed", type, plain)
		t.set_stylebox("hover", type, _pad(_box(COL_HOVER, Color.TRANSPARENT, 0, RADIUS), 4, 4))
		t.set_stylebox("hover_pressed", type, _pad(_box(COL_HOVER, Color.TRANSPARENT, 0, RADIUS), 4, 4))
		t.set_color("font_pressed_color", type, COL_TEXT)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_font("font", type, body_font())
	t.set_icon("checked", "CheckBox", UIIcons.get_icon("check_on", 16, COL_ACCENT))
	t.set_icon("unchecked", "CheckBox", UIIcons.get_icon("check_off", 16, COL_MUTED))

	# --- Progress ---------------------------------------------------------------------
	t.set_stylebox("background", "ProgressBar", _box(COL_PANEL_DEEP, COL_HAIRLINE, 1, 3))
	t.set_stylebox("fill", "ProgressBar", _box(COL_ACCENT, Color.TRANSPARENT, 0, 3))
	return t
