class_name TitleMark
extends Label
## The game's own name as the front end's wordmark: heavy italic capitals with a brushed-metal
## fill, a dark outline and a drop shadow. Only lettering; no emblem.

const SHADER := """
shader_type canvas_item;
// The label draws its shadow, outline and fill as separate passes in their own colours; only the
// light fill pass is recoloured, as a band of polished metal from top to bottom.
uniform float height = 60.0;
varying float local_y;
void vertex() {
	local_y = VERTEX.y;
}
void fragment() {
	vec4 c = COLOR;
	if (c.r > 0.5 && c.g > 0.5) {
		float t = clamp(local_y / max(height, 1.0), 0.0, 1.0);
		vec3 top = vec3(0.97, 0.98, 1.0);
		vec3 upper = vec3(0.80, 0.82, 0.87);
		vec3 band = vec3(0.50, 0.52, 0.58);
		vec3 lower = vec3(0.86, 0.88, 0.92);
		vec3 metal = mix(top, upper, smoothstep(0.18, 0.5, t));
		metal = mix(metal, band, smoothstep(0.5, 0.56, t));
		metal = mix(metal, lower, smoothstep(0.58, 0.86, t));
		c.rgb = metal;
	}
	COLOR = c;
}
"""

static var _shader: Shader = null


func _init(title := "NAVAL FLEET COMMAND", font_size := 56) -> void:
	text = title
	theme_type_variation = "TitleMark"
	add_theme_font_size_override("font_size", font_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	material = mat
	resized.connect(_fit_gradient)


func set_font_size(font_size: int) -> void:
	add_theme_font_size_override("font_size", font_size)
	_fit_gradient()


func _fit_gradient() -> void:
	(material as ShaderMaterial).set_shader_parameter("height", maxf(size.y, 1.0))
