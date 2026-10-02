class_name InterfaceScale
extends RefCounted
## A display preference, independent of engagement rules and saved games. Scaling the canvas
## keeps custom chart lettering, hit targets and themed text at the same readable size.
const PERCENTAGES := [100, 110, 125]
static var percent := 100


static func apply(window: Window, requested: int, persist := true) -> void:
	percent = requested if requested in PERCENTAGES else 100
	window.content_scale_factor = float(percent) / 100.0
	if persist:
		UserSettings.set_value("display", "interface_scale", percent)


static func initialize(window: Window, driven: bool, args: PackedStringArray) -> void:
	var requested := 100 if driven else int(UserSettings.get_value("display", "interface_scale", 100))
	for arg in args:
		if arg.begins_with("--ui-scale="):
			requested = int(arg.trim_prefix("--ui-scale="))
	apply(window, requested, false)
