class_name ConfirmDiscard
extends Control
## The one question asked before a click throws work away: leaving a running engagement for
## another operation, restarting it, clearing a mission being built, deleting a saved engagement.
## A grey dialog over a shade, with the same header as every other dialog. The keeping answer
## holds the focus, so a stray Enter or Space keeps the work, and no key reaches the screen behind.

const NODE_NAME := "ConfirmDiscard"

var _on_confirm := Callable()
var _title: Label
var _question: Label
var _keep: Button
var _discard: Button


## Asks on `host`, reusing its one dialog, and calls `on_confirm` only if the commander agrees.
static func ask(host: Node, title_text: String, question: String, discard_text: String, on_confirm: Callable, keep_text := "Keep it") -> ConfirmDiscard:
	var dialog := host.get_node_or_null(NODE_NAME) as ConfirmDiscard
	if dialog == null:
		dialog = ConfirmDiscard.new()
		dialog.name = NODE_NAME
		host.add_child(dialog)
	host.move_child(dialog, -1)
	dialog._on_confirm = on_confirm
	dialog._title.text = title_text.to_upper()
	dialog._question.text = question
	dialog._discard.text = discard_text.to_upper()
	dialog._keep.text = keep_text.to_upper()
	dialog.show()
	dialog._keep.grab_focus.call_deferred()
	return dialog


## The dialog on `host` while it is asking, or null.
static func asking(host: Node) -> ConfirmDiscard:
	var dialog := host.get_node_or_null(NODE_NAME) as ConfirmDiscard
	return dialog if dialog != null and dialog.visible else null


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	accessibility_name = "Confirm"
	var shade := ColorRect.new()
	shade.color = UITheme.DIALOG_SHADE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = "JfcDialog"
	card.custom_minimum_size = Vector2(500, 0)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	var header := UITheme.dialog_header("", func() -> void: _answer(false), "Esc")
	v.add_child(header)
	_title = header.get_node("Title") as Label
	(header.get_node("Close") as Button).focus_mode = Control.FOCUS_NONE
	_question = Label.new()
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question.custom_minimum_size.x = 460
	_question.add_theme_font_size_override("font_size", UITheme.SIZE_LEAD)
	v.add_child(_question)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(buttons)
	_keep = Button.new()
	_keep.theme_type_variation = "PrimaryButton"
	_discard = Button.new()
	_discard.theme_type_variation = "DangerButton"
	for b: Button in [_keep, _discard]:
		b.custom_minimum_size = Vector2(150, 34)
		b.focus_mode = Control.FOCUS_ALL
		buttons.add_child(b)
	_keep.pressed.connect(_answer.bind(false))
	_discard.pressed.connect(_answer.bind(true))
	_keep.focus_neighbor_right = _keep.get_path_to(_discard)
	hide()


## The question as asked.
func question() -> String:
	return _question.text


## The answer that throws the work away.
func get_ok_button() -> Button:
	return _discard


## The answer that keeps it.
func get_cancel_button() -> Button:
	return _keep


## Every key stops here while the question is up: Esc keeps the work, Enter or Space presses the
## answer that has the focus (keeping, unless the commander moved to the other), the arrows and
## Tab move between the two.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	if k == null:
		return
	get_viewport().set_input_as_handled()
	if not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_ESCAPE:
			_answer(false)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_answer(_discard.has_focus())
		KEY_TAB, KEY_LEFT, KEY_RIGHT:
			(_keep if _discard.has_focus() else _discard).grab_focus()


func _answer(confirmed: bool) -> void:
	if not visible:
		return
	hide()
	var action := _on_confirm
	_on_confirm = Callable()
	if confirmed and action.is_valid():
		action.call()
