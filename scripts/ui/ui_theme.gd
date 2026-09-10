class_name UITheme
## Builds the dark command-center theme in code so no hand-edited .tres theme is needed.

const COL_TEXT := Color(0.72, 0.86, 0.95)
const COL_DIM := Color(0.40, 0.52, 0.60)


static func build() -> Theme:
	var t := Theme.new()

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.045, 0.075, 0.105)
	panel.border_color = Color(0.16, 0.30, 0.40)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(8)
	t.set_stylebox("panel", "PanelContainer", panel)

	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.09, 0.15, 0.20)
	btn.border_color = Color(0.25, 0.45, 0.58)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(2)
	btn.content_margin_left = 8
	btn.content_margin_right = 8
	btn.content_margin_top = 3
	btn.content_margin_bottom = 3
	var hover := btn.duplicate()
	hover.bg_color = Color(0.13, 0.22, 0.29)
	var pressed := btn.duplicate()
	pressed.bg_color = Color(0.17, 0.40, 0.55)
	pressed.border_color = Color(0.55, 0.85, 1.0)
	var disabled := btn.duplicate()
	disabled.bg_color = Color(0.06, 0.09, 0.12)
	disabled.border_color = Color(0.14, 0.20, 0.25)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", COL_DIM)
	t.set_font_size("font_size", "Button", 13)

	t.set_color("font_color", "Label", COL_TEXT)
	t.set_font_size("font_size", "Label", 13)

	var field := btn.duplicate()
	field.bg_color = Color(0.03, 0.05, 0.08)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", hover)
	t.set_color("font_color", "LineEdit", COL_TEXT)
	return t
