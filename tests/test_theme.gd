extends TestCase
## The command-screen skin: the two surface families, the variations the screen shell builds
## with, the colours the spec pins, the faces and their glyphs, the vector chrome and the
## front-end backdrop. Headless; nothing is drawn.

const SHELL_VARIATIONS := ["DataPanel", "DataTitle", "DataLabel", "DataValue", "DataAlert", "DataFooterLabel", "CdsReadout", "CdsCameraLabel", "BevelFrame", "JfcDialog", "MenuPanel", "MenuBigButton", "MenuCaption", "MenuList", "LedToggle"]


func test_bbcode_twins_match_their_colours() -> void:
	var pairs := [
		[UITheme.HEX_TEXT, UITheme.COL_TEXT], [UITheme.HEX_DIM, UITheme.COL_DIM], [UITheme.HEX_MUTED, UITheme.COL_MUTED],
		[UITheme.HEX_ACCENT, UITheme.COL_ACCENT], [UITheme.HEX_BRASS, UITheme.COL_BRASS], [UITheme.HEX_AMBER, UITheme.COL_AMBER],
		[UITheme.HEX_RED, UITheme.COL_RED], [UITheme.HEX_GREEN, UITheme.COL_GREEN], [UITheme.HEX_BLUE, UITheme.COL_BLUE],
		[UITheme.HEX_INK, UITheme.INK], [UITheme.HEX_INK_DIM, UITheme.INK_DIM], [UITheme.HEX_INK_FAINT, UITheme.INK_FAINT],
		[UITheme.HEX_INK_BLUE, UITheme.INK_BLUE], [UITheme.HEX_INK_RED, UITheme.INK_RED], [UITheme.HEX_INK_GREEN, UITheme.INK_GREEN],
		[UITheme.HEX_INK_AMBER, UITheme.INK_AMBER], [UITheme.HEX_DATA_TITLE, UITheme.DATA_TITLE], [UITheme.HEX_DATA_LABEL, UITheme.DATA_LABEL],
		[UITheme.HEX_DATA_VALUE, UITheme.DATA_VALUE], [UITheme.HEX_DATA_ALERT, UITheme.DATA_ALERT],
	]
	for pair: Array in pairs:
		assert_eq(pair[0], "#" + (pair[1] as Color).to_html(false), "a BBCode hex drifted from its colour")


func test_spec_colours_are_pinned() -> void:
	assert_eq(UITheme.JFC_GREY.to_html(false), "c8c8cc", "dialog grey")
	assert_eq(UITheme.JFC_GREY_BORDER.to_html(false), "6b6b78", "dialog border")
	assert_eq(UITheme.JFC_NAVY.to_html(false), "141450", "navy dialog text")
	assert_eq(UITheme.JFC_FIELD.to_html(false), "dadae0", "field background")
	assert_eq(UITheme.JFC_SELECT.to_html(false), "1010c0", "menu hover and selected row")
	assert_eq(UITheme.JFC_DISABLED.to_html(false), "8a8a96", "disabled menu rows")
	assert_eq(UITheme.LED_ON.to_html(false), "e02020", "lit lamp")
	assert_eq(UITheme.LED_OFF.to_html(false), "9a9aa4", "dark lamp")
	assert_eq(UITheme.DATA_PANEL.to_html(false), "0f1837", "data display navy")
	assert_eq(UITheme.DATA_TITLE.to_html(false), "3a7fff", "data title blue")
	assert_eq(UITheme.DATA_VALUE.to_html(false), "ffff55", "data value yellow")
	assert_eq(UITheme.DATA_ALERT.to_html(false), "ff4040", "data alert red")
	assert_eq(UITheme.DATA_BARS.to_html(false), "30e030", "scale bars")
	assert_eq(UITheme.CDS_CAMERA.to_html(false), "e02020", "3D camera label")
	assert_eq(UITheme.CAPTION.to_html(false), "ffd21e", "front-end captions")
	assert_eq(UITheme.MENU_INK.to_html(false), "10106a", "big button ink")
	assert_eq(UITheme.LIST_FIELD.to_html(false), "c8c8d0", "front-end list field")
	assert_eq([UITheme.BEVEL_OUTER.to_html(false), UITheme.BEVEL_MID.to_html(false), UITheme.BEVEL_INNER.to_html(false)], ["edf3f1", "c9ccdb", "6b678c"], "the three-line frame")
	assert_near(UITheme.METAL.a, 0.78, 0.001, "front-end metal is translucent")


func test_both_families_declare_every_variation_the_shell_uses() -> void:
	for t: Theme in [UITheme.build(), UITheme.data_theme()]:
		for v: String in SHELL_VARIATIONS:
			assert_true(t.get_type_variation_base(v) != StringName(), "%s is declared" % v)
		assert_eq(t.get_color("font_color", "DataTitle"), UITheme.DATA_TITLE)
		assert_eq(t.get_color("font_color", "DataLabel"), UITheme.DATA_LABEL)
		assert_eq(t.get_color("font_color", "DataValue"), UITheme.DATA_VALUE)
		assert_eq(t.get_color("font_color", "DataAlert"), UITheme.DATA_ALERT)
		assert_eq(t.get_color("font_color", "DataFooterLabel"), UITheme.DATA_TITLE)
		assert_eq(t.get_color("font_color", "CdsReadout"), Color.WHITE)
		assert_eq(t.get_constant("shadow_offset_x", "CdsReadout"), 1, "one-pixel drop shadow")
		assert_eq(t.get_color("font_color", "CdsCameraLabel"), UITheme.CDS_CAMERA)
		assert_eq(t.get_color("font_color", "MenuCaption"), UITheme.CAPTION)
		assert_eq(t.get_color("font_outline_color", "MenuCaption"), Color.BLACK, "captions are outlined in black")
		assert_eq(t.get_font("font", "MenuBigButton"), UITheme.caption_font(), "big buttons are heavy italic")
		assert_eq(t.get_color("font_color", "MenuBigButton"), UITheme.MENU_INK)
	assert_true(UITheme.data_theme() == UITheme.data_theme(), "one data theme is shared")


func test_text_follows_its_surface() -> void:
	var grey := UITheme.build()
	var navy := UITheme.data_theme()
	assert_eq(grey.get_color("font_color", "Label"), UITheme.INK, "navy text on the grey chrome")
	assert_eq(navy.get_color("font_color", "Label"), UITheme.COL_TEXT, "light text on a navy data panel")
	assert_eq(grey.get_color("default_color", "RichTextLabel"), UITheme.INK)
	assert_eq(navy.get_color("default_color", "RichTextLabel"), UITheme.COL_TEXT)
	assert_eq(navy.get_color("font_color", "TitleLabel"), UITheme.DATA_TITLE, "a title on navy is the data display's blue name line")
	# Buttons and menus are grey chrome on either surface.
	for t: Theme in [grey, navy]:
		assert_eq(t.get_color("font_color", "Button"), UITheme.INK, "navy bold on a grey bevel button")
		assert_eq(t.get_color("font_color", "PopupMenu"), UITheme.INK)
		assert_eq(t.get_color("font_hover_color", "PopupMenu"), Color.WHITE)
		assert_eq(t.get_color("font_disabled_color", "PopupMenu"), UITheme.JFC_DISABLED)
		var hover := t.get_stylebox("hover", "PopupMenu") as StyleBoxFlat
		assert_eq(hover.bg_color, UITheme.JFC_SELECT, "the hovered menu row is selection blue")
		assert_eq(t.get_constant("v_separation", "PopupMenu") + 15, UITheme.MENU_ROW, "menu rows are 22 px")
	var navy_panel := navy.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	assert_eq(navy_panel.bg_color, UITheme.DATA_PANEL, "a data panel is navy")
	var dialog := grey.get_stylebox("panel", "PanelContainer") as JfcStyle
	assert_eq(dialog.face, UITheme.JFC_GREY, "the base panel is the grey dialog")
	assert_eq(dialog.outline, UITheme.JFC_GREY_BORDER)
	assert_eq(dialog.radius, float(UITheme.RADIUS_DIALOG))


func test_bevels_and_lamps() -> void:
	var t := UITheme.build()
	var up := t.get_stylebox("normal", "Button") as JfcStyle
	var down := t.get_stylebox("pressed", "Button") as JfcStyle
	assert_true(up != null and not up.sunken, "a button rests raised")
	assert_true(down != null and down.sunken, "and presses in")
	assert_eq(up.light, UITheme.JFC_BEVEL_HI, "lit top-left")
	assert_eq(up.dark, UITheme.JFC_BEVEL_LO, "shaded bottom-right")
	var lamp_off := t.get_stylebox("normal", "LedToggle") as JfcStyle
	var lamp_on := t.get_stylebox("pressed", "LedToggle") as JfcStyle
	assert_eq(lamp_off.kind, JfcStyle.Kind.LED)
	assert_eq(lamp_off.lamp, UITheme.LED_OFF, "a dark lamp is grey")
	assert_eq(lamp_on.lamp, UITheme.LED_ON, "a lit lamp is red")
	var frame := UITheme.bevel_frame()
	assert_eq(frame.rings, PackedColorArray([UITheme.BEVEL_OUTER, UITheme.BEVEL_MID, UITheme.BEVEL_INNER]), "outer highlight, mid, inner shadow")
	assert_eq(frame.get_margin(SIDE_LEFT), 3.0, "three pixels")
	var dropdown := t.get_stylebox("normal", "OptionButton") as JfcStyle
	assert_true(dropdown.dropdown, "a drop-down list carries its square arrow button")
	for icon: Texture2D in [UITheme.check_icon(true), UITheme.check_icon(false), UITheme.led_icon(true), UITheme.led_icon(false), UITheme.scroll_button_icon("up"), UITheme.arrow_icon("right")]:
		assert_true(icon != null and icon.get_width() > 0, "theme icons rasterise")


func test_rounded_outline_walks_the_rect() -> void:
	var r := Rect2(10, 20, 100, 40)
	var ring := JfcStyle._rounded(r, 8.0, 180.0, 540.0)
	assert_true(ring.size() >= 12, "four arcs")
	for p in ring:
		assert_true(r.grow(0.01).has_point(p), "every point on or inside the rect: %s" % p)
	assert_near(ring[0].x, r.position.x, 0.01, "starts on the left side")
	var lit := JfcStyle._rounded(r, 8.0, 135.0, 315.0)
	var shade := JfcStyle._rounded(r, 8.0, 315.0, 495.0)
	assert_true(lit[lit.size() - 1].distance_to(shade[0]) < 0.01, "the lit and shaded edges meet at the top-right")
	assert_true(shade[shade.size() - 1].distance_to(lit[0]) < 0.01, "and at the bottom-left")


func test_faces_load_and_carry_the_glyphs_the_screens_draw() -> void:
	for f: Font in [UITheme.data_font(), UITheme.ui_font(), UITheme.title_font(), UITheme.caption_font()]:
		assert_true(f != null and f.get_height(13) > 0.0, "a face loads")
	for ch in "★→↑↓▲▼×·—–±°•…′−✓":
		assert_true(UITheme.data_font().has_char(ch.unicode_at(0)) or UITheme.ui_font().has_char(ch.unicode_at(0)), "glyph %s is in the data or interface face" % ch)
	# The heavy italic faces have no arrows, so they fall back to the interface face.
	assert_true(UITheme.caption_font().fallbacks.has(UITheme.ui_font()))
	assert_true(UITheme.title_font().fallbacks.has(UITheme.ui_font()))
	# Retired names map onto the new faces rather than disappearing.
	assert_eq(UITheme.body_font(), UITheme.ui_font())
	assert_eq(UITheme.semibold_font(), UITheme.ui_font())
	assert_eq(UITheme.mono_font(), UITheme.data_font())
	assert_eq(UITheme.heading_font(), UITheme.caption_font())


func test_front_end_backdrop_is_the_games_own_render_and_small() -> void:
	var tex := UITheme.backdrop_texture()
	assert_true(tex != null, "the backdrop imports")
	assert_eq(tex.get_size(), Vector2(1600, 900), "rendered at the design size")
	var f := FileAccess.open(UITheme.BACKDROP_PATH, FileAccess.READ)
	assert_true(f != null and f.get_length() < 400 * 1024, "under 400 KB for the browser build")
	var rect := UITheme.backdrop()
	assert_eq(rect.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED, "covers the screen whatever its shape")
	assert_eq(rect.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	rect.free()


func test_caption_pair_names_its_empty_button_and_the_caption_presses_it() -> void:
	var button := Button.new()
	var pressed := [0]
	button.pressed.connect(func() -> void: pressed[0] += 1)
	var row := UITheme.caption_pair("Accept", button)
	var caption := row.get_child(0) as Label
	assert_eq(caption.text, "ACCEPT")
	assert_eq(caption.theme_type_variation, "MenuCaption")
	assert_eq(button.text, "", "the button itself is an empty bevel")
	assert_eq(button.accessibility_name, "Accept", "but it is named for keyboard and screen-reader users")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	caption.gui_input.emit(click)
	assert_eq(pressed[0], 1, "clicking the caption presses the button")
	button.disabled = true
	caption.gui_input.emit(click)
	assert_eq(pressed[0], 1, "not while it is disabled")
	row.free()


func test_mission_stars_follow_difficulty() -> void:
	assert_eq(ScenarioMenu.stars("Introductory"), "★")
	assert_eq(ScenarioMenu.stars("Intermediate"), "★★")
	assert_eq(ScenarioMenu.stars("Advanced"), "★★★")
	assert_eq(ScenarioMenu.stars(""), "★★", "an unrated mission sits in the middle")
