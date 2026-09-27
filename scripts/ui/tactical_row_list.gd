extends ItemList
## Native ItemList selection, search and accessibility with two genuinely separate text lines.
## ItemList itself strips newlines. A transparent icon establishes each row's height; native
## text remains available to accessibility and incremental search while the two lines draw here.
##
## In single-line mode a row is a badge (a mission's difficulty stars), a title and a detail at the
## right, the late-1990s mission list. Colours come from the RowListText theme type, so the same
## list reads on the grey front end and on a navy data panel.

var row_titles: PackedStringArray = []
var row_details: PackedStringArray = []
var row_colors: Array[Color] = []
var row_badges: PackedStringArray = []
var title_size := 17
var detail_size := 15
## One line per row: badge, title, and the detail right-aligned.
var single_line := false
## Width kept for badges in single-line mode, so titles line up.
var badge_width := 0.0
var _spacer: ImageTexture


func _init() -> void:
	configure_rows(17, 15, 48)
	for color_name in ["font_color", "font_selected_color", "font_hovered_color", "font_hovered_selected_color"]:
		add_theme_color_override(color_name, Color.TRANSPARENT)


func configure_rows(title_font_size: int, detail_font_size: int, row_height: int) -> void:
	title_size = title_font_size
	detail_size = detail_font_size
	var blank := Image.create(1, row_height, false, Image.FORMAT_RGBA8)
	blank.fill(Color.TRANSPARENT)
	_spacer = ImageTexture.create_from_image(blank)


## A transparent `color` draws the title in the surface's own text colour.
func add_row(title: String, detail: String, color := Color.TRANSPARENT, badge := "") -> void:
	row_titles.append(title)
	row_details.append(detail)
	row_colors.append(color)
	row_badges.append(badge)
	add_item(title + " · " + detail, _spacer)


func clear_rows() -> void:
	clear()
	row_titles.clear()
	row_details.clear()
	row_colors.clear()
	row_badges.clear()


func _colour(key: String, fallback: Color) -> Color:
	# A theme type of its own: the node's overrides make its ItemList text colours transparent.
	return get_theme_color(key, "RowListText") if has_theme_color(key, "RowListText") else fallback


func _draw() -> void:
	var font := UITheme.ui_font()
	var title_col := _colour("title_color", UITheme.COL_TEXT)
	var detail_col := _colour("detail_color", UITheme.COL_MUTED)
	var selected_col := _colour("selected_color", Color.WHITE)
	var selected_detail := _colour("selected_detail_color", UITheme.COL_TEXT)
	var badge_col := _colour("badge_color", UITheme.STAR)
	for i in mini(item_count, row_titles.size()):
		var rect := get_item_rect(i)
		rect.position -= Vector2(get_h_scroll_bar().value, get_v_scroll_bar().value)
		if rect.end.y < 0 or rect.position.y > size.y:
			continue
		var selected := is_selected(i)
		var color := selected_col if selected else (row_colors[i] if row_colors[i].a > 0.0 else title_col)
		if single_line:
			_draw_single(i, rect, font, color, selected_detail if selected else detail_col, Color.WHITE if selected else badge_col)
			continue
		var width := maxi(int(rect.size.x - 22), 0)
		var title := _fit_text(font, row_titles[i], width, title_size)
		var detail := _fit_text(font, row_details[i], width, detail_size)
		var base := rect.position + Vector2(10, title_size + 3)
		if base.y >= title_size + 4 and base.y <= size.y - 5:
			draw_string(font, base, title, HORIZONTAL_ALIGNMENT_LEFT, width, title_size, color)
		var detail_base := base + Vector2(0, detail_size + 7)
		if detail_base.y >= detail_size + 4 and detail_base.y <= size.y - 5:
			draw_string(font, detail_base, detail, HORIZONTAL_ALIGNMENT_LEFT, width, detail_size, selected_detail if selected else detail_col)


func _draw_single(i: int, rect: Rect2, font: Font, color: Color, detail_col: Color, badge_col: Color) -> void:
	var baseline := rect.position.y + (rect.size.y + font.get_ascent(title_size) - font.get_descent(title_size)) * 0.5
	if baseline < title_size or baseline > size.y - 3:
		return
	var x := rect.position.x + 6.0
	if row_badges[i] != "":
		draw_string(UITheme.data_font(), Vector2(x, baseline), row_badges[i], HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, badge_col)
	x += badge_width
	var right := rect.end.x - 8.0
	var detail_w := 0.0
	if row_details[i] != "":
		detail_w = font.get_string_size(row_details[i], HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size).x
		draw_string(font, Vector2(right - detail_w, baseline), row_details[i], HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size, detail_col)
	var room := maxi(int(right - detail_w - 12.0 - x), 0)
	draw_string(font, Vector2(x, baseline), _fit_text(font, row_titles[i], room, title_size), HORIZONTAL_ALIGNMENT_LEFT, room, title_size, color)


func _fit_text(font: Font, value: String, width: int, font_size: int) -> String:
	var result := value
	while result.length() > 1 and font.get_string_size(result, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		result = result.left(result.length() - 2) + "…"
	return result
