extends Node
## Autoload `Debug`. Global switch for debug visualization (true positions, ranges, AI states).
## Switched on by the dev harness (--debug). Everything debug-only must be gated behind `Debug.enabled`.

signal toggled(enabled: bool)

var enabled := false


func toggle() -> void:
	enabled = not enabled
	toggled.emit(enabled)
