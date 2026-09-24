class_name UIIcons
## Interface icons drawn as SVG strokes on a 24-unit grid and rasterised on first use.
## Original drawings. Textures are rendered at RASTER_SCALE times the requested size and drawn
## at that size through `icon_max_width`, so they stay sharp when the canvas is stretched on a
## high-density display.

const RASTER_SCALE := 3.0

const _STROKE := {
	"play": "<path d='M8 5.5v13l10.5-6.5z'/>",
	"pause": "<path d='M9 5.5v13M15 5.5v13'/>",
	"plus": "<path d='M12 5v14M5 12h14'/>",
	"minus": "<path d='M5 12h14'/>",
	"route": "<circle cx='5.5' cy='18.5' r='2'/><circle cx='18.5' cy='5.5' r='2'/><path d='M7.2 17.2 11 13.5l3 2 3.2-8.3' stroke-dasharray='0.1 3.2'/>",
	"fit": "<path d='M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5'/><circle cx='12' cy='12' r='2.2'/>",
	"theatre": "<path d='M9 4.5 3.5 6.5v13L9 17.5l6 2 5.5-2v-13L15 6.5z'/><path d='M9 4.5v13M15 6.5v13'/>",
	"focus": "<circle cx='12' cy='12' r='6.5'/><path d='M12 2.5v4M12 17.5v4M2.5 12h4M17.5 12h4'/>",
	"follow": "<path d='M12 3.5 18.5 20 12 16.2 5.5 20z'/>",
	"sensors": "<circle cx='12' cy='12' r='1.4'/><path d='M8.4 16.6a5.2 5.2 0 0 1 0-8.2M15.6 7.4a5.2 5.2 0 0 1 0 8.2M5.6 19.4a9.2 9.2 0 0 1 0-14.8M18.4 4.6a9.2 9.2 0 0 1 0 14.8'/>",
	"vectors": "<circle cx='7' cy='17' r='2.2'/><path d='M8.8 15.2 18.5 5.5M12.5 5.5h6v6'/>",
	"rings": "<circle cx='12' cy='12' r='2'/><circle cx='12' cy='12' r='5.5'/><circle cx='12' cy='12' r='9'/>",
	"aircraft": "<path d='M12 2.8c.9 0 1.5.8 1.5 1.8v5.2l7 4.2v2l-7-2v4.3l2.4 1.8V22L12 21l-3.9 1v-1.9l2.4-1.8V14l-7 2v-2l7-4.2V4.6c0-1 .6-1.8 1.5-1.8z'/>",
	"search": "<circle cx='10.5' cy='10.5' r='6.5'/><path d='m15.5 15.5 5 5'/>",
	"command": "<path d='M9 6.5v11M15 6.5v11M6.5 9h11M6.5 15h11'/><circle cx='6.5' cy='6.5' r='2.5'/><circle cx='17.5' cy='6.5' r='2.5'/><circle cx='6.5' cy='17.5' r='2.5'/><circle cx='17.5' cy='17.5' r='2.5'/>",
	"library": "<rect x='3.5' y='3.5' width='7' height='7' rx='1.5'/><rect x='13.5' y='3.5' width='7' height='7' rx='1.5'/><rect x='3.5' y='13.5' width='7' height='7' rx='1.5'/><rect x='13.5' y='13.5' width='7' height='7' rx='1.5'/>",
	"orders": "<path d='M14 3.5H7a1.5 1.5 0 0 0-1.5 1.5v14A1.5 1.5 0 0 0 7 20.5h10a1.5 1.5 0 0 0 1.5-1.5V8z'/><path d='M14 3.5V8h4.5M9 12.5h6M9 16h6'/>",
	"menu": "<path d='M4 7h16M4 12h16M4 17h16'/>",
	"restart": "<path d='M4.5 12a7.5 7.5 0 1 0 2.2-5.3L4.5 9'/><path d='M4.5 4.5V9H9'/>",
	"expand": "<path d='M14.5 4H20v5.5M9.5 20H4v-5.5M20 4l-6.5 6.5M4 20l6.5-6.5'/>",
	"collapse": "<path d='M19.5 9.5H14.5v-5M4.5 14.5h5v5M14.5 9.5 20 4M9.5 14.5 4 20'/>",
	"alert": "<path d='M10.3 4.3 2.9 17.5a2 2 0 0 0 1.7 3h14.8a2 2 0 0 0 1.7-3L13.7 4.3a2 2 0 0 0-3.4 0z'/><path d='M12 9.5v4.5M12 17.2v.1'/>",
	"chevron_right": "<path d='m9.5 6 6 6-6 6'/>",
	"chevron_left": "<path d='m14.5 6-6 6 6 6'/>",
	"chevron_down": "<path d='m6 9.5 6 6 6-6'/>",
	"arrow_right": "<path d='M5 12h14M13.5 6.5 19 12l-5.5 5.5'/>",
	"arrow_left": "<path d='M19 12H5M10.5 6.5 5 12l5.5 5.5'/>",
	"close": "<path d='M6.5 6.5l11 11M17.5 6.5l-11 11'/>",
	"contacts": "<circle cx='12' cy='12' r='8.5'/><path d='M12 12 18 6'/><circle cx='15.5' cy='14.5' r='1.2'/><circle cx='8.5' cy='9' r='1.2'/>",
	"layers": "<path d='M12 3.5 21 8.5l-9 5-9-5z'/><path d='m3 12.8 9 5 9-5'/><path d='m3 16.8 9 5 9-5' opacity='0.55'/>",
	"eye": "<path d='M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z'/><circle cx='12' cy='12' r='3'/>",
	"sound": "<path d='M4 9.5h3.5L12 5.5v13l-4.5-4H4z'/><path d='M15.5 9a4.2 4.2 0 0 1 0 6M18 6.5a7.8 7.8 0 0 1 0 11'/>",
	"check_off": "<rect x='4.5' y='4.5' width='15' height='15' rx='3'/>",
	"target": "<circle cx='12' cy='12' r='8.5'/><circle cx='12' cy='12' r='4.5'/><circle cx='12' cy='12' r='0.8'/>",
	"keyboard": "<rect x='2.5' y='6' width='19' height='12' rx='2'/><path d='M6 10h.1M9 10h.1M12 10h.1M15 10h.1M18 10h.1M7 14h10'/>",
	"info": "<circle cx='12' cy='12' r='8.5'/><path d='M12 11v5.5M12 7.8v.1'/>",
}

## Filled shapes, drawn with the requested colour as fill.
const _FILL := {
	"check_on": "<rect x='4' y='4' width='16' height='16' rx='3.5'/><path d='m8 12.3 2.7 2.7L16.2 9.3' fill='none' stroke='#03201d' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'/>",
	"dot": "<circle cx='12' cy='12' r='4'/>",
	"mark": "<path d='M12 1.5 13.6 10.4 22.5 12 13.6 13.6 12 22.5 10.4 13.6 1.5 12 10.4 10.4z'/><path d='M17.3 6.7 13.1 12 17.3 17.3 12 13.1 6.7 17.3 10.9 12 6.7 6.7 12 10.9z' fill-opacity='0.55'/>",
}

static var _cache: Dictionary = {}


static func has_icon(icon_name: String) -> bool:
	return _STROKE.has(icon_name) or _FILL.has(icon_name)


## A texture for `icon_name` drawn `size` logical pixels square in `color`.
## `raster_scale` 1.0 gives a texture at its drawn size, for controls such as LineEdit that draw
## an icon at the texture's own size.
static func get_icon(icon_name: String, size := 18, color := Color.WHITE, raster_scale := RASTER_SCALE) -> Texture2D:
	var key := "%s|%d|%s|%.1f" % [icon_name, size, color.to_html(), raster_scale]
	if _cache.has(key):
		return _cache[key]
	var hex := "#" + color.to_html(false)
	var body := ""
	if _STROKE.has(icon_name):
		body = "<g fill='none' stroke='%s' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round' stroke-opacity='%.3f'>%s</g>" % [hex, color.a, _STROKE[icon_name]]
	elif _FILL.has(icon_name):
		body = "<g fill='%s' fill-opacity='%.3f'>%s</g>" % [hex, color.a, _FILL[icon_name]]
	else:
		push_warning("UIIcons: unknown icon '%s'" % icon_name)
		return null
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24'>%s</svg>" % body
	var image := Image.new()
	var err := image.load_svg_from_string(svg, float(size) * raster_scale / 24.0)
	if err != OK:
		push_warning("UIIcons: could not rasterise '%s'" % icon_name)
		return null
	var tex := ImageTexture.create_from_image(image)
	_cache[key] = tex
	return tex


## Puts a white icon on `button`; the theme's icon colours tint it per state.
static func apply(button: Button, icon_name: String, size := 18) -> void:
	button.icon = get_icon(icon_name, size, Color.WHITE)
	button.add_theme_constant_override("icon_max_width", size)
	button.expand_icon = false
