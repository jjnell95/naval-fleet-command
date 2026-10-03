extends Window
## Handle cancel inside this window's own viewport, including keyboard events from embedded
## browser windows. Consuming it here prevents a close from reaching the command-screen menu.

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		set_input_as_handled()
