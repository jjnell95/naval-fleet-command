extends ItemList
## Native ItemList selection, search and accessibility with two genuinely separate text lines.
## ItemList itself strips newlines. A transparent icon establishes each row's height; native
## text remains available to accessibility and incremental search while the two lines draw here.

var row_titles: PackedStringArray = []
var row_details: PackedStringArray = []
var row_colors: Array[Color] = []
var title_size := 17
var detail_size := 15
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


func add_row(title: String, detail: String, color := UITheme.COL_TEXT) -> void:
	row_titles.append(title)
	row_details.append(detail)
	row_colors.append(color)
	add_item(title + " · " + detail, _spacer)


func clear_rows() -> void:
	clear()
	row_titles.clear()
	row_details.clear()
	row_colors.clear()


func _draw() -> void:
	var font := UITheme.semibold_font()
	var detail_font := UITheme.body_font()
	for i in mini(item_count, row_titles.size()):
		var rect := get_item_rect(i)
		rect.position -= Vector2(get_h_scroll_bar().value, get_v_scroll_bar().value)
		if rect.end.y < 0 or rect.position.y > size.y:
			continue
		var width := maxi(int(rect.size.x - 22), 0)
		var title := _fit_text(font, row_titles[i], width, title_size)
		var detail := _fit_text(detail_font, row_details[i], width, detail_size)
		var base := rect.position + Vector2(10, title_size + 3)
		var color := Color.WHITE if is_selected(i) else row_colors[i]
		if base.y >= title_size + 4 and base.y <= size.y - 5:
			draw_string(font, base, title, HORIZONTAL_ALIGNMENT_LEFT, width, title_size, color)
		var detail_base := base + Vector2(0, detail_size + 7)
		if detail_base.y >= detail_size + 4 and detail_base.y <= size.y - 5:
			draw_string(detail_font, detail_base, detail, HORIZONTAL_ALIGNMENT_LEFT, width, detail_size, UITheme.COL_TEXT if is_selected(i) else UITheme.COL_MUTED)


func _fit_text(font: Font, value: String, width: int, font_size: int) -> String:
	var result := value
	while result.length() > 1 and font.get_string_size(result, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		result = result.left(result.length() - 2) + "…"
	return result
