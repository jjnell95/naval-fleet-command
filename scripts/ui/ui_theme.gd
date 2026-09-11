class_name UITheme
## Builds the command-console theme in code so no hand-edited .tres theme is needed.
## One palette for every panel: deep navy grounds, cyan accent for the machine's own voice,
## amber for warnings, red for hostile and damage, green for good news.

const COL_TEXT := Color("d3e3ec")
const COL_DIM := Color("9aafbd")
const COL_MUTED := Color("718998")
const COL_ACCENT := Color("63e6d2")
const COL_AMBER := Color("ffbe77")
const COL_RED := Color("ff8a7a")
const COL_GREEN := Color("8fd99a")
const COL_BLUE := Color("6cb9ff")
const COL_PANEL := Color("0b1924")
const COL_PANEL_DEEP := Color("091421")
const COL_BORDER := Color("22384a")
const COL_BORDER_LIGHT := Color("2f4c60")

const HEX_TEXT := "#d3e3ec"
const HEX_DIM := "#9aafbd"
const HEX_MUTED := "#718998"
const HEX_ACCENT := "#63e6d2"
const HEX_AMBER := "#ffbe77"
const HEX_RED := "#ff8a7a"
const HEX_GREEN := "#8fd99a"
const HEX_BLUE := "#6cb9ff"


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 13

	var panel := StyleBoxFlat.new()
	panel.bg_color = COL_PANEL
	panel.border_color = COL_BORDER
	panel.set_border_width_all(1)
	panel.set_content_margin_all(12)
	panel.set_corner_radius_all(3)
	t.set_stylebox("panel", "PanelContainer", panel)

	var overlay := panel.duplicate()
	overlay.bg_color = Color("0a1520")
	overlay.border_color = COL_BORDER_LIGHT
	overlay.set_content_margin_all(0)
	t.set_type_variation("OverlayPanel", "PanelContainer")
	t.set_stylebox("panel", "OverlayPanel", overlay)

	var card := panel.duplicate()
	card.bg_color = COL_PANEL_DEEP
	card.set_content_margin_all(14)
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", card)

	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("12212e")
	btn.border_color = Color("2c4a5e")
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(3)
	btn.content_margin_left = 10
	btn.content_margin_right = 10
	btn.content_margin_top = 5
	btn.content_margin_bottom = 5
	var hover := btn.duplicate()
	hover.bg_color = Color("1a3244")
	hover.border_color = Color("3f6a83")
	var pressed := btn.duplicate()
	pressed.bg_color = Color("1f5566")
	pressed.border_color = COL_ACCENT
	var disabled := btn.duplicate()
	disabled.bg_color = Color("0b141c")
	disabled.border_color = Color("1a2a36")
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", pressed)
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("445866"))
	t.set_font_size("font_size", "Button", 12)

	var primary := pressed.duplicate()
	primary.bg_color = Color("1c6f78")
	primary.border_color = COL_ACCENT
	primary.content_margin_left = 18
	primary.content_margin_right = 18
	primary.content_margin_top = 9
	primary.content_margin_bottom = 9
	var primary_hover := primary.duplicate()
	primary_hover.bg_color = Color("25868f")
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", primary)
	t.set_stylebox("hover", "PrimaryButton", primary_hover)
	t.set_stylebox("pressed", "PrimaryButton", primary_hover)
	t.set_stylebox("focus", "PrimaryButton", primary_hover)
	t.set_font_size("font_size", "PrimaryButton", 14)
	t.set_color("font_color", "PrimaryButton", Color.WHITE)

	t.set_color("font_color", "Label", COL_TEXT)
	t.set_font_size("font_size", "Label", 13)
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font_size("font_size", "HeaderLabel", 11)
	t.set_color("font_color", "HeaderLabel", COL_ACCENT)
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", COL_DIM)
	t.set_font_size("font_size", "DimLabel", 12)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", 20)
	t.set_color("font_color", "TitleLabel", Color.WHITE)

	var field := btn.duplicate()
	field.bg_color = Color("081019")
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", hover)
	t.set_color("font_color", "LineEdit", COL_TEXT)
	t.set_stylebox("normal", "SpinBox", field)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("v_separation", "ItemList", 9)
	t.set_constant("h_separation", "ItemList", 6)
	t.set_font_size("font_size", "ItemList", 12)
	t.set_color("font_color", "ItemList", COL_TEXT)
	t.set_stylebox("panel", "ItemList", field)
	var row_sel := StyleBoxFlat.new()
	row_sel.bg_color = Color("1c4a58")
	row_sel.border_color = COL_ACCENT
	row_sel.border_width_left = 2
	row_sel.set_corner_radius_all(2)
	t.set_stylebox("selected", "ItemList", row_sel)
	t.set_stylebox("selected_focus", "ItemList", row_sel)
	var row_hover := StyleBoxFlat.new()
	row_hover.bg_color = Color("122433")
	t.set_stylebox("hovered", "ItemList", row_hover)
	t.set_stylebox("panel", "PopupPanel", panel)
	t.set_stylebox("panel", "PopupMenu", panel)
	t.set_font_size("normal_font_size", "RichTextLabel", 13)
	t.set_font_size("bold_font_size", "RichTextLabel", 13)
	t.set_color("default_color", "RichTextLabel", COL_TEXT)
	var rt_bg := StyleBoxEmpty.new()
	t.set_stylebox("normal", "RichTextLabel", rt_bg)
	var tip := panel.duplicate()
	tip.bg_color = Color("0c1a26")
	tip.border_color = COL_BORDER_LIGHT
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", COL_TEXT)
	t.set_font_size("font_size", "TooltipLabel", 12)
	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = Color("0a141d")
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color("2c4a5e")
	grabber.set_corner_radius_all(3)
	t.set_stylebox("scroll", "VScrollBar", scroll_bg)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	var sep := StyleBoxLine.new()
	sep.color = COL_BORDER
	t.set_stylebox("separator", "HSeparator", sep)
	var tab := StyleBoxFlat.new()
	tab.bg_color = Color("0a1721")
	tab.set_content_margin_all(9)
	var selected := tab.duplicate()
	selected.bg_color = Color("15303e")
	selected.border_color = COL_ACCENT
	selected.border_width_top = 2
	t.set_stylebox("tab_selected", "TabContainer", selected)
	t.set_stylebox("tab_unselected", "TabContainer", tab)
	t.set_stylebox("tab_hovered", "TabContainer", selected)
	t.set_stylebox("panel", "TabContainer", tab)
	t.set_color("font_selected_color", "TabContainer", COL_ACCENT)
	t.set_color("font_unselected_color", "TabContainer", COL_DIM)
	t.set_font_size("font_size", "TabContainer", 12)
	return t
